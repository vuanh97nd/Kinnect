# TURN và kiểm thử Kinnect

## Cấu hình đang dùng

Kinnect giữ Hugging Face làm nhà cung cấp TURN. `turn.env` nằm ở thư mục dự án, được gitignore. Không chuyển sang Cloudflare/coturn trong phiên này.

- `KINNECT_TURN_PROVIDER=huggingface`
- `KINNECT_HF_TOKEN`: token chính, chỉ phía server.
- `KINNECT_HF_TOKEN_BACKUP`: tùy chọn, dùng khi token chính bị từ chối xác thực hoặc dịch vụ lỗi.

Chạy `node scripts/check-auth-call-config.js --turn` để gọi dịch vụ và đếm cấu hình relay hợp lệ; lệnh không in token, username hay password TURN. Cấp ICE thành công chưa chứng minh một phiên media đã đi qua relay trên hai mạng khác nhau.

Cuộc gọi riêng và livestream đều đọc `/api/call-config`. Server gom request đang chạy, cache một phút, bỏ cổng 53 và chỉ trả credentials TURN ngắn hạn cho thành viên đã đăng nhập. Client livestream xử lý SDP/ICE tuần tự cho từng peer và hủy tác vụ khi rời phòng.

## Chạy test

```powershell
node --test
npx playwright test --retries=0
```

Playwright tự dùng Chrome đã cài ở vị trí chuẩn trên Windows để hỗ trợ MP4/H.264. Máy khác mặc định dùng Chromium đầy đủ; cài bằng `npx playwright install chromium`. Có thể chọn rõ trình duyệt qua `PLAYWRIGHT_CHANNEL=chrome` hoặc `chromium`, hoặc trỏ `PLAYWRIGHT_CHROMIUM_EXECUTABLE` tới binary cần dùng.

Trong sandbox có cache browser tạm đổi theo lần chạy, đặt `PLAYWRIGHT_BROWSERS_PATH` vào một thư mục ổn định trước cả lệnh install và test. Nếu cổng 3210 đang bận, dùng `E2E_PORT` khác. Không cần dừng server production cổng 3000 để chạy test.

Test `live-turn.spec.js` cấp cấu hình TURN giả tại API để kiểm tra nó tới cả host/viewer, rồi kiểm tra video thật qua kết nối cục bộ. Test này không sử dụng token thật hoặc đo khả năng xuyên NAT của Hugging Face. Kiểm tra Internet thực cần hai thiết bị ở hai mạng khác nhau và xem candidate pair có loại relay.
