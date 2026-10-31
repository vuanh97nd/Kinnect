# Kế hoạch nâng cấp giao diện Kinnect (web + Android)

Cập nhật: 31/10/2026 · Phạm vi: web app (public/), Android native (app.kinnect.live), Live/Studio, Store/Wallet.

## 1. Kết luận nhanh

**Có cần nâng cấp? Có — nhưng theo hướng hệ thống hóa, không đập đi làm lại.**
Nền tảng hiện tại đã khá tốt: bảng màu Pixel/Material You có light + dark, tương phản đạt WCAG AA toàn bộ (5.07–16.55), có token 4-pt grid, thang chữ, motion token, bộ icon riêng đồng bộ web ↔ native, font Be Vietnam Pro trên native. Vấn đề chính là **hai hệ thiết kế song song chưa dùng chung một nguồn token**, phân cấp thị giác còn phẳng, thiếu chuyển động/điểm nhấn thương hiệu, và vài chi tiết kỹ thuật chưa chuẩn (touch target nhỏ, emoji trong UI, trạng thái rỗng/đang tải chưa đồng nhất).

## 2. Hiện trạng (bằng chứng)

Điểm tốt:
- `public/tokens.css`: 4-pt spacing, radius 8/12/18/24, shadow 3 lớp, thang chữ 12–30, motion 120/200/320ms + easing, z-index layer, màu trạng thái; có override cho dark.
- `WebDesign.java`: palette light/dark đầy đủ (BG/CARD/INK/MUTED/LINE/WASH/DANGER/SUCCESS/ONLINE), chữ 15/14/13/22/16, CONTROL 48dp, CARD_RADIUS 24, HEADER 64.
- Icon: `WebIcons` + `SettingsGlyph` đồng bộ từ web; sheet/toast theo M3; Live/Studio có ngôn ngữ riêng khá rõ.
- Tương phản đo được: INK/BG 15.26, INK/CARD 16.55, MUTED/CARD 5.67, trắng/tím 5.81, trắng/đỏ 5.29, dark 16.08/7.11/5.07 — đều ≥ AA.

Điểm cần nâng cấp:
1. **Token bị chia đôi**: web ưu tiên "Inter" còn native bundle Be Vietnam Pro; radius/spacing giữa hai nền tảng khác nhau; CSS trùng lặp lớn (`v2.css` 3005 dòng + `theme.css` 2573 + `compact.css` 1082 + `polish.css` 859). Hệ quả thấy thật trong phiên này: tiêu đề header chat bị cắt chữ, pill "Micro" trong Live bị cắt đáy — đều là lỗi do đo/khung thiếu chuẩn chung.
2. **Phân cấp thị giác phẳng**: card thiên về viền mảnh, ít elevation; tiêu đề/nội dung cùng trọng số; CTA chưa nổi bật; ảnh/video chưa có gradient overlay, tỉ lệ chưa thống nhất.
3. **Motion hạn chế**: native chủ yếu alpha/translateY; token chuyển cảnh có nhưng dùng rời rạc; thiếu skeleton, phản hồi like/gửi, chuyển màn có chủ đích.
4. **Chi tiết chưa chuẩn**: emoji trong UI ("⚡ Combo", "🎮"); nhiều nút 44dp và chip 34dp (<48dp); ellipsize/auto-size chưa phủ hết; letter-spacing/weight lệch giữa web và native.
5. **Trạng thái rỗng/đang tải chưa đồng nhất** giữa các màn; thiếu skeleton cho feed/chat/store.
6. **Dark mode** có nhưng cần rà phủ toàn bộ (store/admin/live).
7. **Ảnh/thumbnail**: chưa có placeholder mờ (blurhash/thumb nhỏ), thumbnail video 240×384, dễ giật khi cuộn.

## 3. Lộ trình

### Giai đoạn 0 — Chuẩn hóa nền tảng (2–3 ngày)
- Tạo **một nguồn token duy nhất** `design/tokens.json` → script sinh `public/tokens.css` + `WebDesign.java` (và lớp spacing/radius dùng chung). Không hard-code màu/kích thước ngoài token.
- Thống nhất typography: **Be Vietnam Pro** cho cả web (bundle woff2) và native; Inter chỉ là fallback.
- Chuẩn kích thước: 4-pt grid; **touch tối thiểu 48dp** (nâng nút 44dp, chip 34dp bằng padding chạm); radius 8/12/18/24; elevation 0/1/2/3.
- Tách CSS theo layer: `tokens → base → components → screens`; gộp phần trùng của `polish/compact`.
- Nghiệm thu: 1 file token; script CI đếm màu hard-code (mục tiêu 0); checklist touch target.

