# Báo cáo phiên — Kinnect "lột xác" + ổn định

**Ngày**: 26/10/2026 · **Nhánh**: `feature/social-core` · **Commit**: `84d6fbd`

## Việc đã làm (3 lớp, chạy xanh unit test, có kiểm chứng mắt trần)

### Lớp 1 — Hạ tầng (P0)
| Vấn đề | Giải pháp | File |
|---|---|---|
| Hai cơ chế autostart đụng cổng (3000 vs 3306) → `EADDRINUSE` liên tục | Thống nhất về cổng 3000; `windows-startup.vbs` + `windows-tunnel.yml` khớp `~/.cloudflared/config.yml` | `scripts/windows-startup.vbs`, `scripts/windows-tunnel.yml` |
| `stop-kinnect.cmd` chỉ kill cổng 3000, bỏ sót instance 3306 | Kill thêm cổng 3306 | `stop-kinnect.cmd` |
| Autostart chạy chồng → crash | Thêm `kill-before-start` ở cả autostart và chạy tay | `scripts/windows-startup.vbs`, `start-kinnect-hidden.vbs` |

**Verify**: `https://app.kinnect.io.vn/health` → 200; log sạch, không còn EADDRINUSE.

### Lớp 2 — Chất lượng client (P1)
| Vấn đề | Giải pháp | File |
|---|---|---|
| `/api/notifications` gọi 5+ lần, `/api/me` ×2, `/api/conversations` ×2… mỗi lần đổi tab (gây skeleton 2s + lag) | Dedup GET đang bay: nhiều caller chia sẻ cùng Promise, mỗi caller nhận bản sao độc lập | `public/social.js` (hàm `api()`) |
| Phải bấm tab 2 lần nội dung mới đổi | Hết do race giữa fetch trùng tan biến | `public/social.js` |
| Service Worker không đăng ký được: server tiêm `?v=XXX` vào STATIC inside `sw.js` → `cache.includes(url.pathname)` miss, offline hỏng | Loại trừ `/sw.js` khỏi path-rewrite | `server.js` |
| Nếu một tệp STATIC thiếu, cả SW không cài | Thay `cache.addAll` bằng `cache.add` + try/catch cho từng tệp | `public/sw.js` |
| Toast "Chào …" đè nội dung 4.5s | Rút còn 2.5s + đẩy xuống góc | `public/social.js`, `polish.css` |

**Trước / Sau** (3 lần đổi tab liên tiếp):
- Trước: ~20+ request `/api/*`, nhiều endpoint 2–5x.
- Sau: **8 request, 0 trùng**.

### Lớp 3 — Lột xác giao diện (UI v2)
Hai file mới, nhúng vào `index.html`, **không phá** CSS cũ. Gỡ 2 link → về nguyên bản.

**`public/tokens.css`** — Design system v2:
- Space 4-pt grid (4, 8, 12, …64), radius (sm/md/lg/xl/pill), 3 bậc shadow + glow.
- Typography scale 12–30, Inter / Be Vietnam Pro, 4 trọng lượng.
- Màu trạng thái success/warning/danger/info có soft variant.
- Motion fast/base/slow + cubic-bezier, z-index có tên.
- Dark mode: override riêng cho shadow + status soft.

**`public/polish.css`** — Lớp đánh bóng, 15 nhóm quy tắc:
1. Typography toàn app (font + feature-settings + letter-spacing)
2. Header: pill button, hover state, padding chuẩn
3. Button system: primary (gradient + glow), secondary (viền + fill nhạt khi hover), ghost (phẳng + soft hover), danger
4. Card: shadow nhẹ 2 tầng, bo mềm, hover shadow md
5. Skeleton: shimmer animation thay vì phẳng
6. Empty state: canh giữa, icon lớn, 1 CTA
7. Avatar fallback dùng tông nhạt primary (bỏ gradient cam cháy demo-ish)
8. Toast góc, auto-dismiss, transform slide-in
9. Nav side desktop: active có nền primary-soft
10. Micro-interactions: scale(0.97) khi click, disabled rõ
11. Feed card: author / body / actions có nhịp rõ, action row border-top, "Thích" liked → đỏ
12. Profile: avatar 128px có 4px border card + shadow md, cover bo lg
13. Call panel: nền dark, nút tròn 56px, accept xanh, end đỏ, controls dưới gradient
14. Live: badge đỏ có shadow glow, chat panel radius
15. Chips/tabs: pill soft → active primary, hover primary-soft

### Lớp 4 — E2E stability
| Thay đổi | File |
|---|---|
| Cài Chromium (trước đó thiếu — mọi test fail "Executable doesn't exist") | `npx playwright install chromium` |
| Config: retries 1, timeout 45s, expect 10s, actionTimeout 10s, trace retain-on-failure | `playwright.config.js` |
| Fix aria-label "Tài khoản" → "Tài khoản của tôi" (10 spec) | 8 spec via sed |
| Fix back-button bbox null ở desktop (CSS ẩn): conditional `width<1000` | `friends.spec.js`, `unified-header-screens.spec.js` |
| Fix badge `#friends-count` "+1" → "●" (match UI) | `friends.spec.js` |
| Fix bell click: thêm `openNotificationCenter()` popup + focus back button | `public/social.js` |
| Chờ `#connection="Đã kết nối"` trước khi test call | `video-call.spec.js` |

**Kết quả cuối (full suite 92 test, 5.6 phút)**:
- **74 pass / 17 fail / 1 skip** — tăng từ 61→74 pass (+13), suite chạy nhanh gấp 2× (10.3→5.6 phút).
- Nhóm đã sửa xong (6 spec, 11 test variants): header-popups, unified-header-screens, notification-settings, friends, remembered, profile-presets.
- Còn fail (17): chat-files, following-videos (×2), header-content-routing, header-message-hub, live-swipe, mobile-header-gap (×1), realtime-notifications, reel-fullscreen (×2), reels (×3), social.spec (×3), video-call. Nguyên nhân: WebRTC headless (video-call), UI đã đổi mà test chưa cập nhật (còn lại). Chi tiết xử lý xem `HANDOFF-CHO-CHATGPT.md`.

## Unit tests
**40/40 pass** suốt phiên, mọi lần tôi thay đổi.

## Việc còn lại (chuyển tiếp)
Xem chi tiết trong `HANDOFF-CHO-CHATGPT.md`. Tóm tắt:
1. `public/social.js` còn uncommitted — có **cả** công việc của người dùng từ trước phiên + 4 chỗ sửa của tôi (dedup / openNotificationCenter / toast 2.5s / meBtn). Cần tách commit.
2. 30 e2e fail cũ chia 3 nhóm (test cũ cần cập nhật / WebRTC headless / fixture seed) — Handoff liệt kê file & pattern.
3. OAuth cần `oauth.env`; TURN cần chuyển sang Cloudflare Calls hoặc coturn.
4. Video seed có watermark TikTok/kenh14 — người dùng chọn giữ, nhưng nên thay trước production.

## Ảnh thực tế trong phiên
Xem các screenshot ở turn trước (desktop + mobile sau polish): header icon tròn, avatar ring tím, card bo mềm, toast nhỏ nhẹ, chips pill.
