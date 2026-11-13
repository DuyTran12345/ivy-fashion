/* ============================================================================
   AURA MODA - Dữ liệu mẫu
   File    : 02_seed.sql   (chạy SAU 01_schema.sql)
   Nội dung: 4 tài khoản, 3 địa chỉ, 11 danh mục, 32 sản phẩm, 64 ảnh, 276 biến thể (S/M/L/XL),
             6 mã giảm giá, 16 đơn hàng đủ 6 trạng thái, lịch sử trạng thái, thanh toán, vận đơn,
             nhật ký kho, 6 đánh giá.
   An toàn : Nếu đã có tài khoản admin@example.com thì script tự dừng, không nạp trùng.
   Mọi mốc thời gian được tính lùi từ lúc bạn chạy script.
   Mã hóa  : Lưu file UTF-8 (có BOM) để SSMS đọc đúng tiếng Việt.
   ============================================================================ */
USE IvyModaShop;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF EXISTS (SELECT 1 FROM dbo.Users WHERE Email = N'admin@example.com')
BEGIN
    PRINT N'Dữ liệu mẫu đã tồn tại (có tài khoản admin@example.com). Bỏ qua, không nạp lại.';
    RETURN;
END

DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

BEGIN TRY
BEGIN TRANSACTION;

/* ---- [UC01] Tài khoản. Mật khẩu lưu dạng bcrypt (cost 12). ---- */
INSERT dbo.Users (Email, PasswordHash, FullName, Phone, DateOfBirth, Role, IsActive, ConsentGivenAt, ConsentVersion)
VALUES
  (N'admin@example.com', N'$2a$12$Ei2RfvHKZ/w1P/zeTSaMsubk/ZOTao3y5SD2pv6rca6UcP1VIkZ9S', N'Quản trị viên', N'0900000001', NULL, N'ADMIN', 1, @now, N'v1'),
  (N'ha.nguyen@example.com', N'$2a$12$ZOX15Sj7mlNUqGDQWAc43O3EJTOy1G7WSNLA.9tNdoGRv5nLS7rd2', N'Nguyễn Thu Hà', N'0912345678', N'1998-05-14', N'CUSTOMER', 1, @now, N'v1'),
  (N'an.tran@example.com', N'$2a$12$dnbXPkVy9ErStY6CaXC9HuJTTrLMI/30zk6FP7eY3j.pp64GBD6lm', N'Trần Minh An', N'0987654321', N'1996-11-02', N'CUSTOMER', 1, @now, N'v1'),
  (N'mai.le@example.com', N'$2a$12$.gYkVBBOAw5MOzcEyXUi7uUXaTBrREGYOBaJH0271RYTj/jUIlZIq', N'Lê Ngọc Mai', N'0933333333', NULL, N'CUSTOMER', 1, @now, N'v1');

DECLARE @adminId INT = (SELECT UserId FROM dbo.Users WHERE Email = N'admin@example.com');

/* ---- [UC01] Sổ địa chỉ giao hàng ---- */
INSERT dbo.Addresses (UserId, RecipientName, Phone, Province, District, Ward, StreetAddress, IsDefault)
SELECT u.UserId, v.RecipientName, v.Phone, v.Province, NULL, v.Ward, v.StreetAddress, v.IsDefault
FROM (VALUES
  (N'ha.nguyen@example.com', N'Nguyễn Thu Hà', N'0912345678', N'Hà Nội', N'Phường Mẫu', N'Số 12 ngõ 34 đường Mẫu', 1),
  (N'ha.nguyen@example.com', N'Nguyễn Thu Hà', N'0912345678', N'Hà Nội', N'Phường Ví Dụ', N'Tầng 5 tòa nhà Ví Dụ, đường Mẫu', 0),
  (N'an.tran@example.com', N'Trần Minh An', N'0987654321', N'TP. Hồ Chí Minh', N'Phường Mẫu', N'45 đường Ví Dụ', 1)
) AS v (Email, RecipientName, Phone, Province, Ward, StreetAddress, IsDefault)
JOIN dbo.Users AS u ON u.Email = v.Email;


/* ---- Danh mục ---- */
INSERT dbo.Categories (ParentId, Name, Slug, Description, SortOrder)
VALUES
  (NULL, N'Nữ', N'nu', N'Thời trang nữ', 1),
  (NULL, N'Nam', N'nam', N'Thời trang nam', 2);

INSERT dbo.Categories (ParentId, Name, Slug, Description, SortOrder)
SELECT p.CategoryId, v.Name, v.Slug, v.Description, v.SortOrder
FROM (VALUES
  (N'nu', N'Áo', N'ao-nu', N'Áo thun, sơ mi, áo kiểu và áo len nữ', 1),
  (N'nu', N'Quần', N'quan-nu', N'Quần dài và quần short nữ', 2),
  (N'nu', N'Chân váy', N'chan-vay', N'Chân váy dài, ngắn, xếp ly', 3),
  (N'nu', N'Đầm', N'dam', N'Đầm công sở, đầm dự tiệc, đầm dạo phố', 4),
  (N'nu', N'Áo khoác', N'ao-khoac-nu', N'Blazer, áo khoác dạ, cardigan', 5),
  (N'nam', N'Áo sơ mi', N'so-mi-nam', N'Sơ mi dài tay và ngắn tay', 1),
  (N'nam', N'Áo thun & polo', N'thun-polo-nam', N'Áo thun và polo nam', 2),
  (N'nam', N'Quần', N'quan-nam', N'Quần kaki, jeans, short nam', 3),
  (N'nam', N'Áo khoác', N'ao-khoac-nam', N'Bomber, áo khoác gió, denim', 4)
) AS v (ParentSlug, Name, Slug, Description, SortOrder)
JOIN dbo.Categories AS p ON p.Slug = v.ParentSlug;


/* ---- Sản phẩm ---- */
INSERT dbo.Products (CategoryId, ProductCode, Name, Slug, Description, Material, IsFeatured, CreatedAt, UpdatedAt)
SELECT c.CategoryId, v.ProductCode, v.Name, v.Slug, v.Description, v.Material, v.IsFeatured,
       DATEADD(HOUR, -v.AgeHours, @now), DATEADD(HOUR, -v.AgeHours, @now)
FROM (VALUES
  (N'ao-nu', N'P001', N'Áo sơ mi lụa cổ nơ', N'ao-so-mi-lua-co-no', N'Chất lụa mềm rủ, cổ nơ thắt tự do, tay dài bo măng. Mặc đi làm hoặc đi chơi đều gọn dáng.', N'Lụa tơ tằm nhân tạo', 1, 257),
  (N'ao-nu', N'P002', N'Áo thun cotton cổ tròn', N'ao-thun-cotton-co-tron', N'Cotton dày vừa, bề mặt mềm. Form suông nhẹ, dễ phối với quần jeans hoặc chân váy.', N'Cotton 100%', 0, 702),
  (N'ao-nu', N'P003', N'Áo kiểu voan tay phồng', N'ao-kieu-voan-tay-phong', N'Voan hai lớp nhẹ, tay phồng, cổ tròn có nút lưng. Hợp đi làm và dự tiệc nhẹ.', N'Voan chiffon hai lớp', 0, 1042),
  (N'ao-nu', N'P004', N'Áo len mỏng cổ V', N'ao-len-mong-co-v', N'Len mỏng, cổ V. Mặc riêng hoặc làm lớp lót dưới áo khoác.', N'Len acrylic pha cotton', 0, 750),
  (N'ao-nu', N'P005', N'Áo croptop thun gân', N'ao-croptop-thun-gan', N'Thun gân ôm vừa, độ dài ngang eo. Chất vải co giãn, dễ vận động.', N'Thun gân cotton co giãn', 0, 1932),
  (N'quan-nu', N'P006', N'Quần ống rộng linen', N'quan-ong-rong-linen', N'Linen pha cotton, cạp cao, ống rộng. Có túi chéo hai bên.', N'Linen pha cotton', 1, 2690),
  (N'quan-nu', N'P007', N'Quần jeans ống đứng', N'quan-jeans-ong-dung', N'Denim dày vừa, cạp cao, ống đứng. Có túi trước và túi sau.', N'Denim cotton', 0, 217),
  (N'quan-nu', N'P008', N'Quần tây ống suông', N'quan-tay-ong-suong', N'Vải tuyết mưa đứng dáng, cạp cao, khóa kéo bên hông. Hợp môi trường công sở.', N'Tuyết mưa', 0, 2548),
  (N'quan-nu', N'P009', N'Quần short kaki', N'quan-short-kaki', N'Kaki cotton, cạp vừa, dài ngang đùi. Mặc đi chơi hoặc đi biển.', N'Kaki cotton', 0, 1418),
  (N'chan-vay', N'P010', N'Chân váy chữ A', N'chan-vay-chu-a', N'Chân váy chữ A dài ngang gối, cạp cao, khóa kéo sau. Dễ phối với áo thun hoặc sơ mi.', N'Tuyết mưa', 0, 1648),
  (N'chan-vay', N'P011', N'Chân váy xếp ly dài', N'chan-vay-xep-ly-dai', N'Xếp ly đều, rủ nhẹ khi di chuyển, có lớp lót bên trong. Cạp chun phía sau.', N'Voan lụa', 1, 25),
  (N'chan-vay', N'P012', N'Chân váy jeans', N'chan-vay-jeans', N'Chân váy jeans dáng ngắn, túi thật hai bên, cúc bấm phía trước.', N'Denim', 0, 318),
  (N'chan-vay', N'P013', N'Chân váy bút chì', N'chan-vay-but-chi', N'Dáng bút chì ôm vừa, xẻ sau, dài qua gối. Dành cho đi làm.', N'Vải tuyết mưa co giãn', 0, 948),
  (N'dam', N'P014', N'Đầm sơ mi thắt eo', N'dam-so-mi-that-eo', N'Đầm sơ mi cài cúc phía trước, kèm đai thắt eo rời. Dài đến gối.', N'Cotton lụa', 1, 1976),
  (N'dam', N'P015', N'Đầm xòe hoa nhí', N'dam-xoe-hoa-nhi', N'Voan hoa nhí hai lớp, cổ vuông, chân váy xòe. Hợp đi chơi và chụp ảnh.', N'Voan hoa', 0, 1044),
  (N'dam', N'P016', N'Đầm ôm dệt kim', N'dam-om-det-kim', N'Dệt kim co giãn, ôm nhẹ theo dáng người, dài đến gối.', N'Dệt kim co giãn', 0, 1218),
  (N'dam', N'P017', N'Đầm maxi lụa', N'dam-maxi-lua', N'Satin rủ dài đến mắt cá, cổ yếm, dây buộc sau lưng. Dành cho tiệc tối và du lịch.', N'Satin', 1, 2767),
  (N'ao-khoac-nu', N'P018', N'Blazer dáng rộng', N'blazer-dang-rong', N'Blazer dáng rộng, vai độn nhẹ, hai túi hộp. Phối được với áo thun hoặc sơ mi.', N'Tuyết mưa dày', 1, 1929),
  (N'ao-khoac-nu', N'P019', N'Áo khoác dạ lửng', N'ao-khoac-da-lung', N'Dạ dày, dài ngang đùi, cổ bẻ lớn, hai hàng cúc. Có lót satin bên trong.', N'Dạ dày', 0, 206),
  (N'ao-khoac-nu', N'P020', N'Cardigan len dáng dài', N'cardigan-len-dang-dai', N'Len dệt dáng dài, cài cúc gỗ phía trước, hai túi bên.', N'Len dệt', 0, 2621),
  (N'so-mi-nam', N'P021', N'Sơ mi Oxford tay dài', N'so-mi-oxford-tay-dai', N'Oxford dày dặn, cổ button-down, form regular. Mặc đi làm hoặc đi chơi.', N'Cotton Oxford', 1, 2007),
  (N'so-mi-nam', N'P022', N'Sơ mi linen ngắn tay', N'so-mi-linen-ngan-tay', N'Linen pha cotton, tay ngắn, form rộng vừa. Phù hợp thời tiết nóng.', N'Linen pha cotton', 0, 1293),
  (N'so-mi-nam', N'P023', N'Sơ mi kẻ sọc', N'so-mi-ke-soc', N'Poplin mịn, kẻ sọc nhỏ, cổ đứng, túi ngực bên trái.', N'Cotton poplin', 0, 1556),
  (N'thun-polo-nam', N'P024', N'Polo pique', N'polo-pique', N'Pique dệt nổi, cổ bẻ bo gân, cài cúc ba nút.', N'Cotton pique', 1, 1037),
  (N'thun-polo-nam', N'P025', N'Áo thun basic cổ tròn', N'ao-thun-basic-co-tron', N'Cotton 100%, cổ tròn bo gân, form regular. Dễ phối đồ hằng ngày.', N'Cotton 100%', 0, 2458),
  (N'thun-polo-nam', N'P026', N'Áo thun in họa tiết', N'ao-thun-in-hoa-tiet', N'Cotton compact đứng dáng, họa tiết in nhỏ ở ngực. Form rộng vừa.', N'Cotton compact', 0, 1535),
  (N'quan-nam', N'P027', N'Quần kaki slimfit', N'quan-kaki-slimfit', N'Kaki co giãn nhẹ, ống slimfit, cạp có passant. Mặc đi làm hoặc đi chơi.', N'Kaki co giãn', 0, 2797),
  (N'quan-nam', N'P028', N'Quần jeans xanh đậm', N'quan-jeans-xanh-dam', N'Denim co giãn nhẹ, ống đứng, cạp vừa. Màu xanh đậm dễ phối.', N'Denim co giãn nhẹ', 1, 1823),
  (N'quan-nam', N'P029', N'Quần short thể thao', N'quan-short-the-thao', N'Vải dù nhẹ, cạp chun có dây rút, túi khóa kéo.', N'Vải dù', 0, 1653),
  (N'ao-khoac-nam', N'P030', N'Áo khoác bomber', N'ao-khoac-bomber', N'Bomber dù phối bo, khóa kéo phía trước, hai túi chéo, lót mỏng.', N'Dù phối bo', 1, 1952),
  (N'ao-khoac-nam', N'P031', N'Áo khoác gió', N'ao-khoac-gio', N'Vải dù chống gió nhẹ, mũ liền có dây rút, hai túi khóa kéo. Gấp gọn được.', N'Vải dù chống gió', 0, 164),
  (N'ao-khoac-nam', N'P032', N'Áo khoác denim', N'ao-khoac-denim', N'Denim dày vừa, cổ bẻ, cúc kim loại, hai túi ngực. Form regular.', N'Denim', 0, 1092)
) AS v (CatSlug, ProductCode, Name, Slug, Description, Material, IsFeatured, AgeHours)
JOIN dbo.Categories AS c ON c.Slug = v.CatSlug;


