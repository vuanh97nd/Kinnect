# Rà soát Kinnect — 26/10/2026

> Bản rà soát, **chưa thay đổi gì**. Mỗi mục kèm đề xuất xử lý và mức ưu tiên (P0 = chặn/nghiêm trọng, P1 = quan trọng, P2 = cải thiện).

## 0. Cách tôi kiểm tra
- Đọc mã: `server.js`, `lib/*` (18 module), `public/index.html` + các JS/CSS chính, script khởi động, tunnel.
- Chạy **unit test**: `node --test` → **40/40 PASS** (logic backend rất vững: auth, quên mật khẩu, bạn bè, nhóm, tin nhắn, album riêng tư, cuộc gọi, nhạc...).
- Chạy thật: mở app đang chạy (cổng 3306), tạo tài khoản thử, đi qua **Khám phá, Bảng tin, Video, Hồ sơ, Tin nhắn** trên cả **desktop và mobile**, đọc console + network.
- **Chưa kiểm tra trực tiếp** (cần thiết bị/quyền camera, peer thứ hai): Live stream, gọi video, quay/đăng video (camera), Stories, Nhóm, Tin tức, Admin, bình luận reel, lời mời kết bạn. Các phần này có unit test đi kèm nên logic lõi nhiều khả năng ổn, nhưng cần test UI riêng.

**Nhận định tổng quan:** Giao diện thực tế **không "đơn sơ/xấu"** như cảm nhận — màn onboarding, đăng nhập, feed, hồ sơ, messenger đều có thiết kế khá chỉn chu (gradient, bo góc, empty state, bottom-tab mobile). Cảm giác "lỗi/chưa chuyên nghiệp" đến chủ yếu từ **hạ tầng khởi động xung đột** và **hành vi tải dữ liệu chậm/trùng lặp** ở client, chứ không phải thiếu màn hình. Xử lý được vài điểm P0/P1 dưới đây là app sẽ "mượt" và "chắc" hơn hẳn.

---

## 1. Lỗi hạ tầng & khởi động (P0)

### 1.1. Hai cơ chế tự khởi động xung đột nhau
Có **hai** bộ script chạy máy chủ + tunnel, cấu hình khác nhau:

| Script | Cổng server | Tunnel config |
|---|---|---|
| `start-kinnect-hidden.vbs` | **3000** (mặc định) | `%USERPROFILE%\.cloudflared\config.yml` |
| `scripts/windows-startup.vbs` | **3306** (ép `PORT=3306`) | `scripts/windows-tunnel.yml` → `127.0.0.1:3306` |

- Nếu cả hai cùng được gọi (hoặc chạy tay `start-kinnect.cmd` trong khi autostart đang chạy) → **`EADDRINUSE`**, tiến trình crash. Log chứng minh điều này: `data/server-restarted-error.log` và `data/server.log` đầy lỗi "address already in use 0.0.0.0:3000".
- `stop-kinnect.cmd` chỉ kill tiến trình nghe **cổng 3000** → **không dừng được** instance chạy ở 3306. Người dùng bấm "dừng" nhưng server vẫn sống.
- Dùng **cổng 3306** (vốn là cổng mặc định của MySQL) dễ gây nhầm/đụng độ về sau.

**Đề xuất (P0):** Chọn **một** cơ chế autostart duy nhất, thống nhất **một cổng** (đề xuất giữ 3000), đồng bộ cổng đó trong cả `windows-tunnel.yml`, `~/.cloudflared/config.yml` và `stop-kinnect.cmd`. Thêm bước "kill tiến trình cũ trước khi start" để tránh EADDRINUSE. Gỡ script dư thừa.

### 1.2. Thiếu tự phục hồi khi crash
Server chạy ẩn qua `wscript`, không có cơ chế **restart khi lỗi** (ngoài việc máy khởi động lại). Một lần `EADDRINUSE` hay exception là app "chết" cho tới khi có người để ý.

**Đề xuất (P1):** Bọc bằng vòng lặp tự restart (một `.cmd` lặp `node server.js`), hoặc đăng ký **Windows Service** (NSSM / `sc create`) để Windows tự giám sát và khởi động lại.

---

## 2. Lỗi/khó chịu phía client (P1)

