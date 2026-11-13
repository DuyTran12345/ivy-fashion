'use strict';
/**
 * Giỏ hàng, đặt hàng, đơn hàng của tôi, đánh giá, và các trang thanh toán dành cho khách.
 *   [UC04] kiểm tra tồn kho khi thêm vào giỏ và khi đặt hàng
 *   [UC05] áp dụng mã giảm giá
 *   [UC06] thanh toán COD / online; trang cổng giả lập để kiểm thử IPN
 *   [UC09] đánh giá sản phẩm (chỉ với đơn "Đã giao")
 * Các endpoint IPN/webhook của cổng thanh toán nằm ở routes/paymentHooks.js (gắn trước CSRF).
 */
const express = require('express');
const ah = require('../utils/asyncHandler');
const v = require('../utils/validate');
const S = require('../utils/orderStatus');
const { formatVnd } = require('../utils/format');
const { evaluateDiscount, computeTotals } = require('../utils/pricing');
const { BusinessError, NotFoundError } = require('../utils/errors');
const { requireAuth } = require('../middleware/auth');
const { getOrCreateCartId, findCartId } = require('../middleware/cartContext');
const cartModel = require('../models/cartModel');
const discountModel = require('../models/discountModel');
const orderModel = require('../models/orderModel');
const paymentModel = require('../models/paymentModel');
const userModel = require('../models/userModel');
const reviewModel = require('../models/reviewModel');
const orderService = require('../services/orderService');
const paymentSvc = require('../services/paymentService');
const registry = require('../services/payment/registry');
const shop = require('../config/shop');
const env = require('../config/env');

const router = express.Router();

const MOCK_ACTIONS = ['success', 'fail', 'tamper', 'wrongamount', 'replay'];

/* ====================================================================
   GIỎ HÀNG
   ==================================================================== */

router.get('/cart', ah(async (req, res) => {
  const cartId = await findCartId(req);
  const cart = cartId ? await cartModel.getDetail(cartId) : { items: [], subtotal: 0 };
  res.render('shop/cart', { title: 'Giỏ hàng', cart, added: req.query.added === '1' });
}));

/** [UC04] Thêm vào giỏ: kiểm tra tồn kho (cartModel.addItem), không cho vượt tồn. */
router.post('/cart/add', ah(async (req, res) => {
  const variantId = v.id(req.body.variantId);
  if (!variantId) throw new BusinessError('Vui lòng chọn kích cỡ và màu sắc.');
  const qty = v.intInRange(req.body.quantity || '1', 'số lượng', 1, shop.limits.maxQtyPerLine);
  if (qty.error) throw new BusinessError(qty.error);

  const cartId = await getOrCreateCartId(req, res);
  await cartModel.addItem(cartId, variantId, qty.value);
  res.redirect('/cart?added=1');
}));

router.post('/cart/update', ah(async (req, res) => {
  const variantId = v.id(req.body.variantId);
  if (!variantId) throw new BusinessError('Thông tin sản phẩm không hợp lệ.');
  const qty = v.intInRange(req.body.quantity, 'số lượng', 0, shop.limits.maxQtyPerLine);
  if (qty.error) throw new BusinessError(qty.error);
  const cartId = await findCartId(req);
  if (cartId) await cartModel.updateItem(cartId, variantId, qty.value);
  res.redirect('/cart');
}));

router.post('/cart/remove', ah(async (req, res) => {
  const variantId = v.id(req.body.variantId);
  const cartId = await findCartId(req);
  if (variantId && cartId) await cartModel.removeItem(cartId, variantId);
  res.redirect('/cart');
}));

/* ====================================================================
   ĐẶT HÀNG [UC01][UC04][UC05]
   ==================================================================== */

