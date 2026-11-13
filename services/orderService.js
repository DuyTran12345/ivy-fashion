'use strict';
/**
 * [UC04] Service đơn hàng: đặt hàng, chuyển trạng thái, kho, mã giảm giá, hoàn tiền.
 *
 * KHO (đúng đề bài):
 *   - Khi THÊM VÀO GIỎ và khi ĐẶT HÀNG: chỉ kiểm tra tồn kho, chưa trừ.
 *   - Khi ADMIN XÁC NHẬN đơn: trừ tồn bằng một câu UPDATE có điều kiện (StockQuantity >= số lượng),
 *     nên hai đơn cùng lúc không thể làm tồn kho âm. Hết hàng thì không xác nhận được.
 *   - Khi HỦY hoặc TRẢ HÀNG sau khi đã trừ: hoàn lại tồn kho.
 *   Mỗi lần trừ/hoàn đều ghi một dòng vào InventoryLogs.
 *   Lưu ý: vì chỉ trừ lúc xác nhận, hai đơn "Chờ xác nhận" có thể cùng đặt phần hàng còn lại;
 *   đơn xác nhận sau sẽ báo thiếu hàng để admin xử lý (hủy hoặc chờ nhập thêm).
 *
 * MÃ GIẢM GIÁ [UC05]: giữ chỗ một lượt dùng bằng UPDATE có điều kiện trong cùng giao dịch đặt hàng.
 * Giao dịch lỗi thì rollback, lượt dùng tự được trả lại. Hủy đơn cũng trả lại lượt dùng.
 */
const crypto = require('crypto');
const db = require('../config/db');
const shop = require('../config/shop');
const S = require('../utils/orderStatus');
const { computeTotals, evaluateDiscount } = require('../utils/pricing');
const { vnYYMMDD } = require('../utils/time');
const { BusinessError, NotFoundError } = require('../utils/errors');
const discountModel = require('../models/discountModel');

const CODE_CHARS = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ'; // bỏ 0, O, 1, I cho dễ đọc

/** Mã đơn dạng AM + yyMMdd + 5 ký tự ngẫu nhiên, ví dụ AM261104K7X2P. */
function makeOrderCode() {
  let tail = '';
  for (let i = 0; i < 5; i += 1) tail += CODE_CHARS[crypto.randomInt(CODE_CHARS.length)];
  return `AM${vnYYMMDD()}${tail}`;
}

const DEFAULT_NOTE = Object.freeze({
  CONFIRMED: 'Admin xác nhận đơn, trừ tồn kho',
  SHIPPING: 'Đã tạo vận đơn, bàn giao đơn vị vận chuyển',
  DELIVERED: 'Giao hàng thành công',
  CANCELLED: 'Đơn hàng bị hủy',
  RETURNED: 'Ghi nhận trả hàng',
});

// ------------------------------------------------------------------ đặt hàng
/**
 * Tạo đơn từ giỏ hàng. Giá và số lượng luôn đọc lại từ CSDL, không nhận từ trình duyệt.
 * Trả về { id, code, total, subtotal, discountAmount, shippingFee, paymentMethod }.
 */
async function createOrder({ userId, cartId, addressId, discountCode, paymentMethod, note, consentGivenAt }) {
  if (!consentGivenAt) {
    throw new BusinessError('Bạn cần đồng ý với việc xử lý dữ liệu cá nhân trước khi đặt hàng.', { code: 'NO_CONSENT' });
  }
  if (!['COD', 'ONLINE'].includes(paymentMethod)) throw new BusinessError('Phương thức thanh toán không hợp lệ.');

  let discount = null;
  if (discountCode) {
    discount = await discountModel.findByCode(discountCode);
    if (!discount) throw new BusinessError('Mã giảm giá không tồn tại.', { code: 'INVALID_DISCOUNT' });
  }

  // Trùng mã đơn (rất hiếm) thì giao dịch đã rollback toàn bộ, thử lại với mã mới.
  for (let attempt = 1; ; attempt += 1) {
    try {
      return await db.tx((t) => insertOrder(t, { userId, cartId, addressId, discount, paymentMethod, note, consentGivenAt }));
    } catch (err) {
      if (attempt < 3 && db.isUniqueViolation(err) && String(err.message || '').includes('UX_Orders_Code')) continue;
      throw err;
    }
  }
}

