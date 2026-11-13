'use strict';
/**
 * [UC06] Model thanh toán: truy vấn đọc và ghi nhật ký webhook.
 * Việc đổi trạng thái thanh toán (PENDING -> PAID...) nằm trong services/payment/apply.js
 * và services/orderService.js vì phải chạy chung giao dịch với đơn hàng.
 */
const db = require('../config/db');

async function listByOrder(orderId) {
  return (await db.query(
    `SELECT PaymentId AS id, Provider AS provider, PaymentRef AS paymentRef, Amount AS amount, Status AS status,
            GatewayTxnNo AS gatewayTxnNo, GatewayResponseCode AS gatewayResponseCode, CheckoutUrl AS checkoutUrl,
            ExpiresAt AS expiresAt, PaidAt AS paidAt, RefundedAt AS refundedAt, CreatedAt AS createdAt
       FROM dbo.Payments WHERE OrderId = @oid ORDER BY CreatedAt, PaymentId`, { oid: orderId })).rows;
}

/** Tìm thanh toán theo mã tham chiếu gửi sang cổng, kèm đơn hàng và chủ đơn. */
async function findByRef(provider, paymentRef) {
  return db.one(
    `SELECT p.PaymentId AS id, p.OrderId AS orderId, p.Provider AS provider, p.PaymentRef AS paymentRef,
            p.Amount AS amount, p.Status AS status, o.OrderCode AS orderCode, o.UserId AS userId, o.Status AS orderStatus
       FROM dbo.Payments p JOIN dbo.Orders o ON o.OrderId = p.OrderId
      WHERE p.Provider = @prov AND p.PaymentRef = @ref`, { prov: provider, ref: paymentRef });
}

/** Link thanh toán còn hiệu lực của đơn (để tiếp tục thanh toán mà không tạo lần thử mới). */
async function pendingCheckout(orderId, provider) {
  return db.one(
    `SELECT TOP (1) PaymentId AS id, PaymentRef AS paymentRef, CheckoutUrl AS url, ExpiresAt AS expiresAt
       FROM dbo.Payments
      WHERE OrderId = @oid AND Provider = @prov AND Status = N'PENDING' AND CheckoutUrl IS NOT NULL
        AND (ExpiresAt IS NULL OR ExpiresAt > SYSUTCDATETIME())
      ORDER BY PaymentId DESC`, { oid: orderId, prov: provider });
}

async function createSepayQr({ orderId, amount, orderCode, qrUrl }) {
  return db.tx(async (t) => {
    const existing = await t.one(
      `SELECT TOP (1) PaymentId AS id, PaymentRef AS paymentRef, CheckoutUrl AS checkoutUrl,
              Amount AS amount, Status AS status, CreatedAt AS createdAt
         FROM dbo.Payments WHERE OrderId = @oid AND Provider = N'SEPAY'
         ORDER BY PaymentId DESC`, { oid: orderId });
    if (existing && existing.status === 'PENDING') return existing;
    await t.query(`UPDATE dbo.Payments SET Status = N'CANCELLED', UpdatedAt = SYSUTCDATETIME()
                     WHERE OrderId = @oid AND Provider = N'SEPAY' AND Status = N'PENDING'`, { oid: orderId });
    const paymentRef = `SEP${Date.now()}${Math.floor(Math.random() * 1000)}`;
    const id = await t.scalar(
      `INSERT dbo.Payments (OrderId, Provider, PaymentRef, Amount, Status, CheckoutUrl)
       OUTPUT INSERTED.PaymentId VALUES (@oid, N'SEPAY', @ref, @amount, N'PENDING', @url)`,
      { oid: orderId, ref: paymentRef, amount, url: qrUrl });
    return { id, paymentRef, checkoutUrl: qrUrl, amount, status: 'PENDING', orderCode };
  });
}

async function listAdmin({ status, q, page = 1, perPage = 20 } = {}) {
  const params = { offset: Math.max(0, (page - 1) * perPage), limit: perPage };
  const where = ["p.Provider = N'SEPAY'"];
  if (status) { where.push('p.Status = @status'); params.status = status; }
  if (q) { where.push('(o.OrderCode LIKE @q OR u.Email LIKE @q OR p.PaymentRef LIKE @q)'); params.q = `%${q}%`; }
  const clause = where.join(' AND ');
  const rows = await db.query(`SELECT p.PaymentId AS id, p.PaymentRef AS paymentRef, p.Amount AS amount,
      p.Status AS status, p.GatewayTxnNo AS gatewayTxnNo, p.CheckoutUrl AS checkoutUrl,
      p.CreatedAt AS createdAt, p.PaidAt AS paidAt, o.OrderCode AS orderCode,
      u.FullName AS customerName, u.Email AS customerEmail
      FROM dbo.Payments p JOIN dbo.Orders o ON o.OrderId = p.OrderId JOIN dbo.Users u ON u.UserId = o.UserId
      WHERE ${clause} ORDER BY p.CreatedAt DESC, p.PaymentId DESC OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY`, params);
  const total = await db.scalar(`SELECT COUNT_BIG(1) FROM dbo.Payments p JOIN dbo.Orders o ON o.OrderId=p.OrderId JOIN dbo.Users u ON u.UserId=o.UserId WHERE ${clause}`, params);
  return { items: rows.rows, pagination: { page, perPage, total: Number(total || 0), pages: Math.max(1, Math.ceil(Number(total || 0) / perPage)) } };
}

/** [UC06] Ghi nhật ký mọi lần cổng gọi IPN/webhook, kể cả sai chữ ký và gửi lặp. Lỗi ghi log không được làm hỏng luồng chính. */
async function logWebhook({ provider, paymentRef, gatewayTxnNo, signatureValid, outcome, rawPayload, sourceIp }) {
  await db.query(
    `INSERT dbo.PaymentWebhookLogs (Provider, PaymentRef, GatewayTxnNo, SignatureValid, Outcome, RawPayload, SourceIp)
     VALUES (@prov, @ref, @txn, @sig, @out, @raw, @ip)`,
    {
      prov: String(provider).slice(0, 10),
      ref: paymentRef ? String(paymentRef).slice(0, 40) : null,
      txn: gatewayTxnNo ? String(gatewayTxnNo).slice(0, 64) : null,
      sig: signatureValid ? 1 : 0,
      out: String(outcome).slice(0, 30),
      raw: rawPayload ? String(rawPayload).slice(0, 4000) : null,
      ip: sourceIp ? String(sourceIp).slice(0, 64) : null,
    });
}

/** Nhật ký webhook của các lần thanh toán thuộc đơn (hiển thị cho admin). */
async function recentWebhookLogs(orderId) {
  return (await db.query(
    `SELECT TOP (20) w.LogId AS id, w.Provider AS provider, w.PaymentRef AS paymentRef, w.GatewayTxnNo AS txn,
            w.SignatureValid AS signatureValid, w.Outcome AS outcome, w.SourceIp AS ip, w.ReceivedAt AS receivedAt
       FROM dbo.PaymentWebhookLogs w
      WHERE EXISTS (SELECT 1 FROM dbo.Payments p
                     WHERE p.OrderId = @oid AND p.Provider = w.Provider AND p.PaymentRef = w.PaymentRef)
      ORDER BY w.ReceivedAt DESC, w.LogId DESC`, { oid: orderId })).rows;
}

module.exports = { listByOrder, findByRef, pendingCheckout, createSepayQr, listAdmin, logWebhook, recentWebhookLogs };
