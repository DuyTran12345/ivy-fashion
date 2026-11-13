'use strict';
/**
 * Model sản phẩm: danh sách (tìm kiếm, lọc theo giá/size/màu, sắp xếp), chi tiết, và quản trị.
 *
 * BẢO MẬT: mọi giá trị người dùng nhập đi qua tham số (@name). Phần ORDER BY lấy từ danh sách
 * cho phép (SORTS) nên không thể chèn SQL. Ô tìm kiếm được thoát ký tự LIKE (% _ [ \).
 */
const db = require('../config/db');
const shop = require('../config/shop');
const { escapeLike } = require('../utils/security');
const { slugify } = require('../utils/slug');
const { paginate } = require('../utils/pagination');
const { BusinessError } = require('../utils/errors');

const SORTS = Object.freeze({
  newest: 'p.CreatedAt DESC, p.ProductId DESC',
  bestseller: 'sold.Qty DESC, p.CreatedAt DESC, p.ProductId DESC',
  price_asc: 'agg.MinPrice ASC, p.ProductId DESC',
  price_desc: 'agg.MinPrice DESC, p.ProductId DESC',
  name: 'p.Name ASC, p.ProductId ASC',
});

const SORT_LABELS = Object.freeze({
  newest: 'Mới nhất',
  bestseller: 'Bán chạy',
  price_asc: 'Giá tăng dần',
  price_desc: 'Giá giảm dần',
  name: 'Tên A - Z',
});

// "Bán chạy" tính theo số lượng ở các đơn đã xác nhận, đang giao hoặc đã giao.
const SOLD_APPLY = `
  OUTER APPLY (
    SELECT COALESCE(SUM(oi.Quantity), 0) AS Qty
      FROM dbo.OrderItems oi JOIN dbo.Orders o ON o.OrderId = oi.OrderId
     WHERE oi.ProductId = p.ProductId AND o.Status IN (N'CONFIRMED', N'SHIPPING', N'DELIVERED')
  ) sold`;

const BASE_FROM = `
  FROM dbo.Products p
  JOIN dbo.Categories c ON c.CategoryId = p.CategoryId
  LEFT JOIN dbo.Categories pc ON pc.CategoryId = c.ParentId
  CROSS APPLY (
    SELECT MIN(v.Price) AS MinPrice, MAX(v.Price) AS MaxPrice,
           COALESCE(SUM(v.StockQuantity), 0) AS TotalStock, COUNT(*) AS VariantCount
      FROM dbo.ProductVariants v
     WHERE v.ProductId = p.ProductId AND v.IsActive = 1
  ) agg`;

const LIST_APPLY = `
  OUTER APPLY (
    SELECT TOP (1) v.CompareAtPrice AS CompareAt
      FROM dbo.ProductVariants v
     WHERE v.ProductId = p.ProductId AND v.IsActive = 1
     ORDER BY v.Price ASC, v.VariantId ASC
  ) cmp
  OUTER APPLY (
    SELECT TOP (1) i.ImageUrl FROM dbo.ProductImages i WHERE i.ProductId = p.ProductId ORDER BY i.SortOrder, i.ImageId
  ) img1
  OUTER APPLY (
    SELECT i.ImageUrl FROM dbo.ProductImages i WHERE i.ProductId = p.ProductId ORDER BY i.SortOrder, i.ImageId
     OFFSET 1 ROWS FETCH NEXT 1 ROWS ONLY
  ) img2`;

/**
 * filters: { q, category (slug), minPrice, maxPrice, sizes[], colors[], onSale, featured, excludeId }
 * Trả về { where, params } dùng chung cho câu đếm và câu lấy trang để hai câu luôn khớp nhau.
 */
