'use strict';
/**
 * Kết nối SQL Server và các hàm truy vấn dùng chung.
 *
 * QUY ƯỚC BẢO MẬT (chống SQL Injection):
 *  - Mọi giá trị đến từ người dùng LUÔN đi qua tham số (@name), không bao giờ nối chuỗi vào câu SQL.
 *  - Phần động của câu SQL (ORDER BY, danh sách IN) chỉ lấy từ danh sách cho phép (whitelist)
 *    hoặc được sinh ra thành các tham số riêng bằng inList().
 */
const env = require('./env');
const logger = require('../utils/logger');

let sql;
if (env.db.auth === 'windows') {
  try {
    sql = require('mssql/msnodesqlv8');
  } catch (e) {
    throw new Error('DB_AUTH=windows cần cài thêm gói msnodesqlv8: chạy "npm install msnodesqlv8". Chi tiết: ' + e.message);
  }
} else {
  sql = require('mssql');
}

function buildConfig() {
  const base = {
    database: env.db.name,
    pool: { max: 10, min: 0, idleTimeoutMillis: 30000 },
    connectionTimeout: 15000,
    requestTimeout: 20000,
  };

  if (env.db.auth === 'windows') {
    if (env.db.odbcConnectionString) {
      return { ...base, connectionString: env.db.odbcConnectionString };
    }
    const server = env.db.instance ? `${env.db.server}\\${env.db.instance}` : env.db.server;
    return {
      ...base,
      server,
      options: {
        trustedConnection: true,
        encrypt: env.db.encrypt,
        trustServerCertificate: env.db.trustServerCert,
        // Cột tính toán lưu sẵn (OrderItems.LineTotal) và các chỉ mục có điều kiện đòi hỏi ARITHABORT ON khi ghi dữ liệu.
        enableArithAbort: true,
      },
    };
  }

  const cfg = {
    ...base,
    server: env.db.server,
    user: env.db.user,
    password: env.db.password,
    options: {
      encrypt: env.db.encrypt,
      trustServerCertificate: env.db.trustServerCert,
      enableArithAbort: true,
      useUTC: true, // thời gian lưu ở CSDL là UTC (SYSUTCDATETIME)
    },
  };
  if (env.db.instance) cfg.options.instanceName = env.db.instance;
  else cfg.port = env.db.port;
  return cfg;
}

let poolPromise = null;

function getPool() {
  if (!poolPromise) {
    const pool = new sql.ConnectionPool(buildConfig());
    pool.on('error', (err) => logger.error('Lỗi pool SQL Server:', err.message));
    poolPromise = pool.connect().catch((err) => {
      poolPromise = null;
      throw err;
    });
  }
  return poolPromise;
}

async function close() {
  if (!poolPromise) return;
  const pool = await poolPromise;
  poolPromise = null;
  await pool.close();
}

/** Chọn kiểu tham số theo giá trị. Chuỗi được gom nhóm độ dài để SQL Server dùng lại kế hoạch thực thi. */
function infer(v) {
  if (v === null || v === undefined) return [sql.NVarChar(4000), null];
  if (typeof v === 'boolean') return [sql.Bit, v];
  if (typeof v === 'number') {
    if (!Number.isFinite(v)) throw new TypeError('Tham số số không hợp lệ');
    if (Number.isInteger(v)) return [v >= -2147483648 && v <= 2147483647 ? sql.Int : sql.BigInt, v];
    return [sql.Float, v];
  }
  if (v instanceof Date) return [sql.DateTime2, v];
  if (typeof v === 'string') {
    const len = v.length;
    if (len <= 50) return [sql.NVarChar(50), v];
    if (len <= 255) return [sql.NVarChar(255), v];
    if (len <= 4000) return [sql.NVarChar(4000), v];
    return [sql.NVarChar(sql.MAX), v];
  }
  throw new TypeError('Kiểu tham số không được hỗ trợ: ' + typeof v);
}

function bind(request, params) {
  for (const [name, raw] of Object.entries(params || {})) {
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) throw new Error('Tên tham số SQL không hợp lệ: ' + name);
    if (raw && typeof raw === 'object' && !(raw instanceof Date) && 'type' in raw && 'value' in raw) {
      request.input(name, raw.type, raw.value);
    } else {
      const [type, value] = infer(raw);
      request.input(name, type, value);
    }
  }
}

async function run(makeRequest, text, params) {
  const request = makeRequest();
  bind(request, params);
  const result = await request.query(text);
  return {
    rows: result.recordset || [],
    rowsAffected: result.rowsAffected || [],
    recordsets: result.recordsets || [],
  };
}

function makeApi(makeRequest) {
  const query = (text, params) => run(makeRequest, text, params);
  return {
    query,
    async one(text, params) {
      const r = await query(text, params);
      return r.rows[0] || null;
    },
    async scalar(text, params) {
      const r = await query(text, params);
      const row = r.rows[0];
      if (!row) return null;
      const keys = Object.keys(row);
      return keys.length ? row[keys[0]] : null;
    },
  };
}

