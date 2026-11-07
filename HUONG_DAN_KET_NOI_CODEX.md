# Hướng dẫn Kết nối Hai Chiều Antigravity IDE ↔ OpenAI Codex (`HUONG_DAN_KET_NOI_CODEX.md`)

Tài liệu này chuẩn hóa giao thức kết nối thời gian thực hai chiều giữa **Phiên Codex CLI đang chạy** (`01a1b659-f0cf-7192-b581-65591fa047db`) và **Phiên Antigravity IDE GUI** (`b8e11388-823f-44c8-a8a2-cdbee0647980`), hoàn toàn không tiêu tốn quota AI và không bao giờ gặp lỗi HTTP 429.

---

## 1. Thông Tin Hai Phiên Đang Hoạt Động

- **Phiên Antigravity IDE (GUI)**:
  - **Conversation ID**: `b8e11388-823f-44c8-a8a2-cdbee0647980`
  - **Vai trò**: Trực tiếp sửa đổi mã nguồn iOS Native, backend Node.js, bộ kiểm thử bảo mật tự động, điều phối CI GitHub Actions runner, chụp màn hình Simulator và trích xuất artifact.
  - **Hộp thư lắng nghe**: `D:\Codex\Kinnect\.agent-mailbox\`
- **Phiên OpenAI Codex (CLI)**:
  - **Thread ID**: `01a1b659-f0cf-7192-b581-65591fa047db`
  - **Vai trò**: Đánh giá kiến trúc, kiểm tra tĩnh (static review), thẩm định bảo mật App Store và đề xuất chỉ thị kỹ thuật.

---

## 2. Cách Codex Gửi Tin Nhắn / Chỉ Thị / Đánh Giá Cho Antigravity IDE

Khi Codex cần gửi phản hồi hoặc giao nhiệm vụ mới cho Antigravity IDE, Codex có 2 lựa chọn:

### Cách 1: Sử dụng Script PowerShell có sẵn (Khuyên dùng - Nhanh nhất)
Chạy lệnh trực tiếp trong Terminal của Codex:
```powershell
powershell.exe -ExecutionPolicy Bypass -File "D:\Codex\Kinnect\scripts\Send-Antigravity.ps1" -Message "<Nội dung đánh giá, phản hồi hoặc chỉ thị mới của Codex>"
```
*Script này đã được cấu hình mặc định trỏ đến conversation `b8e11388-823f-44c8-a8a2-cdbee0647980`, tự động tạo file JSON có timestamp tại `.agent-mailbox\requests\req-codex-<timestamp>.json` và cập nhật `.agent-mailbox\codex-session.json`.*

### Cách 2: Ghi trực tiếp file JSON qua Python
```python
import json, datetime
from pathlib import Path

req_id = f"req-codex-{datetime.datetime.now().strftime('%Y%m%d-%H%M%S')}"
req_data = {
    "id": req_id,
    "sender": "codex",
    "targetConversationId": "b8e11388-823f-44c8-a8a2-cdbee0647980",
    "prompt": "<Nội dung phản hồi hoặc chỉ thị từ Codex>",
    "createdAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "status": "pending"
}
Path(r"D:\Codex\Kinnect\.agent-mailbox\requests\" + f"{req_id}.json").write_text(
    json.dumps(req_data, indent=2, ensure_ascii=False),
    encoding="utf-8"
)
```

---

## 3. Cách Antigravity IDE Gửi Phản Hồi Cho Codex

Antigravity IDE tự động bắn kết quả vào hàng đợi của phiên Codex qua lệnh:
```powershell
powershell.exe -ExecutionPolicy Bypass -File "D:\Codex\Kinnect\scripts\Send-Codex.ps1" -ThreadId "01a1b659-f0cf-7192-b581-65591fa047db" -Message "<Báo cáo tiến độ và kết quả từ Antigravity>"
```
Đồng thời, Antigravity IDE ghi kết quả chi tiết kèm artifact vào thư mục:
`D:\Codex\Kinnect\.agent-mailbox\responses\<mã_yêu_cầu>.json`

---

## 4. Trạng Thái Hiện Tại Của Dự Án Kinnect iOS Native (Commit `fdec976`)

- **GitHub Actions CI Run 80 (`42388419096`)**: **XANH 100% (PASS TẤT CẢ JOBS)**
  - `Build Native iOS Sideload IPA`: Thành công (Bản IPA `13,129,311 bytes` đã xuất bản lên GitHub Release `ios-v1.2.12`).
  - `Capture Native iOS Simulator UI Review Screenshots`: Thành công (**56 ảnh chụp giao diện** đã trích xuất về `dist/ios-ui-review-fdec976`).
- **P0 Critical Security**:
  - Xác thực chữ ký mã hóa RS256 chuẩn cho Apple Auth (`/api/auth/apple`) trong `lib/oauth.js` bằng Node.js crypto.
  - Fail closed (401) trước mọi truy vấn DB nếu token giả mạo, sai iss/aud/exp/alg/kid.
  - Đã kiểm thử 12 ca phủ kín các trường hợp tiêu cực trong `test/test_live_and_contracts_e2e.mjs`: **100% PASS**.
- **P1 Client & Studio Parity**:
  - Xóa bỏ fallback JWT giả lập khỏi `AuthView.swift`.
  - Phân nhánh lưu video `if isVideoActive` trước tiên trong `CameraStudioView.swift`.
  - Tiêu thụ xoay video 0°, 90°, 180°, 270° trong `StudioMediaEngine.swift`.
  - Sửa lỗi biên dịch và truyền tham số tường minh cho `PrivacyConsentSheet`.
- **Kỷ luật dữ liệu**:
  - Bảo lưu nguyên vẹn **67 phân cảnh phụ** ở trạng thái `PENDING_SUBSTATE_VERIFICATION`.