function buildFilter(f = {}) {
  const params = {};
  const where = [
    'p.IsActive = 1',
    'c.IsActive = 1',
    '(pc.CategoryId IS NULL OR pc.IsActive = 1)',
    'agg.VariantCount > 0',
  ];

  if (f.q) {
    params.q = `%${escapeLike(f.q)}%`;
    let cond = `p.Name COLLATE Latin1_General_100_CI_AI LIKE @q ESCAPE '\\' OR p.ProductCode LIKE @q ESCAPE '\\'`;
    // So khớp thêm với slug không dấu, để gõ "dam" vẫn ra "Đầm" (chữ đ không tự bỏ dấu theo collation).
    const slug = slugify(f.q);
    if (slug) {
      params.qs = `%${escapeLike(slug)}%`;
      cond += ` OR p.Slug LIKE @qs ESCAPE '\\'`;
    }
    where.push(`(${cond})`);
  }
  if (f.category) {
    params.cat = f.category;
    where.push('(c.Slug = @cat OR pc.Slug = @cat)');
  }
  if (f.excludeId) {
    params.exclude = f.excludeId;
    where.push('p.ProductId <> @exclude');
  }
  if (f.featured) where.push('p.IsFeatured = 1');

  // Size, màu, giá phải cùng khớp trên MỘT biến thể còn hàng, nên gom vào một EXISTS.
  const v = ['fv.ProductId = p.ProductId', 'fv.IsActive = 1'];
  let useVariant = false;
  if (f.sizes && f.sizes.length) {
    const l = db.inList('sz', f.sizes);
    Object.assign(params, l.params);
    v.push(`fv.Size IN (${l.clause})`);
    useVariant = true;
  }
  if (f.colors && f.colors.length) {
    const l = db.inList('cl', f.colors);
    Object.assign(params, l.params);
    v.push(`fv.ColorName IN (${l.clause})`);
    useVariant = true;
  }
  if (useVariant) v.push('fv.StockQuantity > 0');
  if (f.minPrice !== undefined && f.minPrice !== null) {
    params.minPrice = f.minPrice;
    v.push('fv.Price >= @minPrice');
    useVariant = true;
  }
  if (f.maxPrice !== undefined && f.maxPrice !== null) {
    params.maxPrice = f.maxPrice;
    v.push('fv.Price <= @maxPrice');
    useVariant = true;
  }
  if (f.onSale) {
    v.push('fv.CompareAtPrice IS NOT NULL');
    useVariant = true;
  }
  if (useVariant) where.push(`EXISTS (SELECT 1 FROM dbo.ProductVariants fv WHERE ${v.join(' AND ')})`);

  return { where: where.join('\n    AND '), params };
}

async function attachColors(rows) {
  if (!rows.length) return;
  const l = db.inList('pid', rows.map((r) => r.id));
  const colors = (await db.query(
    `SELECT v.ProductId AS productId, v.ColorName AS name, v.ColorHex AS hex, SUM(v.StockQuantity) AS stock
       FROM dbo.ProductVariants v
      WHERE v.IsActive = 1 AND v.ProductId IN (${l.clause})
      GROUP BY v.ProductId, v.ColorName, v.ColorHex
      ORDER BY v.ProductId, MIN(v.VariantId)`, l.params)).rows;
  const byProduct = new Map();
  for (const c of colors) {
    if (!byProduct.has(c.productId)) byProduct.set(c.productId, []);
    byProduct.get(c.productId).push(c);
  }
  for (const r of rows) r.colors = byProduct.get(r.id) || [];
}

async function fetchPage(where, params, sort, offset, limit) {
  const order = SORTS[sort] || SORTS.newest;
  const rows = (await db.query(
    `SELECT p.ProductId AS id, p.ProductCode AS code, p.Name AS name, p.Slug AS slug,
            c.Name AS categoryName, c.Slug AS categorySlug,
            agg.MinPrice AS minPrice, agg.MaxPrice AS maxPrice, agg.TotalStock AS totalStock,
            cmp.CompareAt AS compareAt, img1.ImageUrl AS image, img2.ImageUrl AS image2, p.IsFeatured AS isFeatured
       ${BASE_FROM}
       ${LIST_APPLY}
       ${order.includes('sold.') ? SOLD_APPLY : ''}
      WHERE ${where}
      ORDER BY ${order}
     OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY`,
    { ...params, offset, limit })).rows;
  await attachColors(rows);
  return rows;
}

