/* ============================================================================
   AURA MODA - Tạo tài khoản SQL Server riêng cho ứng dụng (khuyến nghị)
   File    : 03_create_app_login.sql   (chạy SAU 01_schema.sql)
   Mục đích: ứng dụng chỉ cần đọc và ghi dữ liệu, không cần quyền sa hay quyền sửa cấu trúc.
             Tài khoản ivy_app chỉ có quyền db_datareader và db_datawriter trên CSDL IvyModaShop.
   Cách dùng: 1) Đổi giá trị @Matkhau ở dưới thành mật khẩu mạnh của riêng bạn (tối thiểu 12 ký tự).
              2) Nhấn Execute (F5) trong SSMS.
              3) Điền DB_USER=ivy_app và DB_PASSWORD=<mật khẩu đó> vào file .env.
   Lưu ý   : SQL Server phải bật chế độ "SQL Server and Windows Authentication mode"
             (SSMS > chuột phải tên server > Properties > Security), rồi khởi động lại dịch vụ SQL Server.
   Mã hóa  : Lưu file UTF-8 (có BOM) để SSMS đọc đúng tiếng Việt.
   ============================================================================ */
USE master;
GO

DECLARE @Matkhau NVARCHAR(128) = N'<<DAT_MAT_KHAU_MANH_O_DAY>>';

IF @Matkhau LIKE N'<<%'
    THROW 50000, N'Bạn chưa đổi mật khẩu. Hãy sửa giá trị @Matkhau ở đầu file rồi chạy lại.', 1;

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'ivy_app')
BEGIN
    DECLARE @sql NVARCHAR(MAX) =
        N'CREATE LOGIN ivy_app WITH PASSWORD = ' + QUOTENAME(@Matkhau, '''') +
        N', CHECK_POLICY = ON, DEFAULT_DATABASE = IvyModaShop;';
    EXEC (@sql);
    PRINT N'Đã tạo login ivy_app.';
END
ELSE
    PRINT N'Login ivy_app đã tồn tại, giữ nguyên mật khẩu cũ.';
GO

USE IvyModaShop;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'ivy_app')
    CREATE USER ivy_app FOR LOGIN ivy_app;
GO

ALTER ROLE db_datareader ADD MEMBER ivy_app;
ALTER ROLE db_datawriter ADD MEMBER ivy_app;
GO

PRINT N'Hoàn tất: ivy_app có quyền đọc và ghi dữ liệu trên IvyModaShop.';
GO