### 2.1. Phải bấm tab hai lần nội dung mới đổi
Khi bấm **Bảng tin** từ tab Khám phá: URL đổi thành `?tab=feed` ngay, nhưng **nội dung và trạng thái sidebar không cập nhật** ở lần bấm đầu — phải bấm lần hai mới render. Lặp lại tương tự ở vài tab khác. Đây là lỗi đồng bộ giữa router (đổi URL) và render.

**Đề xuất (P1):** Rà hàm điều hướng/route trong `public/social.js` — đảm bảo đổi URL **và** render chạy trong cùng một luồng; render lại ngay khi state tab thay đổi, không chờ sự kiện thứ hai.

### 2.2. Gọi API trùng lặp mỗi lần đổi tab (ảnh hưởng hiệu năng & cảm giác "lag")
Qua panel Network: mỗi lần chuyển màn, hàng loạt endpoint bị gọi **2 lần hoặc hơn** trong cùng khoảng thời gian:
- `/api/me` ×2, `/api/notifications` **×5+**, `/api/conversations` ×2, `/api/groups` ×2, `/api/users/:id/stats` ×2, `/api/users/:id/private` ×3, `/api/me/private/requests` ×3, `/api/posts?user=...` ×2...

Đây gần như chắc chắn là nguyên nhân khiến màn hình **hiện khung xương (skeleton) ~2s** rồi mới có dữ liệu, và cảm giác app "chậm/giật". Nguyên nhân thường gặp: render chạy hai lần, listener bị gắn trùng, hoặc nhiều widget cùng tự fetch độc lập.

**Đề xuất (P1):** Gộp/đệm (cache ngắn + dedupe) các request trùng; mỗi lần đổi tab chỉ fetch những gì cần cho tab đó. Riêng `/api/notifications` nên có một nguồn duy nhất (đã có WebSocket `notifications-changed` để đẩy realtime — không cần poll nhiều lần).

### 2.3. Service Worker không đăng ký được
Console báo: `An unknown error occurred when fetching the script` (đăng ký `sw.js` thất bại) → **PWA offline, cache, và "Thêm vào màn hình chính" hoạt động kém tin cậy**, nhất là trên iOS vốn là kênh cài đặt chính của app.

**Đề xuất (P1):** Kiểm tra đường dẫn/scope `sw.js` và phản hồi của server cho `/sw.js` (đang được phục vụ, nhưng cần đúng `Content-Type` và không bị CSP chặn). Xác nhận SW đăng ký thành công trên HTTPS thật (qua domain `app.kinnect.io.vn`).

### 2.4. Một tài nguyên trả 401 khi tải trang
Console có `401 (Unauthorized)` khi vào tab Video. Không chặn chức năng chính nhưng là request thừa/sai thời điểm (gọi trước khi xác thực xong).

**Đề xuất (P2):** Tìm request 401 và hoãn tới sau khi `/api/me` xác thực xong, hoặc bỏ nếu không cần.

---

## 3. Tính năng chưa đầy đủ / chưa bật (P1–P2)

### 3.1. Đăng nhập Google/Facebook bị tắt
`lib/oauth.js` đã viết sẵn luồng OAuth và unit test có phần Google login, **nhưng `oauth.env` không tồn tại** (chỉ có `oauth.env.example`). Vì vậy hai nút "Tiếp tục với Google/Facebook" đang để `hidden` — người dùng **không có** đăng nhập mạng xã hội.

**Đề xuất (P1):** Hoặc cấu hình `oauth.env` (client id/secret) để bật, hoặc chủ động ẩn hẳn khỏi UI để không tạo kỳ vọng. Nếu định ra mắt, OAuth gần như là tiêu chuẩn kỳ vọng của người dùng.

### 3.2. Gọi video Internet phụ thuộc TURN mong manh
`turn.env` dùng provider qua **token HuggingFace** (`KINNECT_HF_TOKEN`). Footer cũng ghi "Video Internet cần TURN/SFU". Cách này dễ hết hạn/giới hạn, và với nhiều người xem một phòng live thì mô hình P2P WebRTC (giới hạn 6 người xem/phòng trong code) **không mở rộng được**.

**Đề xuất (P2):** Nếu nhắm tới live nhiều người, cần **SFU** (mediasoup/LiveKit) thay vì mesh P2P. Trước mắt, chuyển TURN sang dịch vụ ổn định (Cloudflare Calls TURN, Twilio, hoặc coturn tự dựng).