/** Danh sách có phân trang. Trả về { items, pagination }. */
async function list(filters, { page = 1, perPage = shop.limits.perPage, sort = 'newest' } = {}) {
  const { where, params } = buildFilter(filters);
  const total = await db.scalar(`SELECT COUNT(*) AS total ${BASE_FROM} WHERE ${where}`, params);
  const pagination = paginate(total || 0, page, perPage);
  const items = await fetchPage(where, params, sort, pagination.offset, perPage);
  return { items, pagination };
}

/** N sản phẩm đầu theo thứ tự, không phân trang (dùng cho trang chủ và gợi ý). */
async function top(filters, limit = 8, sort = 'newest') {
  const { where, params } = buildFilter(filters);
  return fetchPage(where, params, sort, 0, limit);
}

/** Dữ liệu cho bộ lọc: danh sách màu đang bán. */
async function facets() {
  const colors = (await db.query(
    `SELECT v.ColorName AS name, MIN(v.ColorHex) AS hex
       FROM dbo.ProductVariants v JOIN dbo.Products p ON p.ProductId = v.ProductId
      WHERE v.IsActive = 1 AND p.IsActive = 1
      GROUP BY v.ColorName ORDER BY v.ColorName`)).rows;
  return { colors };
}

/** Chi tiết sản phẩm kèm biến thể (size, màu, giá, tồn kho) và ảnh. Trả về null nếu không có. */
async function getBySlug(slug) {
  const product = await db.one(
    `SELECT p.ProductId AS id, p.ProductCode AS code, p.Name AS name, p.Slug AS slug,
            p.Description AS description, p.Material AS material,
            c.CategoryId AS categoryId, c.Name AS categoryName, c.Slug AS categorySlug,
            pc.Name AS parentName, pc.Slug AS parentSlug
       FROM dbo.Products p
       JOIN dbo.Categories c ON c.CategoryId = p.CategoryId
       LEFT JOIN dbo.Categories pc ON pc.CategoryId = c.ParentId
      WHERE p.Slug = @slug AND p.IsActive = 1 AND c.IsActive = 1`, { slug });
  if (!product) return null;

  product.variants = (await db.query(
    `SELECT VariantId AS id, Sku AS sku, Size AS size, ColorName AS color, ColorHex AS hex,
            Price AS price, CompareAtPrice AS compareAt, StockQuantity AS stock,
            MIN(VariantId) OVER (PARTITION BY ColorName) AS colorOrder
       FROM dbo.ProductVariants
      WHERE ProductId = @pid AND IsActive = 1
      ORDER BY colorOrder, CASE Size WHEN N'S' THEN 1 WHEN N'M' THEN 2 WHEN N'L' THEN 3 ELSE 4 END`,
    { pid: product.id })).rows;

  product.images = (await db.query(
    `SELECT ImageUrl AS url, AltText AS alt FROM dbo.ProductImages WHERE ProductId = @pid ORDER BY SortOrder, ImageId`,
    { pid: product.id })).rows;
  return product;
}

// ------------------------------------------------------------------ quản trị
async function adminList({ q, categoryId, active, page = 1, perPage = shop.limits.adminPerPage } = {}) {
  const params = {};
  const where = ['1 = 1'];
  if (q) {
    params.q = `%${escapeLike(q)}%`;
    where.push(`(p.Name COLLATE Latin1_General_100_CI_AI LIKE @q ESCAPE '\\' OR p.ProductCode LIKE @q ESCAPE '\\')`);
  }
  if (categoryId) {
    params.cid = categoryId;
    where.push('p.CategoryId = @cid');
  }
  if (active === 0 || active === 1) {
    params.act = active;
    where.push('p.IsActive = @act');
  }
  const w = where.join(' AND ');
  const total = await db.scalar(`SELECT COUNT(*) AS total FROM dbo.Products p WHERE ${w}`, params);
  const pagination = paginate(total || 0, page, perPage);
  const items = (await db.query(
    `SELECT p.ProductId AS id, p.ProductCode AS code, p.Name AS name, p.Slug AS slug,
            p.IsActive AS isActive, p.IsFeatured AS isFeatured, c.Name AS categoryName,
            (SELECT COUNT(*) FROM dbo.ProductVariants v WHERE v.ProductId = p.ProductId) AS variantCount,
            (SELECT COALESCE(SUM(v.StockQuantity), 0) FROM dbo.ProductVariants v WHERE v.ProductId = p.ProductId AND v.IsActive = 1) AS totalStock,
            (SELECT MIN(v.Price) FROM dbo.ProductVariants v WHERE v.ProductId = p.ProductId AND v.IsActive = 1) AS minPrice,
            (SELECT TOP (1) i.ImageUrl FROM dbo.ProductImages i WHERE i.ProductId = p.ProductId ORDER BY i.SortOrder, i.ImageId) AS image
       FROM dbo.Products p JOIN dbo.Categories c ON c.CategoryId = p.CategoryId
      WHERE ${w}
      ORDER BY p.CreatedAt DESC, p.ProductId DESC
     OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY`,
    { ...params, offset: pagination.offset, limit: perPage })).rows;
  return { items, pagination };
}

