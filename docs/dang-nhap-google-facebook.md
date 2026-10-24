# Tạo khóa đăng nhập Google và Facebook cho Kinnect

Kinnect đã có sẵn nút **Tiếp tục với Google / Facebook**. Nút chỉ hiện khi có khóa trong file `oauth.env`.
Bạn tự tạo khóa bằng tài khoản của mình, rồi dán vào `oauth.env` (sao chép từ `oauth.env.example`).
Không gửi khóa bí mật (Client secret, App secret) qua chat, email hay GitHub.

Thông tin cần dùng khi điền form:

| Mục | Giá trị |
|---|---|
| Tên ứng dụng | Kinnect |
| Trang chủ | https://kinnect.io.vn |
| Chính sách quyền riêng tư | https://kinnect.io.vn/privacy |
| Điều khoản / quy tắc | https://kinnect.io.vn/community |
| Tên miền được phép | kinnect.io.vn |
| Redirect URI Google | https://app.kinnect.io.vn/api/oauth/google/callback |
| Redirect URI Facebook | https://app.kinnect.io.vn/api/oauth/facebook/callback |
| Logo | `kinnect-website/dist/icon-512.png` |

## Google (khoảng 10 phút)

1. Mở https://console.cloud.google.com → đăng nhập Gmail của bạn → chọn **Select a project → New project**, đặt tên `Kinnect` → **Create**.
2. Menu **APIs & Services → OAuth consent screen** (hoặc **Google Auth Platform → Branding**):
   - App name: `Kinnect`, User support email: email của bạn, logo: file ở bảng trên.
   - App domain: điền trang chủ, chính sách quyền riêng tư, điều khoản như bảng trên. Authorized domain: `kinnect.io.vn`.
   - Audience / User type: **External**.
   - Scopes: chỉ cần `openid`, `email`, `profile` (không cần xét duyệt riêng).
3. **Clients (Credentials) → Create client → OAuth client ID**:
   - Application type: **Web application**, Name: `Kinnect web`.
   - Authorized redirect URIs: `https://app.kinnect.io.vn/api/oauth/google/callback`.
   - **Create** → chép **Client ID** và **Client secret** vào `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` trong `oauth.env`.
4. Ở **Audience**, bấm **Publish app** (chuyển sang *In production*). Nếu để *Testing*, chỉ những Gmail bạn thêm vào *Test users* mới đăng nhập được.

## Facebook (khoảng 15 phút + thời gian Meta duyệt)

1. Mở https://developers.facebook.com → **My Apps → Create app**.
2. Use case: **Authenticate and request data from users with Facebook Login**. Tên app `Kinnect`, email liên hệ của bạn.
3. Trong app: **Use cases → Authentication and account creation → Customize**:
   - Thêm quyền **email** (public_profile có sẵn).
   - **Settings** của Facebook Login: bật *Client OAuth login* và *Web OAuth login*; **Valid OAuth Redirect URIs**: `https://app.kinnect.io.vn/api/oauth/facebook/callback`.
4. **App settings → Basic**: điền Privacy Policy URL, Terms of Service URL, App domains `kinnect.io.vn`, icon, danh mục (Social networking). Chép **App ID** và **App secret** vào `FACEBOOK_APP_ID`, `FACEBOOK_APP_SECRET`.
5. Chuyển app sang **Live** (công tắc *App mode* hoặc **Publish**). Meta có thể yêu cầu xác minh doanh nghiệp/nhà phát triển. Khi app còn ở chế độ *Development*, chỉ tài khoản có vai trò trong app (Admin/Developer/Tester) đăng nhập được.

## Bật trên máy chủ

1. Sao chép `oauth.env.example` thành `oauth.env`, dán khóa, giữ `PUBLIC_URL=https://app.kinnect.io.vn`.
2. Chạy `stop-kinnect.cmd` rồi nhấp đúp `start-kinnect-hidden.vbs`.
3. Mở https://app.kinnect.io.vn: thấy nút **Tiếp tục với Google / Facebook** là xong.

## Cách hoạt động

- Lần đầu đăng nhập bằng Google/Facebook, người dùng xác nhận **đủ 18 tuổi** và chọn tên đăng nhập (gợi ý từ email), rồi vào app.
- Các lần sau bấm nút là vào thẳng.
- Kinnect chỉ lưu mã tài khoản Google/Facebook và email (nếu có) để nhận ra người dùng; không đăng gì lên Facebook, không đọc danh bạ.
- Tài khoản tạo bằng Google/Facebook không có mật khẩu Kinnect. Nếu cần đăng nhập bằng mật khẩu, dùng **Quên mật khẩu** để quản trị viên cấp mật khẩu tạm.
- Chỉ áp dụng cho bản web (app.kinnect.io.vn, gồm cả iPhone). App Android native hiện vẫn đăng nhập bằng tên đăng nhập/mật khẩu.