### Giai đoạn 1 — Nâng cấp màn hình chính (1–2 tuần)
Ưu tiên theo tần suất dùng:
- **Feed**: card có phân cấp (ảnh 4:5 hoặc 1:1 thống nhất, gradient nhẹ dưới ảnh, hàng tác vụ có nhãn + trạng thái like đổi màu + animation nhỏ), skeleton loading, empty state minh hoạ.
- **Chat**: bubble chuẩn (bo 18, đuôi, giờ trong bubble), trạng thái đã xem, typing indicator, animation gửi, ảnh trong chat có tỉ lệ + placeholder.
- **Inbox**: avatar 48, badge chưa đọc, preview 2 dòng + thời gian, swipe ghim/xoá (nếu kịp).
- **Discover**: chip lọc dạng pill có icon; lưới thẻ 2 cột, ảnh bo tròn + badge online; filter sheet M3.
- **Profile**: cover 16:9 + gradient, avatar overlap, stat pills, tab segmented M3.
- Nghiệm thu mỗi màn: đủ 3 trạng thái (loading/empty/error), dark mode parity, 100% target ≥48dp, ảnh before/after.

### Giai đoạn 2 — Bản sắc & chuyển động (1–2 tuần)
- **Motion system** dùng chung: duration/easing token; chuyển màn shared-axis; phản hồi like/gửi dạng spring; sheet M3; skeleton shimmer.
- **Thương hiệu**: gradient tím→hồng cho CTA chính, glow nhẹ cho FAB/Live, intro animation, logo mark.
- **Live/Studio**: bỏ emoji, dùng icon; thống nhất pill/dock/tray với phần còn lại; hiệu ứng gift/join.
- **Store/Wallet**: thẻ sản phẩm có ảnh/gradient, giá nổi bật, badge "Pro".
- Nghiệm thu: 1 bộ motion token; 0 emoji trong UI; CTA chính dùng gradient.

### Giai đoạn 3 — Đo lường & tinh chỉnh (song song)
- Đo: thời gian mở màn, FPS cuộn feed/chat, số target <48dp, tỉ lệ tương phản (script tự động), số màu hard-code.
- KPI gợi ý: feed mở <1.5s; cuộn 60fps; 0 vi phạm AA; 100% nút ≥48dp; giảm 30% CSS trùng.

## 4. Ưu tiên / công sức

| Hạng mục | Tác động | Công sức | Ưu tiên |
|---|---|---|---|
| Token hợp nhất + font | Cao (nền tảng) | 2–3 ngày | P0 |
| Touch target + ellipsize/auto-size | Cao (lỗi thấy được) | 1–2 ngày | P0 |
| Feed + Chat nâng cấp | Rất cao (dùng nhiều nhất) | 5–7 ngày | P1 |
| Inbox + Discover + Profile | Cao | 5–7 ngày | P1 |
| Motion + thương hiệu | Trung bình–cao | 5–7 ngày | P2 |
| Live/Studio + Store | Trung bình | 4–6 ngày | P2 |
| Skeleton/empty/error toàn bộ | Cao | 3–4 ngày | P1 |
| Dọn CSS + CI kiểm token | Trung bình | 2–3 ngày | P2 |

## 5. Rủi ro & cách giảm
- Đổi token ảnh hưởng cả web + native → cần **visual regression** (chụp màn trước/sau, so pixel) trước khi merge.
- Motion nhiều gây chậm máy yếu → giới hạn theo API level, tôn trọng "giảm chuyển động".
- Dọn CSS dễ sót selector → làm theo layer, test từng màn.
- Ảnh lớn: thêm thumbnail + placeholder trước, tránh đổi cấu trúc dữ liệu.

## 6. Bắt đầu đề xuất
1. Tuần này: Giai đoạn 0 + Feed + Chat (2 màn người dùng thấy nhiều nhất).
2. Song song: script CI kiểm token/touch target + bộ ảnh chụp chuẩn để so sánh.
3. Ảnh chụp hiện trạng: `work/ui_home.png`, `work/ui_discover.png`, `work/ui_inbox.png`.
