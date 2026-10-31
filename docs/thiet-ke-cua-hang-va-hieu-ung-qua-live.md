# Thiết kế chi tiết: Gói Cửa hàng & Hiệu ứng quà Live

Cập nhật: 31/10/2026 · Phạm vi: Android native (`StoreActivity`, `StorePackageDesign`, `LiveGiftExperience`) và đối chiếu web.
Hiện trạng: 15 gói trong `STORE_PACKAGES`; 10 quà Live với 4 bậc (small/medium/large/legendary); mỗi quà có file WAV riêng (~0,5–0,7s); hiệu ứng hiện dùng **một mẫu chung 2,6s** cho mọi bậc.

---

## PHẦN A — THIẾT KẾ GÓI CỬA HÀNG

### A1. Nguyên tắc
1. **Bậc thang thị giác rõ**: common → rare → epic → legendary phải khác nhau về ánh sáng, chuyển động và độ "đắt" — không chỉ khác màu badge.
2. **Mỗi gói một biểu tượng**: người dùng nhận ra gói qua motif (Neon = đường kẻ sáng, Aurora = dải màu, Castle = lâu đài…), không cần đọc chữ.
3. **Giá là điểm nhấn**, không phải phụ đề: số xu lớn, icon xu, màu tím; giá tham chiếu VND nhỏ bên dưới.
4. **Trạng thái rõ**: Chưa mua / Đã mua / Đang dùng / Sắp ra mắt — khác nhau bằng màu + nhãn + hành động.
5. **Đồng bộ với app**: cùng Be Vietnam Pro, radius 24, gradient thương hiệu, không emoji.

### A2. Bảng nhận diện từng gói
| Gói | Bậc | Ý tưởng hình ảnh | Palette | Motif động (đề xuất) |
|---|---|---|---|---|
| style_neon | rare | "Dấu ấn thành thị" — đường kẻ neon trên nền tối | #7c3aed → #06b6d4 | Vệt sáng chạy chéo 1,2s lặp 6s |
| style_aurora | epic | "Sắc màu kết nối" — dải cực quang mềm | #8b5cf6 → #ec4899 | Dải màu trôi ngang chậm |
| style_galaxy | legendary | "Vũ trụ của bạn" — quỹ đạo và sao | #312e81 → #a855f7 | Sao nhấp nháy + quỹ đạo xoay nhẹ |
| live_chill | rare | "Không gian thư giãn" — biển dịu | #0d9488 → #38bdf8 | Sóng nước lượn nhẹ |
| live_gaming | epic | "Sân khấu trận đấu" — góc cạnh, tốc độ | #4f46e5 → #f43f5e | Tia tốc độ chéo |
| live_spotlight | legendary | "Bạn là tâm điểm" — đèn sân khấu vàng | #a16207 → #fbbf24 | Chùm sáng quét qua lại |
| live_game_30 | epic | "Chơi và kết nối" — màn hình game + tay cầm | #6d28d9 → #db2777 | Nhịp sáng theo nhịp 1s |
| gift_love | rare | "Gửi điều dịu dàng" — hoa và tim | #db2777 → #fb7185 | Tim bay lên chậm |
| gift_speed | epic | "Bứt phá khoảnh khắc" — vệt tốc độ | #2563eb → #06b6d4 | Xe lướt qua khung |
| gift_royal | legendary | "Dấu ấn trân trọng" — vương miện, lâu đài | #7e22ce → #eab308 | Kim tuyến vàng rơi |
| member_plus | rare | "Phong cách mỗi ngày" — khiên + vương miện nhỏ | #4338ca → #a78bfa | Huy hiệu lấp lánh nhẹ |
| member_creator | legendary | "Dành cho người sáng tạo" — clapperboard | #c026d3 → #fb923c | Clapper đóng mở 1 lần/4s |
| studio_7 | common | "Bắt đầu một ý tưởng" | #7c3aed → #c026d3 | — |
| studio_30 | rare | "Sáng tạo mỗi ngày" | #7c3aed → #c026d3 | Thanh tiến trình sáng dần |
| studio_365 | legendary | "Đồng hành dài lâu" | #7c3aed → #c026d3 | Vòng sáng quanh logo |

