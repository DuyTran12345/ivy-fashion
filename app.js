'use strict';
/**
 * Điểm khởi động ứng dụng Express.
 *
 * Thứ tự middleware (quan trọng):
 *   1. Bảo mật HTTP header (Helmet + CSP chặt: không script/style nội tuyến).
 *   2. File tĩnh (trước phiên và giới hạn tần suất, để CSS/ảnh không kéo theo truy vấn CSDL).
 *   3. Webhook IPN của cổng thanh toán [UC06]: gắn TRƯỚC phiên và CSRF vì cổng không có cookie,
 *      mỗi thông báo được xác thực bằng chữ ký (checksum).
 *   4. Giới hạn tần suất, cookie, phiên, nạp tài khoản và giỏ hàng, rồi CSRF.
 *   5. Route ứng dụng, 404, trình xử lý lỗi.
 * Mất kết nối CSDL không làm server dừng: các trang cần CSDL báo lỗi 500, kèm hướng dẫn trong log.
 */
const express = require('express');
const path = require('path');
const session = require('express-session');
const cookieParser = require('cookie-parser');
const helmet = require('helmet');

const env = require('./config/env');
const shop = require('./config/shop');
const db = require('./config/db');
const logger = require('./utils/logger');
const S = require('./utils/orderStatus');
const { formatVnd, percentOff, maskName } = require('./utils/format');
const { formatDate, formatDateTime, toDateInput, toDateTimeLocal } = require('./utils/time');
const { discountState } = require('./utils/pricing');
const { safeJson } = require('./utils/security');
const { toQuery } = require('./utils/query');
const { globalLimiter } = require('./middleware/rateLimit');
const { attachUser } = require('./middleware/auth');
const { readGuest, attachCartCount } = require('./middleware/cartContext');
const { csrf } = require('./middleware/csrf');
const { notFound, handler: errorHandler } = require('./middleware/errorHandler');
const categoryModel = require('./models/categoryModel');

function createApp() {
  const app = express();
  app.disable('x-powered-by');
  if (env.trustProxy) app.set('trust proxy', env.trustProxy);
  app.set('view engine', 'ejs');
  app.set('views', path.join(__dirname, 'views'));
  app.set('query parser', 'simple'); // ?a[b]=1 không bị biến thành object lồng nhau

  // Biến dùng chung cho mọi view. Giá trị theo từng request ghi đè bằng res.locals ở các middleware sau.
  // Đặt mặc định ở đây để trang lỗi vẫn hiển thị được kể cả khi lỗi xảy ra rất sớm.
  Object.assign(app.locals, {
    shop, S, safeJson, discountState, toQuery, percentOff, maskName,
    vnd: formatVnd, fmtDate: formatDate, fmtDateTime: formatDateTime, inputDate: toDateInput, inputDateTime: toDateTimeLocal,
    appBaseUrl: env.appBaseUrl, isProd: env.isProd,
    title: shop.name, user: null, cartCount: 0, csrfToken: '', navCategories: [], query: {}, currentPath: '/',
  });

  /* ---------- 1. Bảo mật HTTP header ---------- */
  app.use(helmet({
    contentSecurityPolicy: {
      useDefaults: true,
      directives: {
        'default-src': ["'self'"],
        'script-src': ["'self'"], // không có script nội tuyến: chống XSS ngay cả khi lọt dữ liệu độc hại vào trang
        'style-src': ["'self'", 'https://fonts.googleapis.com'],
        'font-src': ["'self'", 'https://fonts.gstatic.com'],
        'img-src': ["'self'", 'data:', 'https:'],
        'connect-src': ["'self'"],
        'object-src': ["'none'"],
        'base-uri': ["'self'"],
        'frame-ancestors': ["'none'"],
        // Sau khi gửi form đặt hàng, trình duyệt có thể bị chuyển hướng sang trang của cổng thanh toán (https).
        'form-action': ["'self'", 'https:'],
        // Mặc định của helmet là nâng cấp mọi tài nguyên lên https, làm hỏng CSS/JS khi chạy http://localhost.
        'upgrade-insecure-requests': env.cookieSecure ? [] : null,
      },
    },
    crossOriginEmbedderPolicy: false,
  }));

  app.get('/healthz', (req, res) => res.json({ ok: true }));
  app.get('/favicon.ico', (req, res) => res.status(204).end());

  /* ---------- 2. File tĩnh ---------- */
  app.use(express.static(path.join(__dirname, 'public'), { maxAge: env.isProd ? '7d' : 0, index: false }));

  /* ---------- 3. [UC06] Webhook IPN: trước phiên, CSRF và giới hạn tần suất ---------- */
  app.use(require('./routes/paymentHooks'));

  /* ---------- 4. Phiên, người dùng, giỏ hàng, CSRF ---------- */
  app.use((req, res, next) => {
    res.locals.query = req.query || {};
    res.locals.currentPath = req.path;
    next();
  });
  app.use(express.urlencoded({ extended: false, limit: '1mb' }));
  app.use(globalLimiter);
  app.use(cookieParser(env.sessionSecret));
  app.use(session({
    name: 'ivy.sid',
    secret: env.sessionSecret,
    resave: false,
    saveUninitialized: false,
    cookie: { httpOnly: true, secure: env.cookieSecure, sameSite: 'lax', maxAge: 1000 * 60 * 60 * 24 * 14 },
  }));
  app.use(attachUser);
  app.use(readGuest);
  app.use(attachCartCount);
  app.use(csrf);
  app.use(async (req, res, next) => {
    try {
      res.locals.navCategories = await categoryModel.tree();
    } catch (_) {
      /* giữ mặc định [], trang vẫn hiển thị được */
    }
    next();
  });

  /* ---------- 5. Route ứng dụng ---------- */
  app.use('/', require('./routes/pages'));
  app.use('/', require('./routes/auth'));
  app.use('/', require('./routes/shop'));
  app.use('/admin', require('./routes/admin')); // guard requireAdmin nằm trong routes/admin/index.js

  app.use(notFound);
  app.use(errorHandler);
  return app;
}

async function start() {
  for (const w of env.warnings) logger.warn('[.env]', w);

  try {
    await db.getPool();
    logger.info(`Đã kết nối CSDL ${env.db.name} tại ${env.db.server}${env.db.instance ? `\\${env.db.instance}` : `:${env.db.port}`}`);
  } catch (err) {
    const info = db.describeConnectError(err);
    logger.error('Không kết nối được CSDL:', info.message);
    for (const hint of info.hints) logger.error('  gợi ý:', hint);
    logger.warn('Server vẫn khởi động. Các trang cần CSDL sẽ báo lỗi cho tới khi kết nối được. Sửa .env rồi chạy lại.');
  }

  const app = createApp();
  const server = app.listen(env.port, () => {
    logger.info(`${shop.name} đang chạy tại http://localhost:${env.port} (${env.nodeEnv}, thanh toán: ${env.payment.provider})`);
  });

  const shutdown = () => {
    logger.info('Đang tắt server...');
    server.close(() => db.close().finally(() => process.exit(0)));
    setTimeout(() => process.exit(0), 5000).unref();
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

process.on('unhandledRejection', (reason) => logger.error('Promise bị từ chối mà không được xử lý:', reason));

if (require.main === module) {
  start().catch((err) => {
    logger.error('Khởi động thất bại:', err.stack || err);
    process.exit(1);
  });
}

module.exports = { createApp, start };
