/* ============================================================================
   AURA MODA - Website bán quần áo thời trang (kiểu IVY moda)
   File    : 01_schema.sql
   Chạy    : SSMS 22, SQL Server 2019 trở lên. Mở file này, nhấn Execute (F5).
   Lưu ý   : Script KHÔNG xóa dữ liệu. Nó tạo CSDL và bảng nếu chưa có,
             nên chạy lại nhiều lần vẫn an toàn.
   Mã UC   : Mỗi bảng ghi rõ mã Use Case mà nó phục vụ.
             [UC01] Tài khoản        [UC04] Đơn hàng + kho
             [UC05] Mã giảm giá      [UC06] Thanh toán
             [UC09] Đánh giá         [UC12] Quản lý mã giảm giá (Admin)
   Mã hóa  : Lưu file ở dạng UTF-8 (có BOM) để SSMS đọc đúng tiếng Việt.
   ============================================================================ */

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF DB_ID(N'IvyModaShop') IS NULL
    CREATE DATABASE IvyModaShop;
GO

USE IvyModaShop;
GO

/* ----------------------------------------------------------------------------
   [UC01] Users: tài khoản và phân quyền (CUSTOMER = Khách hàng, ADMIN = Quản trị viên)
   PasswordHash lưu chuỗi bcrypt (60 ký tự), không bao giờ lưu mật khẩu gốc.
   ConsentGivenAt ghi lại thời điểm khách tích đồng ý xử lý dữ liệu cá nhân.
   ---------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Users', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Users (
        UserId           INT IDENTITY(1,1)  NOT NULL CONSTRAINT PK_Users PRIMARY KEY,
        Email            NVARCHAR(255)      NOT NULL,
        PasswordHash     NVARCHAR(100)      NOT NULL,
        FullName         NVARCHAR(100)      NOT NULL,
        Phone            NVARCHAR(20)       NULL,
        DateOfBirth      DATE               NULL,
        Role             NVARCHAR(20)       NOT NULL CONSTRAINT DF_Users_Role DEFAULT N'CUSTOMER',
        IsActive         BIT                NOT NULL CONSTRAINT DF_Users_IsActive DEFAULT 1,
        ConsentGivenAt   DATETIME2(0)       NULL,
        ConsentVersion   NVARCHAR(20)       NULL,
        FailedLoginCount INT                NOT NULL CONSTRAINT DF_Users_FailedLogin DEFAULT 0,
        LockedUntil      DATETIME2(0)       NULL,
        LastLoginAt      DATETIME2(0)       NULL,
        CreatedAt        DATETIME2(0)       NOT NULL CONSTRAINT DF_Users_CreatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedAt        DATETIME2(0)       NOT NULL CONSTRAINT DF_Users_UpdatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_Users_Email UNIQUE (Email),
        CONSTRAINT CK_Users_Role  CHECK (Role IN (N'CUSTOMER', N'ADMIN'))
    );
END
GO

/* [UC01] Addresses: sổ địa chỉ giao hàng của khách.
   District cho phép NULL vì nhiều địa phương đã bỏ cấp quận/huyện.
   Chỉ có tối đa một địa chỉ mặc định cho mỗi khách (chỉ mục duy nhất có điều kiện). */
