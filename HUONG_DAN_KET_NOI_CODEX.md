# Hướng dẫn Kết nối dành riêng cho Codex (`HUONG_DAN_KET_NOI_CODEX.md`)

Tài liệu này hướng dẫn phiên Codex (`01a1887d-0a8d-7b60-8a8c-25b9da8a1f93`) cách gửi yêu cầu và nhận kết quả trực tiếp với **Phiên IDE Antigravity đang chạy** (`b8e11388-823f-44c8-a8a2-cdbee0647980`), **tránh lỗi hạn mức 429 của CLI**.

---

## 1. Bản chất hai phiên Antigravity

- **Phiên 1: Antigravity IDE (chính)** — ID: `b8e11388-823f-44c8-a8a2-cdbee0647980`
  - Đây là phiên đang trực tiếp chỉnh sửa mã nguồn iOS Native, chạy macOS CI, chụp ảnh Simulator và quản lý workspace Kinnect.
  - Phiên này **không nhận lệnh trực tiếp qua CLI `agy.exe`** (do CLI tạo session mới).
  - Phiên này kết nối với Codex thông qua **Hộp thư Workspace (`.agent-mailbox/`)**.
- **Phiên 2: Antigravity CLI** — `agy.exe`
  - Mỗi lần gọi `agy.exe -p ...` sẽ gọi một lượt mô hình AI mới qua Cloud API.
  - Nếu gọi dồn dập sẽ bị **Lỗi 429 (ResourceExhausted / Quota Exceeded)**.
  - **Khuyến nghị**: Không dùng `agy.exe` để gửi chỉ thị lặp đi lặp lại.

---

## 2. Quy trình Kết nối Chuẩn (Zero-Quota, Không bị 429)

### Bước 1: Codex gửi yêu cầu vào Hộp thư
Khi Codex cần giao việc mới cho Antigravity IDE, Codex ghi file:
`D:\Codex\Kinnect\.agent-mailbox\requests\<mã_yêu_cầu>.json`

**Cấu trúc file JSON chuẩn:**
```json
{
  "id": "req-ios-design-parity-v2-followup",
  "sender": "codex",
  "targetConversationId": "b8e11388-823f-44c8-a8a2-cdbee0647980",
  "prompt": "Nội dung chỉ thị chi tiết cần thực hiện...",
  "createdAt": "2026-11-07T03:50:34.996Z",
  "status": "pending"
}
```
*Hoặc Codex có thể chạy lệnh helper:*
```powershell
node D:\Codex\Kinnect\scripts\agent-mailbox.mjs send --id <mã_yêu_cầu> --prompt "<nội dung>"
```

---

### Bước 2: Antigravity IDE nhận và thực thi
Phiên IDE Antigravity (`b8e11388-823f-44c8-a8a2-cdbee0647980`) sẽ:
1. Đọc file yêu cầu trong `.agent-mailbox/requests/`.
2. Ghi file phản hồi xác nhận tại `.agent-mailbox/responses/<mã_yêu_cầu>.json` với trạng thái `running`.
3. Bắn tin ACK trực tiếp vào hàng đợi của thread Codex `01a1887d-0a8d-7b60-8a8c-25b9da8a1f93` qua lệnh:
   ```powershell
   & "$env:LOCALAPPDATA\OpenAI\Codex\bin\a159911ff70742e9\codex.exe" queue --thread 01a1887d-0a8d-7b60-8a8c-25b9da8a1f93 --message "ACK: ..." --resume
   ```
4. Thực hiện toàn bộ mã nguồn, build và chụp ảnh.

---

### Bước 3: Codex kiểm tra kết quả hoàn tất
Codex có thể kiểm tra kết quả bằng cách đọc file phản hồi tương ứng:
`D:\Codex\Kinnect\.agent-mailbox\responses\<mã_yêu_cầu>.json`

File phản hồi có cấu trúc:
```json
{
  "id": "req-ios-design-parity-v2-followup",
  "conversationId": "b8e11388-823f-44c8-a8a2-cdbee0647980",
  "status": "completed",
  "summary": "Tóm tắt kết quả...",
  "artifacts": [
    "D:\\Codex\\Kinnect\\dist\\ios-ui-review\\..."
  ],
  "error": null
}
```

*Hoặc Codex chạy lệnh kiểm tra trạng thái:*
```powershell
node D:\Codex\Kinnect\scripts\agent-mailbox.mjs status --id <mã_yêu_cầu>
```

---

## 3. Trạng thái Hiện tại của Yêu cầu `req-ios-design-parity-v2-followup`

- **Phiên IDE Antigravity**: Đã chuyển trạng thái sang **`running`**.
- **Chuẩn APK Android**: `D:\Codex\Kinnect\dist\google-play\Kinnect-1.2.12-play-test.apk` (versionName 1.2.12, versionCode 118, SHA256 6115E3F836D1AD0CAB9F141DC009B9990F9D00FB6E9544EA209DDEA1A4FC9AA4).
- **Hạng mục đang triển khai**:
  1. Thanh điều hướng 5 tab: `Bảng tin` · `Khám phá` · `(+) Camera` · `Video` · `Live`.
  2. Nút `Studio Pro` ở góc phải màn hình xem trước kèm nút Lưu/Thoát riêng biệt.
  3. Luồng xem Live vuốt chung; tạo Live phân nhánh Trò chuyện/Chơi game từ Camera.
  4. Màn hình Ví tách bạch số dư `Xu mua` và `Xu tặng`.
  5. iPad tối ưu 2 cột chat khi đủ không gian màn hình.
