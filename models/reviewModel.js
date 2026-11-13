'use strict';
/**
 * [UC09] Model đánh giá sản phẩm: CHỈ khách có đơn ở trạng thái "Đã giao" mới được đánh giá.
 *
 * Hai lớp kiểm tra:
 *   1. checkCanReview: kiểm tra ở ứng dụng để báo lỗi tiếng Việt rõ ràng.
 *   2. Trigger TR_Reviews_OnlyDeliveredOrders ở CSDL: chặn cả khi ai đó ghi thẳng vào bảng.
 * Mỗi dòng hàng chỉ đánh giá được một lần (UNIQUE OrderItemId).
 */
const db = require('../config/db');
const { BusinessError } = require('../utils/errors');
const { paginate } = require('../utils/pagination');

async function listVisible(productId, { page = 1, perPage = 5 } = {}) {
  const total = await db.scalar('SELECT COUNT(*) AS total FROM dbo.Reviews WHERE ProductId = @pid AND IsVisible = 1', { pid: productId });
  const pagination = paginate(total || 0, page, perPage);
  const items = (await db.query(
    `SELECT r.ReviewId AS id, r.Rating AS rating, r.Title AS title, r.Comment AS comment, r.CreatedAt AS createdAt,
            u.FullName AS fullName, oi.Size AS size, oi.ColorName AS color
       FROM dbo.Reviews r
       JOIN dbo.Users u ON u.UserId = r.UserId
       JOIN dbo.OrderItems oi ON oi.OrderItemId = r.OrderItemId
      WHERE r.ProductId = @pid AND r.IsVisible = 1
      ORDER BY r.CreatedAt DESC, r.ReviewId DESC
     OFFSET @off ROWS FETCH NEXT @lim ROWS ONLY`,
    { pid: productId, off: pagination.offset, lim: perPage })).rows;
  return { items, pagination };
}

async function summary(productId) {
  const rows = (await db.query(
    'SELECT Rating AS rating, COUNT(*) AS cnt FROM dbo.Reviews WHERE ProductId = @pid AND IsVisible = 1 GROUP BY Rating',
    { pid: productId })).rows;
  const distribution = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };
  let total = 0;
  let sum = 0;
  for (const r of rows) {
    distribution[r.rating] = r.cnt;
    total += r.cnt;
    sum += r.rating * r.cnt;
  }
  return { total, average: total ? Math.round((sum / total) * 10) / 10 : 0, distribution };
}

/** Các dòng hàng của khách đối với sản phẩm này mà đơn ĐÃ GIAO và chưa được đánh giá. */
async function eligibleForProduct(userId, productId) {
  return (await db.query(
    `SELECT oi.OrderItemId AS orderItemId, oi.Size AS size, oi.ColorName AS color,
            o.OrderCode AS orderCode, o.DeliveredAt AS deliveredAt
       FROM dbo.OrderItems oi JOIN dbo.Orders o ON o.OrderId = oi.OrderId
      WHERE o.UserId = @uid AND oi.ProductId = @pid AND o.Status = N'DELIVERED'
        AND NOT EXISTS (SELECT 1 FROM dbo.Reviews r WHERE r.OrderItemId = oi.OrderItemId)
      ORDER BY o.DeliveredAt DESC, oi.OrderItemId DESC`, { uid: userId, pid: productId })).rows;
}

/** Ném BusinessError nếu khách chưa đủ điều kiện đánh giá dòng hàng này. */
async function checkCanReview({ userId, orderItemId, productId }) {
  const row = await db.one(
    `SELECT o.Status AS status, o.UserId AS userId, oi.ProductId AS productId
       FROM dbo.OrderItems oi JOIN dbo.Orders o ON o.OrderId = oi.OrderId
      WHERE oi.OrderItemId = @id`, { id: orderItemId });
  if (!row) throw new BusinessError('Không tìm thấy sản phẩm trong đơn hàng của bạn.', { code: 'NOT_FOUND' });
  if (row.userId !== userId) throw new BusinessError('Bạn chỉ được đánh giá sản phẩm trong đơn hàng của chính mình.', { code: 'NOT_OWNER' });
  if (row.productId !== productId) throw new BusinessError('Đánh giá không khớp với sản phẩm đã mua.', { code: 'MISMATCH' });
  if (row.status !== 'DELIVERED') throw new BusinessError('Chỉ được đánh giá sau khi đơn hàng ở trạng thái "Đã giao".', { code: 'NOT_DELIVERED' });
  const existing = await db.scalar('SELECT TOP (1) 1 AS x FROM dbo.Reviews WHERE OrderItemId = @id', { id: orderItemId });
  if (existing) throw new BusinessError('Bạn đã đánh giá sản phẩm này rồi.', { code: 'ALREADY_REVIEWED' });
}

async function create({ userId, orderItemId, productId, rating, title, comment }) {
  await checkCanReview({ userId, orderItemId, productId });
  try {
    // Không dùng OUTPUT vì bảng có trigger. Không bọc giao dịch vì trigger có thể hủy câu lệnh.
    await db.query(
      `INSERT dbo.Reviews (ProductId, UserId, OrderItemId, Rating, Title, Comment)
         VALUES (@pid, @uid, @oi, @rating, @title, @comment)`,
      { pid: productId, uid: userId, oi: orderItemId, rating, title: title || null, comment });
  } catch (err) {
    if (db.isUniqueViolation(err)) throw new BusinessError('Bạn đã đánh giá sản phẩm này rồi.', { code: 'ALREADY_REVIEWED' });
    if (db.errNumber(err) === 50001) {
      throw new BusinessError('Chỉ khách hàng có đơn ở trạng thái "Đã giao" mới được đánh giá sản phẩm này.', { code: 'TRIGGER_DENIED' });
    }
    throw err;
  }
}

module.exports = { listVisible, summary, eligibleForProduct, checkCanReview, create };