async function insertOrder(t, { userId, cartId, addressId, discount, paymentMethod, note, consentGivenAt }) {
  const address = await t.one(
    `SELECT RecipientName, Phone, Province, District, Ward, StreetAddress
       FROM dbo.Addresses WHERE AddressId = @id AND UserId = @uid`, { id: addressId, uid: userId });
  if (!address) throw new BusinessError('Địa chỉ giao hàng không tồn tại hoặc không thuộc về bạn.', { code: 'BAD_ADDRESS' });

  // Ràng buộc c.UserId = @uid bảo đảm giỏ hàng thuộc đúng người đặt.
  const lines = (await t.query(
    `SELECT ci.CartItemId AS cartItemId, ci.Quantity AS qty,
            v.VariantId AS variantId, v.Sku AS sku, v.Size AS size, v.ColorName AS color, v.Price AS price,
            v.StockQuantity AS stock, v.IsActive AS variantActive,
            p.ProductId AS productId, p.Name AS productName, p.IsActive AS productActive,
            (SELECT TOP (1) i.ImageUrl FROM dbo.ProductImages i WHERE i.ProductId = p.ProductId ORDER BY i.SortOrder, i.ImageId) AS image
       FROM dbo.Carts c
       JOIN dbo.CartItems ci ON ci.CartId = c.CartId
       JOIN dbo.ProductVariants v ON v.VariantId = ci.VariantId
       JOIN dbo.Products p ON p.ProductId = v.ProductId
      WHERE c.CartId = @cid AND c.UserId = @uid
      ORDER BY ci.CartItemId`, { cid: cartId, uid: userId })).rows;
  if (!lines.length) throw new BusinessError('Giỏ hàng trống. Hãy thêm sản phẩm trước khi đặt hàng.', { code: 'EMPTY_CART' });

  // [UC04] Kiểm tra tồn kho khi đặt hàng (chưa trừ kho).
  const problems = [];
  for (const ln of lines) {
    const label = `${ln.productName} (${ln.size}, ${ln.color})`;
    if (!ln.variantActive || !ln.productActive) problems.push(`${label} đã ngừng bán`);
    else if (ln.stock < ln.qty) problems.push(`${label} chỉ còn ${ln.stock} trong kho`);
  }
  if (problems.length) {
    throw new BusinessError(`Giỏ hàng có sản phẩm không thể đặt: ${problems.join('; ')}. Vui lòng cập nhật giỏ hàng.`, { code: 'CART_PROBLEM' });
  }

  const subtotal = lines.reduce((sum, ln) => sum + ln.price * ln.qty, 0);
  if (subtotal > shop.limits.maxOrderTotal) {
    throw new BusinessError('Giá trị đơn hàng vượt mức cho phép. Vui lòng chia thành nhiều đơn nhỏ hơn.');
  }

  // [UC05] Điều kiện mã giảm giá với giá thật từ CSDL, rồi giữ chỗ một lượt dùng.
  let discountId = null;
  let discountCode = null;
  let discountAmount = 0;
  if (discount) {
    const evl = evaluateDiscount(discount, subtotal);
    if (!evl.ok) throw new BusinessError(evl.message, { code: 'INVALID_DISCOUNT' });
    const claimed = await t.scalar(
      `UPDATE dbo.Discounts SET UsedCount = UsedCount + 1, UpdatedAt = SYSUTCDATETIME()
       OUTPUT INSERTED.DiscountId
       WHERE DiscountId = @id AND IsActive = 1 AND MinOrderValue <= @subtotal
         AND (UsageLimit IS NULL OR UsedCount < UsageLimit)
         AND StartsAt <= SYSUTCDATETIME() AND EndsAt >= SYSUTCDATETIME()`,
      { id: discount.DiscountId, subtotal });
    if (claimed === null) {
      throw new BusinessError('Mã giảm giá vừa hết lượt hoặc hết hạn. Vui lòng kiểm tra lại.', { code: 'DISCOUNT_RACE' });
    }
    discountId = discount.DiscountId;
    discountCode = discount.Code;
    discountAmount = evl.amount;
  }

  const totals = computeTotals(subtotal, discountAmount);
  const code = makeOrderCode();

  // Ship* là BẢN SAO địa chỉ lúc đặt, nên sửa hay xóa địa chỉ trong sổ địa chỉ không ảnh hưởng đơn cũ.
  const orderId = await t.scalar(
    `INSERT dbo.Orders (OrderCode, UserId, Status, ShipRecipientName, ShipPhone, ShipProvince, ShipDistrict, ShipWard, ShipStreet,
                        Note, Subtotal, DiscountId, DiscountCode, DiscountAmount, ShippingFee, TotalAmount, PaymentMethod,
                        StockDeducted, ConsentGivenAt)
       OUTPUT INSERTED.OrderId
       VALUES (@code, @uid, N'PENDING', @name, @phone, @province, @district, @ward, @street,
               @note, @subtotal, @discId, @discCode, @discAmt, @shipFee, @total, @method, 0, @consent)`,
    {
      code, uid: userId, name: address.RecipientName, phone: address.Phone, province: address.Province,
      district: address.District || null, ward: address.Ward, street: address.StreetAddress,
      note: note || null, subtotal, discId: discountId, discCode: discountCode, discAmt: totals.discountAmount,
      shipFee: totals.shippingFee, total: totals.total, method: paymentMethod, consent: consentGivenAt,
    });

  // UnitPrice là ĐƠN GIÁ TẠI THỜI ĐIỂM ĐẶT, kèm bản sao tên/SKU/size/màu/ảnh.
  for (const ln of lines) {
    await t.query(
      `INSERT dbo.OrderItems (OrderId, VariantId, ProductId, ProductName, Sku, Size, ColorName, ImageUrl, UnitPrice, Quantity)
         VALUES (@oid, @vid, @pid, @name, @sku, @size, @color, @img, @price, @qty)`,
      {
        oid: orderId, vid: ln.variantId, pid: ln.productId, name: ln.productName, sku: ln.sku,
        size: ln.size, color: ln.color, img: ln.image || null, price: ln.price, qty: ln.qty,
      });
  }

  await t.query(
    `INSERT dbo.OrderStatusHistory (OrderId, FromStatus, ToStatus, ChangedByUserId, Note)
       VALUES (@oid, NULL, N'PENDING', @uid, N'Khách đặt hàng')`, { oid: orderId, uid: userId });

  // COD có sẵn một khoản thanh toán chờ thu. Thanh toán online chỉ tạo khi khách bấm "Thanh toán" (paymentService).
  if (paymentMethod === 'COD') {
    await t.query(
      `INSERT dbo.Payments (OrderId, Provider, Amount, Status) VALUES (@oid, N'COD', @amt, N'PENDING')`,
      { oid: orderId, amt: totals.total });
  }

  // Chỉ xóa đúng các dòng đã đặt khỏi giỏ.
  const del = db.inList('ci', lines.map((l) => l.cartItemId));
  await t.query(`DELETE FROM dbo.CartItems WHERE CartId = @cid AND CartItemId IN (${del.clause})`, { cid: cartId, ...del.params });
  await t.query('UPDATE dbo.Carts SET UpdatedAt = SYSUTCDATETIME() WHERE CartId = @cid', { cid: cartId });

  return {
    id: orderId, code, total: totals.total, subtotal, discountAmount: totals.discountAmount,
    shippingFee: totals.shippingFee, paymentMethod,
  };
}

