# Kinnect Identity / Cloudflare D1

Database `kinnect-identity` được tạo trên tài khoản Cloudflare đang đăng nhập, APAC.
Chỉ provisioning schema. Không Worker/public endpoint, không dữ liệu người dùng thật.

Áp dụng: `npx wrangler d1 migrations apply kinnect-identity --remote --config cloud-identity/wrangler.jsonc`

Kiểm tra: `npx wrangler d1 execute kinnect-identity --remote --config cloud-identity/wrangler.jsonc --command "SELECT COUNT(*) AS accounts FROM identity_accounts"`

## Điều kiện trước khi app dùng thật

- Backend hiện tại vẫn dùng SQLite. `identity_accounts` chưa phải bảng users thay thế trực tiếp.
- Cần API nội bộ xác thực máy chủ, giới hạn quyền và rate limit; không đưa Cloudflare API token hay hash/salt xuống APK. Không mở endpoint SQL tùy ý.
- Chuyển các luồng password, OAuth, khôi phục, quản trị/suspension và xóa tài khoản sang identity service; scrypt tiếp tục chạy trên máy chủ, giữ nguyên hash/salt của tài khoản cũ.
- PostgreSQL cho tin nhắn/ví chưa được tạo. Cần shadow user IDs và outbox/idempotency cho đồng bộ; không có giao dịch nguyên tử xuyên D1/PostgreSQL. Trạng thái pending chỉ active sau khi tạo dữ liệu liên quan thành công.
- Quyết định rõ nguồn dữ liệu có thẩm quyền cho profile/session; không giữ hai nơi cho phép thay mật khẩu hay role độc lập.
- Giữ quy tắc username/đăng nhập đang dùng khi di chuyển; kiểm tra xung đột chữ hoa/thường trước import.
- Snapshot SQLite nhất quán, tách BLOB media, import có kiểm đếm và đối chiếu, thử đăng nhập/khóa/xóa/khôi phục và lỗi cloud trên bản sao trước khi đổi production.
- Không tự chuyển sang SQLite khi D1 lỗi; không dùng D1 làm phần tràn tự động của PostgreSQL.

Không thay đổi máy chủ production, DNS, APK hoặc database soilfirm-db.
