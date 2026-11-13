/* Chạy một lần trên CSDL đã có để cho phép lưu giao dịch QR SePay. */
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Payments_Provider' AND parent_object_id = OBJECT_ID(N'dbo.Payments'))
    ALTER TABLE dbo.Payments DROP CONSTRAINT CK_Payments_Provider;
ALTER TABLE dbo.Payments ADD CONSTRAINT CK_Payments_Provider
    CHECK (Provider IN (N'COD', N'PAYOS', N'VNPAY', N'MOCK', N'SEPAY'));
GO
