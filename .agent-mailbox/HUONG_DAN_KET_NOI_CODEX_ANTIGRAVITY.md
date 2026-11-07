# Hướng dẫn Kết nối Hai Chiều Giữa OpenAI Codex và Antigravity IDE

## 1. Thông tin phiên làm việc
* **OpenAI Codex Thread ID**: `01a1b659-f0cf-7192-b581-65591fa047db`
* **Antigravity IDE Session ID**: `b8e11388-823f-44c8-a8a2-cdbee0647980`
* **Workspace**: `D:\Codex\Kinnect`

---

## 2. Vì sao lệnh gọi CLI cũ gây lỗi 429 và nhầm phiên?
1. Lệnh `agy.exe -p ...` (hoặc `Send-Antigravity.ps1` bản cũ) chạy mô hình AI dạng **Headless CLI**. Mỗi lần gọi sẽ:
   - Tạo ra một session AI mới toanh (`2706868b-0eff-4b8f-b7d7-1aa6becb45e6`), không phải phiên IDE `b8e11388-823f-44c8-a8a2-cdbee0647980` đang code và giữ ngữ cảnh.
   - Tiêu tốn hạn mức AI API độc lập của người dùng dẫn đến lỗi **HTTP 429 Quota Exceeded**.
   - Cố nối lại bằng `--conversation b8e11388-...` sẽ bị `not_found: trajectory not found` vì cơ sở dữ liệu trajectory của Antigravity IDE UI tách biệt với CLI headless runner.

---

## 3. Giao thức kết nối chuẩn (0 Quota, Không xung đột, Tự động hóa)

### Chiều 1: Codex gửi yêu cầu sang Antigravity IDE
Codex chỉ cần chạy lệnh PowerShell sau:
```powershell
powershell.exe -ExecutionPolicy Bypass -File "D:\Codex\Kinnect\scripts\Send-Antigravity.ps1" -Message "<Nội dung yêu cầu / review chi tiết>"
```
*Lưu ý:*
- Script `Send-Antigravity.ps1` đã được cấu hình tự động ghi yêu cầu vào `.agent-mailbox\requests\req-<id>.json` và cập nhật `.agent-mailbox\codex-session.json`.
- Hoàn toàn **0 tốn token API** (Zero-Quota), không bao giờ bị 429.
- Sau khi chạy lệnh trên, Codex thông báo cho User:
  > *"Đã gửi yêu cầu vào Mailbox cho phiên Antigravity IDE `b8e11388-823f-44c8-a8a2-cdbee0647980`. Bạn vui lòng gõ `tiếp tục` ở cửa sổ chat Antigravity IDE để agent thực thi."*

### Chiều 2: Antigravity IDE phản hồi sang Codex
Khi nhận được thông báo từ User, Antigravity IDE sẽ:
1. Đọc nội dung yêu cầu trong `.agent-mailbox\requests\`.
2. Thực thi sửa mã nguồn, commit git, build CI, chụp Simulator, so sánh màn hình APK Android vs iOS.
3. Cập nhật kết quả vào `.agent-mailbox\responses\req-<id>.json`.
4. Gọi tự động:
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File "D:\Codex\Kinnect\scripts\Send-Codex.ps1" -ThreadId "01a1b659-f0cf-7192-b581-65591fa047db" -Message "<Báo cáo kết quả>"
   ```
   Lệnh này đưa tin nhắn trực tiếp vào hàng đợi của Codex Thread `01a1b659-f0cf-7192-b581-65591fa047db`.

---

## 4. Tóm tắt quy trình phối hợp cho Codex
1. **Kiểm tra trạng thái**: Đọc file `.agent-mailbox\responses\req-*.json` hoặc `.agent-mailbox\codex-session.json`.
2. **Giao việc mới**: Gọi `Send-Antigravity.ps1 -Message "..."`.
3. **Nhắc User**: Yêu cầu User gõ `tiếp tục` ở cửa sổ chat Antigravity IDE.
4. **Nhận kết quả**: Đọc phản hồi tự động được đẩy về queue thread Codex từ Antigravity IDE.

