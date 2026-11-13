# AURA moda: website bán quần áo thời trang (kiểu IVY moda)

Đồ án Thương mại điện tử, Học viện Ngân hàng. Công nghệ: Node.js, Express, EJS, SQL Server (SSMS 22), bcrypt.

## 1. Cài đặt

Yêu cầu: Node.js 18 trở lên, SQL Server 2019 trở lên (Express hoặc Developer đều được), SSMS 22, VS Code.

**Bước 1. Tạo CSDL.** Mở SSMS, kết nối vào server, mở lần lượt rồi nhấn Execute (F5):

1. `sql/01_schema.sql`: tạo CSDL `IvyModaShop`, 18 bảng, ràng buộc, chỉ mục và trigger đánh giá. Chạy lại nhiều lần vẫn an toàn.
2. `sql/02_seed.sql`: nạp 4 tài khoản, 11 danh mục, 32 sản phẩm, 276 biến thể, 64 ảnh, 6 mã giảm giá, 16 đơn hàng mẫu, 6 đánh giá. Nếu đã nạp rồi, script tự dừng.
3. `sql/03_create_app_login.sql` (khuyến nghị): tạo tài khoản `ivy_app` chỉ có quyền đọc và ghi. Đổi `@Matkhau` trước khi chạy.

Nếu mở file bị lỗi font tiếng Việt, chọn File > Open > mở bằng "Unicode (UTF-8)".

**Bước 2. Cấu hình kết nối.** Sao chép `.env.example` thành `.env` rồi điền:

| Biến | Ý nghĩa |
|---|---|
| `SESSION_SECRET` | Chuỗi ngẫu nhiên từ 32 ký tự. Tạo bằng `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"` |
| `DB_SERVER`, `DB_PORT` | Mặc định `localhost` và `1433` |
| `DB_INSTANCE` | Điền `SQLEXPRESS` nếu dùng bản Express có tên instance (khi đó bỏ qua `DB_PORT`) |
| `DB_AUTH` | `sql` (dùng `DB_USER`, `DB_PASSWORD`) hoặc `windows` (cần `npm install msnodesqlv8`) |
| `DB_USER`, `DB_PASSWORD` | Ví dụ `ivy_app` và mật khẩu đã đặt ở file 03 |
| `DB_TRUST_SERVER_CERT` | Để `true` khi chạy trên máy cá nhân |

Nếu không kết nối được, server vẫn khởi động và in gợi ý cách sửa ra cửa sổ lệnh (bật TCP/IP trong SQL Server Configuration Manager, bật SQL Server Browser, mở cổng 1433, bật chế độ đăng nhập hỗn hợp).

**Bước 3. Chạy.**

```
npm install
npm start
```

Mở http://localhost:3000. Chạy ở chế độ tự khởi động lại khi sửa code: `npm run dev`.

**Bước 4. Ảnh sản phẩm (bạn tự cung cấp).** Đặt ảnh vào `public/images/products/` theo tên trong `public/images/products/DANH-SACH-ANH.md`: ảnh chính `P001.jpg`, ảnh phụ `P001_2.jpg` (hiện khi rê chuột), tỉ lệ khuyến nghị 3:4. Thiếu ảnh nào, website tự hiện ảnh minh họa mặc định. Dùng đuôi khác (png, webp) thì chạy lệnh `UPDATE dbo.ProductImages SET ImageUrl = REPLACE(ImageUrl, N'.jpg', N'.webp');` trong SSMS.

## 2. Tài khoản thử nghiệm

| Vai trò | Email | Mật khẩu |
|---|---|---|
| Quản trị viên | `admin@example.com` | `Admin@123` |
| Khách hàng (có địa chỉ, có đơn) | `ha.nguyen@example.com` | `Customer@123` |
| Khách hàng (có địa chỉ, có đơn) | `an.tran@example.com` | `Customer@123` |
| Khách hàng (chưa có địa chỉ, chưa có đơn) | `mai.le@example.com` | `Customer@123` |

Mã giảm giá mẫu: `WELCOME10` (giảm 10%, tối đa 100.000₫, đơn từ 300.000₫), `GIAM50K` (giảm 50.000₫, đơn từ 500.000₫), `SALE20` (giảm 20%, tối đa 200.000₫, đơn từ 1.000.000₫). Ba mã để thử lỗi: `HETLUOT` (hết lượt), `HETHAN` (hết hạn), `SAPDIENRA` (chưa đến ngày).