### A3. Thẻ gói — nâng cấp cụ thể
- **Ribbon bậc** ở góc art: pill nhỏ nền tối mờ, chữ "Hiếm/Sử thi/Huyền thoại" theo `tierColor`.
- **Viền art theo bậc**: common viền LINE; rare viền cyan mờ; epic viền tím; **legendary viền vàng + shimmer** (dải sáng chạy chéo mỗi 3s, vẽ Canvas — không ảnh).
- **Giá**: 24sp đậm, icon xu 22dp; khi không đủ xu → giá chuyển DANGER + CTA "Chưa đủ xu".
- **Trạng thái**: Đang dùng → nền SOFT + icon check; Đã mua → nhãn "Đã có"; Sắp ra mắt → art giảm alpha 55% + badge xám.
- **Kho quà (gift_love/speed/royal)**: hiển thị chip nội dung "6 Hoa hồng", "1 Siêu xe + 2 Sao pha lê", "1 Lâu đài" ngay dưới mô tả; tab "Quà" mở kho có badge số lượng.
- **Mua xong**: giữ hiệu ứng hiện có (quả cầu check) nhưng **nâng theo bậc**: legendary → pháo giấy vàng + rung nhẹ + thẻ mở chậm 420ms (đã có cho purchase).

### A4. Chuyển động & tương tác
- Thẻ vào danh sách so le 35ms/thẻ (đã có ở feed — áp dụng tab Cửa hàng).
- Nhấn thẻ: scale 0.98 + ripple (đã có tactile cho nút; bổ sung cho cả card).
- Tab chuyển: gạch chân trượt 180ms.

---

## PHẦN B — HIỆU ỨNG QUÀ LIVE

### B1. Thang bậc & luật leo thang
| Bậc | Quà | Thời lượng | Lớp hiệu ứng | Âm thanh | Rung |
|---|---|---|---|---|---|
| T0 | Tim (heart) | 0,8s | 12 tim bay nhẹ | Không (tránh spam) | Không |
| T1 small | Hoa hồng, Sao pha lê, Bướm mộng | 1,8s | 18 hạt + art 140dp + nhãn | 1 lớp, 0,5s | 1 nhịp nhẹ |
| T2 medium | Vương miện, Cực quang, Sao băng, Sen | 2,6s | 26 hạt + art 170dp + quầng sáng + nhãn | 1 lớp + tail | 1 nhịp |
| T3 large | Siêu xe, Du thuyền | 4,2s | 3 lớp: nền chuyển động + 40 hạt + art 200dp + banner dưới | 2 lớp (intro + thân) | 2 nhịp |
| T4 legendary | Lâu đài | 7,0s | Cinematic toàn màn: nền tối dần, lâu đài mọc lên, 3 đợt pháo hoa, mưa vàng, banner lớn | 3 lớp (intro + impact + fanfare) | 3 nhịp + flash |

**Combo** (server đã có comboCount, cửa sổ 5s):
- Mỗi bậc combo tăng: +20% số hạt, nhãn "x2, x3…" to dần, cao độ âm thanh +1 semitone mỗi 3 combo (dùng `SoundPool.setRate`).
- Combo ≥10 với quà T2+ → thêm hiệu ứng "vòng sáng" quanh tên người gửi.

### B2. Choreography chi tiết cho quà đắt tiền

**Siêu xe (T3, 4,2s)**
1. 0–0,4s: vệt tốc độ hai bên (line trắng mờ) + đèn pha quét.
2. 0,4–2,4s: xe lướt từ trái sang phải (đã có), thêm khói lốp (hạt xám mờ) + tia lửa neon sau đuôi.
3. 2,4–3,2s: xe dừng giữa, "headlight flash" 120ms, banner "Siêu xe · từ <Tên>".
4. 3,2–4,2s: hạt tàn dần, nhãn giữ 0,6s.
- Âm thanh: `car_intro.wav` (swoosh 0,6s) + `car_engine.wav` (rev 1,2s) — 2 stream.
- Rung: 2 nhịp (khi xe vào và khi dừng).

**Du thuyền (T3, 4,2s)**
1. Nền chuyển từ tối sang xanh đêm (gradient quét dọc 0,8s).
2. Sóng nước 3 lớp chuyển động; thuyền trôi ngang chậm; đèn hải đăng quét 1 lần.
3. Kết: bọt sáng + nhãn "Du thuyền · từ <Tên>".
- Âm thanh: `yacht_waves.wav` (nền 1,5s) + `yacht_horn.wav` (0,5s).

