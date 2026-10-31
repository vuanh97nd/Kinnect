# Chuẩn bị cơ sở dữ liệu đám mây Kinnect

Trạng thái: chỉ chuẩn bị cấu hình; chưa chuyển dữ liệu hay bật PostgreSQL.

## Phân chia đã chọn

- PostgreSQL đám mây: tài khoản, scrypt hash/salt hiện có, tin nhắn, quan hệ người dùng, ví/xu, quyền mua gói, lịch sử và cấu hình quản trị.
- PC: API, WebSocket, SFU và ảnh/video sau khi tách khỏi BLOB trong SQLite.
- PC dự phòng: cùng cơ sở dữ liệu đám mây; media cần bản sao riêng. Chỉ một máy ứng dụng hoạt động trước khi có cơ chế chia sẻ presence, phòng Live, session/cache và sự kiện giữa các máy.
- Android chỉ gọi API, không nhận mật khẩu PostgreSQL.

## Khi đã có dịch vụ

1. Tạo PostgreSQL riêng cùng khu vực gần máy chủ; bật sao lưu và kiểm tra khả năng phục hồi của gói dịch vụ.
2. Dùng tài khoản migration riêng; tài khoản ứng dụng không có quyền quản trị hệ thống. Cấu hình TLS xác minh chứng chỉ/hostname và kết nối riêng hoặc hạn chế nguồn truy cập theo dịch vụ.
3. Sao chép `cloud-db.env.example` thành `cloud-db.env`, điền cục bộ trên PC. Không gửi mật khẩu trong chat. Không bật server bằng cấu hình này ở thời điểm hiện tại.
4. Chạy `node scripts/check-cloud-db-config.mjs`. Công cụ chỉ kiểm tra cú pháp và điều kiện cấu hình, không kiểm tra mạng/quyền truy cập/khả năng chạy PostgreSQL. `productionReady` luôn false đến khi chuyển đổi hoàn tất.

## Các việc bắt buộc trước khi chuyển thật

- Thay lớp DatabaseSync đồng bộ và các câu SQL SQLite trong toàn bộ module bằng truy vấn PostgreSQL bất đồng bộ; giữ nguyên tính nguyên tử của ví, tặng xu, mua gói và idempotency.
- Chuyển schema, trigger thưởng đăng ký, JSON, BLOB, khóa ngoại, chỉ mục, timestamp và các lệnh PRAGMA/INSERT OR IGNORE. Không dùng SQLite qua thư mục mạng hoặc đồng bộ file DB đang mở.
- Tách avatar, post_media, shorts và các BLOB media khác sang file; API dùng tham chiếu, sao lưu media và kiểm tra checksum trước khi xóa BLOB.
- Sao lưu SQLite bằng API snapshot nhất quán. Chạy chuyển thử trên bản sao, giữ nguyên ID/hash/salt, kiểm đếm dữ liệu, đối chiếu số dư và thử đăng nhập tài khoản kiểm thử.
- Thử đăng ký không thưởng xu hai lần, tin nhắn/nhóm, phiên đăng nhập, quyền admin, mua gói/tặng quà và lỗi mạng giữa giao dịch.
- Khi chuyển thật: dừng ghi, snapshot cuối, migrate/đối chiếu, bật duy nhất một máy; không âm thầm rơi về SQLite nếu cloud lỗi.
- Nếu đã có ghi trên PostgreSQL, không quay về bản SQLite cũ vì sẽ mất dữ liệu mới. Muốn rollback phải dừng ghi và chuyển dữ liệu phát sinh theo kế hoạch đã kiểm thử.

Chưa có nhà cung cấp, URL, credentials, kiểm tra kết nối, runtime adapter hoặc migration. Không thay đổi dịch vụ hiện hành.