// ------------------------------------------------------------------ chuyển trạng thái
/**
 * [UC04] Chuyển trạng thái đơn theo máy trạng thái trong utils/orderStatus.
 *   actor        : 'ADMIN' hoặc 'CUSTOMER'
 *   expectedFrom : trạng thái mà giao diện đang hiển thị; lệch với CSDL thì báo "đã thay đổi" (tránh thao tác trên dữ liệu cũ)
 *   shipping     : { carrier, trackingCode, note } bắt buộc khi chuyển sang "Đang giao" (tạo vận đơn)
 * Trạng thái đơn, kho, vận đơn, thanh toán, mã giảm giá và lịch sử thay đổi trong CÙNG MỘT giao dịch.
 */
async function changeStatus({ orderCode, toStatus, actor, actorUserId, expectedFrom = null, note = null, shipping = null }) {
  if (!S.isValid(toStatus)) throw new BusinessError('Trạng thái đơn hàng không hợp lệ.');
  const text = note ? String(note).slice(0, 255) : null;

  return db.tx(async (t) => {
    const order = await t.one(
      `SELECT OrderId AS id, UserId AS userId, Status AS status, DiscountId AS discountId,
              StockDeducted AS stockDeducted, PaymentMethod AS paymentMethod
         FROM dbo.Orders WITH (UPDLOCK, ROWLOCK) WHERE OrderCode = @code`, { code: orderCode });
    // Khách xem đơn của người khác cũng nhận "không tìm thấy", không tiết lộ đơn có tồn tại hay không.
    if (!order || (actor === 'CUSTOMER' && order.userId !== actorUserId)) throw new NotFoundError('Không tìm thấy đơn hàng.');

    if (expectedFrom && expectedFrom !== order.status) {
      throw new BusinessError(`Trạng thái đơn đã thay đổi (hiện là "${S.label(order.status)}"). Vui lòng tải lại trang.`, { code: 'STATE_CHANGED' });
    }
    if (!S.canTransition(order.status, toStatus, actor)) {
      throw new BusinessError(`Không thể chuyển đơn từ "${S.label(order.status)}" sang "${S.label(toStatus)}".`, { code: 'INVALID_TRANSITION' });
    }

    // Đơn thanh toán online chỉ được xác nhận sau khi đã nhận tiền.
    if (toStatus === S.STATUS.CONFIRMED && order.paymentMethod === 'ONLINE') {
      const paid = await t.scalar(`SELECT TOP (1) 1 AS x FROM dbo.Payments WHERE OrderId = @oid AND Status = N'PAID'`, { oid: order.id });
      if (!paid) throw new BusinessError('Đơn thanh toán online chỉ xác nhận được sau khi đã nhận tiền. Có thể hủy đơn nếu khách không thanh toán.', { code: 'UNPAID' });
    }
    if (toStatus === S.STATUS.SHIPPING) {
      if (!shipping || !shop.carriers.includes(shipping.carrier) || !shipping.trackingCode) {
        throw new BusinessError('Cần chọn đơn vị vận chuyển và nhập mã vận đơn để chuyển sang "Đang giao".', { code: 'NEED_SHIPPING' });
      }
    }

    // --- Kho
    const items = (await t.query(
      'SELECT VariantId AS variantId, Quantity AS qty FROM dbo.OrderItems WHERE OrderId = @oid ORDER BY VariantId',
      { oid: order.id })).rows; // luôn khóa theo thứ tự VariantId để tránh deadlock giữa hai đơn
    const effect = S.stockEffect(order.status, toStatus);
    let stockDeducted = order.stockDeducted ? 1 : 0;

    if (effect === 'DEDUCT') {
      for (const it of items) {
        const after = await t.scalar(
          `UPDATE dbo.ProductVariants SET StockQuantity = StockQuantity - @qty, UpdatedAt = SYSUTCDATETIME()
           OUTPUT INSERTED.StockQuantity
           WHERE VariantId = @vid AND StockQuantity >= @qty`, { vid: it.variantId, qty: it.qty });
        if (after === null) {
          const v = await t.one('SELECT Sku AS sku, StockQuantity AS stock FROM dbo.ProductVariants WHERE VariantId = @vid', { vid: it.variantId });
          throw new BusinessError(
            `Không đủ tồn kho để xác nhận đơn: ${v ? v.sku : it.variantId} cần ${it.qty}, kho còn ${v ? v.stock : 0}.`,
            { code: 'INSUFFICIENT_STOCK' });
        }
        await t.query(
          `INSERT dbo.InventoryLogs (VariantId, OrderId, Delta, StockAfter, Reason, CreatedByUserId)
             VALUES (@vid, @oid, @delta, @after, N'ORDER_CONFIRM', @uid)`,
          { vid: it.variantId, oid: order.id, delta: -it.qty, after, uid: actorUserId || null });
      }
      stockDeducted = 1;
    } else if (effect === 'RESTORE' && order.stockDeducted) {
      const reason = toStatus === S.STATUS.CANCELLED ? 'ORDER_CANCEL' : 'ORDER_RETURN';
      for (const it of items) {
        const after = await t.scalar(
          `UPDATE dbo.ProductVariants SET StockQuantity = StockQuantity + @qty, UpdatedAt = SYSUTCDATETIME()
           OUTPUT INSERTED.StockQuantity
           WHERE VariantId = @vid`, { vid: it.variantId, qty: it.qty });
        await t.query(
          `INSERT dbo.InventoryLogs (VariantId, OrderId, Delta, StockAfter, Reason, CreatedByUserId)
             VALUES (@vid, @oid, @delta, @after, @reason, @uid)`,
          { vid: it.variantId, oid: order.id, delta: it.qty, after, reason, uid: actorUserId || null });
      }
      stockDeducted = 0;
    }

    // --- Đơn hàng. Các đoạn SET ghép thêm bên dưới đều là chuỗi cố định, không lấy từ dữ liệu người dùng.
    const sets = ['Status = @to', 'StockDeducted = @sd', 'UpdatedAt = SYSUTCDATETIME()'];
    if (toStatus === S.STATUS.CONFIRMED) sets.push('ConfirmedAt = SYSUTCDATETIME()');
    if (toStatus === S.STATUS.DELIVERED) sets.push('DeliveredAt = SYSUTCDATETIME()');
    if (toStatus === S.STATUS.CANCELLED) sets.push('CancelledAt = SYSUTCDATETIME()');
    if (toStatus === S.STATUS.CANCELLED || toStatus === S.STATUS.RETURNED) sets.push('CancelReason = @reason');
    await t.query(`UPDATE dbo.Orders SET ${sets.join(', ')} WHERE OrderId = @id`, {
      to: toStatus, sd: stockDeducted, id: order.id, reason: text || DEFAULT_NOTE[toStatus],
    });

    // --- Vận đơn
    if (toStatus === S.STATUS.SHIPPING) {
      try {
        await t.query(
          `INSERT dbo.Shippings (OrderId, Carrier, TrackingCode, Status, Note, CreatedByUserId)
             VALUES (@oid, @carrier, @tracking, N'SHIPPING', @note, @uid)`,
          { oid: order.id, carrier: shipping.carrier, tracking: shipping.trackingCode, note: shipping.note || null, uid: actorUserId || null });
      } catch (err) {
        if (db.isUniqueViolation(err)) throw new BusinessError('Đơn hàng này đã có vận đơn.');
        throw err;
      }
    } else if (toStatus === S.STATUS.DELIVERED) {
      await t.query(`UPDATE dbo.Shippings SET Status = N'DELIVERED', DeliveredAt = SYSUTCDATETIME() WHERE OrderId = @oid`, { oid: order.id });
    } else if (toStatus === S.STATUS.RETURNED) {
      await t.query(`UPDATE dbo.Shippings SET Status = N'RETURNED' WHERE OrderId = @oid`, { oid: order.id });
    }

    // --- Thanh toán. Giao COD thành công = đã thu tiền. Hủy hoặc trả hàng thì hủy các khoản còn chờ.
    // Khoản đã PAID giữ nguyên, đơn hiện cờ "Cần hoàn tiền" cho tới khi admin xác nhận hoàn (markRefunded).
    if (toStatus === S.STATUS.DELIVERED && order.paymentMethod === 'COD') {
      await t.query(
        `UPDATE dbo.Payments SET Status = N'PAID', PaidAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
          WHERE OrderId = @oid AND Provider = N'COD' AND Status = N'PENDING'`, { oid: order.id });
    }
    if (toStatus === S.STATUS.CANCELLED || toStatus === S.STATUS.RETURNED) {
      await t.query(
        `UPDATE dbo.Payments SET Status = N'CANCELLED', UpdatedAt = SYSUTCDATETIME()
          WHERE OrderId = @oid AND Status = N'PENDING'`, { oid: order.id });
    }

    // --- [UC05] Hủy đơn thì trả lại lượt dùng mã giảm giá (trả hàng thì không, vì khách đã hưởng ưu đãi).
    if (S.releasesDiscount(toStatus) && order.discountId) {
      await t.query(
        `UPDATE dbo.Discounts SET UsedCount = CASE WHEN UsedCount > 0 THEN UsedCount - 1 ELSE 0 END, UpdatedAt = SYSUTCDATETIME()
          WHERE DiscountId = @id`, { id: order.discountId });
    }

    // --- Lịch sử chuyển trạng thái
    await t.query(
      `INSERT dbo.OrderStatusHistory (OrderId, FromStatus, ToStatus, ChangedByUserId, Note)
         VALUES (@oid, @from, @to, @uid, @note)`,
      { oid: order.id, from: order.status, to: toStatus, uid: actorUserId || null, note: text || DEFAULT_NOTE[toStatus] });

    return { orderId: order.id, orderCode, from: order.status, to: toStatus };
  });
}