async function adminGet(id) {
  const product = await db.one(
    `SELECT ProductId AS id, CategoryId AS categoryId, ProductCode AS code, Name AS name, Slug AS slug,
            Description AS description, Material AS material, IsFeatured AS isFeatured, IsActive AS isActive
       FROM dbo.Products WHERE ProductId = @id`, { id });
  if (!product) return null;
  product.images = (await db.query(
    'SELECT ImageUrl AS url FROM dbo.ProductImages WHERE ProductId = @id ORDER BY SortOrder, ImageId', { id })).rows.map((r) => r.url);
  return product;
}

/** Tạo mới (không có id) hoặc cập nhật sản phẩm cùng danh sách ảnh. Trả về ProductId. */
async function save({ id, categoryId, code, name, slug, description, material, isFeatured, isActive, images }) {
  try {
    return await db.tx(async (t) => {
      const cat = await t.scalar('SELECT TOP (1) 1 AS x FROM dbo.Categories WHERE CategoryId = @cid', { cid: categoryId });
      if (!cat) throw new BusinessError('Danh mục không tồn tại.');
      const p = {
        cid: categoryId, code, name, slug, descr: description || null, mat: material || null,
        feat: isFeatured ? 1 : 0, act: isActive ? 1 : 0,
      };
      let productId = id;
      if (id) {
        const r = await t.query(
          `UPDATE dbo.Products SET CategoryId = @cid, ProductCode = @code, Name = @name, Slug = @slug, Description = @descr,
                  Material = @mat, IsFeatured = @feat, IsActive = @act, UpdatedAt = SYSUTCDATETIME()
            WHERE ProductId = @id`, { ...p, id });
        if (!r.rowsAffected[0]) throw new BusinessError('Sản phẩm không tồn tại.');
      } else {
        productId = await t.scalar(
          `INSERT dbo.Products (CategoryId, ProductCode, Name, Slug, Description, Material, IsFeatured, IsActive)
             OUTPUT INSERTED.ProductId
             VALUES (@cid, @code, @name, @slug, @descr, @mat, @feat, @act)`, p);
      }
      await t.query('DELETE FROM dbo.ProductImages WHERE ProductId = @pid', { pid: productId });
      for (let i = 0; i < images.length; i += 1) {
        await t.query(
          'INSERT dbo.ProductImages (ProductId, ImageUrl, AltText, SortOrder) VALUES (@pid, @url, @alt, @sort)',
          { pid: productId, url: images[i], alt: name, sort: i });
      }
      return productId;
    });
  } catch (err) {
    if (db.isUniqueViolation(err)) throw new BusinessError('Mã sản phẩm hoặc đường dẫn (slug) đã tồn tại. Vui lòng dùng giá trị khác.');
    throw err;
  }
}

async function setActive(id, isActive) {
  await db.query('UPDATE dbo.Products SET IsActive = @act, UpdatedAt = SYSUTCDATETIME() WHERE ProductId = @id', { act: isActive ? 1 : 0, id });
}

module.exports = { SORTS, SORT_LABELS, list, top, facets, getBySlug, adminList, adminGet, save, setActive };