IF OBJECT_ID(N'dbo.Addresses', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Addresses (
        AddressId     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Addresses PRIMARY KEY,
        UserId        INT               NOT NULL CONSTRAINT FK_Addresses_Users REFERENCES dbo.Users(UserId) ON DELETE CASCADE,
        RecipientName NVARCHAR(100)     NOT NULL,
        Phone         NVARCHAR(20)      NOT NULL,
        Province      NVARCHAR(100)     NOT NULL,
        District      NVARCHAR(100)     NULL,
        Ward          NVARCHAR(100)     NOT NULL,
        StreetAddress NVARCHAR(255)     NOT NULL,
        IsDefault     BIT               NOT NULL CONSTRAINT DF_Addresses_IsDefault DEFAULT 0,
        CreatedAt     DATETIME2(0)      NOT NULL CONSTRAINT DF_Addresses_CreatedAt DEFAULT SYSUTCDATETIME()
    );
    CREATE INDEX IX_Addresses_User ON dbo.Addresses(UserId);
    CREATE UNIQUE INDEX UX_Addresses_OneDefault ON dbo.Addresses(UserId) WHERE IsDefault = 1;
END
GO

/* Categories: danh mục, hỗ trợ cấp cha - con (ví dụ Nữ > Váy). */
IF OBJECT_ID(N'dbo.Categories', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Categories (
        CategoryId  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Categories PRIMARY KEY,
        ParentId    INT               NULL CONSTRAINT FK_Categories_Parent REFERENCES dbo.Categories(CategoryId),
        Name        NVARCHAR(100)     NOT NULL,
        Slug        NVARCHAR(120)     NOT NULL,
        Description NVARCHAR(500)     NULL,
        SortOrder   INT               NOT NULL CONSTRAINT DF_Categories_Sort DEFAULT 0,
        IsActive    BIT               NOT NULL CONSTRAINT DF_Categories_IsActive DEFAULT 1,
        CreatedAt   DATETIME2(0)      NOT NULL CONSTRAINT DF_Categories_CreatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_Categories_Slug UNIQUE (Slug)
    );
    CREATE INDEX IX_Categories_Parent ON dbo.Categories(ParentId);
END
GO

/* Products: thông tin chung của sản phẩm. Giá, size, màu, tồn kho nằm ở ProductVariants. */
IF OBJECT_ID(N'dbo.Products', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Products (
        ProductId   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Products PRIMARY KEY,
        CategoryId  INT               NOT NULL CONSTRAINT FK_Products_Categories REFERENCES dbo.Categories(CategoryId),
        ProductCode NVARCHAR(30)      NOT NULL,
        Name        NVARCHAR(200)     NOT NULL,
        Slug        NVARCHAR(220)     NOT NULL,
        Description NVARCHAR(MAX)     NULL,
        Material    NVARCHAR(200)     NULL,
        IsFeatured  BIT               NOT NULL CONSTRAINT DF_Products_IsFeatured DEFAULT 0,
        IsActive    BIT               NOT NULL CONSTRAINT DF_Products_IsActive DEFAULT 1,
        CreatedAt   DATETIME2(0)      NOT NULL CONSTRAINT DF_Products_CreatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedAt   DATETIME2(0)      NOT NULL CONSTRAINT DF_Products_UpdatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_Products_Code UNIQUE (ProductCode),
        CONSTRAINT UQ_Products_Slug UNIQUE (Slug)
    );
    CREATE INDEX IX_Products_Category ON dbo.Products(CategoryId, IsActive);
END
GO

/* ProductImages: ảnh sản phẩm. Ảnh có SortOrder nhỏ nhất là ảnh chính, ảnh kế tiếp hiện khi rê chuột. */
IF OBJECT_ID(N'dbo.ProductImages', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProductImages (
        ImageId   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ProductImages PRIMARY KEY,
        ProductId INT               NOT NULL CONSTRAINT FK_ProductImages_Products REFERENCES dbo.Products(ProductId) ON DELETE CASCADE,
        ImageUrl  NVARCHAR(300)     NOT NULL,
        AltText   NVARCHAR(200)     NULL,
        SortOrder INT               NOT NULL CONSTRAINT DF_ProductImages_Sort DEFAULT 0
    );
    CREATE INDEX IX_ProductImages_Product ON dbo.ProductImages(ProductId, SortOrder);
END
GO

/* ProductVariants: biến thể theo (size, màu). Mỗi biến thể có SKU, giá và tồn kho riêng.
   CK_Variants_Stock chặn tồn kho âm ngay ở tầng CSDL, làm lớp bảo vệ cuối cùng chống bán quá số lượng. */
IF OBJECT_ID(N'dbo.ProductVariants', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProductVariants (
        VariantId      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ProductVariants PRIMARY KEY,
        ProductId      INT               NOT NULL CONSTRAINT FK_Variants_Products REFERENCES dbo.Products(ProductId) ON DELETE CASCADE,
        Sku            NVARCHAR(50)      NOT NULL,
        Size           NVARCHAR(5)       NOT NULL,
        ColorName      NVARCHAR(50)      NOT NULL,
        ColorHex       CHAR(7)           NOT NULL,
        Price          INT               NOT NULL,
        CompareAtPrice INT               NULL,
        StockQuantity  INT               NOT NULL CONSTRAINT DF_Variants_Stock DEFAULT 0,
        IsActive       BIT               NOT NULL CONSTRAINT DF_Variants_IsActive DEFAULT 1,
        CreatedAt      DATETIME2(0)      NOT NULL CONSTRAINT DF_Variants_CreatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedAt      DATETIME2(0)      NOT NULL CONSTRAINT DF_Variants_UpdatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_Variants_Sku UNIQUE (Sku),
        CONSTRAINT UQ_Variants_Combo UNIQUE (ProductId, Size, ColorName),
        CONSTRAINT CK_Variants_Size  CHECK (Size IN (N'S', N'M', N'L', N'XL')),
        CONSTRAINT CK_Variants_Hex   CHECK (ColorHex LIKE '#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]'),
        CONSTRAINT CK_Variants_Price CHECK (Price BETWEEN 0 AND 50000000),
        CONSTRAINT CK_Variants_Compare CHECK (CompareAtPrice IS NULL OR CompareAtPrice > Price),
        CONSTRAINT CK_Variants_Stock CHECK (StockQuantity >= 0)
    );
    CREATE INDEX IX_Variants_Product ON dbo.ProductVariants(ProductId, IsActive) INCLUDE (Size, ColorName, ColorHex, Price, StockQuantity);
END
GO

/* [UC01] Carts: giỏ hàng. Khách vãng lai dùng GuestTokenHash (băm SHA-256 của cookie),
   khách đã đăng nhập dùng UserId. Khi đăng nhập, giỏ vãng lai được gộp vào giỏ của tài khoản.
   Mỗi giỏ thuộc đúng một chủ: hoặc UserId, hoặc GuestTokenHash. */
IF OBJECT_ID(N'dbo.Carts', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Carts (
        CartId         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Carts PRIMARY KEY,
        UserId         INT               NULL CONSTRAINT FK_Carts_Users REFERENCES dbo.Users(UserId) ON DELETE CASCADE,
        GuestTokenHash NVARCHAR(64)      NULL,
        CreatedAt      DATETIME2(0)      NOT NULL CONSTRAINT DF_Carts_CreatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedAt      DATETIME2(0)      NOT NULL CONSTRAINT DF_Carts_UpdatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_Carts_Owner CHECK (
            (UserId IS NOT NULL AND GuestTokenHash IS NULL) OR
            (UserId IS NULL AND GuestTokenHash IS NOT NULL))
    );
    CREATE UNIQUE INDEX UX_Carts_User  ON dbo.Carts(UserId)         WHERE UserId IS NOT NULL;
    CREATE UNIQUE INDEX UX_Carts_Guest ON dbo.Carts(GuestTokenHash) WHERE GuestTokenHash IS NOT NULL;
END
GO

IF OBJECT_ID(N'dbo.CartItems', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.CartItems (
        CartItemId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CartItems PRIMARY KEY,
        CartId     INT               NOT NULL CONSTRAINT FK_CartItems_Carts REFERENCES dbo.Carts(CartId) ON DELETE CASCADE,
        VariantId  INT               NOT NULL CONSTRAINT FK_CartItems_Variants REFERENCES dbo.ProductVariants(VariantId),
        Quantity   INT               NOT NULL,
        AddedAt    DATETIME2(0)      NOT NULL CONSTRAINT DF_CartItems_AddedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_CartItems_Variant UNIQUE (CartId, VariantId),
        CONSTRAINT CK_CartItems_Qty CHECK (Quantity BETWEEN 1 AND 20)
    );
END
GO

/* [UC05][UC12] Discounts: mã giảm giá.
   Điều kiện áp dụng: giá trị đơn tối thiểu (MinOrderValue), thời hạn (StartsAt - EndsAt),
   số lượt dùng (UsageLimit, UsedCount). NULL ở UsageLimit nghĩa là không giới hạn lượt. */
IF OBJECT_ID(N'dbo.Discounts', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Discounts (
        DiscountId        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Discounts PRIMARY KEY,
        Code              NVARCHAR(30)      NOT NULL,
        Description       NVARCHAR(255)     NULL,
        DiscountType      NVARCHAR(10)      NOT NULL,
        DiscountValue     INT               NOT NULL,
        MaxDiscountAmount INT               NULL,
        MinOrderValue     INT               NOT NULL CONSTRAINT DF_Discounts_Min DEFAULT 0,
        StartsAt          DATETIME2(0)      NOT NULL,
        EndsAt            DATETIME2(0)      NOT NULL,
        UsageLimit        INT               NULL,
        UsedCount         INT               NOT NULL CONSTRAINT DF_Discounts_Used DEFAULT 0,
        IsActive          BIT               NOT NULL CONSTRAINT DF_Discounts_IsActive DEFAULT 1,
        CreatedAt         DATETIME2(0)      NOT NULL CONSTRAINT DF_Discounts_CreatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedAt         DATETIME2(0)      NOT NULL CONSTRAINT DF_Discounts_UpdatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_Discounts_Code   UNIQUE (Code),
        CONSTRAINT CK_Discounts_Type   CHECK (DiscountType IN (N'PERCENT', N'FIXED')),
        CONSTRAINT CK_Discounts_Value  CHECK (DiscountValue > 0 AND (DiscountType <> N'PERCENT' OR DiscountValue <= 100)),
        CONSTRAINT CK_Discounts_Max    CHECK (MaxDiscountAmount IS NULL OR MaxDiscountAmount > 0),
        CONSTRAINT CK_Discounts_Min    CHECK (MinOrderValue >= 0),
        CONSTRAINT CK_Discounts_Period CHECK (EndsAt > StartsAt),
        CONSTRAINT CK_Discounts_Usage  CHECK (UsedCount >= 0 AND (UsageLimit IS NULL OR (UsageLimit > 0 AND UsedCount <= UsageLimit)))
    );
END
GO

/* [UC04] OrderStatuses: 6 trạng thái đơn hàng theo đề bài. */
IF OBJECT_ID(N'dbo.OrderStatuses', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.OrderStatuses (
        StatusCode NVARCHAR(20) NOT NULL CONSTRAINT PK_OrderStatuses PRIMARY KEY,
        StatusName NVARCHAR(50) NOT NULL,
        SortOrder  INT          NOT NULL
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.OrderStatuses)
BEGIN
    INSERT dbo.OrderStatuses (StatusCode, StatusName, SortOrder) VALUES
        (N'PENDING',   N'Chờ xác nhận',      1),
        (N'CONFIRMED', N'Đã xác nhận',       2),
        (N'SHIPPING',  N'Đang giao',         3),
        (N'DELIVERED', N'Đã giao',           4),
        (N'CANCELLED', N'Đã hủy',            5),
        (N'RETURNED',  N'Trả hàng/Hoàn tiền', 6);
END
GO

/* [UC04] Orders: đơn hàng.
   Ship* là BẢN SAO địa chỉ giao hàng tại thời điểm đặt, nên sửa hoặc xóa địa chỉ trong sổ
   địa chỉ sau này không làm thay đổi đơn cũ.
   StockDeducted = 1 khi tồn kho đã bị trừ (lúc xác nhận), dùng để hoàn kho đúng một lần khi hủy.
   ConsentGivenAt ghi lại việc khách đã tích đồng ý xử lý dữ liệu cá nhân khi đặt hàng. */
IF OBJECT_ID(N'dbo.Orders', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Orders (
        OrderId           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Orders PRIMARY KEY,
        OrderCode         NVARCHAR(30)      NOT NULL,
        UserId            INT               NOT NULL CONSTRAINT FK_Orders_Users REFERENCES dbo.Users(UserId),
        Status            NVARCHAR(20)      NOT NULL CONSTRAINT DF_Orders_Status DEFAULT N'PENDING'
                                            CONSTRAINT FK_Orders_Status REFERENCES dbo.OrderStatuses(StatusCode),
        ShipRecipientName NVARCHAR(100)     NOT NULL,
        ShipPhone         NVARCHAR(20)      NOT NULL,
        ShipProvince      NVARCHAR(100)     NOT NULL,
        ShipDistrict      NVARCHAR(100)     NULL,
        ShipWard          NVARCHAR(100)     NOT NULL,
        ShipStreet        NVARCHAR(255)     NOT NULL,
        Note              NVARCHAR(500)     NULL,
        Subtotal          INT               NOT NULL,
        DiscountId        INT               NULL CONSTRAINT FK_Orders_Discounts REFERENCES dbo.Discounts(DiscountId),
        DiscountCode      NVARCHAR(30)      NULL,
        DiscountAmount    INT               NOT NULL CONSTRAINT DF_Orders_DiscAmt DEFAULT 0,
        ShippingFee       INT               NOT NULL CONSTRAINT DF_Orders_ShipFee DEFAULT 0,
        TotalAmount       INT               NOT NULL,
        PaymentMethod     NVARCHAR(10)      NOT NULL,
        StockDeducted     BIT               NOT NULL CONSTRAINT DF_Orders_StockDeducted DEFAULT 0,
        ConsentGivenAt    DATETIME2(0)      NOT NULL,
        CancelReason      NVARCHAR(255)     NULL,
        PlacedAt          DATETIME2(0)      NOT NULL CONSTRAINT DF_Orders_PlacedAt DEFAULT SYSUTCDATETIME(),
        ConfirmedAt       DATETIME2(0)      NULL,
        DeliveredAt       DATETIME2(0)      NULL,
        CancelledAt       DATETIME2(0)      NULL,
        UpdatedAt         DATETIME2(0)      NOT NULL CONSTRAINT DF_Orders_UpdatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_Orders_Code CHECK (LEN(OrderCode) > 0),
        CONSTRAINT CK_Orders_Method  CHECK (PaymentMethod IN (N'COD', N'ONLINE')),
        CONSTRAINT CK_Orders_Amounts CHECK (
            Subtotal >= 0 AND ShippingFee >= 0 AND DiscountAmount >= 0
            AND DiscountAmount <= Subtotal
            AND TotalAmount = Subtotal - DiscountAmount + ShippingFee)
    );
    CREATE UNIQUE INDEX UX_Orders_Code ON dbo.Orders(OrderCode);
    CREATE INDEX IX_Orders_User      ON dbo.Orders(UserId, PlacedAt DESC);
    CREATE INDEX IX_Orders_Status    ON dbo.Orders(Status, PlacedAt DESC);
    CREATE INDEX IX_Orders_Delivered ON dbo.Orders(DeliveredAt) WHERE DeliveredAt IS NOT NULL;
END
GO

/* [UC04] OrderItems: dòng hàng của đơn.
   UnitPrice là ĐƠN GIÁ TẠI THỜI ĐIỂM ĐẶT. Tên sản phẩm, SKU, size, màu cũng được sao chép sang,
   vì vậy đổi giá hay sửa sản phẩm về sau không làm sai lệch đơn cũ. */
IF OBJECT_ID(N'dbo.OrderItems', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.OrderItems (
        OrderItemId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_OrderItems PRIMARY KEY,
        OrderId     INT               NOT NULL CONSTRAINT FK_OrderItems_Orders REFERENCES dbo.Orders(OrderId),
        VariantId   INT               NOT NULL CONSTRAINT FK_OrderItems_Variants REFERENCES dbo.ProductVariants(VariantId),
        ProductId   INT               NOT NULL CONSTRAINT FK_OrderItems_Products REFERENCES dbo.Products(ProductId),
        ProductName NVARCHAR(200)     NOT NULL,
        Sku         NVARCHAR(50)      NOT NULL,
        Size        NVARCHAR(5)       NOT NULL,
        ColorName   NVARCHAR(50)      NOT NULL,
        ImageUrl    NVARCHAR(300)     NULL,
        UnitPrice   INT               NOT NULL,
        Quantity    INT               NOT NULL,
        LineTotal   AS (UnitPrice * Quantity) PERSISTED,
        CONSTRAINT CK_OrderItems_Qty   CHECK (Quantity > 0),
        CONSTRAINT CK_OrderItems_Price CHECK (UnitPrice >= 0)
    );
    CREATE INDEX IX_OrderItems_Order   ON dbo.OrderItems(OrderId);
    CREATE INDEX IX_OrderItems_Variant ON dbo.OrderItems(VariantId);
    CREATE INDEX IX_OrderItems_Product ON dbo.OrderItems(ProductId);
END
GO

/* [UC04] OrderStatusHistory: lịch sử chuyển trạng thái. Mỗi lần đổi trạng thái thêm một dòng.
   FromStatus = NULL ở dòng đầu tiên (lúc tạo đơn). */
IF OBJECT_ID(N'dbo.OrderStatusHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.OrderStatusHistory (
        HistoryId       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_OrderStatusHistory PRIMARY KEY,
        OrderId         INT               NOT NULL CONSTRAINT FK_OSH_Orders REFERENCES dbo.Orders(OrderId),
        FromStatus      NVARCHAR(20)      NULL CONSTRAINT FK_OSH_From REFERENCES dbo.OrderStatuses(StatusCode),
        ToStatus        NVARCHAR(20)      NOT NULL CONSTRAINT FK_OSH_To REFERENCES dbo.OrderStatuses(StatusCode),
        ChangedByUserId INT               NULL CONSTRAINT FK_OSH_Users REFERENCES dbo.Users(UserId),
        Note            NVARCHAR(255)     NULL,
        ChangedAt       DATETIME2(0)      NOT NULL CONSTRAINT DF_OSH_ChangedAt DEFAULT SYSUTCDATETIME()
    );
    CREATE INDEX IX_OSH_Order ON dbo.OrderStatusHistory(OrderId, ChangedAt);
END
GO

/* [UC04] InventoryLogs: sổ nhật ký kho. Ghi mỗi lần trừ tồn (xác nhận đơn) hoặc hoàn tồn (hủy, trả hàng). */
IF OBJECT_ID(N'dbo.InventoryLogs', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.InventoryLogs (
        LogId           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_InventoryLogs PRIMARY KEY,
        VariantId       INT               NOT NULL CONSTRAINT FK_InvLogs_Variants REFERENCES dbo.ProductVariants(VariantId),
        OrderId         INT               NULL CONSTRAINT FK_InvLogs_Orders REFERENCES dbo.Orders(OrderId),
        Delta           INT               NOT NULL,
        StockAfter      INT               NOT NULL,
        Reason          NVARCHAR(30)      NOT NULL,
        CreatedByUserId INT               NULL CONSTRAINT FK_InvLogs_Users REFERENCES dbo.Users(UserId),
        CreatedAt       DATETIME2(0)      NOT NULL CONSTRAINT DF_InvLogs_CreatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_InvLogs_Reason CHECK (Reason IN (N'ORDER_CONFIRM', N'ORDER_CANCEL', N'ORDER_RETURN', N'ADMIN_ADJUST'))
    );
    CREATE INDEX IX_InvLogs_Variant ON dbo.InventoryLogs(VariantId, CreatedAt DESC);
END
GO

/* [UC06] Payments: mỗi lần thanh toán là một dòng (một đơn có thể có nhiều lần thử).
   PaymentRef là mã tham chiếu gửi sang cổng thanh toán (payOS orderCode hoặc vnp_TxnRef).
   Idempotency: chỉ một dòng PAID cho mỗi đơn (UX_Payments_OnePaidPerOrder), và một mã giao dịch
   của cổng chỉ gắn được vào một dòng (UX_Payments_GatewayTxn). */
IF OBJECT_ID(N'dbo.Payments', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Payments (
        PaymentId           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Payments PRIMARY KEY,
        OrderId             INT               NOT NULL CONSTRAINT FK_Payments_Orders REFERENCES dbo.Orders(OrderId),
        Provider            NVARCHAR(10)      NOT NULL,
        PaymentRef          NVARCHAR(40)      NULL,
        Amount              INT               NOT NULL,
        Status              NVARCHAR(12)      NOT NULL CONSTRAINT DF_Payments_Status DEFAULT N'PENDING',
        GatewayTxnNo        NVARCHAR(64)      NULL,
        GatewayResponseCode NVARCHAR(20)      NULL,
        CheckoutUrl         NVARCHAR(1000)    NULL,
        ExpiresAt           DATETIME2(0)      NULL,
        PaidAt              DATETIME2(0)      NULL,
        RefundedAt          DATETIME2(0)      NULL,
        CreatedAt           DATETIME2(0)      NOT NULL CONSTRAINT DF_Payments_CreatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedAt           DATETIME2(0)      NOT NULL CONSTRAINT DF_Payments_UpdatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_Payments_Provider CHECK (Provider IN (N'COD', N'PAYOS', N'VNPAY', N'MOCK', N'SEPAY')),
        CONSTRAINT CK_Payments_Status   CHECK (Status IN (N'PENDING', N'PAID', N'FAILED', N'CANCELLED', N'REFUNDED')),
        CONSTRAINT CK_Payments_Amount   CHECK (Amount >= 0)
    );
    CREATE INDEX IX_Payments_Order ON dbo.Payments(OrderId);
    CREATE UNIQUE INDEX UX_Payments_Ref           ON dbo.Payments(Provider, PaymentRef)    WHERE PaymentRef IS NOT NULL;
    CREATE UNIQUE INDEX UX_Payments_GatewayTxn    ON dbo.Payments(Provider, GatewayTxnNo)  WHERE GatewayTxnNo IS NOT NULL;
    CREATE UNIQUE INDEX UX_Payments_OnePaidPerOrder ON dbo.Payments(OrderId)               WHERE Status = N'PAID';
END
GO

/* [UC06] PaymentWebhookLogs: nhật ký mọi lần cổng thanh toán gọi IPN/webhook, kể cả lần sai chữ ký
   và lần gửi lặp. Outcome cho biết kết quả xử lý, ví dụ DUPLICATE là thông báo lặp đã được bỏ qua. */
IF OBJECT_ID(N'dbo.PaymentWebhookLogs', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.PaymentWebhookLogs (
        LogId          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PaymentWebhookLogs PRIMARY KEY,
        Provider       NVARCHAR(10)      NOT NULL,
        PaymentRef     NVARCHAR(40)      NULL,
        GatewayTxnNo   NVARCHAR(64)      NULL,
        SignatureValid BIT               NOT NULL,
        Outcome        NVARCHAR(30)      NOT NULL,
        RawPayload     NVARCHAR(MAX)     NULL,
        SourceIp       NVARCHAR(64)      NULL,
        ReceivedAt     DATETIME2(0)      NOT NULL CONSTRAINT DF_PWL_ReceivedAt DEFAULT SYSUTCDATETIME()
    );
    CREATE INDEX IX_PWL_Ref ON dbo.PaymentWebhookLogs(Provider, PaymentRef, ReceivedAt DESC);
END
GO

/* Shippings: vận đơn do Admin tạo cho đơn đã xác nhận. Mỗi đơn có tối đa một vận đơn. */
IF OBJECT_ID(N'dbo.Shippings', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Shippings (
        ShippingId      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Shippings PRIMARY KEY,
        OrderId         INT               NOT NULL CONSTRAINT FK_Shippings_Orders REFERENCES dbo.Orders(OrderId),
        Carrier         NVARCHAR(50)      NOT NULL,
        TrackingCode    NVARCHAR(50)      NOT NULL,
        Status          NVARCHAR(12)      NOT NULL CONSTRAINT DF_Shippings_Status DEFAULT N'SHIPPING',
        Note            NVARCHAR(255)     NULL,
        CreatedByUserId INT               NULL CONSTRAINT FK_Shippings_Users REFERENCES dbo.Users(UserId),
        ShippedAt       DATETIME2(0)      NOT NULL CONSTRAINT DF_Shippings_ShippedAt DEFAULT SYSUTCDATETIME(),
        DeliveredAt     DATETIME2(0)      NULL,
        CONSTRAINT UQ_Shippings_Order  UNIQUE (OrderId),
        CONSTRAINT CK_Shippings_Status CHECK (Status IN (N'SHIPPING', N'DELIVERED', N'RETURNED'))
    );
END
GO

/* [UC09] Reviews: đánh giá sản phẩm. OrderItemId là dòng hàng đã mua, duy nhất cho mỗi đánh giá,
   nên một dòng hàng chỉ được đánh giá một lần.
   Trigger bên dưới là lớp bảo vệ ở CSDL: chỉ chấp nhận khi đơn chứa dòng hàng đó thuộc về
   chính người đánh giá và đang ở trạng thái "Đã giao" (DELIVERED). */
IF OBJECT_ID(N'dbo.Reviews', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Reviews (
        ReviewId    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Reviews PRIMARY KEY,
        ProductId   INT               NOT NULL CONSTRAINT FK_Reviews_Products REFERENCES dbo.Products(ProductId),
        UserId      INT               NOT NULL CONSTRAINT FK_Reviews_Users REFERENCES dbo.Users(UserId),
        OrderItemId INT               NOT NULL CONSTRAINT FK_Reviews_OrderItems REFERENCES dbo.OrderItems(OrderItemId),
        Rating      TINYINT           NOT NULL,
        Title       NVARCHAR(100)     NULL,
        Comment     NVARCHAR(1000)    NOT NULL,
        IsVisible   BIT               NOT NULL CONSTRAINT DF_Reviews_IsVisible DEFAULT 1,
        CreatedAt   DATETIME2(0)      NOT NULL CONSTRAINT DF_Reviews_CreatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_Reviews_OrderItem UNIQUE (OrderItemId),
        CONSTRAINT CK_Reviews_Rating CHECK (Rating BETWEEN 1 AND 5)
    );
    CREATE INDEX IX_Reviews_Product ON dbo.Reviews(ProductId, IsVisible, CreatedAt DESC);
END
GO

CREATE OR ALTER TRIGGER dbo.TR_Reviews_OnlyDeliveredOrders
ON dbo.Reviews
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    -- [UC09] Từ chối nếu dòng hàng không tồn tại, không thuộc người đánh giá,
    -- không đúng sản phẩm, hoặc đơn chưa ở trạng thái "Đã giao".
    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        LEFT JOIN dbo.OrderItems AS oi ON oi.OrderItemId = i.OrderItemId
        LEFT JOIN dbo.Orders     AS o  ON o.OrderId      = oi.OrderId
        WHERE o.OrderId IS NULL
           OR o.Status    <> N'DELIVERED'
           OR o.UserId    <> i.UserId
           OR oi.ProductId <> i.ProductId
    )
        THROW 50001, N'[UC09] Chỉ khách hàng có đơn ở trạng thái "Đã giao" mới được đánh giá sản phẩm này.', 1;
END
GO

PRINT N'Hoàn tất: đã tạo CSDL IvyModaShop và các bảng. Chạy tiếp 02_seed.sql để nạp dữ liệu mẫu.';
GO