Dữ liệu mẫu có sẵn các tình huống tồn kho: `P001-DEN-XL` và `P017-DOD-S` hết hàng, `P018-DEN-M` còn 1, `P001-TRG-M` còn 3, và sản phẩm `P032` hết sạch.

## 3. Bản đồ mã Use Case trong mã nguồn

Mọi chú thích đều có dạng `[UCxx]`, tìm bằng Ctrl+Shift+F.

| Mã | Nội dung | File chính |
|---|---|---|
| UC01 | Đăng ký, đăng nhập, đăng xuất, hồ sơ, sổ địa chỉ, gộp giỏ hàng vãng lai | `routes/auth.js`, `models/userModel.js`, `views/auth/`, `views/account/` |
| UC04 | Kiểm tra tồn kho khi thêm giỏ và đặt hàng, trừ kho khi xác nhận, hoàn kho khi hủy hoặc trả, 6 trạng thái, lịch sử chuyển trạng thái | `services/orderService.js`, `utils/orderStatus.js`, `models/cartModel.js` |
| UC05 | Mã giảm giá theo giá trị tối thiểu, thời hạn, số lượt | `utils/pricing.js`, `models/discountModel.js` |
| UC06 | COD, cổng thanh toán, kiểm tra chữ ký IPN, chống xử lý lặp | `services/paymentService.js`, `services/payment/`, `utils/payment/`, `routes/paymentHooks.js` |
| UC09 | Chỉ đơn "Đã giao" mới được đánh giá | `models/reviewModel.js`, trigger `TR_Reviews_OnlyDeliveredOrders` trong `sql/01_schema.sql` |
| UC12 | Quản trị mã giảm giá | `routes/admin/discounts.js` |

Tôi chỉ gắn các mã UC mà đề bài nêu. Các chức năng khác (danh mục, sản phẩm, báo cáo) không gắn mã, vì tôi không biết mã của chúng trong tài liệu học phần của bạn. Nếu tài liệu có mã cho các phần đó, hãy bổ sung chú thích.

## 4. Thanh toán online

`PAYMENT_PROVIDER` trong `.env` chọn cổng:

- `mock` (mặc định): cổng giả lập để demo. Có trang `/payment/mock/<mã>` cho phép mô phỏng thành công, thất bại, gửi lặp, sửa số tiền. Bị chặn khi `NODE_ENV=production`.
- `payos`: nhận tiền chuyển khoản vào tài khoản ngân hàng đã liên kết với payOS.
- `vnpay`: VNPay sandbox.

**Về tài khoản MB Bank của bạn.** MB Bank là ngân hàng, không phải cổng thanh toán có môi trường thử. Để website nhận tiền vào tài khoản MB, cần một cổng trung gian. Tôi viết sẵn payOS vì payOS liên kết với tài khoản ngân hàng cá nhân. Bạn cần tự đăng ký kênh thanh toán trên payOS, liên kết tài khoản MB, rồi điền `PAYOS_CLIENT_ID`, `PAYOS_API_KEY`, `PAYOS_CHECKSUM_KEY` vào `.env` (không gửi các khóa này cho ai).

**Chưa kiểm chứng.** Phần giao tiếp payOS và VNPay được viết theo hiểu biết của tôi về tài liệu của họ. Môi trường tôi làm việc không truy cập được trang tài liệu và không có tài khoản cổng thật, nên chưa chạy thử với cổng thật. Trước khi nộp, hãy đối chiếu địa chỉ API, tên trường và cách ký trong `services/payment/providers/payos.js`, `vnpay.js` và `utils/payment/signature.js` với tài liệu mới nhất. Phần kiểm tra chữ ký, so số tiền và chống xử lý lặp (dùng chung cho mọi cổng) đã được kiểm thử bằng 55 test tự động.

Webhook của cổng thật chỉ gọi được địa chỉ công khai. Khi chạy trên localhost, dùng ngrok (đặt `APP_BASE_URL` thành địa chỉ ngrok) hoặc dùng cổng `mock`.

## 5. Kịch bản kiểm thử bắt buộc

Thực hiện lần lượt, ghi kết quả (ảnh chụp) vào báo cáo.

**A. Tài khoản [UC01]**