**Lâu đài (T4, 7s) — "cinematic"**
1. 0–0,8s: màn tối dần (overlay 60%), 2 tia sáng từ dưới.
2. 0,8–2,2s: lâu đài mọc từ đáy lên (scale + translate, glow vàng), bụi sáng bay.
3. 2,2–4,2s: pháo hoa 3 đợt (mỗi đợt 24 hạt, 3 màu: vàng/hồng/tím), rung 2 nhịp.
4. 4,2–5,4s: mưa vàng (40 hạt rơi chậm) + banner lớn giữa màn: "Lâu đài · <Tên> tặng <Người nhận>".
5. 5,4–7,0s: mờ dần, trả lại màn hình.
- Âm thanh 3 lớp: `castle_intro.wav` (trống dồn 1s) → `castle_impact.wav` (boom 0,6s) → `castle_fanfare.wav` (kèn 1,5s). Phát tuần tự, tổng ≤3s, mix 0,45.
- Đặc quyền đi kèm (đề xuất): người gửi được gắn nhãn "Huyền thoại" cạnh tên trong 60s; top-sender ribbon cập nhật ngay.

### B3. Ngân sách hiệu ứng & an toàn
- Tối đa 1 T4 + 1 T3 cùng lúc; nếu vượt → xếp hàng (delay), không chồng màn.
- `reduceEffects` bật: T1–T2 chỉ phát âm thanh + nhãn nhỏ; T3–T4 hiện banner 1 dòng + âm thanh (không chiếm màn).
- Tôn trọng chế độ im lặng: hiện có (`RINGER_MODE_NORMAL`, âm lượng > 0); giữ throttle 450ms giữa các âm thanh.
- Không dùng Bitmap mỗi frame: toàn bộ vẽ Canvas vector như hiện tại; hạt giới hạn ≤48.
- Máy yếu: nếu `ActivityManager.isLowRamDevice()` → hạ T3/T4 xuống mức T2 (đề xuất).

### B4. Chọn quà trong bảng quà
- Chia 3 nhóm có tiêu đề: "Quà nhỏ", "Quà nổi bật", "Quà huyền thoại" (dựa `tier`).
- Quà T3+ hiển thị thêm dòng "Hiệu ứng toàn màn hình" + xác nhận khi giá ≥ 1000 xu.
- Thanh combo hiển thị khi chọn quà comboable: "Chọn số lượng x1/x5/x10/x99" (đã có) + gợi ý "Gửi liên tiếp để tăng combo".

---

## PHẦN C — LỘ TRÌNH TRIỂN KHAI (bám code hiện tại)
1. **P1 — Leo thang theo bậc** (`LiveGiftExperience.Effect`): duration/particle/label/flash theo `tier`; combo scale; haptics. ~1–2 ngày.
2. **P2 — Cinematic T3/T4**: 3 hiệu ứng riêng (car/yacht/castle) + sound layering (SoundPool 2–3 stream) + banner. ~3–4 ngày.
3. **P3 — Cửa hàng**: ribbon bậc + viền legendary shimmer + trạng thái + chip kho quà + so le thẻ. ~2–3 ngày.
4. **P4 — Bảng quà theo nhóm + xác nhận quà đắt + top-sender ribbon**. ~2 ngày.
5. **P5 — Âm thanh**: bổ sung asset (`car_intro`, `car_engine`, `yacht_waves`, `yacht_horn`, `castle_intro`, `castle_impact`, `castle_fanfare`) — cần file WAV ngắn, 44,1kHz mono, ≤1,5s, tổng ≤300KB.

## Tiêu chí nghiệm thu
- 4 bậc quà khác nhau rõ rệt về thời lượng/lớp hiệu ứng/âm thanh; T4 chiếm trọn màn hình ≥6s.
- Combo tăng dần trực quan (hạt, nhãn, cao độ).
- Chế độ giảm hiệu ứng và im lặng hoạt động đúng.
- Thẻ cửa hàng phân biệt bậc trong 1 giây nhìn; legendary có shimmer.
- Không tụt FPS khi 2 hiệu ứng chạy đồng thời trên máy tầm trung.
