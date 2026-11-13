'use strict';
/**
 * [UC06] Endpoint nhận IPN/webhook từ cổng thanh toán.
 *
 * Gắn TRƯỚC phiên, CSRF và giới hạn tần suất (xem app.js), vì:
 *   - cổng thanh toán không có cookie phiên và không có mã CSRF;
 *   - mỗi thông báo được xác thực bằng CHỮ KÝ (checksum), không phải bằng đăng nhập.
 * Thông báo sai chữ ký bị từ chối và vẫn được ghi nhật ký. Thông báo gửi lặp được xử lý idempotent.
 * Lỗi hệ thống (ví dụ CSDL tạm thời không truy cập được) trả 500 để cổng gửi lại sau.
 */
const express = require('express');
const ah = require('../utils/asyncHandler');
const logger = require('../utils/logger');
const paymentSvc = require('../services/paymentService');

const router = express.Router();
const jsonBody = express.json({ type: () => true, limit: '64kb' });

function send(res, result) {
  res.status(result.status).json(result.json);
}

/** VNPay gọi IPN bằng GET, các tham số vnp_* nằm trên URL. */
router.get('/payment/vnpay/ipn', ah(async (req, res) => {
  send(res, await paymentSvc.handleWebhook('vnpay', { body: null, query: req.query, ip: req.ip }));
}));

/** payOS và cổng giả lập gọi bằng POST JSON. */
router.post('/payment/:provider/ipn', jsonBody, ah(async (req, res) => {
  const provider = String(req.params.provider).slice(0, 20);
  send(res, await paymentSvc.handleWebhook(provider, { body: req.body, query: req.query, ip: req.ip }));
}));

// eslint-disable-next-line no-unused-vars
router.use((err, req, res, next) => {
  const status = err && err.status >= 400 && err.status < 600 ? err.status : 500;
  if (status >= 500) logger.error('Lỗi khi xử lý webhook thanh toán:', err && err.stack ? err.stack : err);
  res.status(status).json({ ok: false });
});

module.exports = router;
