# Thiết kế chi tiết game Nông trại Kinnect

Trạng thái: P1 đã có bản chơi 3D native. Tài liệu chốt luật chơi, kinh tế, giao diện 3D và kỹ thuật cho các giai đoạn tiếp theo.

## 1. Tổng quan

- Tên game: Nông trại Kinnect.
- Thể loại: mô phỏng nông trại nhẹ, chơi bất đồng bộ, có yếu tố xã hội.
- Nền tảng: Android native, dùng chung giao diện và ví của ứng dụng Kinnect.
- Đối tượng: thành viên đang dùng Kinnect, thích chơi nhanh, quay lại mỗi ngày, thích thăm bạn bè và phòng Live.
- Thời lượng một phiên: 2 đến 4 phút, chơi 2 đến 3 lần mỗi ngày.
- Đồ họa: 3D low-poly thời gian thực bằng OpenGL ES 2.0. Cảnh vườn có chiều sâu, ánh sáng, bóng đổ và camera xoay được. Cây trồng, nhà kho, hàng rào, ao và cây cảnh được dựng thủ tục trong app, không cần tải tài nguyên nặng.
- HUD phẳng nằm trên cảnh 3D, dùng chung bảng màu, font và UI_SCALE của Kinnect.
- Không trả tiền để thắng. Xu mua không dùng cho tăng trưởng trong game.

## 2. Vòng lặp chơi

Vòng lặp ngắn:
1. Mở game, thấy cây đã chín.
2. Thu hoạch, nhận xu tặng và điểm kinh nghiệm.
3. Mua hạt giống mới, trồng lại vào ô trống.
4. Tưới nước, bón phân, xử lý sâu nếu có.

Vòng lặp ngày:
1. Làm nhiệm vụ ngày.
2. Thăm 3 nông trại bạn bè, tưới giúp.
3. Ghé chợ phiên để mua hạt giống giảm giá.
4. Nhận quà từ bạn bè.

Vòng lặp dài:
1. Tăng cấp nông dân, mở cây mới và ô đất mới.
2. Hoàn thành bộ sưu tập cây và trang trí.
3. Tham gia sự kiện mùa và nông trại trong Live.

## 3. Khu vườn

- Bắt đầu với 6 ô đất xếp 2 hàng 3 cột trong một cảnh 3D có nhà kho, hàng rào, ao, cây cảnh và lối đi.
- Mở tối đa 12 ô.
- Giá mở ô: 500, 1.000, 2.000, 4.000, 8.000 xu.
- Cấp cần có: 1, 4, 7, 10, 13, 16.
- Nhà kho mở ở cấp 3, ao cá ở cấp 6, chuồng vật nuôi ở cấp 9.
- Có 6 vị trí trang trí quanh vườn. Trang trí chỉ thay đổi ngoại hình, không tăng sức mạnh.
- Mỗi ô có bốn trạng thái: đất trống, đã trồng, cần chăm sóc, đã chín.
- Camera 3D đặt nghiêng 35 đến 45 độ, nhìn toàn vườn. Kéo để xoay 360 độ, chụm hai ngón để zoom. Chạm vào ô đất để chọn.
- Cây vẫn lớn khi offline. Thời gian tính từ lúc trồng trên máy chủ.

## 4. Cây trồng

| Cây | Cấp | Thời gian | Giá hạt | Thu hoạch | Kinh nghiệm | Ghi chú |
|---|---|---|---|---|---|---|
| Hoa hồng | 1 | 5 phút | 20 xu | 30 xu | 2 | Cây nhập môn |
| Cà chua | 1 | 30 phút | 80 xu | 120 xu | 4 | Cây phổ thông |
| Hướng dương | 2 | 2 giờ | 250 xu | 380 xu | 8 | Mở ở cấp 2 |
| Bí ngô | 3 | 4 giờ | 600 xu | 900 xu | 14 | Hợp sự kiện mùa |
| Dưa hấu | 4 | 8 giờ | 1.200 xu | 1.900 xu | 22 | Cây qua ngày |
| Nho | 5 | 12 giờ | 2.200 xu | 3.500 xu | 32 | Cần chăm đều |
| Pha lê | 6 | 24 giờ | 4.000 xu | 7.000 xu | 60 | Cây hiếm, có hiệu ứng riêng |
| Dâu tây | 2 | 1 giờ | 150 xu | 230 xu | 6 | Cây mở rộng |

