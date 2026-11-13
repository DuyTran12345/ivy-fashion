'use strict';
/** Danh sách cổng thanh toán và cổng đang dùng (chọn bằng PAYMENT_PROVIDER trong .env). */
const env = require('../../config/env');
const { createMockProvider } = require('./providers/mock');
const { createPayosProvider } = require('./providers/payos');
const { createVnpayProvider } = require('./providers/vnpay');

const providers = Object.freeze({
  mock: createMockProvider({ secret: env.payment.mockSecret }),
  payos: createPayosProvider(env.payment.payos),
  vnpay: createVnpayProvider(env.payment.vnpay),
});

function active() {
  return providers[env.payment.provider];
}

function get(key) {
  return Object.prototype.hasOwnProperty.call(providers, key) ? providers[key] : null;
}

module.exports = { active, get };
