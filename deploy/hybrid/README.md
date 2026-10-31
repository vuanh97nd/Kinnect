# Cấu trúc được chốt: cloud API, PC media/SFU/TURN

Đây là cấu hình đích và mẫu triển khai, không phải hệ thống đã chuyển xong.

## Chính sách mới: ưu tiên backend khỏe phản hồi nhanh hơn

Gateway thử nghiệm đo đồng thời truy vấn phiên chỉ đọc ở PC và cloud, lưu lựa chọn 60 giây và chỉ đổi khi nhanh hơn trên 25 ms để tránh dao động. Cloud tối đa 100 suất; PC lỗi thì chuyển cloud trong giới hạn này. Không tự phát lại lệnh ghi khi kết quả không rõ; dùng nonce để kiểm tra và gửi lại an toàn.

Hai backend dùng chung PostgreSQL cho tài khoản/phiên/ví và D1 cho chat riêng/nhóm/trạng thái gửi/đã xem. Không tạo hai cơ sở dữ liệu tài khoản và chat độc lập cần đồng bộ hai chiều. PC vẫn cần mạng để truy cập nguồn dữ liệu cloud. Mất mạng cloud không tự cho phép ghi SQLite rồi gộp sau.

Đã kiểm tra thực tế tắt riêng API PC thử nghiệm: đăng nhập mới trên cloud, giữ phiên cũ, gửi/đọc cùng lịch sử D1, gửi lại không trùng, PC phục hồi đọc dữ liệu mới. Chat API tương thích native, nhóm, thông báo và đã xem qua PC/cloud đã qua thử nghiệm. Chưa chuyển app chính: productionRouting=false, server cũ cổng 3000 vẫn SQLite. Cần hoàn tất API còn thiếu, đường dẫn PC ổn định và đối chiếu dữ liệu mới trước chuyển chính thức.

Cloud chạy API, đăng nhập, session, chat, ví và thông báo. PostgreSQL giữ tài khoản/ví; D1 giữ chat. Signaling Live/cuộc gọi cũng ở cloud, còn media SFU/TURN ở PC. PC giữ ảnh/video và tệp đính kèm. Không tự chuyển sang nhà cung cấp media cloud khi PC mất mạng.

Khi PC ngừng: cloud vẫn phải phục vụ text/account/wallet; yêu cầu ảnh/video có timeout ngắn và thông báo không khả dụng, không chặn đăng nhập. Live qua SFU và cuộc gọi cần TURN ngừng. Cuộc gọi P2P có thể vẫn kết nối nếu mạng hai máy cho phép, không bảo đảm.

## Trạng thái đã kiểm tra

- PostgreSQL TLS kết nối thành công, tài khoản/cấu hình đã chuyển thử JSONB staging.
- D1 chat đã có schema và 228 bản ghi staging được đối chiếu.
- Repository D1 cơ bản có kiểm tra, chưa gắn vào API production.
- API/SFU hiện tại vẫn ở PC. Chưa có cloud compute host được cấp.
- TURN hiện có hỗ trợ HuggingFace hoặc static credentials; chưa có PC coturn/short-lived issuer được triển khai trong thay đổi này.
- Ảnh/video hiện vẫn trong SQLite BLOB ở PC, chưa có media service độc lập.

## Các bước cần hoàn tất

1. Chuyển lớp tài khoản/ví/phiên sang PostgreSQL và chat sang D1, giữ nguyên kiểm tra role, block, xóa/thu hồi, idempotency và số dư.
2. Tách BLOB thành file trên PC + file service xác thực quyền từng tệp. Không công khai private album/attachment hay cho phép liệt kê kho tệp.
3. Cấp cloud API host hoặc hoàn tất port sang Workers. Không tự đăng ký dịch vụ có phí khi chưa chốt ngân sách.
4. Giữ SFU control private/authenticated TLS, bí mật chỉ ở cloud backend/PC. Mở đường UDP media đúng NAT/firewall; HTTP Tunnel không thay thế đường UDP.
5. Cài coturn trên PC, dùng credential ngắn hạn và cấu hình chống relay vào mạng nội bộ. Kiểm tra public IP/CGNAT trước khi hứa hỗ trợ qua mạng ngoài.
6. Kiểm tra cả khi PC bật/tắt: text vẫn chạy; media timeout; Live/call trả lỗi gọn; không vô tình fallback HuggingFace/cloud relay.
7. Đối chiếu dữ liệu cuối, dừng ghi có kế hoạch rồi mới đổi DNS/API. 30 phòng/2000 tổng người xem chỉ là admission cap, chưa có thử tải bảo đảm.

Không sao chép nguyên cloud.env.example đè sfu.env đang hoạt động. Các biến MEDIA là mục tiêu tích hợp, chưa được runtime đọc. `KINNECT_SFU_MANAGED=remote` được server-manager hỗ trợ, nhưng manager hiện vẫn dùng PID/CIM Windows và không thể dùng nguyên trên Linux.


## Latest: PostgreSQL chat preview (2026-10-30)
Private preview now stores chat in dedicated Supabase Kinnect Chat project mmxqhcngrejxyhhfirzo. PC direct TLS and cloud CHAT_HYPERDRIVE use the same PostgreSQL chat tables; D1 remains an unchanged legacy preview copy. 108 imported messages/content hashes checked. Native PC/cloud chat/group/notifications/seen and actual PC stop/cloud fallback/recovery tested. Main app remains legacy SQLite pending parity and current-data reconciliation. A private PC snapshot backup exists; ongoing synchronization and offline API access are NOT enabled.