Chăm sóc:
- Tưới nước một lần mỗi cây, tăng 10 phần trăm sản lượng.
- Bón phân một lần mỗi cây, tăng thêm 25 phần trăm sản lượng. Phân bón mua trong cửa hàng.
- Sâu xuất hiện ngẫu nhiên với xác suất 25 phần trăm. Nếu không xử lý trong 2 giờ, sản lượng giảm 15 phần trăm. Cây không chết.
- Không có hình phạt mất trắng để tránh gây ức chế.
- Thu hoạch có 5 phần trăm cơ hội vàng, nhận gấp đôi xu.
- Mỗi cây có thể thu hoạch bất cứ lúc nào sau khi chín, không mất nếu quên.

## 5. Tiến trình

- Cấp nông dân từ 1 đến 30.
- Kinh nghiệm đến từ trồng, thu hoạch, nhiệm vụ ngày, thăm bạn và sự kiện.
- Cấp mở khóa cây, ô đất, nhà kho, ao cá, chuồng và trang trí.
- Nhiệm vụ ngày:
  - Trồng 3 cây.
  - Thu hoạch 5 cây.
  - Tưới 3 nông trại bạn bè.
  - Ghé chợ phiên một lần.
- Phần thưởng nhiệm vụ ngày: 20 đến 50 xu tặng và 20 kinh nghiệm.
- Bộ sưu tập: mỗi loại cây có ba mốc thu hoạch. Hoàn thành nhận huy hiệu và trang trí.
- Bảng xếp hạng hàng xóm theo tuần, dựa trên số lần giúp bạn và sản lượng thu hoạch, không dựa trên số xu đã tiêu.

## 6. Xã hội

- Bạn bè lấy từ danh sách bạn bè Kinnect. Tôn trọng chặn và quyền riêng tư hiện có.
- Thăm nông trại bạn bè: xem vườn, tưới giúp 3 lần mỗi ngày.
- Tưới giúp bạn tăng 5 phần trăm thời gian lớn cho cây của bạn ấy. Người tưới nhận 10 xu và 2 kinh nghiệm.
- Tặng hạt giống: chọn một hạt trong kho để tặng. Món quà hiện trong hộp thư nông trại của bạn.
- Chợ bạn bè: mỗi người bạn bán một hạt giống giảm giá mỗi ngày. Mua sẽ giúp cả hai tăng điểm thân thiết.
- Sự kiện thu hoạch chung: 2 đến 5 người cùng góp cây để mở rương quà chung.
- Thông báo khi bạn bè tưới vườn hoặc tặng hạt giống.

## 7. Nông trại trong Live

- Chủ phòng có thể đưa nông trại lên sân khấu Live.
- Người xem bình luận các lệnh ngắn: tưới, thu hoạch, bón phân.
- Mỗi lệnh có thời gian chờ để tránh spam. Tối đa 1 lệnh mỗi 3 giây cho mỗi người.
- Thả tim giúp cây lớn nhanh hơn. Quà tặng mở hiệu ứng thu hoạch vàng và tăng sản lượng cho vườn đang phát.
- Chợ Live: người xem mua hạt giống hoặc vật tư tặng chủ phòng. Hiệu ứng hiện ngay trên sân khấu.
- Bảng Người tài trợ trong Live dựa trên số vật phẩm đã tặng, không quy đổi thành tiền mặt.
- Chỉ dùng xu tặng. Không dùng xu mua cho hiệu ứng trong Live.

## 8. Kinh tế

Chỉ dùng xu tặng trong game. Xu mua chỉ dành cho thanh toán và các gói trả tiền nếu có, không dùng để mua hạt giống hay mở đất.

Nguồn xu:
- Thu hoạch cây: 30 đến 7.000 xu tùy cây.
- Nhiệm vụ ngày: 20 đến 50 xu.
- Thăm và tưới vườn bạn: 10 xu mỗi lần.
- Sự kiện Live: thưởng theo mốc quà, có giới hạn ngày.

Nơi tiêu xu:
- Hạt giống.
- Vật tư: nước, phân bón, thuốc sâu.
- Mở ô đất, nhà kho, ao cá.
- Trang trí.
- Hạt giống tặng bạn.

Chống lạm phát:
- Giới hạn mua hạt giống cao cấp mỗi ngày: Dưa hấu 5 hạt, Nho 3 hạt, Pha lê 2 hạt.
- Giới hạn xu thu từ nông trại mỗi ngày: 30.000 xu.
- Trang trí và mở đất là nơi hút xu chính.
- Không bán vật phẩm tăng sản lượng vĩnh viễn.
- Máy chủ giữ giá, tồn kho và số lượt mua.