/* ---- Ảnh sản phẩm: ảnh chính P###.jpg, ảnh phụ P###_2.jpg (hiện khi rê chuột) ---- */
INSERT dbo.ProductImages (ProductId, ImageUrl, AltText, SortOrder)
SELECT p.ProductId, v.ImageUrl, p.Name, v.SortOrder
FROM (VALUES
  (N'P001', N'/images/products/P001.jpg', 0),
  (N'P001', N'/images/products/P001_2.jpg', 1),
  (N'P002', N'/images/products/P002.jpg', 0),
  (N'P002', N'/images/products/P002_2.jpg', 1),
  (N'P003', N'/images/products/P003.jpg', 0),
  (N'P003', N'/images/products/P003_2.jpg', 1),
  (N'P004', N'/images/products/P004.jpg', 0),
  (N'P004', N'/images/products/P004_2.jpg', 1),
  (N'P005', N'/images/products/P005.jpg', 0),
  (N'P005', N'/images/products/P005_2.jpg', 1),
  (N'P006', N'/images/products/P006.jpg', 0),
  (N'P006', N'/images/products/P006_2.jpg', 1),
  (N'P007', N'/images/products/P007.jpg', 0),
  (N'P007', N'/images/products/P007_2.jpg', 1),
  (N'P008', N'/images/products/P008.jpg', 0),
  (N'P008', N'/images/products/P008_2.jpg', 1),
  (N'P009', N'/images/products/P009.jpg', 0),
  (N'P009', N'/images/products/P009_2.jpg', 1),
  (N'P010', N'/images/products/P010.jpg', 0),
  (N'P010', N'/images/products/P010_2.jpg', 1),
  (N'P011', N'/images/products/P011.jpg', 0),
  (N'P011', N'/images/products/P011_2.jpg', 1),
  (N'P012', N'/images/products/P012.jpg', 0),
  (N'P012', N'/images/products/P012_2.jpg', 1),
  (N'P013', N'/images/products/P013.jpg', 0),
  (N'P013', N'/images/products/P013_2.jpg', 1),
  (N'P014', N'/images/products/P014.jpg', 0),
  (N'P014', N'/images/products/P014_2.jpg', 1),
  (N'P015', N'/images/products/P015.jpg', 0),
  (N'P015', N'/images/products/P015_2.jpg', 1),
  (N'P016', N'/images/products/P016.jpg', 0),
  (N'P016', N'/images/products/P016_2.jpg', 1),
  (N'P017', N'/images/products/P017.jpg', 0),
  (N'P017', N'/images/products/P017_2.jpg', 1),
  (N'P018', N'/images/products/P018.jpg', 0),
  (N'P018', N'/images/products/P018_2.jpg', 1),
  (N'P019', N'/images/products/P019.jpg', 0),
  (N'P019', N'/images/products/P019_2.jpg', 1),
  (N'P020', N'/images/products/P020.jpg', 0),
  (N'P020', N'/images/products/P020_2.jpg', 1),
  (N'P021', N'/images/products/P021.jpg', 0),
  (N'P021', N'/images/products/P021_2.jpg', 1),
  (N'P022', N'/images/products/P022.jpg', 0),
  (N'P022', N'/images/products/P022_2.jpg', 1),
  (N'P023', N'/images/products/P023.jpg', 0),
  (N'P023', N'/images/products/P023_2.jpg', 1),
  (N'P024', N'/images/products/P024.jpg', 0),
  (N'P024', N'/images/products/P024_2.jpg', 1),
  (N'P025', N'/images/products/P025.jpg', 0),
  (N'P025', N'/images/products/P025_2.jpg', 1),
  (N'P026', N'/images/products/P026.jpg', 0),
  (N'P026', N'/images/products/P026_2.jpg', 1),
  (N'P027', N'/images/products/P027.jpg', 0),
  (N'P027', N'/images/products/P027_2.jpg', 1),
  (N'P028', N'/images/products/P028.jpg', 0),
  (N'P028', N'/images/products/P028_2.jpg', 1),
  (N'P029', N'/images/products/P029.jpg', 0),
  (N'P029', N'/images/products/P029_2.jpg', 1),
  (N'P030', N'/images/products/P030.jpg', 0),
  (N'P030', N'/images/products/P030_2.jpg', 1),
  (N'P031', N'/images/products/P031.jpg', 0),
  (N'P031', N'/images/products/P031_2.jpg', 1),
  (N'P032', N'/images/products/P032.jpg', 0),
  (N'P032', N'/images/products/P032_2.jpg', 1)
) AS v (ProductCode, ImageUrl, SortOrder)
JOIN dbo.Products AS p ON p.ProductCode = v.ProductCode;