async function pooledRequestFactory() {
  const pool = await getPool();
  return () => pool.request();
}

/** Truy vấn dùng pool kết nối. */
async function query(text, params) {
  const make = await pooledRequestFactory();
  return makeApi(make).query(text, params);
}
async function one(text, params) {
  const make = await pooledRequestFactory();
  return makeApi(make).one(text, params);
}
async function scalar(text, params) {
  const make = await pooledRequestFactory();
  return makeApi(make).scalar(text, params);
}

/**
 * Chạy một nhóm lệnh trong một giao dịch. fn nhận đối tượng t có query/one/scalar.
 * Có lỗi (kể cả BusinessError) thì rollback toàn bộ, không để lại dữ liệu dở dang.
 */
async function tx(fn) {
  const pool = await getPool();
  const transaction = new sql.Transaction(pool);
  await transaction.begin();
  const t = makeApi(() => new sql.Request(transaction));
  try {
    const result = await fn(t);
    await transaction.commit();
    return result;
  } catch (err) {
    try {
      await transaction.rollback();
    } catch (_) {
      /* giao dịch đã bị SQL Server hủy trước đó, bỏ qua */
    }
    throw err;
  }
}

/** Tạo danh sách tham số cho mệnh đề IN. Danh sách rỗng trả về NULL để IN (NULL) không khớp dòng nào. */
function inList(prefix, values) {
  const params = {};
  const names = (values || []).map((v, i) => {
    const n = `${prefix}${i}`;
    params[n] = v;
    return '@' + n;
  });
  return { clause: names.length ? names.join(', ') : 'NULL', params };
}

function errNumber(err) {
  if (!err) return 0;
  return err.number || (err.originalError && (err.originalError.number || (err.originalError.info && err.originalError.info.number))) || 0;
}

/** 2627 = vi phạm UNIQUE constraint, 2601 = vi phạm unique index. */
function isUniqueViolation(err) {
  const n = errNumber(err);
  return n === 2627 || n === 2601;
}

/** Diễn giải lỗi kết nối bằng tiếng Việt kèm gợi ý cách sửa. */
function describeConnectError(err) {
  const code = err && err.code;
  const msg = String((err && err.message) || err);
  const n = errNumber(err);
  const hints = [];
  if (code === 'ELOGIN' || /Login failed/i.test(msg)) {
    hints.push('Đăng nhập SQL Server thất bại. Kiểm tra DB_USER và DB_PASSWORD trong file .env.');
    hints.push('Nếu dùng tài khoản SQL (ví dụ ivy_app), SQL Server phải bật chế độ "SQL Server and Windows Authentication mode" rồi khởi động lại dịch vụ.');
  } else if (n === 4060 || /Cannot open database/i.test(msg)) {
    hints.push(`Không mở được CSDL "${env.db.name}". Hãy chạy sql/01_schema.sql và sql/02_seed.sql trong SSMS trước, hoặc kiểm tra DB_NAME.`);
    hints.push('Tài khoản đăng nhập cần có quyền truy cập CSDL này (xem README, phần tạo tài khoản ivy_app).');
  } else if (/self[- ]signed|certificate/i.test(msg)) {
    hints.push('Chứng chỉ SSL của SQL Server không được tin cậy. Đặt DB_TRUST_SERVER_CERT=true trong .env (chỉ dùng khi chạy trên máy cá nhân).');
  } else if (code === 'ESOCKET' || code === 'ETIMEOUT' || code === 'ECONNREFUSED' || code === 'EINSTLOOKUP' || /Failed to connect|ECONNREFUSED|ENOTFOUND|timeout/i.test(msg)) {
    hints.push(`Không kết nối được tới SQL Server tại "${env.db.server}${env.db.instance ? '\\' + env.db.instance : ':' + env.db.port}".`);
    hints.push('Mở SQL Server Configuration Manager: bật giao thức TCP/IP cho instance, khởi động lại dịch vụ SQL Server.');
    hints.push('Instance có tên (ví dụ SQLEXPRESS): đặt DB_INSTANCE=SQLEXPRESS và bật dịch vụ SQL Server Browser, hoặc đặt cổng cố định rồi điền DB_PORT.');
    hints.push('Kiểm tra DB_SERVER, DB_PORT và tường lửa Windows (cho phép cổng 1433).');
  } else {
    hints.push('Xem thông báo gốc bên dưới và đối chiếu mục "Cấu hình kết nối CSDL" trong README.');
  }
  return { message: msg, hints };
}

module.exports = {
  sql,
  getPool,
  close,
  query,
  one,
  scalar,
  tx,
  inList,
  errNumber,
  isUniqueViolation,
  describeConnectError,
};