router.get('/checkout', requireAuth, ah(async (req, res) => {
  const cartId = await findCartId(req);
  const [cart, addresses] = await Promise.all([
    cartId ? cartModel.getDetail(cartId) : { items: [], subtotal: 0 },
    userModel.listAddresses(req.user.id),
  ]);
  if (!cart.items.length) return res.redirect('/cart');

  res.render('shop/checkout', {
    title: 'Đặt hàng',
    cart,
    addresses,
    // SePay luôn là lựa chọn online duy nhất. Nếu thiếu URL cấu hình, service sẽ báo lỗi rõ ràng sau khi đặt hàng.
    gateway: { label: 'SePay VietQR', ready: true, key: 'sepay' },
    blocked: cart.items.some((it) => it.warning),
  });
}));

/** Kiểm tra mã giảm giá cho giỏ hiện tại (AJAX). Tổng tiền luôn tính lại từ giỏ trong CSDL. */
router.post('/checkout/apply-discount', requireAuth, ah(async (req, res) => {
  const code = v.line(req.body.discountCode, 30);
  if (!code) return res.json({ ok: false, message: 'Vui lòng nhập mã giảm giá.' });
  const cartId = await findCartId(req);
  const cart = cartId ? await cartModel.getDetail(cartId) : { items: [], subtotal: 0 };
  if (!cart.items.length) return res.json({ ok: false, message: 'Giỏ hàng trống.' });

  const discount = await discountModel.findByCode(code);
  const evl = evaluateDiscount(discount, cart.subtotal);
  if (!evl.ok) return res.json({ ok: false, message: evl.message });

  const totals = computeTotals(cart.subtotal, evl.amount);
  return res.json({
    ok: true,
    message: `Đã áp dụng mã ${discount.Code}.`,
    code: discount.Code,
    discount: totals.discountAmount,
    shippingFee: totals.shippingFee,
    total: totals.total,
    labels: {
      discount: `-${formatVnd(totals.discountAmount)}`,
      shippingFee: totals.shippingFee === 0 ? 'Miễn phí' : formatVnd(totals.shippingFee),
      total: formatVnd(totals.total),
    },
  });
}));

router.post('/checkout', requireAuth, ah(async (req, res) => {
  const b = req.body;

  // Ô đồng ý xử lý dữ liệu cá nhân KHÔNG đánh dấu sẵn; không tích thì không đặt được (kiểm tra phía server).
  if (!v.checked(b.consentData)) {
    throw new BusinessError('Bạn cần đồng ý với chính sách xử lý dữ liệu cá nhân để tiếp tục đặt hàng.', { code: 'NO_CONSENT' });
  }
  const addressId = v.id(b.addressId);
  if (!addressId) throw new BusinessError('Vui lòng chọn địa chỉ giao hàng.');

  const method = b.paymentMethod === 'ONLINE' ? 'ONLINE' : 'COD';
  const note = v.optionalLine(b.note, 'ghi chú', 500);
  if (note.error) throw new BusinessError(note.error);

  const cartId = await findCartId(req);
  if (!cartId) throw new BusinessError('Giỏ hàng trống. Hãy thêm sản phẩm trước khi đặt hàng.');

  const order = await orderService.createOrder({
    userId: req.user.id,
    cartId,
    addressId,
    discountCode: v.line(b.discountCode, 30) || null,
    paymentMethod: method,
    note: note.value,
    consentGivenAt: new Date(),
  });

  if (method === 'ONLINE') {
    try {
      const pay = await paymentSvc.startSepayQrPayment({ orderCode: order.code, userId: req.user.id });
      return res.redirect(`/payment/sepay/${encodeURIComponent(pay.orderCode)}`);
    } catch (err) {
      // Đơn đã được tạo. Cổng chưa sẵn sàng thì để khách bấm "Thanh toán" lại ở trang đơn hàng.
      return res.redirect(`/orders/${order.code}?payment=unavailable`);
    }
  }
  return res.redirect(`/orders/${order.code}?placed=1`);
}));

/* ====================================================================
   ĐƠN HÀNG CỦA TÔI [UC04]
   ==================================================================== */