/* ---- Biến thể: size S/M/L/XL x màu. Mỗi biến thể có SKU, giá và tồn kho riêng (276 dòng). ---- */
INSERT dbo.ProductVariants (ProductId, Sku, Size, ColorName, ColorHex, Price, CompareAtPrice, StockQuantity)
SELECT p.ProductId, v.Sku, v.Size, v.ColorName, v.ColorHex, v.Price, v.CompareAtPrice, v.StockQuantity
FROM (VALUES
  (N'P001', N'P001-TRG-S', N'S', N'Trắng', '#F5F5F2', 690000, NULL, 14),
  (N'P001', N'P001-TRG-M', N'M', N'Trắng', '#F5F5F2', 690000, NULL, 3),
  (N'P001', N'P001-TRG-L', N'L', N'Trắng', '#F5F5F2', 690000, NULL, 8),
  (N'P001', N'P001-TRG-XL', N'XL', N'Trắng', '#F5F5F2', 690000, NULL, 7),
  (N'P001', N'P001-BE-S', N'S', N'Be', '#D9C8AE', 690000, NULL, 8),
  (N'P001', N'P001-BE-M', N'M', N'Be', '#D9C8AE', 690000, NULL, 13),
  (N'P001', N'P001-BE-L', N'L', N'Be', '#D9C8AE', 690000, NULL, 14),
  (N'P001', N'P001-BE-XL', N'XL', N'Be', '#D9C8AE', 690000, NULL, 2),
  (N'P001', N'P001-DEN-S', N'S', N'Đen', '#1C1C1C', 690000, NULL, 6),
  (N'P001', N'P001-DEN-M', N'M', N'Đen', '#1C1C1C', 690000, NULL, 12),
  (N'P001', N'P001-DEN-L', N'L', N'Đen', '#1C1C1C', 690000, NULL, 5),
  (N'P001', N'P001-DEN-XL', N'XL', N'Đen', '#1C1C1C', 690000, NULL, 0),
  (N'P002', N'P002-TRG-S', N'S', N'Trắng', '#F5F5F2', 290000, NULL, 12),
  (N'P002', N'P002-TRG-M', N'M', N'Trắng', '#F5F5F2', 290000, NULL, 17),
  (N'P002', N'P002-TRG-L', N'L', N'Trắng', '#F5F5F2', 290000, NULL, 14),
  (N'P002', N'P002-TRG-XL', N'XL', N'Trắng', '#F5F5F2', 290000, NULL, 3),
  (N'P002', N'P002-DEN-S', N'S', N'Đen', '#1C1C1C', 290000, NULL, 10),
  (N'P002', N'P002-DEN-M', N'M', N'Đen', '#1C1C1C', 290000, NULL, 12),
  (N'P002', N'P002-DEN-L', N'L', N'Đen', '#1C1C1C', 290000, NULL, 2),
  (N'P002', N'P002-DEN-XL', N'XL', N'Đen', '#1C1C1C', 290000, NULL, 9),
  (N'P002', N'P002-HPH-S', N'S', N'Hồng phấn', '#E8B4BC', 290000, NULL, 13),
  (N'P002', N'P002-HPH-M', N'M', N'Hồng phấn', '#E8B4BC', 290000, NULL, 8),
  (N'P002', N'P002-HPH-L', N'L', N'Hồng phấn', '#E8B4BC', 290000, NULL, 18),
  (N'P002', N'P002-HPH-XL', N'XL', N'Hồng phấn', '#E8B4BC', 290000, NULL, 10),
  (N'P003', N'P003-TRG-S', N'S', N'Trắng', '#F5F5F2', 450000, 590000, 10),
  (N'P003', N'P003-TRG-M', N'M', N'Trắng', '#F5F5F2', 450000, 590000, 17),
  (N'P003', N'P003-TRG-L', N'L', N'Trắng', '#F5F5F2', 450000, 590000, 8),
  (N'P003', N'P003-TRG-XL', N'XL', N'Trắng', '#F5F5F2', 450000, 590000, 3),
  (N'P003', N'P003-HPH-S', N'S', N'Hồng phấn', '#E8B4BC', 450000, 590000, 7),
  (N'P003', N'P003-HPH-M', N'M', N'Hồng phấn', '#E8B4BC', 450000, 590000, 17),
  (N'P003', N'P003-HPH-L', N'L', N'Hồng phấn', '#E8B4BC', 450000, 590000, 9),
  (N'P003', N'P003-HPH-XL', N'XL', N'Hồng phấn', '#E8B4BC', 450000, 590000, 5),
  (N'P004', N'P004-BE-S', N'S', N'Be', '#D9C8AE', 520000, NULL, 4),
  (N'P004', N'P004-BE-M', N'M', N'Be', '#D9C8AE', 520000, NULL, 17),
  (N'P004', N'P004-BE-L', N'L', N'Be', '#D9C8AE', 520000, NULL, 15),
  (N'P004', N'P004-BE-XL', N'XL', N'Be', '#D9C8AE', 520000, NULL, 7),
  (N'P004', N'P004-XAM-S', N'S', N'Xám', '#8E8E8E', 520000, NULL, 11),
  (N'P004', N'P004-XAM-M', N'M', N'Xám', '#8E8E8E', 520000, NULL, 14),
  (N'P004', N'P004-XAM-L', N'L', N'Xám', '#8E8E8E', 520000, NULL, 12),
  (N'P004', N'P004-XAM-XL', N'XL', N'Xám', '#8E8E8E', 520000, NULL, 10),
  (N'P004', N'P004-DOD-S', N'S', N'Đỏ đô', '#7B1E2B', 520000, NULL, 10),
  (N'P004', N'P004-DOD-M', N'M', N'Đỏ đô', '#7B1E2B', 520000, NULL, 12),
  (N'P004', N'P004-DOD-L', N'L', N'Đỏ đô', '#7B1E2B', 520000, NULL, 13),
  (N'P004', N'P004-DOD-XL', N'XL', N'Đỏ đô', '#7B1E2B', 520000, NULL, 9),
  (N'P005', N'P005-DEN-S', N'S', N'Đen', '#1C1C1C', 250000, 320000, 8),
  (N'P005', N'P005-DEN-M', N'M', N'Đen', '#1C1C1C', 250000, 320000, 8),
  (N'P005', N'P005-DEN-L', N'L', N'Đen', '#1C1C1C', 250000, 320000, 16),
  (N'P005', N'P005-DEN-XL', N'XL', N'Đen', '#1C1C1C', 250000, 320000, 8),
  (N'P005', N'P005-TRG-S', N'S', N'Trắng', '#F5F5F2', 250000, 320000, 14),
  (N'P005', N'P005-TRG-M', N'M', N'Trắng', '#F5F5F2', 250000, 320000, 9),
  (N'P005', N'P005-TRG-L', N'L', N'Trắng', '#F5F5F2', 250000, 320000, 7),
  (N'P005', N'P005-TRG-XL', N'XL', N'Trắng', '#F5F5F2', 250000, 320000, 5),
  (N'P006', N'P006-BE-S', N'S', N'Be', '#D9C8AE', 590000, NULL, 13),
  (N'P006', N'P006-BE-M', N'M', N'Be', '#D9C8AE', 590000, NULL, 5),
  (N'P006', N'P006-BE-L', N'L', N'Be', '#D9C8AE', 590000, NULL, 13),
  (N'P006', N'P006-BE-XL', N'XL', N'Be', '#D9C8AE', 590000, NULL, 7),
  (N'P006', N'P006-DEN-S', N'S', N'Đen', '#1C1C1C', 590000, NULL, 14),
  (N'P006', N'P006-DEN-M', N'M', N'Đen', '#1C1C1C', 590000, NULL, 13),
  (N'P006', N'P006-DEN-L', N'L', N'Đen', '#1C1C1C', 590000, NULL, 13),
  (N'P006', N'P006-DEN-XL', N'XL', N'Đen', '#1C1C1C', 590000, NULL, 2),
  (N'P006', N'P006-REU-S', N'S', N'Xanh rêu', '#5B6B4A', 590000, NULL, 11),
  (N'P006', N'P006-REU-M', N'M', N'Xanh rêu', '#5B6B4A', 590000, NULL, 11),
  (N'P006', N'P006-REU-L', N'L', N'Xanh rêu', '#5B6B4A', 590000, NULL, 12),
  (N'P006', N'P006-REU-XL', N'XL', N'Xanh rêu', '#5B6B4A', 590000, NULL, 8),
  (N'P007', N'P007-JEA-S', N'S', N'Xanh jeans', '#4A6FA5', 640000, NULL, 9),
  (N'P007', N'P007-JEA-M', N'M', N'Xanh jeans', '#4A6FA5', 640000, NULL, 9),
  (N'P007', N'P007-JEA-L', N'L', N'Xanh jeans', '#4A6FA5', 640000, NULL, 7),
  (N'P007', N'P007-JEA-XL', N'XL', N'Xanh jeans', '#4A6FA5', 670000, NULL, 10),
  (N'P007', N'P007-DEN-S', N'S', N'Đen', '#1C1C1C', 640000, NULL, 3),
  (N'P007', N'P007-DEN-M', N'M', N'Đen', '#1C1C1C', 640000, NULL, 14),
  (N'P007', N'P007-DEN-L', N'L', N'Đen', '#1C1C1C', 640000, NULL, 16),
  (N'P007', N'P007-DEN-XL', N'XL', N'Đen', '#1C1C1C', 670000, NULL, 9),
  (N'P008', N'P008-DEN-S', N'S', N'Đen', '#1C1C1C', 620000, NULL, 11),
  (N'P008', N'P008-DEN-M', N'M', N'Đen', '#1C1C1C', 620000, NULL, 9),
  (N'P008', N'P008-DEN-L', N'L', N'Đen', '#1C1C1C', 620000, NULL, 13),
  (N'P008', N'P008-DEN-XL', N'XL', N'Đen', '#1C1C1C', 620000, NULL, 6),
  (N'P008', N'P008-XAM-S', N'S', N'Xám', '#8E8E8E', 620000, NULL, 13),
  (N'P008', N'P008-XAM-M', N'M', N'Xám', '#8E8E8E', 620000, NULL, 20),
  (N'P008', N'P008-XAM-L', N'L', N'Xám', '#8E8E8E', 620000, NULL, 17),
  (N'P008', N'P008-XAM-XL', N'XL', N'Xám', '#8E8E8E', 620000, NULL, 8),
  (N'P009', N'P009-BE-S', N'S', N'Be', '#D9C8AE', 380000, 450000, 13),
  (N'P009', N'P009-BE-M', N'M', N'Be', '#D9C8AE', 380000, 450000, 5),
  (N'P009', N'P009-BE-L', N'L', N'Be', '#D9C8AE', 380000, 450000, 6),
  (N'P009', N'P009-BE-XL', N'XL', N'Be', '#D9C8AE', 380000, 450000, 10),
  (N'P009', N'P009-NAV-S', N'S', N'Xanh navy', '#1F2A44', 380000, 450000, 4),
  (N'P009', N'P009-NAV-M', N'M', N'Xanh navy', '#1F2A44', 380000, 450000, 11),
  (N'P009', N'P009-NAV-L', N'L', N'Xanh navy', '#1F2A44', 380000, 450000, 11),
  (N'P009', N'P009-NAV-XL', N'XL', N'Xanh navy', '#1F2A44', 380000, 450000, 4),
  (N'P010', N'P010-DEN-S', N'S', N'Đen', '#1C1C1C', 520000, NULL, 14),
  (N'P010', N'P010-DEN-M', N'M', N'Đen', '#1C1C1C', 520000, NULL, 19),
  (N'P010', N'P010-DEN-L', N'L', N'Đen', '#1C1C1C', 520000, NULL, 16),
  (N'P010', N'P010-DEN-XL', N'XL', N'Đen', '#1C1C1C', 520000, NULL, 10),
  (N'P010', N'P010-BE-S', N'S', N'Be', '#D9C8AE', 520000, NULL, 3),
  (N'P010', N'P010-BE-M', N'M', N'Be', '#D9C8AE', 520000, NULL, 19),
  (N'P010', N'P010-BE-L', N'L', N'Be', '#D9C8AE', 520000, NULL, 17),
  (N'P010', N'P010-BE-XL', N'XL', N'Be', '#D9C8AE', 520000, NULL, 6),
  (N'P011', N'P011-KEM-S', N'S', N'Kem', '#EFE6D2', 580000, NULL, 12),
  (N'P011', N'P011-KEM-M', N'M', N'Kem', '#EFE6D2', 580000, NULL, 20),
  (N'P011', N'P011-KEM-L', N'L', N'Kem', '#EFE6D2', 580000, NULL, 10),
  (N'P011', N'P011-KEM-XL', N'XL', N'Kem', '#EFE6D2', 580000, NULL, 3),
  (N'P011', N'P011-DEN-S', N'S', N'Đen', '#1C1C1C', 580000, NULL, 5),
  (N'P011', N'P011-DEN-M', N'M', N'Đen', '#1C1C1C', 580000, NULL, 7),
  (N'P011', N'P011-DEN-L', N'L', N'Đen', '#1C1C1C', 580000, NULL, 18),
  (N'P011', N'P011-DEN-XL', N'XL', N'Đen', '#1C1C1C', 580000, NULL, 7),
  (N'P012', N'P012-JEA-S', N'S', N'Xanh jeans', '#4A6FA5', 480000, NULL, 7),
  (N'P012', N'P012-JEA-M', N'M', N'Xanh jeans', '#4A6FA5', 480000, NULL, 16),
  (N'P012', N'P012-JEA-L', N'L', N'Xanh jeans', '#4A6FA5', 480000, NULL, 11),
  (N'P012', N'P012-JEA-XL', N'XL', N'Xanh jeans', '#4A6FA5', 480000, NULL, 5),
  (N'P013', N'P013-DEN-S', N'S', N'Đen', '#1C1C1C', 490000, NULL, 10),
  (N'P013', N'P013-DEN-M', N'M', N'Đen', '#1C1C1C', 490000, NULL, 9),
  (N'P013', N'P013-DEN-L', N'L', N'Đen', '#1C1C1C', 490000, NULL, 7),
  (N'P013', N'P013-DEN-XL', N'XL', N'Đen', '#1C1C1C', 490000, NULL, 3),
  (N'P013', N'P013-XAM-S', N'S', N'Xám', '#8E8E8E', 490000, NULL, 7),
  (N'P013', N'P013-XAM-M', N'M', N'Xám', '#8E8E8E', 490000, NULL, 16),
  (N'P013', N'P013-XAM-L', N'L', N'Xám', '#8E8E8E', 490000, NULL, 17),
  (N'P013', N'P013-XAM-XL', N'XL', N'Xám', '#8E8E8E', 490000, NULL, 5),
  (N'P014', N'P014-TRG-S', N'S', N'Trắng', '#F5F5F2', 890000, 1090000, 12),
  (N'P014', N'P014-TRG-M', N'M', N'Trắng', '#F5F5F2', 890000, 1090000, 12),
  (N'P014', N'P014-TRG-L', N'L', N'Trắng', '#F5F5F2', 890000, 1090000, 6),
  (N'P014', N'P014-TRG-XL', N'XL', N'Trắng', '#F5F5F2', 890000, 1090000, 10),
  (N'P014', N'P014-NAV-S', N'S', N'Xanh navy', '#1F2A44', 890000, 1090000, 4),
  (N'P014', N'P014-NAV-M', N'M', N'Xanh navy', '#1F2A44', 890000, 1090000, 17),
  (N'P014', N'P014-NAV-L', N'L', N'Xanh navy', '#1F2A44', 890000, 1090000, 14),
  (N'P014', N'P014-NAV-XL', N'XL', N'Xanh navy', '#1F2A44', 890000, 1090000, 10),
  (N'P015', N'P015-HPH-S', N'S', N'Hồng phấn', '#E8B4BC', 790000, NULL, 8),
  (N'P015', N'P015-HPH-M', N'M', N'Hồng phấn', '#E8B4BC', 790000, NULL, 18),
  (N'P015', N'P015-HPH-L', N'L', N'Hồng phấn', '#E8B4BC', 790000, NULL, 6),
  (N'P015', N'P015-HPH-XL', N'XL', N'Hồng phấn', '#E8B4BC', 790000, NULL, 10),
  (N'P015', N'P015-KEM-S', N'S', N'Kem', '#EFE6D2', 790000, NULL, 12),
  (N'P015', N'P015-KEM-M', N'M', N'Kem', '#EFE6D2', 790000, NULL, 15),
  (N'P015', N'P015-KEM-L', N'L', N'Kem', '#EFE6D2', 790000, NULL, 9),
  (N'P015', N'P015-KEM-XL', N'XL', N'Kem', '#EFE6D2', 790000, NULL, 3),
  (N'P016', N'P016-DEN-S', N'S', N'Đen', '#1C1C1C', 690000, NULL, 9),
  (N'P016', N'P016-DEN-M', N'M', N'Đen', '#1C1C1C', 690000, NULL, 17),
  (N'P016', N'P016-DEN-L', N'L', N'Đen', '#1C1C1C', 690000, NULL, 8),
  (N'P016', N'P016-DEN-XL', N'XL', N'Đen', '#1C1C1C', 690000, NULL, 6),
  (N'P016', N'P016-DOD-S', N'S', N'Đỏ đô', '#7B1E2B', 690000, NULL, 12),
  (N'P016', N'P016-DOD-M', N'M', N'Đỏ đô', '#7B1E2B', 690000, NULL, 16),
  (N'P016', N'P016-DOD-L', N'L', N'Đỏ đô', '#7B1E2B', 690000, NULL, 15),
  (N'P016', N'P016-DOD-XL', N'XL', N'Đỏ đô', '#7B1E2B', 690000, NULL, 5),
  (N'P017', N'P017-DOD-S', N'S', N'Đỏ đô', '#7B1E2B', 1190000, NULL, 0),
  (N'P017', N'P017-DOD-M', N'M', N'Đỏ đô', '#7B1E2B', 1190000, NULL, 16),
  (N'P017', N'P017-DOD-L', N'L', N'Đỏ đô', '#7B1E2B', 1190000, NULL, 13),
  (N'P017', N'P017-DOD-XL', N'XL', N'Đỏ đô', '#7B1E2B', 1190000, NULL, 5),
  (N'P017', N'P017-DEN-S', N'S', N'Đen', '#1C1C1C', 1190000, NULL, 14),
  (N'P017', N'P017-DEN-M', N'M', N'Đen', '#1C1C1C', 1190000, NULL, 11),
  (N'P017', N'P017-DEN-L', N'L', N'Đen', '#1C1C1C', 1190000, NULL, 16),
  (N'P017', N'P017-DEN-XL', N'XL', N'Đen', '#1C1C1C', 1190000, NULL, 9),
  (N'P018', N'P018-DEN-S', N'S', N'Đen', '#1C1C1C', 1290000, 1590000, 10),
  (N'P018', N'P018-DEN-M', N'M', N'Đen', '#1C1C1C', 1290000, 1590000, 1),
  (N'P018', N'P018-DEN-L', N'L', N'Đen', '#1C1C1C', 1290000, 1590000, 5),
  (N'P018', N'P018-DEN-XL', N'XL', N'Đen', '#1C1C1C', 1340000, 1640000, 3),
  (N'P018', N'P018-BE-S', N'S', N'Be', '#D9C8AE', 1290000, 1590000, 14),
  (N'P018', N'P018-BE-M', N'M', N'Be', '#D9C8AE', 1290000, 1590000, 8),
  (N'P018', N'P018-BE-L', N'L', N'Be', '#D9C8AE', 1290000, 1590000, 5),
  (N'P018', N'P018-BE-XL', N'XL', N'Be', '#D9C8AE', 1340000, 1640000, 6),
  (N'P019', N'P019-XAM-S', N'S', N'Xám', '#8E8E8E', 1890000, NULL, 3),
  (N'P019', N'P019-XAM-M', N'M', N'Xám', '#8E8E8E', 1890000, NULL, 12),
  (N'P019', N'P019-XAM-L', N'L', N'Xám', '#8E8E8E', 1890000, NULL, 7),
  (N'P019', N'P019-XAM-XL', N'XL', N'Xám', '#8E8E8E', 1940000, NULL, 3),
  (N'P019', N'P019-NAU-S', N'S', N'Nâu', '#7A5A3A', 1890000, NULL, 9),
  (N'P019', N'P019-NAU-M', N'M', N'Nâu', '#7A5A3A', 1890000, NULL, 20),
  (N'P019', N'P019-NAU-L', N'L', N'Nâu', '#7A5A3A', 1890000, NULL, 9),
  (N'P019', N'P019-NAU-XL', N'XL', N'Nâu', '#7A5A3A', 1940000, NULL, 6),
  (N'P020', N'P020-KEM-S', N'S', N'Kem', '#EFE6D2', 790000, NULL, 5),
  (N'P020', N'P020-KEM-M', N'M', N'Kem', '#EFE6D2', 790000, NULL, 6),
  (N'P020', N'P020-KEM-L', N'L', N'Kem', '#EFE6D2', 790000, NULL, 7),
  (N'P020', N'P020-KEM-XL', N'XL', N'Kem', '#EFE6D2', 820000, NULL, 6),
  (N'P020', N'P020-XAM-S', N'S', N'Xám', '#8E8E8E', 790000, NULL, 3),
  (N'P020', N'P020-XAM-M', N'M', N'Xám', '#8E8E8E', 790000, NULL, 6),
  (N'P020', N'P020-XAM-L', N'L', N'Xám', '#8E8E8E', 790000, NULL, 9),
  (N'P020', N'P020-XAM-XL', N'XL', N'Xám', '#8E8E8E', 820000, NULL, 10),
  (N'P021', N'P021-TRG-S', N'S', N'Trắng', '#F5F5F2', 590000, NULL, 10),
  (N'P021', N'P021-TRG-M', N'M', N'Trắng', '#F5F5F2', 590000, NULL, 13),
  (N'P021', N'P021-TRG-L', N'L', N'Trắng', '#F5F5F2', 590000, NULL, 17),
  (N'P021', N'P021-TRG-XL', N'XL', N'Trắng', '#F5F5F2', 590000, NULL, 6),
  (N'P021', N'P021-XNH-S', N'S', N'Xanh nhạt', '#A9C4DE', 590000, NULL, 10),
  (N'P021', N'P021-XNH-M', N'M', N'Xanh nhạt', '#A9C4DE', 590000, NULL, 8),
  (N'P021', N'P021-XNH-L', N'L', N'Xanh nhạt', '#A9C4DE', 590000, NULL, 16),
  (N'P021', N'P021-XNH-XL', N'XL', N'Xanh nhạt', '#A9C4DE', 590000, NULL, 3),
  (N'P022', N'P022-BE-S', N'S', N'Be', '#D9C8AE', 540000, 650000, 10),
  (N'P022', N'P022-BE-M', N'M', N'Be', '#D9C8AE', 540000, 650000, 10),
  (N'P022', N'P022-BE-L', N'L', N'Be', '#D9C8AE', 540000, 650000, 9),
  (N'P022', N'P022-BE-XL', N'XL', N'Be', '#D9C8AE', 540000, 650000, 4),
  (N'P022', N'P022-TRG-S', N'S', N'Trắng', '#F5F5F2', 540000, 650000, 7),
  (N'P022', N'P022-TRG-M', N'M', N'Trắng', '#F5F5F2', 540000, 650000, 19),
  (N'P022', N'P022-TRG-L', N'L', N'Trắng', '#F5F5F2', 540000, 650000, 17),
  (N'P022', N'P022-TRG-XL', N'XL', N'Trắng', '#F5F5F2', 540000, 650000, 8),
  (N'P023', N'P023-XNH-S', N'S', N'Xanh nhạt', '#A9C4DE', 560000, NULL, 4),
  (N'P023', N'P023-XNH-M', N'M', N'Xanh nhạt', '#A9C4DE', 560000, NULL, 16),
  (N'P023', N'P023-XNH-L', N'L', N'Xanh nhạt', '#A9C4DE', 560000, NULL, 5),
  (N'P023', N'P023-XNH-XL', N'XL', N'Xanh nhạt', '#A9C4DE', 560000, NULL, 6),
  (N'P023', N'P023-TRG-S', N'S', N'Trắng', '#F5F5F2', 560000, NULL, 6),
  (N'P023', N'P023-TRG-M', N'M', N'Trắng', '#F5F5F2', 560000, NULL, 11),
  (N'P023', N'P023-TRG-L', N'L', N'Trắng', '#F5F5F2', 560000, NULL, 8),
  (N'P023', N'P023-TRG-XL', N'XL', N'Trắng', '#F5F5F2', 560000, NULL, 6),
  (N'P024', N'P024-NAV-S', N'S', N'Xanh navy', '#1F2A44', 420000, NULL, 14),
  (N'P024', N'P024-NAV-M', N'M', N'Xanh navy', '#1F2A44', 420000, NULL, 19),
  (N'P024', N'P024-NAV-L', N'L', N'Xanh navy', '#1F2A44', 420000, NULL, 10),
  (N'P024', N'P024-NAV-XL', N'XL', N'Xanh navy', '#1F2A44', 420000, NULL, 7),
  (N'P024', N'P024-TRG-S', N'S', N'Trắng', '#F5F5F2', 420000, NULL, 14),
  (N'P024', N'P024-TRG-M', N'M', N'Trắng', '#F5F5F2', 420000, NULL, 9),
  (N'P024', N'P024-TRG-L', N'L', N'Trắng', '#F5F5F2', 420000, NULL, 14),
  (N'P024', N'P024-TRG-XL', N'XL', N'Trắng', '#F5F5F2', 420000, NULL, 5),
  (N'P024', N'P024-DEN-S', N'S', N'Đen', '#1C1C1C', 420000, NULL, 3),
  (N'P024', N'P024-DEN-M', N'M', N'Đen', '#1C1C1C', 420000, NULL, 6),
  (N'P024', N'P024-DEN-L', N'L', N'Đen', '#1C1C1C', 420000, NULL, 10),
  (N'P024', N'P024-DEN-XL', N'XL', N'Đen', '#1C1C1C', 420000, NULL, 7),
  (N'P025', N'P025-DEN-S', N'S', N'Đen', '#1C1C1C', 260000, NULL, 8),
  (N'P025', N'P025-DEN-M', N'M', N'Đen', '#1C1C1C', 260000, NULL, 18),
  (N'P025', N'P025-DEN-L', N'L', N'Đen', '#1C1C1C', 260000, NULL, 5),
  (N'P025', N'P025-DEN-XL', N'XL', N'Đen', '#1C1C1C', 260000, NULL, 5),
  (N'P025', N'P025-TRG-S', N'S', N'Trắng', '#F5F5F2', 260000, NULL, 6),
  (N'P025', N'P025-TRG-M', N'M', N'Trắng', '#F5F5F2', 260000, NULL, 7),
  (N'P025', N'P025-TRG-L', N'L', N'Trắng', '#F5F5F2', 260000, NULL, 8),
  (N'P025', N'P025-TRG-XL', N'XL', N'Trắng', '#F5F5F2', 260000, NULL, 7),
  (N'P025', N'P025-XAM-S', N'S', N'Xám', '#8E8E8E', 260000, NULL, 7),
  (N'P025', N'P025-XAM-M', N'M', N'Xám', '#8E8E8E', 260000, NULL, 13),
  (N'P025', N'P025-XAM-L', N'L', N'Xám', '#8E8E8E', 260000, NULL, 7),
  (N'P025', N'P025-XAM-XL', N'XL', N'Xám', '#8E8E8E', 260000, NULL, 5),
  (N'P026', N'P026-TRG-S', N'S', N'Trắng', '#F5F5F2', 320000, 390000, 4),
  (N'P026', N'P026-TRG-M', N'M', N'Trắng', '#F5F5F2', 320000, 390000, 20),
  (N'P026', N'P026-TRG-L', N'L', N'Trắng', '#F5F5F2', 320000, 390000, 12),
  (N'P026', N'P026-TRG-XL', N'XL', N'Trắng', '#F5F5F2', 320000, 390000, 4),
  (N'P026', N'P026-DEN-S', N'S', N'Đen', '#1C1C1C', 320000, 390000, 8),
  (N'P026', N'P026-DEN-M', N'M', N'Đen', '#1C1C1C', 320000, 390000, 18),
  (N'P026', N'P026-DEN-L', N'L', N'Đen', '#1C1C1C', 320000, 390000, 12),
  (N'P026', N'P026-DEN-XL', N'XL', N'Đen', '#1C1C1C', 320000, 390000, 8),
  (N'P027', N'P027-BE-S', N'S', N'Be', '#D9C8AE', 560000, NULL, 13),
  (N'P027', N'P027-BE-M', N'M', N'Be', '#D9C8AE', 560000, NULL, 7),
  (N'P027', N'P027-BE-L', N'L', N'Be', '#D9C8AE', 560000, NULL, 12),
  (N'P027', N'P027-BE-XL', N'XL', N'Be', '#D9C8AE', 590000, NULL, 7),
  (N'P027', N'P027-NAV-S', N'S', N'Xanh navy', '#1F2A44', 560000, NULL, 6),
  (N'P027', N'P027-NAV-M', N'M', N'Xanh navy', '#1F2A44', 560000, NULL, 12),
  (N'P027', N'P027-NAV-L', N'L', N'Xanh navy', '#1F2A44', 560000, NULL, 8),
  (N'P027', N'P027-NAV-XL', N'XL', N'Xanh navy', '#1F2A44', 590000, NULL, 10),
  (N'P027', N'P027-DEN-S', N'S', N'Đen', '#1C1C1C', 560000, NULL, 12),
  (N'P027', N'P027-DEN-M', N'M', N'Đen', '#1C1C1C', 560000, NULL, 7),
  (N'P027', N'P027-DEN-L', N'L', N'Đen', '#1C1C1C', 560000, NULL, 8),
  (N'P027', N'P027-DEN-XL', N'XL', N'Đen', '#1C1C1C', 590000, NULL, 10),
  (N'P028', N'P028-JEA-S', N'S', N'Xanh jeans', '#4A6FA5', 690000, NULL, 5),
  (N'P028', N'P028-JEA-M', N'M', N'Xanh jeans', '#4A6FA5', 690000, NULL, 15),
  (N'P028', N'P028-JEA-L', N'L', N'Xanh jeans', '#4A6FA5', 690000, NULL, 16),
  (N'P028', N'P028-JEA-XL', N'XL', N'Xanh jeans', '#4A6FA5', 720000, NULL, 5),
  (N'P028', N'P028-DEN-S', N'S', N'Đen', '#1C1C1C', 690000, NULL, 13),
  (N'P028', N'P028-DEN-M', N'M', N'Đen', '#1C1C1C', 690000, NULL, 6),
  (N'P028', N'P028-DEN-L', N'L', N'Đen', '#1C1C1C', 690000, NULL, 12),
  (N'P028', N'P028-DEN-XL', N'XL', N'Đen', '#1C1C1C', 720000, NULL, 2),
  (N'P029', N'P029-DEN-S', N'S', N'Đen', '#1C1C1C', 290000, NULL, 5),
  (N'P029', N'P029-DEN-M', N'M', N'Đen', '#1C1C1C', 290000, NULL, 17),
  (N'P029', N'P029-DEN-L', N'L', N'Đen', '#1C1C1C', 290000, NULL, 16),
  (N'P029', N'P029-DEN-XL', N'XL', N'Đen', '#1C1C1C', 290000, NULL, 2),
  (N'P029', N'P029-XAM-S', N'S', N'Xám', '#8E8E8E', 290000, NULL, 5),
  (N'P029', N'P029-XAM-M', N'M', N'Xám', '#8E8E8E', 290000, NULL, 10),
  (N'P029', N'P029-XAM-L', N'L', N'Xám', '#8E8E8E', 290000, NULL, 18),
  (N'P029', N'P029-XAM-XL', N'XL', N'Xám', '#8E8E8E', 290000, NULL, 7),
  (N'P030', N'P030-REU-S', N'S', N'Xanh rêu', '#5B6B4A', 890000, 1090000, 13),
  (N'P030', N'P030-REU-M', N'M', N'Xanh rêu', '#5B6B4A', 890000, 1090000, 18),
  (N'P030', N'P030-REU-L', N'L', N'Xanh rêu', '#5B6B4A', 890000, 1090000, 9),
  (N'P030', N'P030-REU-XL', N'XL', N'Xanh rêu', '#5B6B4A', 940000, 1140000, 8),
  (N'P030', N'P030-DEN-S', N'S', N'Đen', '#1C1C1C', 890000, 1090000, 3),
  (N'P030', N'P030-DEN-M', N'M', N'Đen', '#1C1C1C', 890000, 1090000, 11),
  (N'P030', N'P030-DEN-L', N'L', N'Đen', '#1C1C1C', 890000, 1090000, 7),
  (N'P030', N'P030-DEN-XL', N'XL', N'Đen', '#1C1C1C', 940000, 1140000, 2),
  (N'P031', N'P031-DEN-S', N'S', N'Đen', '#1C1C1C', 750000, NULL, 11),
  (N'P031', N'P031-DEN-M', N'M', N'Đen', '#1C1C1C', 750000, NULL, 8),
  (N'P031', N'P031-DEN-L', N'L', N'Đen', '#1C1C1C', 750000, NULL, 18),
  (N'P031', N'P031-DEN-XL', N'XL', N'Đen', '#1C1C1C', 780000, NULL, 2),
  (N'P031', N'P031-NAV-S', N'S', N'Xanh navy', '#1F2A44', 750000, NULL, 5),
  (N'P031', N'P031-NAV-M', N'M', N'Xanh navy', '#1F2A44', 750000, NULL, 18),
  (N'P031', N'P031-NAV-L', N'L', N'Xanh navy', '#1F2A44', 750000, NULL, 16),
  (N'P031', N'P031-NAV-XL', N'XL', N'Xanh navy', '#1F2A44', 780000, NULL, 7),
  (N'P032', N'P032-JEA-S', N'S', N'Xanh jeans', '#4A6FA5', 850000, NULL, 0),
  (N'P032', N'P032-JEA-M', N'M', N'Xanh jeans', '#4A6FA5', 850000, NULL, 0),
  (N'P032', N'P032-JEA-L', N'L', N'Xanh jeans', '#4A6FA5', 850000, NULL, 0),
  (N'P032', N'P032-JEA-XL', N'XL', N'Xanh jeans', '#4A6FA5', 850000, NULL, 0)
) AS v (ProductCode, Sku, Size, ColorName, ColorHex, Price, CompareAtPrice, StockQuantity)
JOIN dbo.Products AS p ON p.ProductCode = v.ProductCode;


