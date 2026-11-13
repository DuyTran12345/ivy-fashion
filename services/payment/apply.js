'use strict';
/**
 * [UC06] Áp dụng một sự kiện thanh toán (đã qua kiểm tra chữ ký) vào CSDL, trong MỘT giao dịch do bên gọi mở.
 * Nhận đối tượng giao dịch `t` (có one/scalar/query) để kiểm thử được bằng CSDL giả, không cần SQL Server.
 *
 * Chống xử lý lặp (idempotency) có ba lớp:
 *   1. Khóa dòng thanh toán (UPDLOCK): hai thông báo cùng lúc phải xếp hàng, thông báo sau thấy trạng thái đã PAID.
 *   2. decide(): thông báo thành công đến sau khi đã PAID cho ra action NONE.
 *   3. UPDATE có điều kiện trạng thái, cộng chỉ mục duy nhất UX_Payments_OnePaidPerOrder và UX_Payments_GatewayTxn ở CSDL.
 */
const { decide } = require('../../utils/payment/decide');

/**
 * ev = { provider, paymentRef, success, amount, txnNo, responseCode }
 * Trả về { outcome, paymentId, orderId, orderCode, userId, needsRefund }.
 */
async function applyEventInTx(t, ev) {
  const payment = await t.one(
    `SELECT p.PaymentId AS id, p.OrderId AS orderId, p.Amount AS amount, p.Status AS status, p.GatewayTxnNo AS gatewayTxnNo,
            o.OrderCode AS orderCode, o.UserId AS userId, o.Status AS orderStatus
       FROM dbo.Payments AS p WITH (UPDLOCK, ROWLOCK)
       JOIN dbo.Orders AS o ON o.OrderId = p.OrderId
      WHERE p.Provider = @prov AND p.PaymentRef = @ref`,
    { prov: ev.provider, ref: ev.paymentRef });

  if (!payment) {
    const d = decide(null, ev);
    return { outcome: d.outcome, paymentId: null, orderId: null, orderCode: null, userId: null, needsRefund: false };
  }

  const canBecomePaid = payment.status !== 'PAID' && payment.status !== 'REFUNDED';
  const otherPaid = ev.success && canBecomePaid
    ? Boolean(await t.scalar(
      'SELECT TOP (1) 1 AS x FROM dbo.Payments WHERE OrderId = @oid AND PaymentId <> @pid AND Status = N\'PAID\'',
      { oid: payment.orderId, pid: payment.id }))
    : false;
  const orderClosed = payment.orderStatus === 'CANCELLED' || payment.orderStatus === 'RETURNED';

  const decision = decide(payment, ev, { otherPaid, orderClosed });
  let outcome = decision.outcome;

  if (decision.action === 'MARK_PAID') {
    const r = await t.query(
      `UPDATE dbo.Payments SET Status = N'PAID', GatewayTxnNo = @txn, GatewayResponseCode = @rc,
              PaidAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
        WHERE PaymentId = @id AND Status IN (N'PENDING', N'FAILED', N'CANCELLED')`,
      {
        id: payment.id,
        txn: ev.txnNo ? String(ev.txnNo).slice(0, 64) : null,
        rc: ev.responseCode ? String(ev.responseCode).slice(0, 20) : null,
      });
    if (!((r.rowsAffected[0] || 0) > 0)) {
      outcome = 'DUPLICATE'; // một thông báo khác đã xử lý xong ngay trước đó
    } else {
      const note = orderClosed
        ? 'Nhận được thanh toán online sau khi đơn đã đóng. Cần hoàn tiền cho khách.'
        : 'Đã nhận thanh toán online.';
      await t.query(
        `INSERT dbo.OrderStatusHistory (OrderId, FromStatus, ToStatus, ChangedByUserId, Note)
           VALUES (@oid, @st, @st, NULL, @note)`,
        { oid: payment.orderId, st: payment.orderStatus, note });
    }
  } else if (decision.action === 'MARK_FAILED') {
    await t.query(
      `UPDATE dbo.Payments SET Status = N'FAILED', GatewayResponseCode = @rc, UpdatedAt = SYSUTCDATETIME()
        WHERE PaymentId = @id AND Status = N'PENDING'`,
      { id: payment.id, rc: ev.responseCode ? String(ev.responseCode).slice(0, 20) : null });
  }

  return {
    outcome,
    paymentId: payment.id,
    orderId: payment.orderId,
    orderCode: payment.orderCode,
    userId: payment.userId,
    needsRefund: outcome === 'PAID_ORDER_CLOSED',
  };
}

module.exports = { applyEventInTx };