1. Mở `/register`: cả hai ô đồng ý **không được đánh dấu sẵn**. Bỏ trống ô đồng ý rồi bấm Đăng ký: bị từ chối (cả khi tắt kiểm tra của trình duyệt, vì server kiểm tra lại).
2. Đăng ký email đã có: báo "email đã được đăng ký". Mật khẩu `12345678` hoặc ngắn hơn 8 ký tự: bị từ chối.
3. Trong SSMS chạy `SELECT Email, PasswordHash FROM dbo.Users`: mật khẩu là chuỗi bcrypt bắt đầu bằng `$2a$12$`, không phải mật khẩu gốc.
4. Đăng nhập sai mật khẩu 5 lần: tài khoản khóa tạm 15 phút.
5. Khi chưa đăng nhập, thêm 2 sản phẩm vào giỏ, rồi đăng nhập: giỏ hàng vẫn còn và được gộp vào tài khoản.
6. Đăng xuất bằng nút trên đầu trang, mở lại `/orders`: bị chuyển về trang đăng nhập.
7. Vào `/account/addresses`: thêm, sửa, đặt mặc định, xóa địa chỉ. Địa chỉ mặc định không xóa được.

**B. Phân quyền `/admin`**

1. Đăng nhập `ha.nguyen@example.com`, mở `/admin` và `/admin/orders`: trang 403.
2. Chưa đăng nhập, mở `/admin`: chuyển tới đăng nhập. Đăng nhập admin xong quay về đúng trang.
3. Khách hàng gửi POST tới `/admin/orders/<mã>/status` (dùng công cụ như Postman): bị chặn 403. Test tự động: `test/adminGuard.test.js`.

**C. Tồn kho và đặt hàng [UC04]**

1. Mở sản phẩm `P001`, chọn màu Đen: ô size XL hiện "Hết hàng" và không chọn được. Chọn Trắng, size M: hiện "Còn 3".
2. Thêm 5 cái `P001` Trắng size M vào giỏ: báo "Không đủ hàng, kho hiện chỉ còn 3".
3. Đặt hàng COD: đơn ở "Chờ xác nhận", **tồn kho chưa bị trừ**. Đơn lưu đơn giá tại lúc đặt và bản sao địa chỉ.
4. Trong admin, đổi giá một biến thể và sửa địa chỉ trong sổ địa chỉ: đơn cũ không đổi giá, không đổi địa chỉ.
5. Admin xác nhận đơn: tồn kho **bị trừ**, có dòng mới trong `dbo.InventoryLogs` (lý do `ORDER_CONFIRM`) và `dbo.OrderStatusHistory`.
6. Admin chuyển "Đang giao": bắt buộc chọn đơn vị vận chuyển và nhập mã vận đơn (tạo vận đơn). Sau đó "Đã giao thành công": đơn COD ghi nhận đã thu tiền.
7. Hủy một đơn đã xác nhận: tồn kho **được hoàn lại**, lượt dùng mã giảm giá được trả lại. Hủy đơn "Chờ xác nhận" bằng tài khoản khách: được, không đụng kho.
8. Khách hủy đơn đã "Đã xác nhận": không có nút hủy; gửi POST thủ công cũng bị từ chối.
9. Đủ 6 trạng thái: dữ liệu mẫu đã có sẵn đơn ở cả 6 trạng thái, xem tại `/admin/orders`.
10. Hai trình duyệt cùng mở một đơn, một bên xác nhận rồi bên kia bấm xác nhận: bên sau báo "trạng thái đơn đã thay đổi".

**D. Mã giảm giá [UC05][UC12]**

1. Ở trang đặt hàng, nhập `WELCOME10` với đơn dưới 300.000₫: báo cần đạt tối thiểu. Nhập `HETHAN`, `HETLUOT`, `SAPDIENRA`, mã sai: mỗi mã báo một lý do riêng.
2. Nhập `WELCOME10` với đơn hợp lệ: tổng tiền cập nhật ngay; phí giao hàng miễn phí khi đơn sau giảm giá từ 500.000₫.
3. Admin tạo mã mới (phần trăm và cố định), sửa, tạm dừng; mã tạm dừng khách không dùng được.

**E. Thanh toán [UC06]** (với `PAYMENT_PROVIDER=mock`)