/* ---- [UC05][UC12] Mã giảm giá: có mã hợp lệ, mã hết lượt, mã hết hạn, mã chưa đến hạn ---- */
INSERT dbo.Discounts (Code, Description, DiscountType, DiscountValue, MaxDiscountAmount, MinOrderValue, StartsAt, EndsAt, UsageLimit, UsedCount)
VALUES
  (N'WELCOME10', N'Giảm 10% cho đơn từ 300.000đ, tối đa 100.000đ', N'PERCENT', 10, 100000, 300000, DATEADD(DAY, -90, @now), DATEADD(DAY, 180, @now), 500, 1),
  (N'GIAM50K', N'Giảm 50.000đ cho đơn từ 500.000đ', N'FIXED', 50000, NULL, 500000, DATEADD(DAY, -90, @now), DATEADD(DAY, 180, @now), 200, 1),
  (N'SALE20', N'Giảm 20% tối đa 200.000đ cho đơn từ 1.000.000đ', N'PERCENT', 20, 200000, 1000000, DATEADD(DAY, -60, @now), DATEADD(DAY, 30, @now), 100, 1),
  (N'HETLUOT', N'Mã mẫu đã dùng hết lượt, dùng để kiểm thử', N'FIXED', 30000, NULL, 0, DATEADD(DAY, -60, @now), DATEADD(DAY, 60, @now), 1, 1),
  (N'HETHAN', N'Mã mẫu đã hết hạn, dùng để kiểm thử', N'PERCENT', 15, 150000, 0, DATEADD(DAY, -120, @now), DATEADD(DAY, -30, @now), 100, 0),
  (N'SAPDIENRA', N'Mã mẫu chưa đến ngày áp dụng, dùng để kiểm thử', N'PERCENT', 25, 250000, 0, DATEADD(DAY, 30, @now), DATEADD(DAY, 60, @now), 100, 0);


