'use strict';
const express = require('express');
const ah = require('../../utils/asyncHandler');
const v = require('../../utils/validate');
const paymentModel = require('../../models/paymentModel');
const { toQuery } = require('../../utils/query');

const router = express.Router();
router.get('/payments', ah(async (req, res) => {
  const page = Number.parseInt(req.query.page, 10) || 1;
  const status = ['PENDING', 'PAID', 'FAILED', 'CANCELLED', 'REFUNDED'].includes(req.query.status) ? req.query.status : '';
  const q = typeof req.query.q === 'string' ? v.line(req.query.q, 100) : '';
  const result = await paymentModel.listAdmin({ page, status: status || null, q: q || null });
  res.render('admin/payments', { title: 'Lịch sử giao dịch', items: result.items, pagination: result.pagination, filters: { status, q }, baseQuery: toQuery({ status, q }) });
}));
module.exports = router;