1. Đặt hàng chọn "Thanh toán online", bấm các nút trên trang cổng demo:
   - "Thanh toán thành công": đơn chuyển "Đã thanh toán".
   - "Gửi thông báo hai lần": lần hai trả `DUPLICATE`, không ghi nhận lần nữa (**idempotency**).
   - "Sửa số tiền sau khi ký": trả `INVALID_SIGNATURE`, dữ liệu không đổi (**kiểm tra chữ ký**).
   - "Sai số tiền": trả `AMOUNT_MISMATCH`.
2. Trong admin, mở đơn và xem "Nhật ký thông báo từ cổng thanh toán": mọi lần gọi đều được ghi, kể cả sai chữ ký.
3. Từ dòng lệnh: `node scripts/simulate-ipn.js <paymentRef> <số tiền> replay`.
4. Đơn thanh toán online chưa nhận tiền: admin không xác nhận được. Hủy một đơn đã thanh toán online: đơn hiện "Cần hoàn tiền", admin bấm "Đã hoàn tiền" sau khi chuyển tiền thật.
5. Test tự động: `npm test` (chữ ký, xử lý lặp, tình huống thanh toán muộn, trả tiền hai lần).

**F. Đánh giá [UC09]**

1. Đăng nhập `ha.nguyen@example.com`. Sản phẩm `P014` (Đầm sơ mi thắt eo) và `P004` (Áo len mỏng cổ V) thuộc đơn "Đã giao" và chưa được đánh giá, nên trang sản phẩm hiện form "Viết đánh giá". Sản phẩm `P019`, `P015`, `P025` thuộc đơn chưa giao (đang giao, đã xác nhận, chờ xác nhận) nên **không** hiện form. `P002` đã được đánh giá trong dữ liệu mẫu nên cũng không hiện form lần nữa.
2. Gửi POST tới `/reviews` với `orderItemId` của đơn chưa giao hoặc của người khác: bị từ chối.
3. Ghi thẳng vào bảng trong SSMS, ví dụ `INSERT dbo.Reviews ...` với đơn chưa giao: trigger `TR_Reviews_OnlyDeliveredOrders` chặn với lỗi 50001.
4. Mỗi dòng hàng chỉ đánh giá được một lần.

**G. Pháp lý và bảo mật**

1. Chân trang có đủ bốn liên kết: thông tin người bán, điều khoản, bảo vệ dữ liệu cá nhân, chính sách đổi trả. Ô đồng ý ở trang đặt hàng không đánh dấu sẵn và đặt hàng không được nếu chưa tích.
2. SQL Injection: ô tìm kiếm nhập `' OR 1=1 --` và `%`: không lỗi, không lộ dữ liệu. Mọi câu SQL dùng tham số hóa.
3. XSS: đăng ký họ tên `<script>alert(1)</script>`: hiển thị nguyên chữ, không chạy. Header `Content-Security-Policy` không cho script nội tuyến.
4. CSRF: gửi form không có `csrfToken`: bị từ chối.
5. Báo cáo `/admin/reports`: doanh thu theo ngày hoặc tháng và sản phẩm bán chạy khớp với đơn "Đã giao".

## 6. Cấu trúc thư mục

```
app.js                  khởi động Express, thứ tự middleware
config/                 env.js (đọc .env), db.js (SQL Server), shop.js (thông tin cửa hàng, quy tắc)
middleware/             auth.js (guard /admin), csrf.js, rateLimit.js, cartContext.js, errorHandler.js
models/                 truy vấn SQL tham số hóa theo từng bảng
services/               orderService.js, paymentService.js, payment/ (mock, payos, vnpay)
routes/                 pages.js, auth.js, shop.js, paymentHooks.js, admin/
utils/                  validate.js, security.js, pricing.js, orderStatus.js, payment/signature.js ...
views/                  giao diện EJS (shop, auth, account, admin, legal, errors)
public/                 css, js, images
sql/                    01_schema.sql, 02_seed.sql, 03_create_app_login.sql
test/                   103 test tự động (npm test)
```

## 7. Thay thông tin cửa hàng

Thông tin người bán, phí giao hàng, ngưỡng miễn phí, số ngày đổi trả nằm ở `config/shop.js`. Thông tin hiện tại là nội dung mẫu cho đồ án; hãy thay bằng thông tin thật của nhóm. Nội dung các trang pháp lý cũng là bản mẫu, cần đối chiếu với tài liệu học phần.