const FLASH = Object.freeze({
  placed: { type: 'ok', text: 'Đặt hàng thành công. Chúng tôi sẽ xác nhận đơn sớm nhất có thể.' },
  cancelled: { type: 'ok', text: 'Đơn hàng đã được hủy.' },
  reviewed: { type: 'ok', text: 'Cảm ơn bạn đã đánh giá sản phẩm.' },
  paid: { type: 'ok', text: 'Đã nhận thanh toán của bạn. Cảm ơn bạn đã mua hàng.' },
  pending: { type: 'info', text: 'Chúng tôi đang chờ cổng thanh toán xác nhận. Trang này sẽ cập nhật khi nhận được kết quả.' },
  failed: { type: 'error', text: 'Thanh toán chưa thành công. Bạn có thể thử thanh toán lại.' },
  unavailable: { type: 'error', text: 'Đơn hàng đã được tạo nhưng chưa mở được cổng thanh toán. Bạn có thể bấm "Thanh toán online" để thử lại.' },
});

function flashFrom(query) {
  if (query.placed === '1') return FLASH.placed;
  if (query.cancelled === '1') return FLASH.cancelled;
  if (query.reviewed === '1') return FLASH.reviewed;
  const p = typeof query.payment === 'string' ? query.payment : '';
  if (p === 'cancelled') return { type: 'info', text: 'Bạn đã hủy thanh toán. Đơn hàng vẫn được giữ, bạn có thể thanh toán lại.' };
  return FLASH[p] || null;
}

router.get('/orders', requireAuth, ah(async (req, res) => {
  const page = Number.parseInt(req.query.page, 10) || 1;
  const { items, pagination } = await orderModel.listForUser(req.user.id, { page });
  res.render('shop/orders', { title: 'Đơn hàng của tôi', items, pagination });
}));

router.get('/orders/:code', requireAuth, ah(async (req, res) => {
  const order = await orderModel.getByCode(v.line(req.params.code, 30), req.user.id); // chỉ trả đơn của chính khách này
  if (!order) throw new NotFoundError('Không tìm thấy đơn hàng.');
  const gateway = registry.active();
  res.render('shop/order-detail', {
    title: `Đơn ${order.code}`,
    order,
    flash: flashFrom(req.query),
    gatewayReady: Boolean(gateway && gateway.isConfigured()),
  });
}));

router.post('/orders/:code/cancel', requireAuth, ah(async (req, res) => {
  const code = v.line(req.params.code, 30);
  await orderService.cancelByCustomer({ orderCode: code, userId: req.user.id });
  res.redirect(`/orders/${code}?cancelled=1`);
}));

/* ====================================================================
   ĐÁNH GIÁ [UC09]: chỉ khách có đơn ở trạng thái "Đã giao"
   ==================================================================== */

router.post('/reviews', requireAuth, ah(async (req, res) => {
  const b = req.body;
  const orderItemId = v.id(b.orderItemId);
  const productId = v.id(b.productId);
  const rating = v.intInRange(b.rating, 'số sao', 1, 5);
  const title = v.optionalLine(b.title, 'tiêu đề', 100);
  const comment = v.requiredLine(b.comment, 'nhận xét', 1000);
  if (!orderItemId || !productId) throw new BusinessError('Thông tin đánh giá không hợp lệ.');
  const bad = rating.error || title.error || comment.error;
  if (bad) throw new BusinessError(bad);

  await reviewModel.create({
    userId: req.user.id, orderItemId, productId,
    rating: rating.value, title: title.value, comment: comment.value,
  });

  const back = v.slug(b.backSlug || '');
  if (!back.error) return res.redirect(`/products/${back.value}?reviewed=1#reviews`);
  return res.redirect('/orders');
}));

/* ====================================================================
   THANH TOÁN ONLINE [UC06]
   ==================================================================== */

/** Bắt đầu hoặc tiếp tục thanh toán online cho một đơn đang chờ. */
router.post('/orders/:code/pay', requireAuth, ah(async (req, res) => {
  const code = v.line(req.params.code, 30);
  await paymentSvc.startSepayQrPayment({ orderCode: code, userId: req.user.id });
  res.redirect(`/payment/sepay/${encodeURIComponent(code)}`);
}));