/* ---- [UC04] Đơn hàng mẫu: đủ 6 trạng thái. Ship* là bản sao địa chỉ tại lúc đặt. ---- */
INSERT dbo.Orders (OrderCode, UserId, Status, ShipRecipientName, ShipPhone, ShipProvince, ShipDistrict, ShipWard, ShipStreet, Note,
                   Subtotal, DiscountId, DiscountCode, DiscountAmount, ShippingFee, TotalAmount, PaymentMethod, StockDeducted,
                   ConsentGivenAt, CancelReason, PlacedAt, ConfirmedAt, DeliveredAt, CancelledAt, UpdatedAt)
SELECT v.OrderCode, u.UserId, v.Status, v.Recipient, v.Phone, v.Province, NULL, v.Ward, v.Street, v.Note,
       v.Subtotal, d.DiscountId, v.DiscountCode, v.DiscountAmount, v.ShippingFee, v.TotalAmount, v.PaymentMethod, v.StockDeducted,
       DATEADD(HOUR, -v.PlacedH, @now), v.CancelReason, DATEADD(HOUR, -v.PlacedH, @now),
       DATEADD(HOUR, -v.ConfirmedH, @now), DATEADD(HOUR, -v.DeliveredH, @now), DATEADD(HOUR, -v.CancelledH, @now),
       DATEADD(HOUR, -v.UpdatedH, @now)
