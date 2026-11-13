'use strict';
/**
 * Đọc và kiểm tra biến môi trường (file .env). Mọi cấu hình của ứng dụng đi qua file này.
 * Thiếu cấu hình bắt buộc khi chạy production sẽ dừng ứng dụng ngay, không chạy với giá trị yếu.
 */
const path = require('path');
const crypto = require('crypto');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const warnings = [];

function str(name, def = '') {
  const v = process.env[name];
  return v === undefined || v === '' ? def : String(v).trim();
}

function bool(name, def = false) {
  const v = str(name, '');
  if (v === '') return def;
  return ['1', 'true', 'yes', 'on'].includes(v.toLowerCase());
}

function int(name, def) {
  const v = str(name, '');
  if (v === '') return def;
  const n = Number.parseInt(v, 10);
  if (!Number.isFinite(n)) {
    warnings.push(`Biến ${name} phải là số nguyên, đang dùng giá trị mặc định ${def}.`);
    return def;
  }
  return n;
}

const nodeEnv = str('NODE_ENV', 'development');
const isProd = nodeEnv === 'production';

let sessionSecret = str('SESSION_SECRET');
if (sessionSecret.length < 32) {
  if (isProd) throw new Error('SESSION_SECRET phải có ít nhất 32 ký tự khi chạy production.');
  warnings.push('SESSION_SECRET chưa đặt hoặc quá ngắn. Đang dùng khóa tạm ngẫu nhiên, phiên đăng nhập sẽ mất mỗi khi khởi động lại server.');
  sessionSecret = crypto.randomBytes(32).toString('hex');
}

const provider = str('PAYMENT_PROVIDER', 'mock').toLowerCase();
if (!['mock', 'payos', 'vnpay'].includes(provider)) {
  throw new Error(`PAYMENT_PROVIDER="${provider}" không hợp lệ. Chọn một trong: mock, payos, vnpay.`);
}
if (isProd && provider === 'mock') {
  throw new Error('Không được dùng cổng thanh toán giả lập (PAYMENT_PROVIDER=mock) khi chạy production.');
}

let mockSecret = str('MOCK_GATEWAY_SECRET');
if (!mockSecret) mockSecret = 'dev-only-mock-secret-khong-dung-o-production';

const dbAuth = str('DB_AUTH', 'sql').toLowerCase();
if (!['sql', 'windows'].includes(dbAuth)) {
  throw new Error(`DB_AUTH="${dbAuth}" không hợp lệ. Chọn sql hoặc windows.`);
}

const port = int('PORT', 3000);
const appBaseUrl = str('APP_BASE_URL', `http://localhost:${port}`).replace(/\/+$/, '');

module.exports = Object.freeze({
  nodeEnv,
  isProd,
  port,
  appBaseUrl,
  sessionSecret,
  cookieSecure: bool('COOKIE_SECURE', false),
  trustProxy: int('TRUST_PROXY', 0),
  db: Object.freeze({
    auth: dbAuth,
    server: str('DB_SERVER', 'localhost'),
    port: int('DB_PORT', 1433),
    instance: str('DB_INSTANCE'),
    name: str('DB_NAME', 'IvyModaShop'),
    user: str('DB_USER'),
    password: process.env.DB_PASSWORD || '',
    encrypt: bool('DB_ENCRYPT', false),
    trustServerCert: bool('DB_TRUST_SERVER_CERT', true),
    odbcConnectionString: str('DB_ODBC_CONNECTION_STRING'),
  }),
  payment: Object.freeze({
    provider,
    mockSecret,
    sepayQrUrl: str('SEPAY_QR_URL', 'https://qr.sepay.vn/img'),
    sepayAccountNumber: str('SEPAY_ACCOUNT_NUMBER'),
    sepayBankName: str('SEPAY_BANK_NAME'),
    sepayAccountName: str('SEPAY_ACCOUNT_NAME'),
    sepayContentPrefix: str('SEPAY_CONTENT_PREFIX', 'HD36-'),
    sepayContentSuffix: str('SEPAY_CONTENT_SUFFIX'),
    payos: Object.freeze({
      apiUrl: str('PAYOS_API_URL', 'https://api-merchant.payos.vn').replace(/\/+$/, ''),
      clientId: str('PAYOS_CLIENT_ID'),
      apiKey: str('PAYOS_API_KEY'),
      checksumKey: str('PAYOS_CHECKSUM_KEY'),
    }),
    vnpay: Object.freeze({
      url: str('VNP_URL', 'https://sandbox.vnpayment.vn/paymentv2/vpcpay.html'),
      tmnCode: str('VNP_TMN_CODE'),
      hashSecret: str('VNP_HASH_SECRET'),
    }),
  }),
  warnings,
});