## 9. Cửa hàng trong game

Năm tab:
1. Hạt giống.
2. Vật tư.
3. Mở rộng.
4. Trang trí.
5. Quà tặng.

Giá tham khảo:
- Nước 10 xu, phân bón 40 xu, thuốc sâu 25 xu.
- Ô đất mới 500 đến 8.000 xu.
- Trang trí 150 đến 2.000 xu.
- Hộp 3 hạt giống tặng bạn 200 đến 500 xu.
- Chợ phiên mỗi ngày có 3 món giảm 20 đến 40 phần trăm, làm mới lúc 0 giờ.
- Chợ Live mở trong phòng Live, cho phép người xem mua vật phẩm tặng chủ phòng.
- Món từ 500 xu có hộp xác nhận. Mọi giao dịch có mã yêu cầu riêng để tránh trừ hai lần.
- Không hiển thị giá tiền thật trong cửa hàng game. Chỉ hiển thị xu.

## 10. Giao diện

Màn hình chính 3D:
- Thẻ trạng thái phía trên: cấp nông dân, thanh kinh nghiệm, số xu tặng.
- Khung cảnh 3D chiếm phần lớn màn hình: 6 ô đất nổi, cây theo 4 giai đoạn lớn, nhà kho, hàng rào, ao, cây cảnh, bóng đổ và ánh nắng.
- Camera mặc định nhìn nghiêng 35 đến 45 độ. Kéo một ngón để xoay, chụm hai ngón để zoom, chạm ô đất để mở bảng chăm sóc.
- Khi mở từ danh sách trò chơi, game chuyển sang màn hình ngang và hiện splash logo khoảng 2 giây: huy hiệu nông trại, vòng sáng xoay, tên Nông trại Kinnect. Hết splash mới vào cảnh chính; nút quay lại trả về danh sách trò chơi ở màn hình dọc.
- Ô đang chọn có viền vàng. Cây chín có vòng sáng và hạt lấp lánh. Sâu bay quanh cây bị bệnh.
- Nút Cửa hàng và Nhiệm vụ ngay dưới cảnh. Bảng chăm sóc dạng tấm trượt gồm Trồng, Tưới, Bón, Xử lý sâu, Thu hoạch.
- Thẻ nhiệm vụ ngày hiển thị tiến độ ngay trên cảnh.
- HUD chỉ là lớp phẳng để đọc số liệu và thao tác; không dùng lưới 2D thay cho cảnh 3D.

Màn hình phụ:
- Cửa hàng dạng tấm trượt lớn hoặc màn hình riêng, có tab và thẻ món.
- Thăm vườn bạn: cùng cảnh 3D, đổi màu trời và trang trí theo chủ vườn; có nút Tưới giúp và Tặng hạt.
- Live farm: sân khấu thu nhỏ, bảng lệnh và bảng tài trợ.
- Bộ sưu tập: danh sách cây, mốc và phần thưởng.

Quy ước:
- Dùng bảng màu, font và UI_SCALE của ứng dụng.
- Hỗ trợ sáng và tối.
- Hiệu ứng ngắn 120 đến 220ms. Tôn trọng chế độ giảm hiệu ứng.
- Cảnh 3D chạy 30 đến 60 fps, dưới 20.000 tam giác, không tải texture lớn.
- Không chạy hoạt ảnh cho ô ngoài màn hình.
- Cây chín có nhãn, rung nhẹ một lần và vòng sáng trong cảnh 3D.

## 11. Âm thanh và hiệu ứng

- Tưới nước: tiếng nước ngắn.
- Thu hoạch: tiếng chuông nhẹ, khác nhau theo nhóm cây.
- Lên cấp: hiệu ứng vàng nhẹ, không chói.
- Thu hoạch vàng: hiệu ứng ánh vàng và âm thanh riêng.
- Có nút tắt âm thanh trong game, dùng chung cài đặt với quà Live.

## 12. Kỹ thuật