### 3.3. E2E (Playwright) đang timeout
`test-results/.last-run.json` cho thấy lần chạy gần nhất **`timedout`** + 1 test fail. Có ~50 file `.spec.js` (bao phủ rất rộng), nhưng nếu suite không chạy xanh thì không còn tác dụng bảo vệ.

**Đề xuất (P1):** Ổn định lại e2e (tăng timeout hợp lý, sửa test chập chờn, đảm bảo server test khởi động sạch). Đây là "lưới an toàn" quý giá cho một codebase lớn như vậy.

### 3.4. Nội dung video mẫu là clip TikTok có watermark (rủi ro bản quyền)
Tab Video phát các clip có watermark **TikTok / kenh14.vn**. Dù chỉ là dữ liệu mẫu, nếu lên production đây là **rủi ro bản quyền** rõ ràng.

**Đề xuất (P1 trước khi ra mắt):** Thay bằng nội dung tự quay/được cấp phép, hoặc để trống chờ người dùng đăng.

---

## 4. Giao diện & UX — điểm nâng chất (P2)

Nền tảng thiết kế đã tốt; các điểm dưới đây là **đánh bóng** để "chuyên nghiệp" hơn:
- **Toast dính màn hình:** thông báo "Chào QA Reviewer!" nằm đè lên nội dung khá lâu và che bài viết. Nên tự ẩn sau ~2–3s và không che vùng thao tác.
- **Skeleton kéo dài ~2s** (hệ quả mục 2.2) khiến cảm giác "trống/chưa xong". Khi sửa được việc fetch trùng, cảm giác này sẽ biến mất.
- **Nhất quán thành phần:** nút "Thêm vào tin" ở Hồ sơ đang là một khối tím full-width khá nặng so với phần còn lại; nên hạ cấp thị giác (outline/secondary).
- **Hệ thiết kế rải rác:** CSS tách thành nhiều file lớn (`theme.css` 2.572 dòng, `compact.css` 1.081, `desktop.css`, `live.css`, `messenger.css`, `studio.css`...). Dễ phát sinh lệch màu/khoảng cách giữa các màn. Nên gom **design tokens** (màu, spacing, radius, bóng) về một nơi và tái dùng.
- Khuyến nghị một **buổi rà UI chuyên sâu theo từng màn** (live, camera/quay video, nhóm, stories) — tôi mới xem được 5 màn chính.

---

## 5. Chất lượng mã & bảo trì (P2)
- **File quá lớn:** `public/social.js` **2.451 dòng** và `lib/social.js` **1.240 dòng** gom quá nhiều trách nhiệm → khó sửa, dễ sinh lỗi "double render/double fetch" như mục 2. Nên tách theo tính năng (feed, messenger, profile, discover...).
- **Điểm cộng:** backend tách module gọn (18 file trong `lib/`), có migration dữ liệu cũ (test xác nhận), CSP + security headers nghiêm túc, rate-limit WebSocket, kiểm tra origin. Phần nền này làm tốt.

---

## 6. Thứ tự ưu tiên đề xuất

**P0 — làm ngay (ổn định vận hành):**
1. Thống nhất một cơ chế autostart + một cổng; sửa `stop-kinnect.cmd` đúng cổng (mục 1.1).

**P1 — quan trọng (chất lượng cảm nhận & tính năng):**
2. Sửa điều hướng phải-bấm-hai-lần (2.1).
3. Dedupe/giảm gọi API trùng lặp → hết lag/skeleton (2.2).
4. Sửa đăng ký Service Worker cho PWA/iOS (2.3).
5. Bật hoặc ẩn hẳn OAuth (3.1); ổn định lại e2e (3.3); thay nội dung video mẫu (3.4).
6. Tự phục hồi khi server crash (1.2).

**P2 — cải thiện dần:**
7. Đánh bóng UX (toast, nút, empty state) + gom design tokens (mục 4).
8. Tách nhỏ `social.js` (mục 5); kế hoạch SFU/TURN ổn định cho live (3.2).

---

*Tôi chưa chỉnh sửa bất cứ file nào. Khi bạn chọn mục muốn xử lý, tôi sẽ đi vào sửa từng phần.*