FROM (VALUES
  (N'AMDEMO0001', N'ha.nguyen@example.com', N'DELIVERED', N'Nguyễn Thu Hà', N'0912345678', N'Hà Nội', N'Phường Mẫu', N'Số 12 ngõ 34 đường Mẫu', NULL, 1220000, NULL, 0, 0, 1220000, N'COD', 1, NULL, 720, 718, 660, NULL, 660),
  (N'AMDEMO0002', N'ha.nguyen@example.com', N'DELIVERED', N'Nguyễn Thu Hà', N'0912345678', N'Hà Nội', N'Phường Mẫu', N'Số 12 ngõ 34 đường Mẫu', NULL, 890000, N'WELCOME10', 89000, 0, 801000, N'ONLINE', 1, NULL, 600, 599, 560, NULL, 560),
  (N'AMDEMO0003', N'ha.nguyen@example.com', N'DELIVERED', N'Nguyễn Thu Hà', N'0912345678', N'Hà Nội', N'Phường Mẫu', N'Số 12 ngõ 34 đường Mẫu', NULL, 1040000, NULL, 0, 0, 1040000, N'COD', 1, NULL, 480, 478, 420, NULL, 420),
  (N'AMDEMO0004', N'an.tran@example.com', N'DELIVERED', N'Trần Minh An', N'0987654321', N'TP. Hồ Chí Minh', N'Phường Mẫu', N'45 đường Ví Dụ', NULL, 1400000, N'GIAM50K', 50000, 0, 1350000, N'COD', 1, NULL, 450, 448, 390, NULL, 390),
  (N'AMDEMO0005', N'an.tran@example.com', N'DELIVERED', N'Trần Minh An', N'0987654321', N'TP. Hồ Chí Minh', N'Phường Mẫu', N'45 đường Ví Dụ', NULL, 590000, N'HETLUOT', 30000, 0, 560000, N'ONLINE', 1, NULL, 400, 399, 350, NULL, 350),
  (N'AMDEMO0006', N'an.tran@example.com', N'RETURNED', N'Trần Minh An', N'0987654321', N'TP. Hồ Chí Minh', N'Phường Mẫu', N'45 đường Ví Dụ', NULL, 520000, NULL, 0, 0, 520000, N'COD', 0, N'Khách trả hàng vì không vừa size, shop đã nhận lại hàng và hoàn tiền', 350, 349, 300, NULL, 250),
  (N'AMDEMO0007', N'ha.nguyen@example.com', N'DELIVERED', N'Nguyễn Thu Hà', N'0912345678', N'Hà Nội', N'Phường Mẫu', N'Số 12 ngõ 34 đường Mẫu', NULL, 1290000, N'SALE20', 200000, 0, 1090000, N'ONLINE', 1, NULL, 300, 299, 250, NULL, 250),
  (N'AMDEMO0008', N'an.tran@example.com', N'CANCELLED', N'Trần Minh An', N'0987654321', N'TP. Hồ Chí Minh', N'Phường Mẫu', N'45 đường Ví Dụ', NULL, 890000, NULL, 0, 0, 890000, N'ONLINE', 0, N'Khách đổi ý, yêu cầu hủy sau khi đã thanh toán. Cần hoàn tiền cho khách', 250, 249, NULL, 230, 230),
  (N'AMDEMO0009', N'ha.nguyen@example.com', N'CANCELLED', N'Nguyễn Thu Hà', N'0912345678', N'Hà Nội', N'Phường Mẫu', N'Số 12 ngõ 34 đường Mẫu', NULL, 480000, N'WELCOME10', 48000, 30000, 462000, N'COD', 0, N'Khách tự hủy khi đơn chưa được xác nhận', 200, NULL, NULL, 190, 190),
  (N'AMDEMO0010', N'an.tran@example.com', N'DELIVERED', N'Trần Minh An', N'0987654321', N'TP. Hồ Chí Minh', N'Phường Mẫu', N'45 đường Ví Dụ', NULL, 1040000, NULL, 0, 0, 1040000, N'COD', 1, NULL, 150, 148, 90, NULL, 90),
  (N'AMDEMO0011', N'ha.nguyen@example.com', N'SHIPPING', N'Nguyễn Thu Hà', N'0912345678', N'Hà Nội', N'Phường Mẫu', N'Số 12 ngõ 34 đường Mẫu', NULL, 1890000, NULL, 0, 0, 1890000, N'COD', 1, NULL, 60, 58, NULL, NULL, 30),
  (N'AMDEMO0012', N'an.tran@example.com', N'SHIPPING', N'Trần Minh An', N'0987654321', N'TP. Hồ Chí Minh', N'Phường Mẫu', N'45 đường Ví Dụ', NULL, 970000, NULL, 0, 0, 970000, N'ONLINE', 1, NULL, 48, 47, NULL, NULL, 24),
  (N'AMDEMO0013', N'ha.nguyen@example.com', N'CONFIRMED', N'Nguyễn Thu Hà', N'0912345678', N'Hà Nội', N'Phường Mẫu', N'Số 12 ngõ 34 đường Mẫu', NULL, 790000, NULL, 0, 0, 790000, N'ONLINE', 1, NULL, 20, 19, NULL, NULL, 19),
  (N'AMDEMO0014', N'an.tran@example.com', N'CONFIRMED', N'Trần Minh An', N'0987654321', N'TP. Hồ Chí Minh', N'Phường Mẫu', N'45 đường Ví Dụ', NULL, 1080000, NULL, 0, 0, 1080000, N'COD', 1, NULL, 12, 10, NULL, NULL, 10),
  (N'AMDEMO0015', N'ha.nguyen@example.com', N'PENDING', N'Nguyễn Thu Hà', N'0912345678', N'Hà Nội', N'Phường Mẫu', N'Số 12 ngõ 34 đường Mẫu', N'Gọi trước khi giao giúp mình', 260000, NULL, 0, 30000, 290000, N'COD', 0, NULL, 5, NULL, NULL, NULL, 5),
  (N'AMDEMO0016', N'an.tran@example.com', N'PENDING', N'Trần Minh An', N'0987654321', N'TP. Hồ Chí Minh', N'Phường Mẫu', N'45 đường Ví Dụ', NULL, 540000, NULL, 0, 0, 540000, N'ONLINE', 0, NULL, 2, NULL, NULL, NULL, 2)
) AS v (OrderCode, Email, Status, Recipient, Phone, Province, Ward, Street, Note, Subtotal, DiscountCode, DiscountAmount, ShippingFee, TotalAmount, PaymentMethod, StockDeducted, CancelReason, PlacedH, ConfirmedH, DeliveredH, CancelledH, UpdatedH)
JOIN dbo.Users AS u ON u.Email = v.Email
LEFT JOIN dbo.Discounts AS d ON d.Code = v.DiscountCode;