Kết xuất 3D:
- Dùng OpenGL ES 2.0 qua TextureView, không thêm game engine hay tài nguyên ngoài.
- Game chạy trong một Activity riêng khóa sensorLandscape, toàn màn hình, ẩn thanh hệ thống. HUD phẳng đè lên cảnh 3D.
- Splash logo vẽ bằng Canvas: huy hiệu nông trại, vòng sáng xoay và hiệu ứng vào. Chỉ hiện một lần mỗi lần mở game.
- Mô hình low-poly dựng thủ tục: hộp, cầu, trụ, nón, đĩa. Cây gồm thân, lá và quả theo loại.
- Ánh sáng định hướng, bóng đổ mềm, trời chuyển màu và sương nhẹ ở xa.
- Camera quỹ đạo quanh vườn, giới hạn góc nghiêng 24 đến 66 độ, zoom 9 đến 23 đơn vị.
- Chạm ô đất dùng tia từ camera cắt mặt đất, không dùng vùng chạm 2D.
- Tiến trình lớn của cây nội suy theo mốc thời gian máy chủ, không cần tải lại liên tục.
- Cảnh 3D nằm trong màn hình nông trại hiện có, giữ nguyên API và các tấm trượt.

Máy chủ giữ toàn bộ trạng thái quan trọng:
- Bảng farm_plots: người chơi, ô, cây, thời điểm trồng, thời điểm chín, đã tưới, đã bón, sâu, sản lượng dự kiến.
- Bảng farm_inventory: hạt giống, vật tư, vật phẩm trang trí.
- Bảng farm_visits: người thăm, người được thăm, thời điểm, hành động.
- Bảng farm_gifts: quà hạt giống, người gửi, người nhận, trạng thái.
- Bảng farm_shop_purchases: mã yêu cầu, món, giá, thời điểm.
- Bảng farm_daily: nhiệm vụ ngày, lượt mua, lượt thu.
- Bảng farm_collections: mốc bộ sưu tập.

API đề xuất:
- GET /api/farm trả về vườn, kho, nhiệm vụ, cửa hàng hôm nay.
- POST /api/farm/plant, water, fertilize, treat, harvest.
- POST /api/farm/expand, shop/buy, gift, visit.
- Sự kiện Live đi qua socket hiện có.

Nguyên tắc:
- Thời gian lớn tính từ mốc máy chủ, không tin đồng hồ máy.
- Mọi giao dịch có mã yêu cầu và kiểm tra trùng.
- Trừ xu và ghi nhận vật phẩm trong cùng một giao dịch.
- Giới hạn lượt mua và lượt thu mỗi ngày.
- Không cho phép số dư âm.
- Thông báo đẩy khi cây chín, khi bạn tưới vườn, khi nhận hạt giống.
- Dùng lại ví, xu tặng và hệ thống quà hiện có. Không thêm loại tiền mới ở P1.

## 13. Lộ trình

P1, bản chơi được, đã triển khai:
- Splash logo và màn hình ngang khi mở game.
- Cảnh 3D low-poly 6 ô đất, 8 cây, nhà kho, hàng rào, ao và cây cảnh.
- Trồng, tưới, bón, xử lý sâu, thu hoạch; camera xoay và zoom; chạm ô đất.
- Cửa hàng hạt giống và vật tư.
- Nhiệm vụ ngày, cấp và kinh nghiệm.
- Máy chủ giữ trạng thái và chống trùng giao dịch.
- Còn lại trong P1: thông báo đẩy khi cây chín.

P2, xã hội:
- Thăm vườn, tưới giúp, tặng hạt giống.
- Chợ bạn bè, bảng xếp hạng tuần.
- Bộ sưu tập và huy hiệu.

P3, Live và sự kiện:
- Nông trại trong Live, chợ Live, bảng tài trợ.
- Sự kiện mùa, trang trí giới hạn, vật nuôi.

## 14. Kiểm thử và chỉ số

Kiểm thử:
- Cảnh 3D dựng đủ 6 ô, cây đổi hình theo tiến trình, chạm ô mở đúng bảng.
- Trồng, lớn offline, thu hoạch đúng thời điểm.
- Mua khi thiếu xu, mua trùng mã yêu cầu, mua quá giới hạn ngày.
- Tưới trùng, bón trùng, sâu xuất hiện và xử lý.
- Thăm bạn, tặng hạt, chặn người chơi.
- Live: lệnh bị giới hạn, quà tặng hiện đúng, không trừ hai lần.
- Không cho số dư âm, không có xu mua trong game.

Chỉ số cần theo dõi:
- Người quay lại ngày 1 và ngày 7.
- Số lần mở game mỗi ngày.
- Số vườn được thăm và số hạt giống được tặng.
- Tỷ lệ tham gia nông trại Live.
- Tỷ lệ người chơi đạt cấp 6 và mở ô thứ 8.
- FPS trung bình, số lần tụt khung hình và nhiệt độ máy khi mở cảnh 3D.