router.get('/payment/sepay/:code', requireAuth, ah(async (req, res) => {
  const code = v.line(req.params.code, 30);
  const order = await orderModel.getByCode(code, req.user.id);
  if (!order || order.paymentMethod !== 'ONLINE') throw new NotFoundError('Không tìm thấy đơn hàng.');
  const payments = await paymentModel.listByOrder(order.id);
  const payment = payments.find((p) => p.provider === 'SEPAY' && p.status === 'PENDING') || payments.find((p) => p.provider === 'SEPAY');
  if (!payment) throw new NotFoundError('Không tìm thấy giao dịch thanh toán.');
  res.render('shop/payment-sepay', {
    title: `Thanh toán ${order.code}`, order, payment,
    sepay: { accountNumber: env.payment.sepayAccountNumber, bankName: env.payment.sepayBankName, accountName: env.payment.sepayAccountName,
      content: `${env.payment.sepayContentPrefix}${order.code}${env.payment.sepayContentSuffix}` },
  });
}));

/** Khách quay về từ cổng. Kết quả chỉ được tin khi đã xác thực (chữ ký hoặc tra cứu lại với cổng). */
router.get('/payment/:provider/return', requireAuth, ah(async (req, res) => {
  const r = await paymentSvc.handleReturn(v.line(req.params.provider, 20), { query: req.query, userId: req.user.id });
  if (r.state === 'INVALID' || !r.orderCode) return res.redirect('/orders');
  return res.redirect(`/orders/${r.orderCode}?payment=${r.state.toLowerCase()}`);
}));

router.get('/payment/:provider/cancel', requireAuth, ah(async (req, res) => {
  const r = await paymentSvc.handleReturn(v.line(req.params.provider, 20), { query: { ...req.query, cancel: 'true' }, userId: req.user.id });
  if (r.state === 'INVALID' || !r.orderCode) return res.redirect('/orders');
  return res.redirect(`/orders/${r.orderCode}?payment=${r.state === 'PAID' ? 'paid' : 'cancelled'}`);
}));

/* ---------- Cổng giả lập (chỉ khi PAYMENT_PROVIDER=mock) ---------- */

async function loadMockPayment(req) {
  if (registry.active().key !== 'mock') throw new NotFoundError();
  const pay = await paymentModel.findByRef('MOCK', v.line(req.params.ref, 40));
  if (!pay || pay.userId !== req.user.id) throw new NotFoundError('Không tìm thấy giao dịch.');
  return pay;
}

router.get('/payment/mock/:ref', requireAuth, ah(async (req, res) => {
  const pay = await loadMockPayment(req);
  res.render('shop/payment-mock', { title: 'Cổng thanh toán demo', pay, results: null });
}));

/**
 * Mô phỏng cổng gửi IPN. Server dựng thông báo và KÝ bằng MOCK_GATEWAY_SECRET (trình duyệt không bao giờ thấy khóa),
 * rồi đi qua đúng quy trình như cổng thật: kiểm tra chữ ký, so số tiền, xử lý idempotent.
 */
router.post('/payment/mock/:ref/simulate', requireAuth, ah(async (req, res) => {
  const pay = await loadMockPayment(req);
  const action = MOCK_ACTIONS.includes(req.body.action) ? req.body.action : 'success';
  const sequence = action === 'replay' ? ['success', 'success'] : [action];

  const results = [];
  for (const a of sequence) {
    const body = paymentSvc.buildMockEvent({ paymentRef: pay.paymentRef, amount: pay.amount, action: a });
    const r = await paymentSvc.handleWebhook('mock', { body, ip: req.ip });
    results.push({ action: a, outcome: r.outcome, httpStatus: r.status });
  }
  const fresh = await paymentModel.findByRef('MOCK', pay.paymentRef);
  res.render('shop/payment-mock', { title: 'Cổng thanh toán demo', pay: fresh, results });
}));

module.exports = router;