/* ---- [UC04] Dòng hàng: UnitPrice là đơn giá tại thời điểm đặt, kèm bản sao tên/SKU/size/màu/ảnh ---- */
INSERT dbo.OrderItems (OrderId, VariantId, ProductId, ProductName, Sku, Size, ColorName, ImageUrl, UnitPrice, Quantity)
SELECT o.OrderId, pv.VariantId, pv.ProductId, p.Name, pv.Sku, pv.Size, pv.ColorName, img.ImageUrl, v.UnitPrice, v.Quantity
FROM (VALUES
  (N'AMDEMO0001', N'P002-TRG-M', 290000, 2),
  (N'AMDEMO0001', N'P007-JEA-L', 640000, 1),
  (N'AMDEMO0002', N'P014-TRG-S', 890000, 1),
  (N'AMDEMO0003', N'P010-DEN-M', 520000, 1),
  (N'AMDEMO0003', N'P004-BE-M', 520000, 1),
  (N'AMDEMO0004', N'P024-NAV-L', 420000, 2),
  (N'AMDEMO0004', N'P027-BE-L', 560000, 1),
  (N'AMDEMO0005', N'P021-TRG-L', 590000, 1),
  (N'AMDEMO0006', N'P025-DEN-M', 260000, 2),
  (N'AMDEMO0007', N'P018-DEN-S', 1290000, 1),
  (N'AMDEMO0008', N'P030-DEN-M', 890000, 1),
  (N'AMDEMO0009', N'P012-JEA-M', 480000, 1),
  (N'AMDEMO0010', N'P031-NAV-L', 750000, 1),
  (N'AMDEMO0010', N'P029-DEN-L', 290000, 1),
  (N'AMDEMO0011', N'P019-XAM-M', 1890000, 1),
  (N'AMDEMO0012', N'P006-BE-M', 590000, 1),
  (N'AMDEMO0012', N'P009-BE-M', 380000, 1),
  (N'AMDEMO0013', N'P015-HPH-S', 790000, 1),
  (N'AMDEMO0014', N'P022-BE-M', 540000, 2),
  (N'AMDEMO0015', N'P025-XAM-M', 260000, 1),
  (N'AMDEMO0016', N'P005-DEN-S', 250000, 1),
  (N'AMDEMO0016', N'P002-HPH-M', 290000, 1)
) AS v (OrderCode, Sku, UnitPrice, Quantity)
JOIN dbo.Orders AS o ON o.OrderCode = v.OrderCode
JOIN dbo.ProductVariants AS pv ON pv.Sku = v.Sku
JOIN dbo.Products AS p ON p.ProductId = pv.ProductId
OUTER APPLY (SELECT TOP (1) i.ImageUrl FROM dbo.ProductImages AS i WHERE i.ProductId = p.ProductId ORDER BY i.SortOrder) AS img;

/* ---- [UC04] Lịch sử chuyển trạng thái ---- */
INSERT dbo.OrderStatusHistory (OrderId, FromStatus, ToStatus, ChangedByUserId, Note, ChangedAt)
SELECT o.OrderId, v.FromStatus, v.ToStatus,
       CASE v.Actor WHEN N'admin' THEN @adminId ELSE o.UserId END, v.Note, DATEADD(HOUR, -v.H, @now)
FROM (VALUES
  (N'AMDEMO0001', NULL, N'PENDING', N'customer', N'Khách đặt hàng', 720),
  (N'AMDEMO0001', N'PENDING', N'CONFIRMED', N'admin', N'Admin xác nhận đơn, trừ tồn kho', 718),
  (N'AMDEMO0001', N'CONFIRMED', N'SHIPPING', N'admin', N'Đã tạo vận đơn, bàn giao đơn vị vận chuyển', 700),
  (N'AMDEMO0001', N'SHIPPING', N'DELIVERED', N'admin', N'Giao hàng thành công', 660),
  (N'AMDEMO0002', NULL, N'PENDING', N'customer', N'Khách đặt hàng', 600),
  (N'AMDEMO0002', N'PENDING', N'CONFIRMED', N'admin', N'Admin xác nhận đơn, trừ tồn kho', 599),
  (N'AMDEMO0002', N'CONFIRMED', N'SHIPPING', N'admin', N'Đã tạo vận đơn, bàn giao đơn vị vận chuyển', 590),
  (N'AMDEMO0002', N'SHIPPING', N'DELIVERED', N'admin', N'Giao hàng thành công', 560),
  (N'AMDEMO0003', NULL, N'PENDING', N'customer', N'Khách đặt hàng', 480),
  (N'AMDEMO0003', N'PENDING', N'CONFIRMED', N'admin', N'Admin xác nhận đơn, trừ tồn kho', 478),
  (N'AMDEMO0003', N'CONFIRMED', N'SHIPPING', N'admin', N'Đã tạo vận đơn, bàn giao đơn vị vận chuyển', 460),
  (N'AMDEMO0003', N'SHIPPING', N'DELIVERED', N'admin', N'Giao hàng thành công', 420),
  (N'AMDEMO0004', NULL, N'PENDING', N'customer', N'Khách đặt hàng', 450),
  (N'AMDEMO0004', N'PENDING', N'CONFIRMED', N'admin', N'Admin xác nhận đơn, trừ tồn kho', 448),
  (N'AMDEMO0004', N'CONFIRMED', N'SHIPPING', N'admin', N'Đã tạo vận đơn, bàn giao đơn vị vận chuyển', 430),
  (N'AMDEMO0004', N'SHIPPING', N'DELIVERED', N'admin', N'Giao hàng thành công', 390),
  (N'AMDEMO0005', NULL, N'PENDING', N'customer', N'Khách đặt hàng', 400),
  (N'AMDEMO0005', N'PENDING', N'CONFIRMED', N'admin', N'Admin xác nhận đơn, trừ tồn kho', 399),
  (N'AMDEMO0005', N'CONFIRMED', N'SHIPPING', N'admin', N'Đã tạo vận đơn, bàn giao đơn vị vận chuyển', 390),
  (N'AMDEMO0005', N'SHIPPING', N'DELIVERED', N'admin', N'Giao hàng thành công', 350),
  (N'AMDEMO0006', NULL, N'PENDING', N'customer', N'Khách đặt hàng', 350),
  (N'AMDEMO0006', N'PENDING', N'CONFIRMED', N'admin', N'Admin xác nhận đơn, trừ tồn kho', 349),
  (N'AMDEMO0006', N'CONFIRMED', N'SHIPPING', N'admin', N'Đã tạo vận đơn, bàn giao đơn vị vận chuyển', 340),
  (N'AMDEMO0006', N'SHIPPING', N'DELIVERED', N'admin', N'Giao hàng thành công', 300),
  (N'AMDEMO0006', N'DELIVERED', N'RETURNED', N'admin', N'Khách trả hàng vì không vừa size, shop đã nhận lại hàng và hoàn tiền', 250),
  (N'AMDEMO0007', NULL, N'PENDING', N'customer', N'Khách đặt hàng', 300),
  (N'AMDEMO0007', N'PENDING', N'CONFIRMED', N'admin', N'Admin xác nhận đơn, trừ tồn kho', 299),
  (N'AMDEMO0007', N'CONFIRMED', N'SHIPPING', N'admin', N'Đã tạo vận đơn, bàn giao đơn vị vận chuyển', 290),
  (N'AMDEMO0007', N'SHIPPING', N'DELIVERED', N'admin', N'Giao hàng thành công', 250),
  (N'AMDEMO0008', NULL, N'PENDING', N'customer', N'Khách đặt hàng', 250),
  (N'AMDEMO0008', N'PENDING', N'CONFIRMED', N'admin', N'Admin xác nhận đơn, trừ tồn kho', 249),
  (N'AMDEMO0008', N'CONFIRMED', N'CANCELLED', N'admin', N'Khách đổi ý, yêu cầu hủy sau khi đã thanh toán. Cần hoàn tiền cho khách', 230),
  (N'AMDEMO0009', NULL, N'PENDING', N'customer', N'Khách đặt hàng', 200),
  (N'AMDEMO0009', N'PENDING', N'CANCELLED', N'customer', N'Khách tự hủy khi đơn chưa được xác nhận', 190),
  (N'AMDEMO0010', NULL, N'PENDING', N'customer', N'Khách đặt hàng', 150),
  (N'AMDEMO0010', N'PENDING', N'CONFIRMED', N'admin', N'Admin xác nhận đơn, trừ tồn kho', 148),
  (N'AMDEMO0010', N'CONFIRMED', N'SHIPPING', N'admin', N'Đã tạo vận đơn, bàn giao đơn vị vận chuyển', 130),
  (N'AMDEMO0010', N'SHIPPING', N'DELIVERED', N'admin', N'Giao hàng thành công', 90),
  (N'AMDEMO0011', NULL, N'PENDING', N'customer', N'Khách đặt hàng', 60),
  (N'AMDEMO0011', N'PENDING', N'CONFIRMED', N'admin', N'Admin xác nhận đơn, trừ tồn kho', 58),
  (N'AMDEMO0011', N'CONFIRMED', N'SHIPPING', N'admin', N'Đã tạo vận đơn, bàn giao đơn vị vận chuyển', 30),
  (N'AMDEMO0012', NULL, N'PENDING', N'customer', N'Khách đặt hàng', 48),
  (N'AMDEMO0012', N'PENDING', N'CONFIRMED', N'admin', N'Admin xác nhận đơn, trừ tồn kho', 47),
  (N'AMDEMO0012', N'CONFIRMED', N'SHIPPING', N'admin', N'Đã tạo vận đơn, bàn giao đơn vị vận chuyển', 24),
  (N'AMDEMO0013', NULL, N'PENDING', N'customer', N'Khách đặt hàng', 20),
  (N'AMDEMO0013', N'PENDING', N'CONFIRMED', N'admin', N'Admin xác nhận đơn, trừ tồn kho', 19),
  (N'AMDEMO0014', NULL, N'PENDING', N'customer', N'Khách đặt hàng', 12),
  (N'AMDEMO0014', N'PENDING', N'CONFIRMED', N'admin', N'Admin xác nhận đơn, trừ tồn kho', 10),
  (N'AMDEMO0015', NULL, N'PENDING', N'customer', N'Khách đặt hàng', 5),
  (N'AMDEMO0016', NULL, N'PENDING', N'customer', N'Khách đặt hàng', 2)
) AS v (OrderCode, FromStatus, ToStatus, Actor, Note, H)
JOIN dbo.Orders AS o ON o.OrderCode = v.OrderCode;

/* ---- [UC06] Thanh toán. Cổng MOCK là cổng giả lập dùng để demo. Đơn AMDEMO0008 đã thanh toán rồi bị hủy,
        nên còn ở trạng thái PAID và cần admin bấm "Đã hoàn tiền". ---- */