/** Khách tự hủy đơn khi còn "Chờ xác nhận". */
function cancelByCustomer({ orderCode, userId }) {
  return changeStatus({
    orderCode, toStatus: S.STATUS.CANCELLED, actor: 'CUSTOMER', actorUserId: userId,
    expectedFrom: S.STATUS.PENDING, note: 'Khách tự hủy khi đơn chưa được xác nhận',
  });
}

/**
 * Admin xác nhận đã hoàn tiền cho đơn đã hủy/trả hàng mà khách đã thanh toán.
 * Việc chuyển tiền thật diễn ra ngoài hệ thống (ngân hàng, cổng thanh toán); đây chỉ ghi nhận lại.
 */
async function markRefunded({ orderCode, adminUserId, note }) {
  return db.tx(async (t) => {
    const order = await t.one('SELECT OrderId AS id, Status AS status FROM dbo.Orders WITH (UPDLOCK, ROWLOCK) WHERE OrderCode = @code', { code: orderCode });
    if (!order) throw new NotFoundError('Không tìm thấy đơn hàng.');
    if (order.status !== S.STATUS.CANCELLED && order.status !== S.STATUS.RETURNED) {
      throw new BusinessError('Chỉ hoàn tiền cho đơn đã hủy hoặc đã trả hàng.');
    }
    const r = await t.query(
      `UPDATE dbo.Payments SET Status = N'REFUNDED', RefundedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
        WHERE OrderId = @oid AND Status = N'PAID'`, { oid: order.id });
    if (!((r.rowsAffected[0] || 0) > 0)) throw new BusinessError('Đơn hàng này không có khoản thanh toán nào cần hoàn.');
    await t.query(
      `INSERT dbo.OrderStatusHistory (OrderId, FromStatus, ToStatus, ChangedByUserId, Note)
         VALUES (@oid, @st, @st, @uid, @note)`,
      { oid: order.id, st: order.status, uid: adminUserId || null, note: note ? String(note).slice(0, 255) : 'Đã hoàn tiền cho khách' });
    return { orderId: order.id };
  });
}

module.exports = { createOrder, changeStatus, cancelByCustomer, markRefunded, makeOrderCode };