INSERT dbo.Payments (OrderId, Provider, PaymentRef, Amount, Status, GatewayTxnNo, GatewayResponseCode, PaidAt, RefundedAt, CreatedAt, UpdatedAt)
SELECT o.OrderId, v.Provider, v.PaymentRef, o.TotalAmount, v.Status, v.GatewayTxnNo, v.RespCode,
       DATEADD(HOUR, -v.PaidH, @now), DATEADD(HOUR, -v.RefundH, @now), DATEADD(HOUR, -v.CreatedH, @now), DATEADD(HOUR, -v.UpdatedH, @now)
FROM (VALUES
  (N'AMDEMO0001', N'COD', NULL, N'PAID', NULL, NULL, 660, NULL, 720, 660),
  (N'AMDEMO0002', N'MOCK', N'2610000002', N'PAID', N'MOCK37941493', N'00', 600, NULL, 600, 560),
  (N'AMDEMO0003', N'COD', NULL, N'PAID', NULL, NULL, 420, NULL, 480, 420),
  (N'AMDEMO0004', N'COD', NULL, N'PAID', NULL, NULL, 390, NULL, 450, 390),
  (N'AMDEMO0005', N'MOCK', N'2610000005', N'PAID', N'MOCK41963428', N'00', 400, NULL, 400, 350),
  (N'AMDEMO0006', N'COD', NULL, N'REFUNDED', NULL, NULL, 300, 240, 350, 250),
  (N'AMDEMO0007', N'MOCK', N'2610000007', N'PAID', N'MOCK10618785', N'00', 300, NULL, 300, 250),
  (N'AMDEMO0008', N'MOCK', N'2610000008', N'PAID', N'MOCK94538503', N'00', 250, NULL, 250, 230),
  (N'AMDEMO0009', N'COD', NULL, N'CANCELLED', NULL, NULL, NULL, NULL, 200, 190),
  (N'AMDEMO0010', N'COD', NULL, N'PAID', NULL, NULL, 90, NULL, 150, 90),
  (N'AMDEMO0011', N'COD', NULL, N'PENDING', NULL, NULL, NULL, NULL, 60, 30),
  (N'AMDEMO0012', N'MOCK', N'2610000012', N'PAID', N'MOCK17089988', N'00', 48, NULL, 48, 24),
  (N'AMDEMO0013', N'MOCK', N'2610000013', N'PAID', N'MOCK37068859', N'00', 20, NULL, 20, 19),
  (N'AMDEMO0014', N'COD', NULL, N'PENDING', NULL, NULL, NULL, NULL, 12, 10),
  (N'AMDEMO0015', N'COD', NULL, N'PENDING', NULL, NULL, NULL, NULL, 5, 5),
  (N'AMDEMO0016', N'MOCK', N'2610000016', N'PENDING', NULL, NULL, NULL, NULL, 2, 2)
) AS v (OrderCode, Provider, PaymentRef, Status, GatewayTxnNo, RespCode, PaidH, RefundH, CreatedH, UpdatedH)
JOIN dbo.Orders AS o ON o.OrderCode = v.OrderCode;

/* ---- Vận đơn ---- */
INSERT dbo.Shippings (OrderId, Carrier, TrackingCode, Status, CreatedByUserId, ShippedAt, DeliveredAt)
SELECT o.OrderId, v.Carrier, v.TrackingCode, v.Status, @adminId, DATEADD(HOUR, -v.ShippedH, @now), DATEADD(HOUR, -v.DeliveredH, @now)
FROM (VALUES
  (N'AMDEMO0001', N'Viettel Post', N'VTP260000137', N'DELIVERED', 700, 660),
  (N'AMDEMO0002', N'J&T Express', N'JT260000274', N'DELIVERED', 590, 560),
  (N'AMDEMO0003', N'Giao Hàng Tiết Kiệm', N'GHTK260000411', N'DELIVERED', 460, 420),
  (N'AMDEMO0004', N'Giao Hàng Nhanh', N'GHN260000548', N'DELIVERED', 430, 390),
  (N'AMDEMO0005', N'Viettel Post', N'VTP260000685', N'DELIVERED', 390, 350),
  (N'AMDEMO0006', N'J&T Express', N'JT260000822', N'RETURNED', 340, 300),
  (N'AMDEMO0007', N'Giao Hàng Tiết Kiệm', N'GHTK260000959', N'DELIVERED', 290, 250),
  (N'AMDEMO0010', N'J&T Express', N'JT260001370', N'DELIVERED', 130, 90),
  (N'AMDEMO0011', N'Giao Hàng Tiết Kiệm', N'GHTK260001507', N'SHIPPING', 30, NULL),
  (N'AMDEMO0012', N'Giao Hàng Nhanh', N'GHN260001644', N'SHIPPING', 24, NULL)
) AS v (OrderCode, Carrier, TrackingCode, Status, ShippedH, DeliveredH)
JOIN dbo.Orders AS o ON o.OrderCode = v.OrderCode;

/* ---- [UC04] Nhật ký kho: trừ khi xác nhận, hoàn khi hủy/trả. StockAfter khớp với tồn kho hiện tại. ---- */
INSERT dbo.InventoryLogs (VariantId, OrderId, Delta, StockAfter, Reason, CreatedByUserId, CreatedAt)
SELECT pv.VariantId, o.OrderId, v.Delta, v.StockAfter, v.Reason, @adminId, DATEADD(HOUR, -v.H, @now)
FROM (VALUES
  (N'P002-TRG-M', N'AMDEMO0001', -2, 17, N'ORDER_CONFIRM', 718),
  (N'P007-JEA-L', N'AMDEMO0001', -1, 7, N'ORDER_CONFIRM', 718),
  (N'P014-TRG-S', N'AMDEMO0002', -1, 12, N'ORDER_CONFIRM', 599),
  (N'P004-BE-M', N'AMDEMO0003', -1, 17, N'ORDER_CONFIRM', 478),
  (N'P010-DEN-M', N'AMDEMO0003', -1, 19, N'ORDER_CONFIRM', 478),
  (N'P024-NAV-L', N'AMDEMO0004', -2, 10, N'ORDER_CONFIRM', 448),
  (N'P027-BE-L', N'AMDEMO0004', -1, 12, N'ORDER_CONFIRM', 448),
  (N'P021-TRG-L', N'AMDEMO0005', -1, 17, N'ORDER_CONFIRM', 399),
  (N'P025-DEN-M', N'AMDEMO0006', -2, 16, N'ORDER_CONFIRM', 349),
  (N'P018-DEN-S', N'AMDEMO0007', -1, 10, N'ORDER_CONFIRM', 299),
  (N'P025-DEN-M', N'AMDEMO0006', 2, 18, N'ORDER_RETURN', 250),
  (N'P030-DEN-M', N'AMDEMO0008', -1, 10, N'ORDER_CONFIRM', 249),
  (N'P030-DEN-M', N'AMDEMO0008', 1, 11, N'ORDER_CANCEL', 230),
  (N'P029-DEN-L', N'AMDEMO0010', -1, 16, N'ORDER_CONFIRM', 148),
  (N'P031-NAV-L', N'AMDEMO0010', -1, 16, N'ORDER_CONFIRM', 148),
  (N'P019-XAM-M', N'AMDEMO0011', -1, 12, N'ORDER_CONFIRM', 58),
  (N'P006-BE-M', N'AMDEMO0012', -1, 5, N'ORDER_CONFIRM', 47),
  (N'P009-BE-M', N'AMDEMO0012', -1, 5, N'ORDER_CONFIRM', 47),
  (N'P015-HPH-S', N'AMDEMO0013', -1, 8, N'ORDER_CONFIRM', 19),
  (N'P022-BE-M', N'AMDEMO0014', -2, 10, N'ORDER_CONFIRM', 10)
) AS v (Sku, OrderCode, Delta, StockAfter, Reason, H)
JOIN dbo.ProductVariants AS pv ON pv.Sku = v.Sku
JOIN dbo.Orders AS o ON o.OrderCode = v.OrderCode;


/* ---- [UC09] Đánh giá. Trigger TR_Reviews_OnlyDeliveredOrders chỉ cho qua khi đơn ở trạng thái "Đã giao". ---- */
INSERT dbo.Reviews (ProductId, UserId, OrderItemId, Rating, Title, Comment, CreatedAt)
SELECT oi.ProductId, o.UserId, oi.OrderItemId, v.Rating, v.Title, v.Comment, DATEADD(HOUR, -v.H, @now)
FROM (VALUES
  (N'AMDEMO0001', N'P002-TRG-M', 5, N'Vải mềm, mặc thoải mái', N'Cotton dày vừa, form suông đúng như mô tả. Mình cao 1m60 mặc size M vừa vặn.', 640),
  (N'AMDEMO0001', N'P007-JEA-L', 4, N'Quần đẹp nhưng hơi dài', N'Ống đứng, lên dáng đẹp. Mình thấp nên phải lên gấu thêm.', 640),
  (N'AMDEMO0003', N'P010-DEN-M', 5, N'Chân váy dễ phối', N'Dài ngang gối, khóa kéo êm. Phối với áo sơ mi rất hợp.', 400),
  (N'AMDEMO0007', N'P018-DEN-S', 5, N'Blazer đứng dáng', N'Vải dày vừa, vai độn nhẹ nên đứng form. Mặc đi làm rất ổn.', 230),
  (N'AMDEMO0004', N'P024-NAV-L', 4, N'Polo đúng size', N'Cổ bo gân gọn, màu navy đậm giống ảnh. Giao hàng nhanh.', 370),
  (N'AMDEMO0005', N'P021-TRG-L', 5, N'Sơ mi mặc đi làm ổn', N'Vải Oxford dày, ủi phẳng dễ. Cổ button-down gọn.', 330)
) AS v (OrderCode, Sku, Rating, Title, Comment, H)
JOIN dbo.Orders AS o ON o.OrderCode = v.OrderCode
JOIN dbo.OrderItems AS oi ON oi.OrderId = o.OrderId AND oi.Sku = v.Sku;

COMMIT TRANSACTION;

PRINT N'Hoàn tất nạp dữ liệu mẫu.';
SELECT
    (SELECT COUNT(*) FROM dbo.Users)           AS Users,
    (SELECT COUNT(*) FROM dbo.Categories)      AS Categories,
    (SELECT COUNT(*) FROM dbo.Products)        AS Products,
    (SELECT COUNT(*) FROM dbo.ProductImages)   AS ProductImages,
    (SELECT COUNT(*) FROM dbo.ProductVariants) AS ProductVariants,
    (SELECT COUNT(*) FROM dbo.Discounts)       AS Discounts,
    (SELECT COUNT(*) FROM dbo.Orders)          AS Orders,
    (SELECT COUNT(*) FROM dbo.Reviews)         AS Reviews;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
