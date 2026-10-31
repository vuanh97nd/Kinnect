## 2026-10-30 — APK1.0.36 Game Live recursion fix

Source2b5d8838cdb1153480b6a7d1fb1914d71298d742(parente654cb38). Published GitHub latestv1.0.36/code101; full official Android-UA download SHA matches pointer. User screenshot761.jpg shows recursively repeated host Live UI during LiênQuan screen capture.

Root cause: LiveActivity.startGameSession allocated local SurfaceViewRenderer and NativeRtc.screen added capture track as its sink, rendering the screen into itself. Now screen session uses local=null and no SurfaceViewRenderer; NativeRtc.screen never adds local sink as defense in depth, while camera preview media() unchanged. Outgoing track/source remain active.

Host control view uses static cover plus Open game button, no captured-video preview. gameControllerVisible independent from manual screenPaused; effective hold is OR. Startup held until game opens; onResume Live controller holds outgoing screen video/gameAudio, onStop resumes only if manual pauseoff. Joinedack syncs state then opensgame for approved cameraSetup route. Notification/mic updates preserve effective hold. Viewer mode-state applies authoritative mask; host mask uses local effectivehold to avoid stale echo hiding it. Microphone remains user's selection. Connection status moved below center controls to avoid covering text/button. This automatic cover is LiveActivity control page only, not every KinnectActivity; do not claim all unrelated app screens are automatically hidden.

Validation25actual Android36 emulator checks: real MediaProjection consent/captured frames, separate-UID synthetic game audioPCM, local joined-ack simulationautoopensfixture, native localSinknull, control return video/audiohold, game resume, manual pause/resume, OSrevocationcleanup. No public Live created, no actual LiênQuan/Samsung physical test. A fixed700ms game-return audit wait was flaky; now polls controller lifecycle up5s, finalPASS25. Screenshotcontroller+verification in docs/cloud-handoff/game36. QAcode/assets equal production exceptmanifest/signature, v1/v2/v3+16KBalignmentverified. Backend/SFU/web unchanged and not restarted.

## 2026-10-30 — APK1.0.35: Nearby only under Friends

Source e654cb38b3dbc8255a4bd6de54cc803f99b59248, release/kinnect-1.0.35;code100. Published GitHub latestv1.0.35; official download full Android-UA SHA verified against pointer. User requested remove Nearby from search because it belongs in Friends. MainActivity discover now ForYou/Following, normalizes old near state tointerests. Native Friends previously had no explicit Nearby entry, so adds one on Friends tab and opens a dedicated nearby screen using shared renderPeopleSearch(true), friends back button/header. Location and filter apply/reset refresh the correct Friends Nearby screen. Search tutorial preview also removes thirdtab. No backend or web UI changes/restart. Build/signaturev1/v2/v3/16KBalignment passed and narrow source reviewed. No real-phone GPS test or new test suite for this small reversible UIchange. Generated family/language assets match34; source includes updated icon usage only. Never whole-checkout commit the ancient dirtyindex.

## 2026-10-30 — Published APK1.0.34: compact coin card + unlimited admin

Published source2fdd68f3fb8af7d32109c7f556e1eec5d633bfa5 on release/kinnect-1.0.34 (parentd43e007). Website APK1.0.34/code99, full Android-UA official download63906739bytes SHA matches dist/published-apk.json. No web UI/Playcandidate change. Backend SQLite backed up then restarted;SFUready2000/30 unchanged,no capacitybenchmark.

User decisions: admin must use every feature without purchase, show unlimitedcoins, and STILL be allowed to buy for purchase effects. Store must show balance. Wallet purchased/gifted balance compact, attractive/no clipping; requested coin-shaped icon. Screenshot issues: toolbar should display own avatar; duplicated profile-interest text under buttons removed while About interests remain.

Implementation: wallet.unlimited uses DB roleadmin and suspended0 (fails closed in minimal fixture). Wallet returns booleanunlimitedCoins, no infinite numeric money/no real credit generated. Trial admin gifts debit0 and leave stock untouched, never create withdrawable earnings. Emergency server kill remains respected. PackageStore admin virtual ownership all15 + until year9999 sentinel; all legacy Store products owned virtually too. Studio/Game authority checked server-side. Admin package buy creates admin_package_events idempotent audit only,no walletdebit/no persistent purchase entitlement. Demotion removes virtual rights, genuine prior bought rights remain. Native cardWallet/Shop shows∞admin; optional Mua gói·∞xu in details calls free admin purchase and successFX. Photo export now rechecks server license before rendering to handle changed role/session/expiry.

CoinBalanceCard shared Wallet/Shop: single gradient card, Purchased/Gifted side-by-side, common hide inWallet, compact Shop. Number auto-size uses horizontallyScrolling=false (necessary with singleLine); large values abbreviated inbillions, full numeric accessibility description. Gold native vector coins with K atpaid balance and packageprices, gifticon distinguishes giftedcoins. Store balance reloads after transactions. Admin shows one∞line and uses no actual cash.

CommerceChrome fetches /api/me and image ownavatar via existing authenticated NativeApi; initials fallback. MainActivity duplicate profile-header interestline removed; real About chips unchanged. Wallet history classifies store_paid/coin_purchase/live_gift_paid ascoins instead of creatorVnd0 (fixes prior knownfutureissue; paid-entry explanatory footer wording still generic).

Evidence126backend pass0fail incl forgedclientflag rejection,adminfreebuy/replay,zero giftcharge,demotion revocation/no permanent ownership.2298native checks320dp/font130 light/dark incl normal/admin/verylarge balances,six Shop tabs,optional admin purchase. QA bytes equal release exceptmanifest/signature. v1/v2/v3 and16KBalignment passed. PhysicalSamsung nottested; no real GooglePlay payment. docs/cloud-handoff/admin34 screenshots+verification. All purchases/grants in tests isolated; no production admin coin credit created.

Still pending real GooglePlay topup/service account/products/consumable verification/refundpipeline and payout adapter; user chose GooglePlay for eventual nạp thật. They explicitly allow gifted coins for all packages during trial, admin can disable futuregiftedpurchases. Do not claim GooglePlay real payments or infinite cash withdrawal. Important future edge case: admin_package_events retries after role demotion currently fall through normal purchase rules (native does not auto-retry, but API-level retry should eventually be rejected instead of becoming a normal charged purchase).

## 2026-10-30 — APK1.0.33: functional store designs, purchase FX, admin contrast

Release source d43e0072d2fe4a04214ac1ad1099215fc6fee7f2, parent56a8e05. Published GitHub latestv1.0.33 and official /download/android. Full Android-UA download63906584bytes SHA558539a01b9833f8d89bf3b3543d33855219bbd680567463ccc6799310d55711 verified. Nativecode98/version1.0.33, stable website signaturev1/v2/v3 and16KBalignment. Active checkout/index not committed wholesale. No web UI or Play AAB change.

Latest user decisions: each package must have professional meaningful artwork and actual in-app purchase/apply/effects. Purchase success uses image animation, not text popup. Convert suitable success notifications to visual effects; preserve important decisions/errors. Gifted coins may buy ALL package families during trial. User selected Google Play for eventual real topup. Admin gift page white/washed text explicitly fixed.

Implemented StorePackageDesign:15 unique vector identities, meaning +3 truthful benefits per package, detail scroll; same price tiers. StorePackageDesign only promises what is implemented:avatar frame/chat colors; Live corner frame; profile/Live membership badge; gifted gift inventory; Studio/Game entitlement. Plus/Creator differ badge color/label, no fabricated advanced tools. Studio3periods same tools, different duration. No free Studio banner.

lib/store-packages.js opens15packages for gifted trial purchases, real rights, lifetime skin/live themes,30-day memberships. storePackages.owned integrates legacy store ownership/style route. package_preferences stores selected Live decoration. Social publicUser gives storeMembership; joined room includes authoritative liveDecoration/hostMembership. Native StoreStyle/MainActivity/LiveActivity render actual styles/badges/corner frame. Gift packs:love6rose;speed1car+2star;royal1castle. gift_inventory (source tagged) redeemed atomically before gifted wallet debit;0 second debit, nonce replay does not consume twice. New package source chooser supports gifted/purchased; gifted permitted only if economy trialPackagePurchases (defaulttrue; merged for legacy configs). Admin economy toggle controls new gifted purchases, never revokes existing purchased duration. Purchased gift-pack buying is503 until real payment/settlement integration.

PackagePurchase: source choice -> precise confirmation -> authoritative server -> SuccessEffects purchase (art,particles/check,Use now), no success text modal. No replay on duplicate/restore/error/cancel. Generic positive success categories saved/applied/copied/updated/post/video/friends/report/admin grants use transient icon+accessible announcement. Errors/security/delete/financial confirmations remain readable. Visual audit JSON in docs/cloud-handoff/store33/notification-audit.json. SuccessEffects respects reduced motion and auto cleanup; no added purchase sound. Gift sounds remain original10assets.

Admin contrast: CoinGrantActivity explicit input/hint/switch/checkbox/disabled button text AND icon colors, custom field backgrounds; compact All selected label. EconomyAdmin inputs use ink; CommerceChrome disables system Force Dark since app controls theme. Actual320dp/font130 light/dark checked.

Evidence125backend tests,902native checks (15distinct artwork hashes,30detail sheets light/dark,6tabs,success/error separation,purchase effectUse now/cleanup,admincontrast). QA APK code/assets equal release exceptmanifest/signature. Purchase animation QA is locally simulated callback, not real money. PhysicalSamsung not tested; production32->33 update not separately re-run (signing/alignment andQAinstall verified).14screenshots+gallery. Backend consistent SQLite backup then restarted;SFUready2000/30 unchanged(no capacitybenchmark). No public admin grants or purchases executed by QA.

IMPORTANT remaining real-money work:billing.env absent; no Play service-account/product setup. No consumable coin receipt/consume/refund pipeline added in this release; Play AAB remains1.2.4. Real topup/payout remainclosed, no manufactured purchased credits. Package purchased-source spending is server-tested with isolated trusted credit fixtures only. Before enabling real money, implement verified consumable GooglePlay credit/consume/refund/reconciliation, provider payout/holds and review requested direct redemption of purchased currency against Play policy. WalletActivity history currently classifies store_paid as non-trial and would display creatorVnd0 rather than paid coin debit; MUST fix history/source labels before real purchased balance is enabled. Existing gifted history is correct. Do not tell user real GooglePlay topup is active.

## 2026-10-30 — APK1.0.32: paid packages, admin grants, dual coin wallet

Source56a8e0549b9371782d6113d39c7ec1c82d22407e, parent4c07167. Published GitHub latestv1.0.32; official /download/android serves32 and full Android-UA download SHA matches. Keep web UI and Playcandidate unchanged.

Final user decisions supersede earlier free Studio: Studio Pro7days190xu/month490xu/year3990xu, no free-trial label or access. Existing verified legacy permanent Studio purchases remain valid. New store_packages grants time-limited rights after explicit trial-coin debit, idempotent nonce, no auto renewal or stacking while active. Chat Live/viewing free; Game490xu/30days. Server enforces Game entitlement on creation. Native camera setup checks installed game before pay prompt, then preserves original permission/projection/start flow. Never charge unavailable decoration/membership/bundles; show their approved prices and Coming soon. Six storefront tabs, compact Studio rows. Ref1xu100VND; plan equivalent follows configured reference rate. Payment adapters still closed.

Admin: Settings -> Gift coins to members / Gift coins & gift prices. CoinGrantActivity supports selected1..500 or all active users, search, preview fixed recipient snapshot, total, explicit confirm, ten-minute preview expiry, idempotent retry, audit. lib/admin-coin-grants.js server role/CSRF/atomic wallet grant. A changed/deleted/suspended recipient aborts entire batch. No public grants executed in verification. Signup2000once remains separate config. Grant admin_trial is gifted source.

Wallet final rule: Gifted coins + gifted-coin gifts never withdraw. Both purchased-coin remainder AND earnings from purchased-coin gifts are eligible for withdrawal (user explicitly chose this). State separates giftedCoins/purchasedCoins/giftedGiftValueCoins/purchasedRefundableVnd/giftIncomeWithdrawableVnd/withdrawableVnd. Trial gift recipient tracked for display only, no cash income. Purchased gift source currently rejected until provider integration, no fake purchased credits. Real topup/payout remain503. Trusted creator settlement75/25 net retained; no public settlement endpoint. Full paid purchase/refund/reservation adapter NOT implemented. Current executable plan purchases use gifted coins only.

Evidence123backend tests;698nativeUI checks320dp/font130%,light/dark incl store6tabs, paidStudio/no free banner, grantselect/all/confirm, wallet separation. Actual production31->32 update+launch passed Android36 emulator; QA code/assets equal release exceptmanifest/signature. v1/v2/v3signature and16KB alignment verified. Physical S23Ultra and real money not tested. docs/cloud-handoff/store32 has15screenshots+verification. Consistent SQLite backup before backendrestart; SFU2000viewers/30rooms remainsready (limits,notcapacitybenchmark).

## 2026-10-30 — APK 1.0.31: commerce, trial coins, ten Live gifts

Source snapshot 4c0716771bbd1aec022e82f48bb2432515c61959 (release/kinnect-1.0.31), parent SFU83fe2d9. Artifact dist/Kinnect-1.0.31-native.apk/code96, SHA25646590e9af1a5942e08b03f4b8ec8a511dde09675ef6b61c1827141d7698448b7. Published to GitHub latest v1.0.31 and official /download/android; pointer updated atomically after GitHub asset hash verification. Full Android-UA public download hash verified.

Native Wallet/Store rebuilt compact/icon-first; Studio Pro temporarily free, ownership/apply/restore preserved. Ten Live gifts with unique native effects and bundled original WAV sounds, including car/yacht/castle. Prices from server, explicit confirm, transactional trial debit/idempotency/stale-price protection. New successful signup gets2000 trial coins once via SQLite insert trigger; NO retroactive existing-user bonus.100VND/coin; six reference packs100/500/1000/2000/5000/10000. Trial coins do not settle cash. Real checkout and payout remain closed. Admin Economy screen controls bonus/rate/giftprices/packs with version/audit and backend authorization.

Backend safely SQLite-backed-up under data/backups before restart; actual database economy_config version1 rate100 bonus2000 and wallet_signup_trial_v1 trigger verified. Public health200, SFUready limits2000viewers/30rooms (not capacity benchmark). No web UI development or Playcandidate1.2.4 changes.

Evidence:116backend tests,290native checks at320dp/font130%, light/dark; docs/cloud-handoff/commerce31 screenshots+verification. QA code/assets match production ZIP exceptmanifest/signature. Exact production31 clean ARM64 extraction and x86_64 install+launch,30->31 update passed on Android36 emulator, QA snapshot restored.32-bit ABI included but emulator unsupported. Explicit extractNativeLibs=true, v1/v2/v3 signatures verified and16KBzipalignment. Actual S23Ultra OneUI7 not tested; original30 package-invalid issue not reproduced (never installed before; don't assume signing conflict). Do not claim all devices verified. Install-check initial assertion incorrectly searched package name in numeric pid; corrected and passed, no production crash found.

Build work/build-commerce31.py uses fresh timestamped build path and explicit signing flags; older scripts/build-apk-windows.py defaults differ. No secrets in release. Active ancient checkout/index intentionally not committed wholesale. Review release source selectedfiles only. No real billing or public gift transaction tests.

## 2026-10-30 — Live SFU phục vụ APK, giới hạn2000/30, web tạm dừng

Source snapshot 83fe2d9baec687d9f64b93f51bc035ac3fd455d9 trên feature/live-sfu-20261030; dist/Kinnect-live-sfu-2026-10-30-source.zip. Không đổi active checkout/index, không tạo release hoặc đổi APK pointer.

User chốt tập trung app, tạm dừng phát triển web. Đã triển khai services/live-sfu (Go/Pion4.2.26, VP8/Opus, UDP mux7886, loopback control7885 + secret) và lib/live-sfu.js broker xác thực. APK1.0.30 không cần sửa/cài lại: protocol multiGuest hiện tại hỗ trợ @sfu upstream và downstream publisher-ID. Một uplink mỗi người phát; Go downstream send-only để không nhận lặp media từ host/guest. Mời khách/block/revision được kiểm soát backend; loss control kết thúc phòng liên quan, app chờ SFU ready trước create mới.

Đang chạy SFU do server-manager quản lý; sfu.env riêng được ignore, secret không đưa Git/APK. User yêu cầu max2000 viewers/phòng và30 rooms: publichealth ready xác nhận đúng. Đây admission config, KHÔNG phải sức chứa kiểm chứng; chưa có cụm SFU/VPS/băng thông cho60k viewers. Máy hiệnRTX3050 6GiB, SFUkhông dùng NVENC/VRAM, GPUworker chưa triển khai. Đã batch room presence100ms/8avatar + block snapshot mộtquery cho2001members, tránhSQLiteN². Không sửa public/v2.js hoặcwebUI/Play/APKdownload.

110 backend tests đạt; Go2 tests gồm actualRTP50 synthetic low-bitrate receivers/oneuplink + revoke; nativefullstack camera->authenticatedNodeinmemory->privateSFU->nativeviewer decode6frames, khôngpublicroom, chưaphysical/crossnetwork/2000×30HD. Publicdownload vẫn1.0.30. docs/LIVE-SFU.md và docs/cloud-handoff/sfu/verification.json. node scripts/live-sfu-status.mjs xemmetrics/limits, node scripts/server-manager.mjs restart-server giữSFU/tunnel, restart-sfu ngắtSFUrooms. Build bằng node scripts/build-live-sfu.mjs; toolsGo verified trongwork/sfu-tools. Không exposecontrolWSplaintext remote; remotephảiwss. Dockerfile/compose chuẩn bịnhưngchưaDocker-tested.

## APK1.0.30 / code95 — Live chung camera, bottom setup, tự mở game

Studio tabLive giữ camera/texture, mở LiveSetupSheet một nơi chọn Chat/Game; game mới có picker12, exact launcher label/alias + intent visibility query, không QUERY_ALL_PACKAGES/upload. Một Start cố định; OS consent default-display API34+, rồi create room, joined ack mới openGameApp đúng component; không về Home như29. Chưa cài/không khớp label báo trước khi xin quyền/phát. Mic/sound/comments icon toggle; nguồn camera trước/sau mở đúng từ đầu và common look extras. Cancel/failure về Studio; revoke cleanup. ViewerLive/web/Play/backend giữ nguyên. NativeUI31 và actualprojection/audio17 đạt; serverack mô phỏng/socketnull, fixture riêngUID, khôngpublicbroadcast, chưađiệnthoạithật/game thương mại. QA120 payloadmatchesrelease95trừmanifest/signature. docs/cloud-handoff/live30/verification.json. Đã phát hành30; GitHub latest + SHA và link chính thức HTTP200 đúng file đã xác nhận. Source b861f2c96c89f11b6a2be6a282d92c393cc79fc9.

## APK1.0.29 / code94 — Chọn game cólist

Trong+cameraLiveGame: ôChọnGame mởsheet12gợiý, tìmkhôngdấu/alias, selectedtick, Gamekhác/clear. LiveGamePicker.java mới, gameTitleđượccậpnhậtmetadata. Khôngautoopen/càigame, khôngscaninstalled apps/khôngthêmquyền. Catalogcuratedkhôngrank. NativePicker17 đạt+Preparation16hồiquy,320dp/font130;chưađiệnthoạithật. QA119 payloadmatchesAPK94trừmanifest/signature;certgiữnguyên. Sourceee2726740f8e9c64ea7195cf308829dd4f0589de;Đãpublish29, publiclatest/SHA/download200 xácnhận;dist/published-apk.jsonpointerchuẩn. Web/Play/backendkhôngđổi. docs/releases/v1.0.29.md,docs/cloud-handoff/game29/verification.json.

## APK1.0.28 / code93 — Live từ+ mở thẳng chuẩn bị

Chốt mới: StudioLive khôngđi vào viewer/sảnh. Host intent onCreate vẽpreparationWaiting với2 mode inline ngay, khônglobby; welcome→prepareHost mởcamera xemtrước mặcđịnhChat. InlineChat/Game ở cảcamera/gamepreparation, switchgiữtitleđóngRTCcamera; khôngcreate/joinchođếnStart+consent. StudioActivity khôngfinishkhi mởLive nênbackvềcamera. IconXcónền và2 modeicontrênchữ đồngđều. ViewerLive27vuốtchung giữnguyên.

NativePreparation16 đạt actualemulatorcamera/modes/release/noautoSignal,320dp/font130. QA118 payloadmatchesAPK93trừmanifest/signature;certgiữnguyên. Chưaphysical. Source30737634a9e03ddd1b2bb4084d73cebec86d43ff; Đãpublish28, publiclatest/SHA/download200 xácnhận; dist/published-apk.json làpointerchuẩn. Khôngsửaweb/Play/backend. docs/releases/v1.0.28.md và docs/cloud-handoff/live28/verification.json.

## APK1.0.27 / code92 — bỏ hàng lọc Live theo chốt cuối

Màn xem Live vuốt chung mọi phòng Chat/Game. Bỏ hẳn All/Chat/Game category tabs khỏi viewer và lobby; viewingRooms trảtoàn bộlastRooms. Chỉ lối tạo Live từ+camera mới chọnChat/Game, khôngautoJoin. GiữfreeStudioPro vàgameoverlay/reply/mắtxem;Karaoke đãgỡ. NativeUnifiedLiveAudit10 đạt (rootstageonly/noAll/swipeChat→Game/creation2choices) vớisocketintercept; chưađiệnthoạithật. QA117 payload khớp APK92 trừmanifest/chữký. Không sửaweb/Play.

Source1b6cfb302bc45d223c1ddfb49bc581b3744c5145, Đãpublishv1.0.27, publiclatest/SHA/download200 đãxácnhận;dist/published-apk.json làpointerchuẩn. docs/releases/v1.0.27.md vàdocs/cloud-handoff/live27/verification.json. Đây làchốt supersede hàng lọc trêncùng ở26.

## APK1.0.26 / code91 — chốt cuối BỎ KARAOKE

Người dùng đã đổi quyết định: bỏ Karaoke, YouTube/live karaoke và Việt KTV. Live tạo chỉ Trò chuyện/Chơi game. Bộ lọc trên cùng viewer: Tất cả/Trò chuyện/Chơi game. Xóa LiveKaraoke/KaraokeLyrics/YouTubeSongSearch và audit lỗi thời; backend không có karaoke state, chặn sing-* và normalize legacy karaoke mode vềchat. Giữ game overlay/cmt/mắt/reply và + directcamera.

Studio Pro tạmFREE theoAPI studioProFree defaulttrue, KINNECT_STUDIO_PRO_FREE=false đểtắt. NativePhoto dùng/lưu vàVideo template/export kiểm cờserver;Store cófreebadge/nút mở, pickerảnh/video, khôngghi fake purchase/khôngđụngstyleowned. Backend113 đạt; freePhoto33 pixel/export/save thật vàfilter3tab9 đạt320dp/font130;chưađiệnthoạithật. Node đãrestart. Web/Play1.2.4 khôngsửa.

Draft26 cũ bịdừngtrướcpublish khi userbỏkaraoke;đãclobberdraftbằngnguồnfinal7760771edc07d1f5e241f1d863389491e6d04698. Đãpublish, publiclatest/SHA/download200 đúng1.0.26 xácnhận; kiểm dist/published-apk.json. Không tiếp tục tíchhợpYouTube/VietKTV khi chưa có yêu cầu mới.

## APK1.0.25 / code90 — Live game overlay và YouTube reference

Yêu cầu: Live cạnh Video vẫn swipe viewer; Live trong + camera mới chọn3 chế độ. Đã re-enable viewer autoJoin có creationEntry guard. Game: SYSTEM_ALERT_WINDOW optional checkbox, Settings permission trước projection; overlay trong background từ bound FGS hiển thị4cmt/mắt xem, kéo/thu gọn, mic/pause/room và reply. Reply cókeyboard focus (reattach WindowManager khi chuyển focus flags), @name prefix, gửi qua socketchat; mainActivity onResume ẩn overlay; stop/cleanup xóa. Native29 overlaychecks,16 projection/audio,7 routeYT đạt. Appops grant permission trong QA; chưa manualSettings/physicalgame end-to-end.

YouTube: visible official m.youtube.com WebView search/reference, thực thấy kết quả tải; chưa trọnbài. Không scraping/downloading/extraction/hidden background/rebroadcast. Karaoke local backing mix pause khi mởYT; chọnYT chỉ reference, người xem KHÔNG nghe nhạcYT quaLive. Đây là giới hạn phải nói rõ, không tuyên bố đã hát nhạcYT cho cảphòng. Chưa APIkey cần thiết vì browsingsite, khôngDataAPI. UI ghi rõ.

Version90 certificate giữ nguyên; QA115 payload khớp ngoại trừmanifest/signature. Source5d0f7155c7d4317878457876bb0fc09e8e2e3c55; Đã phát hành GitHubv1.0.25, publiclatest/SHA/download200 xác nhận; dist/published-apk.json chỉ chuyển sauverify. Web/Play không đổi. docs/releases/v1.0.25.md và docs/cloud-handoff/live25/verification.json.

## APK1.0.24 / code89 — icon thoát Studio Pro

Theo chốt mới: ưu tiên icon, ít chữ ở nút thao tác; giữ đủ chức năng. Thoát góc trái hai editor dùng close icon với accessibility Thoát, giữ xác nhận. Native9 exit test đạt320dp/font130; QA114 payload khớp. Source de45e4572f99ea9b34d6b822307dd665af4dcaf6. Đã publish, public latest/SHA/download200 đúng1.0.24 xác nhận; dist/published-apk.json là trạng thái public chuẩn. Không sửa web/Play.

## APK1.0.23 / code88 — sửa theo chốt cuối

+ phải mở thẳng camera photo, không menu trung gian. Giữ thẻ Ảnh/Video/Live trong Studio. Lưu ảnh và Studio Pro giờ cùng cột layout tự đo, cách10dp không overlay. Nút Thoát bằng chữ trong cả editor; hỏi Tiếp tục chỉnh sửa/Thoát không lưu, không giảm tính năng. Ảnh discard xóa draft sau pending writes và chặn lifecycle tạo lại; original/previous export giữ nguyên. Sheet.button wrap height, min50dp+padding để đủ chữ ởfont130. Camera17 + editorExit9 đạt giả lập320dp/font130; chưa máy thật. Chứng chỉ không đổi. Bản đã build và QA113 payload khớp trừ manifest/signature.

Nguồn7cb783dd9a0c8dda5c621111aadaedb6eeb7283d; Đã phát hành GitHubv1.0.23, public latest/SHA và /download/android200 đúng1.0.23 đã xác nhận. Kiểm dist/published-apk.json để biết public đã chuyển chưa; chỉ publisher đổi sau xác nhận SHA. Web/Play không đổi, Live22 giữ nguyên. Người dùng muốn trả lời ngắn, không phải bỏ bớt nút.

## APK 1.0.22 / code87 — đã phát hành

Người dùng chốt + chỉ Camera / Video / Live. Thư viện chọn ảnh/video xong mới có Studio Pro góc phải màn xem lại, giống vừa chụp/quay. Không còn menu chọn cơ bản/Pro trước picker; không thêm lối sửa ảnh/video trùng ở +. Camera default photo; Video chọn tệp rồi Studio review; quay video cũng review, Pro trả về cùng video/cùng thẻ; camera dừng khi review video.

Live: chọn Trò chuyện / Hát karaoke / Chơi game trước phát; lobby có lọc và nhãn. Karaoke local audio + LRC, PCM mix trực tiếp WebRTC, một singer theo hàng chờ và consent khách; không kho bài thương mại/đổi tông/duet đồng thời. Game MediaProjection foreground service, mic + capture game Android10+ theo chính sách ứng dụng, notification controls/pause/revocation, không face overlay.

116 backend đạt; native88 ở VI/EN font130, camera12; game16 gồm OS consent/screen frames/âm từ app fixture riêng/background/pause/revoke; hai peer WebRTC local nhận nhạc qua Opus khi mute mic. QA112 payload giống APK87 trừ manifest/chữ ký. Chưa điện thoại thật/đa máy/Bluetooth. Native photo/menu corrections latest scope supersedes earlier design.

Source e76bc98077d1711a86b886f8791a58502a970cb2; release GitHub v1.0.22, SHA/digest + đường tải GitHub và /download/android đã xác nhận200 đúng filename. Node restarted áp dụng server/live-modes; giữ mail isolation; không sửa web/Play1.2.4. Xem docs/releases/v1.0.22.md và docs/cloud-handoff/live22/verification.json.

## Cập nhật APK 1.0.21 / code86 — đã phát hành

Studio Pro sửa ảnh native đã tích hợp: + → Studio Pro · Sửa ảnh nâng cao; cũng mở từ thư viện/ảnh vừa chụp Studio. Cắt/xoay/lật, màu/Curves/HSL, làm mịn toàn ảnh, mask xóa/khôi phục thủ công, lớp ảnh/chữ, undo/redo, nháp riêng tài khoản, JPEG/PNG tối đa3072px. Icon/màu/phông đồng bộ video. Export kiểm quyền sản phẩm kinnect_studio_pro từ API phiên hiện tại; trial được xem/sửa. Không AI/PSD.

33 kiểm tra pixel/thao tác/xuất/lưu và130 bố cục VI/EN font130, entry picker,4 backend store/mail đạt; font100 cũng chạy. APK QA code111 khác manifest/chứng chỉ để cập nhật trên giả lập, payload còn lại đối chiếu giống bản phát hành code86. Chứng chỉ phát hành giữ nguyên1.0.20. Chưa điện thoại thật hoặc mua gói thật. Web client/Play1.2.4 giữ nguyên. Chỉ restart Node áp dụng mô tả gói Studio, giữ tunnel.

Public latest/list, SHA GitHub và HEAD cả GitHub APK + app.kinnect.io.vn/download/android đạt. Source commit7d43940119b801c2936016a825dbf0ff4e08bbd0; docs/releases/v1.0.21.md và docs/cloud-handoff/photo21/verification.json. dist/published-apk.json đã đổi sau publish.

## Cập nhật APK 1.0.20 / code85 — đã phát hành

Menu tin nhắn/video/bài viết đã có icon; bỏ Thả cảm xúc trùng trong menu tin nhắn, giữ nút ngoài. Nền nút gọi/video/ba gạch đầu hội thoại trong suốt, giữ icon và vùng chạm44dp. Đã rà setItems toàn native: bổ sung icon chia sẻ, người nhận, bình luận, ngôn ngữ/hồ sơ, Live, thư viện và Studio. Sheet hỗ trợ icon chung cho danh sách động và circle_check dự phòng cho lựa chọn đơn; checkbox chọn nhiều giữ nguyên.

QA: Android16 font100/130; menu tin gửi/nhận/thu hồi, video/bài viết chủ/người khác; 25 loại icon popup từ mảng nguồn vẽ thực tế đạt; header xem ảnh. Chưa điện thoại thật hoặc trọn mọi luồng mạng. Xem docs/releases/v1.0.20.md và docs/cloud-handoff/options20/verification.json. Giữ chứng chỉ1.0.19. Public updater và cả hai đường tải xác nhận1.0.20. Web/backend/Play candidate1.2.4 không đổi.

## Cập nhật APK 1.0.19 / code84 — đã phát hành

Hàng tin nhắn: giờ → trạng thái → cảm xúc → menu ⋯; chuyển tiếp/thu hồi/xóa/ghim vào menu. Menu hội thoại có Quay lại; cài đặt quay về menu cha rồi về chat. Feed giữ nguyên viewport/ảnh/vị trí ngay frame đầu khi trở về; bấm Feed đang mở vẫn làm mới từ đầu. Bỏ popup crash khi startup, giữ log nội bộ; timeout báo ngắn, chống toast trùng.

Email spam đã xác định từ test reset_support_limit/reset_without_email: server.js trước đây bỏ qua emailSender cho thông báo quản trị. Nay OTP và thông báo dùng deliverEmail được cấp; createApp mặc định chặn SMTP thật, chỉ CLI production opt-in. Đã restart riêng Node, giữ tunnel. 110 backend đạt; 10 mail/recovery tập trung đạt sau opt-in. Android16 component font100/130 và luồng live feed/menu/back đạt; chưa điện thoại thật. Chi tiết: docs/releases/v1.0.19.md, docs/cloud-handoff/steady19/verification.json. Web client và Play candidate1.2.4 giữ nguyên. Public updater + GitHub download + /download/android đã xác nhận 1.0.19.

## Cập nhật APK 1.0.18 / code 83 — sửa riêng native

Bong bóng tin ngắn có hai hàng: nội dung và hàng giờ/trạng thái/thao tác. Tin dài vẫn xuống dòng, không cắt nội dung. Giữ cảm xúc/chuyển tiếp/thu hồi/xóa; thời gian và trạng thái có mô tả trợ năng, metadata dài có tooltip. Ô chú thích Đăng video giữ đệm ngang 14dp, cách tiêu đề thêm 8dp. Trang cá nhân mặc định Giới thiệu. Web chưa sửa theo yêu cầu.

APK cục bộ `dist/Kinnect-1.0.18-native.apk`, chứng chỉ ký giống 1.0.17; đã publish GitHub v1.0.18 và đổi con trỏ tải sau khi kiểm SHA; API cập nhật công khai và /download/android đều xác nhận 1.0.18. QA component offline trên Android 16 font100/130; xem `docs/cloud-handoff/compact18/verification.json`. Chưa thử điện thoại thật. Play candidate vẫn 1.2.4, không build Play mới.

## Cập nhật mới nhất — APK 1.0.17 / Play candidate 1.2.4

Live thiết kế lại, khách mời video/audio tối đa 3 người; công cụ/quà xổ ngang. Giữ vị trí feed khi trở về; tap lại về đầu/tải mới. Hai nhánh Studio Pro/Tiếp tục sau chọn/quay video. Đồng bộ phông và popup chữ gọn; bỏ nút sửa ở Giới thiệu. Vuốt media dùng chung controller, loại bỏ handler video bị trùng. Tắt cuộc gọi phải hủy nối lại, kể cả khi offline. Xem docs/releases/v1.0.17.md và artifact.json về kiểm tra, giới hạn và việc chưa xác minh trên máy thật. Khởi động lại riêng Node bằng scripts/server-manager.mjs restart-server để áp dụng backend, giữ tunnel. Không đưa work/private reviewer/signing keys vào nguồn.

## Cập nhật mới nhất — APK 1.0.16 / Play candidate 1.2.3

220 vector icon đồng bộ theo hướng bo mềm, ô màu; giữ K trắng và thanh điều hướng. Kéo xuống đầu feed/video đầu để làm mới, double tap Bảng tin trong 550 ms; giữ thẻ/dữ liệu không đổi. Sửa nhãn tab/bộ lọc bị cắt ở font130. Chi tiết và kiểm tra: docs/releases/v1.0.16.md, docs/cloud-handoff/artifact.json. Google Play chưa nộp; chưa kiểm tra điện thoại thật. Không đưa work/private reviewer/signing keys vào Git hoặc gói nguồn.

## Cập nhật ngôn ngữ 29/10/2026

APK 1.0.9 / 74, Play 1.1.1 / 101: Tiếng Việt / English / Theo hệ thống. Nguồn dịch android/i18n/en.json; kiểm tra scripts/sync-android-languages.py; kiểm thử android/test/LanguageAudit.java. Xem docs/google-play/READINESS.md. Chưa nộp Play Console.

# Chuẩn bị Google Play — 29/10/2026

- APK website 1.0.8/build 73 được build đầy đủ từ source, dùng OkHttp/Okio mới và giữ chứng chỉ ký cũ. Bản Play riêng 1.1.0/build 100 dùng `android/app/src/play/AndroidManifest.xml`, AAB target 36, khóa upload riêng và không đóng gói trình cài APK ngoài.
- Tài liệu và các việc Console còn phải làm: `docs/google-play/READINESS.md`, `CONSOLE-FIELDS.md`, `DATA-SAFETY-WORKSHEET.md`, `SIGNING.md`.
- Xóa thật dữ liệu, xác nhận sử dụng dữ liệu, AI opt-in/withdrawal, nguồn policy chung, báo cáo livestream/tin nhóm và công cụ kiểm duyệt đã thêm. Không dùng khóa tài khoản thay cho xóa.
- 97 bài backend/AI/Worker đạt. Native Play chạy trên Android 16, page size 16384 và font scale 1.3, nạp được WebRTC JNI. Các bằng chứng công khai nằm ở `docs/google-play/evidence/`.
- KHÔNG có private signing key/mật khẩu/reviewer credentials trong Git hoặc gói nguồn. Những dữ liệu này chỉ ở thư mục work cục bộ bị ignore. Không tự tạo lại khóa upload trên máy khác, không tự đổi khóa app-signing vì sẽ hỏng cập nhật từ APK cũ.
- AAB là ứng viên Internal testing, chưa được Google duyệt. Không tuyên bố đã hoàn tất Play Console, 12 người/14 ngày hoặc kiểm thử điện thoại thật.

# Cập nhật 29/10 — Kinnect 1.0.7 / build 72

- Thêm tab Giới thiệu ở trái Bài viết cho cả web và APK; mặc định vẫn mở Bài viết. Nội dung public và trường ẩn được lọc, gồm cả identityPublic khi APK dùng dữ liệu chủ hồ sơ.
- Web dùng SVG cùng hình học/màu với vector APK; icon PNG cho PWA/Safari được render từ SVG bằng `scripts/render-brand-icons.mjs`. Worker website được deploy từ `website/`.
- Đường `/download/android` phục vụ file đã phát hành trực tiếp, hỗ trợ Range/HEAD. Con trỏ `dist/published-apk.json` chỉ cập nhật sau khi publish GitHub thành công; không lấy APK mới nhất trong thư mục. `lib/apk-download.js` kiểm SHA trước khi phục vụ. Thiếu file/con trỏ thì dùng nguồn GitHub dự phòng.
- 26 kiểm thử tập trung đạt. Web Giới thiệu qua 4 chiều rộng, tải APK HTTPS trên mobile/PC kiểm đủ SHA. APK Giới thiệu/ẩn thông tin qua Android 14 font 1.0/1.3. Chưa thử điện thoại vật lý.
- APK SHA-256: `ba304c12393dcf60c22c73f7ae00913c30da1245980df3ad63f29e32d25d2685`. Baseline 1.0.6; chỉ thay MainActivity, giữ logo/tài nguyên/lớp khác và khóa ký.
- Bằng chứng và instrumentation: `docs/cloud-handoff/profile-about-*.png`, `scripts/handoff-checks/AboutAudit.java`; đóng gói: `scripts/handoff-checks/package-profile-about-windows.py`.

# Cập nhật logo 29/10 — Kinnect 1.0.6 / build 71

- Logo bo góc dạng vector `android/app/src/main/res/drawable/kinnect_logo.xml`: chữ K trắng, nền tím–hồng, tỷ lệ góc giữ nguyên ở mọi kích thước.
- Thay logo tại launcher, splash, đăng nhập, giới thiệu, cập nhật và IntroArt. Bỏ dòng “Kết nối theo cách của bạn.” tại splash theo yêu cầu người dùng.
- APK SHA-256: `01142b3694f0a70da51787e931c6d2f968abf1384e1a08626539dd8ac38da838`; giữ chứng chỉ ký cũ. Baseline 1.0.5; chỉ thay MainActivity, IntroArt, ApkUpdateActivity cùng tài nguyên logo/launch và tham chiếu icon manifest.
- Kiểm tra logo 34/96/192px, chữ K trắng, icon ứng dụng và không còn tagline startup đều đạt trên Android 14 giả lập. Chưa kiểm trên thiết bị thật. Bằng chứng: `docs/cloud-handoff/brand-splash.png`; instrumentation: `scripts/handoff-checks/BrandAudit.java`.
- Đóng gói: `scripts/handoff-checks/package-logo-update-windows.py`, cần APK baseline 1.0.5, toolchain và khóa ký được cấp riêng.

# Cập nhật 29/10 — Kinnect 1.0.5 / build 70

- APK: `dist/Kinnect-1.0.5-native.apk`; SHA-256: `6eb639dda99f521c28aa35961c75adaccbb6f3eb5cfe9e6853f075656160f8b6`.
- Bỏ minimum height của profileSections; giữ nguyên tab controls để tránh mất focus khi chuyển tab.
- Thêm `lib/ai-stream.js` (SSE UTF-8), truyền sự kiện AI chỉ tới phiên đăng nhập của người nhận; web và APK dựng bản nháp riêng, chỉ lưu tin nhắn đầy đủ.
- Worker nguồn nằm trong `ai-worker/`; triển khai bằng `wrangler deploy --config ai-worker/wrangler.jsonc`. Cần secret KINNECT_API_TOKEN đã cấp; không đưa vào repo.
- Máy chủ và Worker đã triển khai; APK được kiểm trên giả lập ở font 1.0/1.3, chưa kiểm trên thiết bị thật. 21 bài AI/Worker và kiểm tra streaming web đạt. `node --test` trước lần thêm kiểm thử Worker cuối: 87/87 đạt.
- Kiểm tra lại trên thiết bị thật: hồ sơ ít nội dung, chuyển tab bài/ảnh/video, câu AI dài, rớt mạng khi đang nhận chữ và thao tác yêu cầu quản trị viên.
- APK được đóng gói trên baseline 1.0.4, chỉ thay MainActivity; giữ logo/tài nguyên/lớp khác và chứng chỉ ký cũ. Xem script đóng gói `scripts/handoff-checks/package-profile-stream-windows.py`.

Các mục bên dưới là lịch sử bàn giao 1.0.4 và cũ hơn.

# Bàn giao Kinnect 1.0.4 cho phiên đám mây — 29/10/2026

Đọc phần này trước. Các ghi chú từ 26/10 ở phía dưới là lịch sử, không phải trạng thái hiện tại.

## Điểm bắt đầu
- Nhánh bàn giao: `handoff/kinnect-1.0.4-cloud`. Đây là ảnh chụp mã nguồn đang chạy ở Windows; không phải mọi thay đổi so với main đều được viết trong cùng một lượt sửa.
- App/server: thư mục gốc. Trang giới thiệu `kinnect.io.vn`: `website/`; cấu hình static assets `website/wrangler.jsonc`.
- APK mới: **1.0.4, versionCode 69**. SHA-256: `a26553be2fab98b96dea38b490113725ffc91b5f46ad9232335aa950c250f2d0`.
- Chứng thư ký cần giữ: `d8809c1e21f00ccf96984b37123d3d916d2e103bfa1dc2032043f47bb3b9988d`.
- Khóa ký, database, tệp .env, credential Cloudflare/GitHub và dữ liệu tài khoản không nằm trong bàn giao.

## Hành vi và giới hạn phạm vi
- Giữ bố cục/màu hiện có; chỉ sửa những lỗi đã xác định. Logo chuẩn là K trắng nền chuyển sắc tím–hồng `public/kinnect-icon-192.png`, giống từng byte với `res/drawable/kinnect_icon.png` trong APK đã ký.
- Web entry: `public/index.html`, `v2.html`, `v2.js`, `v2.css`. PC giữ màn đăng nhập cũ dạng tường chân dung; mobile có cuộn khi màn hình thấp/bàn phím mở.
- Khởi động web đồng bộ splash native: logo 96px, Kinnect, “Kết nối theo cách của bạn.”, hai vòng tím–hồng.
- Trang giới thiệu mobile nằm trong iframe `website/dist/native-welcome.html`. `native-fit.js` phải chạy trước JS demo lớn. Chỉ hiện mô hình sau khi tính xong kích thước; mô hình đã giảm 10%. Khi sửa, đổi mã phiên bản ở iframe, CSS và JS: tài nguyên static có cache 24 giờ.
- Bốn ảnh demo Khám phá trước đây bị thiếu; đã có `welcome-profile*.png` trong public và website/dist. Không xóa các ảnh này khỏi APK assets.
- 1.0.3 bổ sung cập nhật trong app: Cài đặt → Kiểm tra cập nhật → Đồng ý cập nhật → tải trong Kinnect, hiện tiến độ, kiểm SHA-256/package/version/chứng thư → trình cài đặt Android. Không dùng Chrome để tải. Android vẫn yêu cầu cấp quyền nguồn cài và xác nhận cài đặt khi cần.
- 1.0.4 căn giữa tiêu đề/mô tả “Chưa theo dõi ai”, dùng chung `discoveryEmptyState()`. Web loại bỏ CSS cũ ép `discover-people` thành flex một cột; ảnh hồ sơ vuông tối đa 144px, bố trí theo hàng.

## Kiểm tra đã làm
- Xem `docs/cloud-handoff/artifact.json` và ảnh QA cùng thư mục. Không gọi 26 ảnh APK là kiểm thử toàn bộ luồng ứng dụng.
- Android: biên dịch; apktool đóng gói trên APK 1.0.3 để giữ nguyên phần khác; kiểm version/package/chữ ký; xác nhận assets, thư viện native và logo giữ nguyên; kiểm toàn bộ lớp app được tham chiếu đã đóng gói.
- Máy ảo Android 14: 13 trạng thái × 2 cấu hình màn hình/font. Thành phần empty-state được kiểm bằng instrumentation trong APK thật; các trang tài khoản dùng đối tượng người dùng mẫu trong bộ nhớ, không dùng database/tài khoản thật.
- Web: 7 màn × 6 chiều rộng = 42 trường hợp; kiểm tràn ngang/chữ tiêu đề, giới hạn ảnh, giữ lưới nhiều cột và căn giữa empty-state. Không thay thế việc duyệt ảnh mọi màn hình có dữ liệu thật.
- Updater: kiểm URL nguồn/redirect HTTPS, checksum sai/thiếu, giới hạn dung lượng, thứ tự phiên bản. Chưa nghiệm thu trọn luồng tải–cài trên điện thoại vật lý.

## Chạy và build trong phiên đám mây
1. `npm ci`; dùng Node >=22.13 (node:sqlite).
2. `npm test`. Có các E2E lịch sử dùng selector cũ và đường dẫn Windows; đừng kết luận toàn bộ suite đã pass.
3. Để audit responsive: `npx playwright install chromium`; `PLAYWRIGHT_CHANNEL=chromium node scripts/handoff-checks/web-layout-audit.mjs` (script hỗ trợ Chromium trên Linux). Script dùng database tạm trong bộ nhớ. Không chạy test vào dữ liệu thật.
4. Android Linux: `bash scripts/prepare-android-tools.sh`, `bash scripts/test-android-config.sh`, rồi `bash scripts/build-apk.sh`. Toolchain Linux và khóa ký phải được cung cấp đúng. Không tạo khóa ngẫu nhiên để thay APK đang dùng.
5. Windows đã dùng `python scripts/build-apk-windows.py`. Bản phát hành chính xác 1.0.4 được tạo bằng cách thay nhóm MainActivity trong baseline 1.0.3, giữ nguyên updater/tài nguyên. Script đóng gói đã dùng nằm ở `scripts/handoff-checks/package-layout-update-windows.py` (cần baseline APK 1.0.3 trong dist và biến `KINNECT_APKTOOL_JAR`; khóa ký được cấp riêng). Script đóng gói đã dùng nằm ở `scripts/handoff-checks/package-layout-update-windows.py` (cần baseline APK 1.0.3 trong dist và biến `KINNECT_APKTOOL_JAR`; khóa ký được cấp riêng). Script đóng gói đã dùng nằm ở `scripts/handoff-checks/package-layout-update-windows.py` (cần baseline APK 1.0.3 trong dist và biến `KINNECT_APKTOOL_JAR`; khóa ký được cấp riêng). Script đóng gói đã dùng nằm ở `scripts/handoff-checks/package-layout-update-windows.py` (cần baseline APK 1.0.3 trong dist và biến `KINNECT_APKTOOL_JAR`; khóa ký được cấp riêng). Không tự ghi đè APK release đã kiểm bằng APK build khác chỉ vì cùng versionName.
6. Site: `python3 website/build.py`; CSS/JS/ảnh trong website/dist là đầu vào cần giữ. Xem diff trước deploy để tránh làm mất iframe mobile hoặc mã cache-bust. Build đã bổ sung giữ iframe mobile và tự gắn hash cho native HTML/CSS/JS. Cloudflare project: `odd-disk-3093`.

Unit test mới nhất: 79 bài, 78 đạt, 1 lỗi ở private call signaling (HTTP 503 trong cấu hình kiểm thử). Xem `docs/cloud-handoff/unit-test-summary.txt`. Không coi toàn bộ suite đã đạt.

## Việc tiếp theo cần phiên đám mây làm
- Tiếp tục rà căn chữ bằng ảnh và dữ liệu dài, trạng thái trống/đầy, font lớn; đặc biệt các luồng có mạng, hồ sơ, tin nhắn, Live/video/camera chưa được kiểm hết trong đợt QA này.
- Kiểm thử cập nhật 1.0.3 → 1.0.4 trên Android vật lý: từ chối/cấp quyền nguồn cài, quay lại app, mất mạng, huỷ tải, checksum/chứng thư sai, xác nhận cài, dữ liệu giữ nguyên. Không coi cài trên emulator là nghiệm thu thiết bị thật.
- Thống nhất build Linux với bản phát hành và kiểm khóa ký CI trước khi tự động phát hành. Quy trình GitHub hiện bảo vệ APK đã upload thủ công khỏi bị build khác ghi đè.
- Tách/refactor CSS cũ có !important sau khi có baseline ảnh; không đổi toàn bộ layout/màu trong lúc xử lý lỗi căn chữ.

---
# Lịch sử bàn giao cũ (26/10/2026)

# Handoff cho ChatGPT — tiếp tục công việc Kinnect

> Người bàn giao: Claude Opus 4.7. Ngày: 2026-10-26. Commit điểm xuất phát: `84d6fbd`.
> Nhánh: `feature/social-core`.

## Bối cảnh
Dự án **Kinnect** là mạng xã hội Vietnamese (feed, reels, stories, live, messenger,
WebRTC call, nhóm, hồ sơ, admin). Server Node + ws, SQLite, Cloudflare tunnel. Phiên
làm việc trước đã làm:
- P0 hạ tầng: thống nhất cổng 3000, kill-before-start, gỡ xung đột autostart.
- P1 client: dedupe API GET (giảm `/api/notifications` ×5 → ×1), fix bell → openNotificationCenter popup, Service Worker không bị tiêm `?v=XXX`.
- Design system v2 mới: `public/tokens.css` + `public/polish.css` — tokens, header, button, toast, skeleton, card, call panel, live, chips.
- E2E stability: Playwright chromium installed, retries, timeouts, 10+ spec sửa.
- Unit test: 40/40 pass.
- Commit `84d6fbd` chứa tất cả. Còn LẠI trong working tree là công việc uncommitted của người dùng (từ trước phiên này).

## Việc còn lại (ưu tiên giảm dần)

### 1. [BLOCKER] `public/social.js` chưa commit — có hai lớp thay đổi chồng lên nhau
File này đang có:
- (a) Công việc uncommitted của người dùng từ TRƯỚC phiên: không rõ scope, diff ~1200 dòng.
- (b) Chỉnh sửa của Claude trong phiên: dedupe `api()` GET, `openNotificationCenter`, toast 2.5s, `meBtn` luôn mở popup.

**Yêu cầu**: Người dùng cần review file, tách commit riêng cho (a) rồi commit (b). Hoặc
chạy `git diff public/social.js` để xem toàn bộ và chốt. 4 thay đổi của (b) có thể tìm bằng grep:
- `inFlightGets`
- `openNotificationCenter`
- `noticeTimer = setTimeout(... 2500)`
- `meBtn.onclick = () =>` (bỏ nhánh desktop → navigate("account"))

### 2. [E2E] 30 test fail cần xử lý theo nhóm
Các test chưa pass trong lần chạy đầy đủ cuối cùng (xem `data/e2e-final.log` nếu còn,
hoặc chạy lại `npx playwright test`). Có 3 nhóm:

**Nhóm A — Test cần cập nhật theo UI mới** (an toàn, sửa test):
- `e2e/header-content-routing.spec.js`, `e2e/header-message-hub.spec.js`,
  `e2e/profile-settings-layout.spec.js` (biến thể 1280), `e2e/chat-files.spec.js`,
  `e2e/cross-screen-links.spec.js`, `e2e/following-videos.spec.js`,
  `e2e/live-swipe.spec.js`, `e2e/reel-fullscreen.spec.js`, `e2e/reels.spec.js`,
  `e2e/realtime-notifications.spec.js`.
- Pattern phổ biến: aria-label đã đổi (ví dụ "Tài khoản" → "Tài khoản của tôi"),
  back-button bị ẩn trên desktop ≥1000px nên `boundingBox()` null, badge `#friends-count`
  trả `●` thay vì `+1`, hoặc notification-center chuyển sang popup `#notification-center`
  khi click bell.
- Cách xử: chạy từng spec `--retries=0`, đọc Error, sửa selector/giá trị kỳ vọng.

**Nhóm B — WebRTC trong headless chromium**:
- `e2e/video-call.spec.js`, `e2e/message-actions.spec.js` (video call), `e2e/messaging.spec.js` (private video call).
- Vấn đề: `chromium_headless_shell` không chạy đủ WebRTC. Phải dùng Chromium đầy đủ:
  `npx playwright install chromium` (đã làm) + trong `playwright.config.js` set
  `channel: "chromium"` HOẶC chạy `headless: false`. Thử lại trên máy có GUI để xác nhận.

**Nhóm C — Phụ thuộc dữ liệu seed thực**:
- `e2e/social.spec.js` (một số test), `e2e/live-swipe.spec.js`.
- Cần dọn dữ liệu test hoặc inject fixture.

### 3. [POLISH UI] Sâu hơn (sau khi test ổn)
Đã làm nông: feed card / profile / call panel / live. Cần đánh bóng:
- **Màn hồ sơ (profile edit)**: viewport desktop, bố cục ảnh bìa + avatar + tab chưa gọn.
- **Studio quay video (`camera.js`)**: UI shutter / timeline chưa đồng bộ với design system mới.
- **Live stage**: badge/controls đã có polish, chat panel cần review ở mobile landscape.
- **Dark theme**: kiểm tra bóng + contrast ở `tokens.css` (đã có override) — đọ với Figma nếu có.

### 4. [FEATURE] Audit & bật
- **OAuth Google/Facebook**: code có, chưa cấu hình. Tạo `oauth.env` theo `oauth.env.example`.
  Khi có provider, UI tự hiện nút (`social.js:352-357`).
- **TURN**: `turn.env` dùng token HuggingFace mỏng manh. Chuyển sang Cloudflare Calls hoặc coturn tự dựng.
- **Nội dung video seed**: các reel có watermark TikTok/kenh14 (bản quyền). Người dùng
  bảo "để nguyên" trong phiên này, nhưng trước khi production cần thay.

### 5. [CODE] Refactor
- `public/social.js` 2.486 dòng — nên tách feed/messenger/profile/discover thành module riêng.
- `lib/social.js` 1.240 dòng — tương tự tách theo domain.
- CSS: `theme.css` 2.572 + `compact.css` 1.081 + nhiều file nhỏ — gom về tokens.

## Quy ước phiên này
- Commit messages: tiếng Việt + prefix `chore/fix/feat/style/test` theo semantic.
- End commit message:
  ```
  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
  ```
  (hoặc model đang dùng).
- Nhánh: `feature/social-core`. Chưa đẩy up (không `git push` trừ khi người dùng yêu cầu).

## Chạy dự án
```bash
# Khởi động chính (autostart Windows gọi file này):
wscript "scripts\windows-startup.vbs"   # cổng 3000, tunnel https://app.kinnect.io.vn

# Dừng:
stop-kinnect.cmd

# Test:
node --test                              # unit (40/40 nên pass)
npx playwright test                      # e2e full
npx playwright test e2e/<file>.spec.js --retries=0 --reporter=line   # debug 1 spec

# Dev:
set PORT=3000 && node server.js
```

## File giao
- Báo cáo rà soát ban đầu: `RA-SOAT-KINNECT-2026-10-26.md`
- Handoff này: `HANDOFF-CHO-CHATGPT.md`
- Commit điểm xuất phát: `git show 84d6fbd`


## Cập nhật 29/10: cửa hàng và căn giao diện
APK trực tiếp 1.0.10 (75); Play AAB 1.2.0 (102) dùng Billing 9.1.0. Đọc docs/google-play/MONETIZATION.md trước mở bán. Checkout chưa cấu hình; chưa kiểm thử giao dịch thật. Không tuyên bố đã phát hành Play. Sửa VI/EN, Live trống và nhãn xem trước.

## 2026-10-30 — Cloud database preparation / D1 provisioned
User chose D1 identity + PostgreSQL messages; no PostgreSQL service created yet. Cloudflare CLI authenticated; created kinnect-identity 4d72f5d1-b40e-4230-af4f-cbb7109e7464 APAC. Applied cloud-identity/migrations/0001_identity.sql remotely; verified 4 identity tables, zero accounts, foreign_key_check clean. No public Worker or API, no credential issuance, no production identity import or runtime cutover. Existing SQLite backend untouched. cloud-identity/README.md lists adapter/OAuth/recovery/session/profile/outbox and migration requirements. Existing soilfirm-db untouched.
Earlier prepared cloud-db.env.example + scripts/check-cloud-db-config.mjs (3 tests passed, productionReady always false), ignored cloud-db.env. This is not a working PostgreSQL adapter. Standby installer ZIP in dist is foundation only, no data/secrets/SFU/failover automation; never claim operational backup server.

## 2026-10-30 — Superseding decision: D1 chat, PostgreSQL identity/wallet
User reversed division: D1 private/group messages + delivered/seen; PostgreSQL accounts/profile/session/wallet. Created kinnect-chat ede253ed-ddc4-4a9e-a6d5-d6d3baa3f74e APAC, applied cloud-chat/migrations/0001_chat.sql. Four chat tables, no production data. cloud-chat/README.md is latest design and outstanding authorization/migration/receipt constraints. Old kinnect-identity remains empty/inactive, not deleted. No live backend changes or data cutover. Supabase project creation page configured Kinnect Free/Singapore, Data API off; password/project creation still user step, not confirmed created. Older docs referring to PostgreSQL messages/D1 accounts are superseded by this entry.

## 2026-10-30 — PostgreSQL TLS repaired, connection verified
User saved private cloud-db.env via Node hidden-password tool (PowerShell scripts blocked). Supabase fetzoqpdxoaxfqqrcfci Free/Nano Singapore healthy. Session pooler host aws-0-ap-southeast-1.pooler.supabase.com:5432, provisioning postgres user; no app-role yet. Downloaded provider CA from certificate link shown in authenticated Database Settings: https://supabase-downloads.s3-ap-southeast-1.amazonaws.com/prod/ssl/prod-ca-2021.crt to ignored data/certificates/supabase-prod-ca-2021.crt; validated CA flag/expiry; set KINNECT_DATABASE_CA_FILE in private env (no secrets printed). work/check-postgres.mjs using pg8.16.3 in work/pg-tools passes connected=true,tls=true,authorized=true with SELECT 1. Explicit ca + rejectUnauthorized:true; removes URL sslmode only inside client options to prevent pg overwriting explicit TLS configuration. No insecure TLS bypass. No production schema, data migration or runtime adapter/cutover yet. Keep future PG connector using this CA behavior; cloud config validator alone is not connectivity test.

## 2026-10-30 — PostgreSQL staging import verified
Consistent SQLite backup via node:sqlite backup() at data/backups/cloud-1793349180252/kinnect.sqlite; integrity_check ok. Actual snapshot has34 users,107 private messages,1 group message,2 groups,100 private receipts,2 group receipts. Wallet ledger and purchased packages zero in this source snapshot; do not invent balance validation on nonzero production funds. 18 selected identity/economy/store tables staged to private kinnect_migration schema in Supabase using scripts/stage-postgres-snapshot.mjs (pg in ignored work/pg-tools). Run76f8a1f5-b554-43f7-98de-34fceed71034 verified row counts and canonical payloads incl password hash/salt; source SHA efe8db8c3809a3195eaca9e65c1ef0b0b05cfebfbe79174f160cf64fcb75fab4. First run rolled back due nested JSONB key-order comparison, fixed canonical comparison then transaction committed. Report alongside snapshot. This is JSONB staging, NOT production relational schema or runtime. BLOB values replaced with hash/size local references; source bytes preserved, sessions excluded. Existing app SQLite unchanged; no D1 chat data import yet, no public worker. Need real schemas/adapters/migration tests/final freeze snapshot and cutover before app uses cloud.

## 2026-10-30 — D1 chat staging verified
Applied cloud-chat 0002_import_staging.sql. scripts/stage-d1-chat.mjs imported 228 source rows from same SQLite snapshot into chat_import_rows staging, run2d06d2cf-b345-4126-ab73-b66badc70505 verified by full payload+SHA readback, marked verified. Includes107 DM,1groupmessage,100DMreceipts,2groupreceipts,2groups,8members,4reactions and hide/recall metadata. Attachment BLOB hash/length reference only, actual bytes stay snapshot. 3 focused tests passed. Report data/backups/cloud-1793349180252/d1-chat-staging-report.json. This is NOT final chat_conversations/messages runtime import; app stays SQLite. No public Worker/access token granted. Existing DB current messages after snapshot not included. Need repositories/API auth/group privacy/receipt transitions/full end-to-end + final write freeze before cutover. Tool now invokes npx-cli.js directly without shell to remove DEP0190; do not rerun import merely to test script because creates new staging run.

## 2026-10-30 — D1 repository foundation (not wired)
Added lib/cloud-chat-repository.js for injected D1 binding: async list with bounded cursor, send with required nonce/conflict/idempotency and same-room reply, receipt seen=>delivered server timestamp and no sender ack. Required authorize callback must revalidate PG account/block/privacy; membership checked locally and again in INSERT. 4 behavioral tests (SQLite D1 facade) pass; combined cloud config/import tests 10pass. Not tested against D1 execution binding, not wired to social.js or exposed Worker. Existing chat runtime has many synchronous joins to users, notifications, AI and media; cannot simply swap db handle. Hidden/recalled/preferences/attachments/group lifecycle/projection migration and PG runtime not done. list currently raw internal storage rows and requires privacy decoration/filter before any user-facing API. Do not expose this repository directly or claim production cloud active. No production restart or cutover.

## 2026-10-30 — Latest approved topology: PC SFU/TURN/media, cloud app
User explicitly chose SFU/TURN back on PC, not Cloudflare Realtime. deploy/hybrid/topology.json + cloud.env.example + pc.env.example + README.md capture exact topology, readiness false. JSON check passed. Cloud API/auth/chat/wallet/notifications/signaling; PG account/wallet, D1 chat; PC files/SFU/TURN. No runtime/env/DNS restart/change. Existing TURN supports HuggingFace/static; PC coturn NOT installed, do not claim PC-only relay active. Need UDP routing/CGNAT checks; HTTP Tunnel not media transport. Pure P2P calls may work with PC offline; relay/SFU not. Media BLOB not yet split. No cloud compute host or budget chosen. Previous broad statements of PC-independent app describe target, not current production behavior.

## 2026-10-30 — PostgreSQL relational identity imported (not runtime cutover)
Added cloud-postgres/0001_core.sql and lib/postgres-identity.js + lib/cloud-postgres.js. kinnect_core.users34 + oauth_accounts6 imported from same consistent snapshot using scripts/import-postgres-identity.mjs; exact id/username/hash/salt/role/suspended compared. Remaining profile fields JSONB; media bytes local references. Sessions intentionally not migrated. Real PG SAVEPOINT synthetic user probe verified password success/wrong rejection, hashed token sessions, immediate suspended-user denial; probe rolled back before commit. Actual users/OAuth committed; report postgres-identity-report.json alongside snapshot. Import refuses nonempty target, do not rerun blindly. PG core RLS enabled, no public policy/API access; connection still provisioning postgres owner, dedicated runtime role pending. Identity helper is NOT wired into social.js/auth/recovery/OAuth/admin/deletion, no rate limiter/router/cookies yet. It must not be exposed as standalone endpoint. Do not claim cloud login active. app/SFU/TURN stay PC; cloud compute not provisioned. Wallet only JSONB staging so far, not relational runtime.

## 2026-10-30 — Allocator deployed, production routing NOT enabled
Latest user approved100cloud users, overflowPC, sharedPG/D1; user explicitly requested deploy. Created cloud-gateway Worker kinnect-allocation + SQLite Durable Object Allocator, deployed https://kinnect-allocation.vuanh97nd.workers.dev. Private GATEWAY_INTERNAL_SECRET provisioned via stdin, stored gateway.env user-only ACL/gitignored. Health public; all admission/status/heartbeat routes require internal secret. No raw secrets in APK/log. 90sec sticky per-user leases, cap100, PC heartbeat expires30sec, waiting if unavailable. D1/Postgres remain shared target; this allocator is not a data backend or reverse proxy. Tested actual DO101parallel requests=>100cloud,1waiting whenPCoffline, repeateduser sticky, otheruser cannot renew; releasedallsynthetic leases, final0. work/allocation-live-verification.json. Local overflowPC/offline/expiry tests passed. lib/hybrid-allocation-client.js future authenticated-server client not wired. productionRouting=false. Do NOT run heartbeat advertising current SQLite backend ready. Need fullPG/D1 backend integration, cross-backendevents, session multi-device lifecycle, signed/proxied routing, worker runtime port incl scrypt, PC media service/coturn and finalfreshsnapshot cutover. No app DNS/API changed or old service stopped. Multiple devices oneuser useoneslot; lifecycle aggregation pending. Updated deploy/hybrid configs/docs truthful false readiness.

## 2026-10-30 — PC healthy, PostgreSQL commerce tables ready
server-manager status now HTTP OK server10184 tunnel29420 SFU25696; left running. Added cloud-postgres/0002_commerce.sql: relational wallet_entries/store_packages/gift_inventory/economy_config/package_preferences all RLS on. Imported snapshot data and compared exact canonical contents; source has0 wallet/store/gift rows, economy1 preference1. RealPG savepoint synthetic ledger test checked gifted2000-490=1510,purchased1000-300=700,earnings750,adminunlimited; rolled all synthetic data back. lib/postgres-wallet.js read-only internal state repository not wired into live HTTP routes; safe-integer guard, suspendeduser denial; realpaymentsremainoff. import-postgres-commerce.mjs refuses nonempty table, not idempotent rerun. First comparison attempt rolledback on nestedJSON keyorder; canonicalized then passed/committed. Report data/backups/cloud-1793349180252/postgres-commerce-report.json. BackendAPI/Store/Admincoin/Gifts still useSQLite production, cloud admission not activated. Need full cloud backend (Workers port or provisioned host), privatePG runtime role, D1 runtime projection and events, same-sourcePCbackend before switching. Actual runtime remainsPC+SQLite despite stagedPG/D1.

## 2026-10-30 — Real Cloudflare API preview deployed, auth/wallet/chat verified
cloud-api/worker.js deployed kinnect-cloud-api.vuanh97nd.workers.dev; public health only, ALL actual routes require private X-Kinnect-Preview from cloud-api-server.env user-only ACL/gitignored. Do not reveal previewkey/DBpassword. npm pg8.16.3 cloud-api/package*.json. Dedicated PG kinnect_api role (no super/create/etc): SELECT coreusers/wallet/blocks/friendships and SELECT/INSERT/DELETE sessions with backend-only RLS policies; not grant all DB or use admin credentials inWorker. scripts/provision-cloud-api.mjs creates/reuses private secret file, DBrole, pushes secrets stdin. Current cloud login uses createPostgresIdentity native scrypt; liveCloud tests pass, no need changehash algorithm. Rawpg Workerorigin TLS terminated; resolved by Hyperdrive6898c16b24b942b5893159d301f0037e, originverify-full customCA5b448ad4-fb0a-4b8d-bac0-a2c4b964ae3a, cachingdisabled, originlimit5. DBuser/password connection only viaHyperdrive; Worker initially has PG_CONNECTION_STRING/PG_CA secrets as well, no longer used incode, may remove later. Real worker valid/wronglogin/session/readwallet/suspension tests pass; synthetic account/session removed. work/cloud-api-auth-verification.json. No rate limiter yet=>MUST keep preview gate closed, no appDNS route.
D1 migration0003_visibility added hidden/reactions/preferences/pins/attachmentrefs. scripts/project-d1-chat.mjs projected snapshot into actualruntime tables:108messages,17directconversations,2groups,102receipts,1hidden,4reactions,1attachmentref; full message body/sender/conversation compared, FKclean. d1-chat-runtime-report.json. Refusesnonempty rerun. Localblob remainsPC. Snapshotstale relative tocurrentlivePC, finalfreeze/delta migration required.
cloud-api/chat-routes.js preview-only /api/cloud/conversations/:id/messages GET/POST and /:messageId/receipt POST; D1 bindingCHAT_DB. PGcoreblocks0/friendships7 imported (0003_relations.sql) and readonlyappgrant. Checks activeaccount, groupmembership, directblock/suspendedpeer, recipient dm_mode/friends, hiddenmessagefilter, recalledredaction, blocked/suspendedsenderfilter. lib/cloud-chat-repository.js list now uses hidden table and recall redaction; testfixture loads0003schema. ActualCloudAPI synthetic chat test: send/read/seen/retry idempotency/outsider/block/hidden pass; allPG/D1fixtures cleaned. work/cloud-chat-live-verification.json. Not nativeexistingAPIresponse parity, no groupmanagement/realtime/events/reactionsAPI/preferencesAPI/attachmentdelivery, no registration/recovery/OAuthadmin/storewrites. Globalproductionroutingfalse. Existing app usesPCSQLite, notnewcloudAPI. Cloud-gatewayallocatornot yet wired tologin/session. No PCoverflowbackendsharedDB. Do not claim taskcomplete or turn routingon. Next: complete oldAPI parity+eventbus/privateD1transportforPC, session/allocator lifecycle and finaltests/cutover. Current user insists full implementation; do not keep presenting foundation as finished.

## 2026-10-30 — Superseding allocation: PC primary, cloud fallback100
Latest user explicitly reversed priority: prefer PC API while healthy; use cloud whenPCoff. Changed cloud-gateway/allocation.js to PCprimary then cloud<=100, overcapwaiting. Renew moves backend PC→cloud on heartbeatloss and cloud→PC on recovery; userleaseID stable.4localtests pass incl101PCfailover capped100; deployed allocator version5eb56411-01fe-40cb-824e-36143352662f, health policy pc-primary-cloud-fallback, productionRoutingfalse. Updated topology/docs. This supersedes older100cloud-first entries. No heartbeat/actualappcutover enabled because legacyPCSQLite and newcloudPG/D1 still different authorities. Inflight writes MUST NOT auto replay on backendchange, same nonce/resultlookup; nativeWebSocket lifecycle/reconnect integration pending. Live/media/SFU/TURN remainPC. Cloudpreviewauth/chat currently works as priorentry but notfullnativeAPI parity. Do not claim automaticlivefailover active yet.

## 2026-10-30 — Realtime/shared PC API and actual preview failover verified; latest PC-first auth
User asks complete end-to-end. Added cloud-api/realtime.js UserEvents hibernating DO (binding/migration v1) with per-user opaque chat:changed notifications, checks activePGsession/suspended onnotify, sessionhash attachments (notrawtoken), expiry alarms, closes sockets onlogout. cloud-api /api/cloud/events authenticated WebSocket, DO receives forwardedoriginalUpgradeRequest; initial POSTupgrade500/426 fixed by forwardingoriginalRequest+trustedmetadataheaders. work/test-cloud-realtime.mjs passes real WebSocket event + logoutclose with syntheticfixturescleaned. Receipt path currently no explicit realtime sender notification (pending).
Added D1 RPC backend bridge: cloud-api/d1-queries.js 11fixed normalized SQL allowlist, lib/d1-backend-transport.js queryID hashes; /internal/d1-query accepts only fixedhash/mode/params and privatepreviewkey, no arbitrarySQL. /internal/events fixednotify/revoke actions; allinternal calls remainbehindkey. Samepreviewkey gates integrationAPI; MUST NEVER put this key into APK/browser because it also authorizes privilegedbackendRPC. Publicproductionauth/rate-limit separation pending.
PC shared preview scripts/pc-shared-api.mjs runs Node on127.0.0.1:3001, samecloud-api workerhandler+dedicatedPGrole directTLS, fixedD1RPC, cloudUserEvents bridge. scripts/start-pc-shared-api.mjs starts detachedhidden, PIDdata/pc-shared-api.pid, logdata/pc-shared-api.log. Existing production server3000/SFU/tunnel untouched. work/test-cross-backend.mjs passes PCsend→D1→cloudread+realtime. PCWebSocket upgrades notimplemented; sharedcloudsocketused.
Isolated quicktunnel created using existing cloudflared exe from managerstate, separatePIDdata/pc-shared-quick-tunnel.pid/log. IMPORTANT cloudflared defaultconfig initiallycaused404; explicit data/pc-shared-quick.yml fixes. QuickURL MUST select LAST regexmatch in appendedlog. Current women-volt-tomorrow-relationships.trycloudflare.com (ephemeral, notproductionstable). work/start-pc-preview-tunnel.mjs helper (ignored). Existing tunnel neverstopped.
cloud-gateway/preview-router.js private /preview/api/* routes PCfirst if previewPChealthready, cloudfallbackvia servicebindingCLOUD_API (publicWorker-toWorkerfetch returned404 so servicebindingrequired). Updates allocator PCreadiness. Allrequests requireprivatepreviewkey. GatewayWorkers fetch does NOT accept redirect:error (TypeErrorredirect); changed to manual andexplicit3xx rejection. OtherNodefetchredirect:error remainsfine. Noautomaticretry ofmutatingrequests onuncertainfailure. /preview/api/preview-connectivity private diagnosticexists.
Gateway secrets updated via work/configure-preview-gateway.mjs: PREVIEW_KEY,PC_ORIGIN,CLOUD_ORIGIN,GATEWAY_INTERNAL_SECRET via stdin only. No secretsprinted. Latest gatewayversions captured CLI; productionRoutingfalse.
work/test-hybrid-failover.mjs performs actual stopONLY sharedPCpreviewPID (verifies CIMexepath/command), calls gateway samecookie oncloud, cloudwrites/idempotentretry, restartsharedPC andreads sameD1; PASS. Also freshloginPCoff PASS. AllsyntheticPG/D1fixtures and allocatorleases cleaned; sharedPC restarted. work/hybrid-failover-verification.json. Does not stop3000/mainSFU.
Latest user PRIORITY supersedes brief always-cloud-auth request: PCprimary for ALL API includinglogin, cloudonlyfallback. Removed authalwayscloud earlybranch frompreview-router, topology authentication pc-primary-cloud-fallback-postgres. test/preview-auth-routing.test.js updated mocks bothPChealthy/offline, identity/logout andorigin/previewgate,6allocation+auth tests passed. Deployed gateway eb8d7406-b518-4c3e-a832-fdb4715c5805 then reran actualfailover (check session82395 result ifstillrunning). PostgreSQL data remainscloud; PCdirectconnections bypassHyperdrivequota, notSupabasecapacity. D1 reads/writes stillquota fromPC. Workersgateway itself stillcloudquota, no unlimitedescape. Cloudlimit100 only admission, notfreequotaguarantee. Quota config request should not create separateSQLitefallbacksilentdivergence.
STILL NOT fullproduction: legacyapp endpoints301? actual3000 staySQLite, snapshotsstale, APIpreview onlylogin/me/walletread/logout/customchat send/list/receipt+events. MissingnativeexistingAPIparity, registration/recovery/OAuth/admin/storewrites/groups/preferences/reactionsAPI, durablePCtunnelconfig, publicrate-limits/separatebackendRPCsecret, eventlifecycleadmissioncapforquietWebSockets, media/coturn, currentdatareconcile/cutover/APKverification. Do not claim allfinished or enableappDNS. Need continue work but user latest turn onlyreprioritized PC/cloud. No newAPK orproductionDNSchanged.

## 2026-10-30 — Registration/store port and latest adaptive-fastest routing
User explicitly says finish without asking, and MOST RECENT asks prioritize whichever backend responds faster, shared accounts/messages PC/cloud. Supersedes PCfirst / briefalways-cloud auth. cloud-gateway/latency-policy.js now parallel read-only synthetic sessionlookup PC/cloud, caches60sec perenv/isolate, switches only>25ms margin, no write replay. allocator accepts trusted input.preferred cloud but cap100 thenPCoverflow; defaultPCstill ifnopreference. preview-router passes measuredchoice, handlesPCdown; cloud5xx read-onlyGET mayfallbackPC, mutatingrequestsneverreplayed, marksclouddegraded30sec. /health policyfastest-healthy-backend, productionfalse.8routingtests passed, deployedgateway5b4ccebd-32e8-4e60-993d-83f4a60763ce. topologyupdated. No mainappDNSchange.
cloud-postgres/0004_runtime.sql applied newprivacy/storeprefs/adminpackageevents/storepurchases/notifications/follows/economyaudit. importedsource tables counts6/1/0/0/145/13/0. Dedicated backendrole now CRUDall kinnect_coretables+sequences with backend-onlyRLS policies; DataAPIoff/noanon grants; role is trustedservercredentialonly. New registration.js atomicuser+one signupbonus+privacy+session; cloudWorkerhandles /api/register and returns profile.js sanitizednativefields. AuthLimitsDO persistent20/min hashedclientIP sharedviaPCinternalRPC; cloudgatewayforwards trustedCFIP. Actual concurrentcloudregistrationtestPASS one200one409, bonusonce, sessionvalid,nopasswordinresponse, syntheticcleaned; work/cloud-registration-verification.json. Registrationalreadydeployedprivatepreview; publicproductionstillclosed.
commerce-routes.js implemented /api/store GET, /api/economy, /api/store/packages/buy, /style,/packages/apply. Reuses approvedSTORE_PACKAGES/PRODUCTS. Fulladminvirtualentitlements/unlimited, optionalauditpurchase0debit; nonadminuserrowlock, atomicledger+grant/inventory, nonceidempotency/conflict/demotionoldadminnonce409. Realbillingverify/topupstilldisabled503. Defaults mergedDEFAULT_ECONOMY to handle oldconfig missingtrialPackagePurchases (firstprobe403 found/fixed). RealCloudcommerceprobePASS catalog15, concurrentretry1debit1700remaining, nonceconflict, applystyle, adminfullaccess&0debit, fixturescleaned; work/cloud-commerce-verification.json. Fixed accountId to existing storeAccountId (kinnect-store-v1), latestpatchnotyetredeployedafter ee9d349f unless subsequentdeploydone. PC shared preview restarted after thesechanges by verifiedPID; currentPIDfileauthoritative. New postgres-wallet helper response stillminimalvslegacy wallet fields, pendingfullparity.
MainappstillPCSQLite. Missingconversations/groups nativecompat, admin/profile/recovery/OAuth/notificationsroutes, publicsecurityseparation, stabletunnel, media/coturn/finalmigration/cutover. Do not claim fullfinished. User wantsnoquestionsuntilOK; keepimplementing, reportonlytruthfulmilestones. New tests8routing + earlier cloud16 foundation; rerun broader onlychangesjustify. Old hybridfailovertest assertsPCprimary and mustadapt tofastestpolicy; sameData/PCoffcloudsuccess remainsvalidhistoricalevidence, not proofcurrentfullapp.


## 2026-10-30 — Fastest routing and shared native chat verified
Latest user confirms fastest healthy backend, same accounts/messages PC/cloud. Kept shared PostgreSQL identity/session/wallet and D1 DM/group/receipts (single authorities, no divergent local DB replicas). Gateway deployed 1da9bc09-1c39-4462-9d0c-01811fe47e8f; added PC authentication preflight failure fallback after healthy healthcheck, respects cloud admission. 19 focused tests passed including new regression. Real hybrid stop/restart test adapted fastest assertions; PASS login while PC off, same session/history, nonce no duplicate, cloud writes and recovery; work/hybrid-failover-verification.json updated.
Native compatibility chat/group + notifications deployed; work/test-native-shared.mjs actual PC DM send/cloud read, nonce same ID, exactly one notification, cloud seen visible PC, conversations, PC group create/cloud member read and outsider denial PASS. Notifications now persisted PG with deterministic IDs; D1 read receipts shared. Optimized reveal all via one SQL to avoid group-member-count query limit. Receipt upsert only changes previously-unseen and notifies other members only to avoid realtime reload loops. Fixed D1 allowlist now33queries, generated from native/notification sources too. Latest cloud deploy25a64235-2229-447f-aeff-ff072c1131fd. Shared preview restarted verified PID only (PIDfile authority), never main3000.
README policy updated fastest. Still PRIVATE PREVIEW, productionRouting=false; old app/server3000 still SQLite, main data snapshot stale. Do not claim app migrated. Remaining: full native API parity incl group actions/message actions, complete wallet/profile/admin/recovery/OAuth, separate public auth vs backendRPCsecret, stable PCtunnel/media, SFU/TURN and final data reconciliation/fencing/APK cutover. PC still requires cloud connection for canonical PG/D1; quota not bypassed by PC. No new APK/mainDNS changed.


## 2026-10-30 — New dedicated chat PostgreSQL initialized
User approved moving chat from D1 to separate Supabase project Kinnect Chat mmxqhcngrejxyhhfirzo, org zxxtriznogksjgonbtwo, Singapore, DataAPIoff. User entered password privately through Cau-hinh-PostgreSQL-Chat.cmd. chat-db.env is gitignored, user-only ACL; never print. Set-ChatDatabase.ps1 no longer depends Set-Acl module: .NET ACL tested PS5.1 and7.6, handles empty failed file but refuses nonemptyconfig. Sessionpooler observed UI aws-0-ap-southeast-1.pooler.supabase.com:5432, userpostgres.mmxqhcngrejxyhhfirzo. initialize-chat-postgres.mjs initially failed tls-check because pg_stat_ssl is pooler->backend, NOT PC->pooler; corrected to actual TLSSocket encrypted+authorized, CAverification still rejectUnauthorized:true. SUCCESS actualconnection/schema/9chattablesRLS enabled; schema_migrations checksummed, no productionrouting/data migration. data/reports/chat-postgres-setup.json. Schema cloud-chat-postgres/migrations/0001_chat.sql fromD1 normalizedBIGINTtimestamps. Need build PGchat adapter/routes, import/checkdata, dedicatedbackendrestrictedrole+Hyperdrivechatbinding, PC readreplica and public/directnativefailover, finalproductioncutover. OldappstillSQLite and previewchatD1; do not falselyclaimchatmigrated.


## 2026-10-30 — PostgreSQL chat private preview migrated and verified
User says automatic until success/no questions. New lib/postgres-chat-adapter.js compiles ONLY fixed33 allowlisted SQLitechatqueries to PG parameterized/schemaqualified SQL (JSON/functions), normalizes bigints and JSONoutput; transactional batch. Real PREPARE33/33 and nativeDM/group/notification/seen tests PASS. Added2 adaptertests plus existingfocused15totalPASS. WorkeroptionalCHAT_HYPERDRIVE/PCCHAT_POSTGRES_OPTIONS opens separatechat connection afterauth and closesfinally; same native routes retained. Dedicatedkinnect_chat_api role provisioned via scripts/provision-chat-api.mjs, credentials chat-api-server.env gitignored user-onlyACL (neverprint), CRUD9chattables+backendRLS only; no provisioningcredential inruntime. Hyperdrivechat1fc742f412c74f9cb02885907aff29e1 verify-full existingproviderCA5b448ad4-fb0a-4b8d-bac0-a2c4b964ae3a cachingdisabled origin5. cloud-api/wrangler.jsonc CHAT_HYPERDRIVE binding; deployed e8e92f56-22de-4781-a6ba-0a0e888fe033. cloud-api/package.json type:module avoidsNodewarnings.
Imported D1preview toPG using scripts/import-d1-chat-postgres.mjs all9tables transaction, refuse nonempty, hashcontentcompare.19conversations42members108messages102receipts plushidden/reaction/files. Initialrollback atinsertattachment fixed source_sha256 columnvalidationdigits. data/reports/chat-postgres-import.json. Does NOT include newer mainSQLitechanges; no productioncutover. D1retained untouched as oldcopy; liveprivatepreviewread/write nowPG. PCsharedscript autoopts ifchat-api-server.envexists, restartPIDfileauthoritative. Work/test-pg-cross-backend.mjs realcloud/PC sharednative DMnonce/notifications/seen/groups outsiderdenial PASS; cleansPGchat+identityfixtures. Work/test-pg-hybrid-failover.mjs actualstopONLYsharedPCpreview+cloudfreshlogin/samecookie/messages/retry/recovery PASS, PGfixturescleaned. Gatewaymayselectcloudwhenquicktunnelunavailable; doesn'tprove stablePCpublicpath.
Private PC backup via scripts/backup-chat-postgres.mjs repeatableread snapshot of9tables, gzipverify, newfileACLbeforecontents. SUCCESS data/reports/chat-postgres-backup.json; ONLY snapshot, NOT ongoingreplication/offlineAPI. Test-onlyloopback3002server work/pg-chat-test-api.mjs temporary; stopwhenunusedwithoutmain3000. No APK/mainDNS/productionrouting changed. Remainingmajor: sourcecurrentdatareconcile/fence, fullAPIparity/publicsecurity+directnativefailover stabletunnel, ongoingPCreplica/offlineauthpolicy, media/SFU/TURN setup. Nevercallallfinished.


## 2026-10-30 — Windows media sync manager 0.1.0 packaged
User requests Windows software with bundled Node, incremental peer-to-peer photo/video sync, choose drive/folder, noNAS/GoogleDrive. Added services/windows-server/{store.mjs,sync.mjs,server.mjs,index.html,Start.ps1,Install.ps1,choose-folder.ps1,Cai-dat.cmd,Kinnect-Server.cmd,README.txt}. Source noAGENTSfound. App admin loopback3128 Host/Origin+adminheader authenticated, browserlaunchfragment scrubbed/sessionStorage; settings user-onlyACL beforesecretwrite. Sync3129 opt-in bindsallinterfaces, bearerpernode privilegedreadwholemedia vault (inclprivate), notenduserAPI. HTTP onlyliteralRFC1918/loopback; otherpeersHTTPS, rejectsredirects. Noautomaticfirewall/router/Tunnelconfig. Peerpair pulls identityauthenticated andrequiresbothdirections ifbothwrite. Persist root/source/peers/enabled. LocalLocalAppDataKinnectServer settings; installerappLocalAppDataKinnectServerApp Desktopshortcut, bundledNode24.22.1 signedOpenJSFoundation valid, exactLICENSEdownloadedofficialnodeGitHubtag, noNoderequiredoutside.
Store: SQLiteWAL catalog, immutableSHA256 objectfiles, pernodeLamportrevision+origin conflictordering, appendjournal+perpeercursor persisted, range.partresume SHA256validated beforeapply/cursor, tombstones retained notphysicaldelete. Rejectpathtraversaldigest; has verifiesstoredhash bounded1MBbuffers. Nojournal/objectGCyet. Source exporter read-onlysnapshotSQLite post_media/shorts/privatephotos/chatattachments/usersavatarcover, ownsourcepreviouskeyset fordeletions; neverresurrecttombstone automatically. ReadsBLOBhashesagain each30secscan (CPU/heavy largevaults); networkonlynewmissing. Ignoresfuturegroupavatar etc notmapped. DoesNOTserveproductionappmedia norAPI/Live/SFU/TURN. Needfollowupintegration/enduserpermissionchecks andstablecrossnetworkrouting before claimstandalonefullKinnectserver.
Tests test/media-sync.test.js coversresume70KB/200KB, deltasnocopy, restartcursor, tombstonewrongauth/path, misleadingHTTPdomains; test/media-manager.test.js twoREALnodeprocesses choosefolders/importsyntheticSQLite/pair/network/sync/restartpersistence/auth/blockrootchangewhileactive.3testsPASS. PSparserInstall/Start/pickerPASS. UIcheckedCUA localtesthome work/media-manager-ui choosework/media-manager-test-storage; screenshot outputs/Kinnect-Server-giao-dien.png, visuallyverified nooverlap. TestUIserver PIDfile inthatworkhome, node toolsession45673 (notmain3000).
Artifact outputs/Kinnect-Server-Windows-0.1.0.zip 34.5MB, ZIPCRCtested, whitelistverified13files+SHA256.json excludesALLcredentials/dbdata; sibling.sha256. ExtractthenCai-dat.cmd. Portablefolderoutputs/Kinnect-Server-Windows-0.1.0. Notinstalledinuserprofile byagent. NoactualPC-B/Internettest. MainKinnectproductionunchanged.


## Windows EXE installer 0.1.1
User asks EXE. Added C#WinForms sources services/windows-server/exe/{Launcher.cs,Setup.cs,kinnect.ico} (iconconvertedapprovedpubliclogo). Built via WindowsPowerShell5 Add-Type CodeDom v4 /target:winexe /platform:x64, work/build-server-exe.ps1 and work/build-server-setup.ps1; noSDKinstalled, compilerworks. EXElauncher runsStart.ps1 hidden. Setup embeds ZIPwithbundledNode, extracts under LocalAppDataKinnectServerApp/0.1.1-uniqueGUID, Desktop.lnk points directlyKinnectServer.exe viaCOM, user clicksCaiDatthenMo. Noautomaticinstallperformed. outputs/Kinnect-Server-Setup-0.1.1.exe ~34.5MB+siblingSHA256, portableoutputs/Kinnect-Server-Windows-0.1.1. Setup --verify-payload extracts uniqueTEMP and actuallyexecutesbundlednodeversion passed0; launcher--self-test passed0. UIopenedCUA visuallyinspected nooverlap thenclosed. RecompiledwithKicon afterwards, samecontrols. NoAuthenticodesignatureforcustomEXEs; NodebinarysignedOpenJSalreadyverified. InstallerWindowsNETFramework4 existingWindows11, x64only. Still media-manageronly asdocumented, NOTfullproductionserverAPI/Liveintegration.


## User correction: REAL Windows desktop, not browser UI (0.2.0)
User rejected browserGUI despite EXEinstaller. Built actualWinFormsdesktop services/windows-server/exe/Desktop.cs, noWebView/browser. NativeComboDriveInfo list, FolderBrowserDialog, OpenFileDialog, statuses, peers, maskedkeys and nativepairingdialog. BackgroundWorkerloopbackAPIrequests only; bundledNodeheadless spawned directly (noPS/CMD/browser). SourceNode GET/ nowreturnsJSONhealth, noHTMLGUIserved. C#desktopautostartsengine, 4secstatus, closesUIleavesenabledsyncbackground. Smoke--smoke-testisolatedworkhome39628 startsNode/API/loadsstate/exitschild0. Initialsmokefailedunhandledmissingmediawhenstoreunset; fixedContainsKeymedia, retestPASS. RealWinFormsUIinspectedCUA; firstsourcepanelclippedbuttons fixedremoveextraLabel, screenshotoutputs/Kinnect-Server-Desktop-0.2.0.png showsallcontrols/noapplicationoverlap (unrelatedZalotooltipatbottom). Desktopwindowcurrentlyopen ownuserLocalAppDataKinnectServer defaultrootnull/networkfalse, backend3128 startedbytestUI, production3000untouched.
Artifactoutputs/Kinnect-Server-Setup-0.2.0.exe (~35MB)+SHA, portableoutputs/Kinnect-Server-Windows-0.2.0 contains ONLYnativeexe/server/store/sync/runtime/README/manifest, noHTML/Start.ps1/CMD. Setup.csupdatedpayloadrootversion0.2.0, nativeEXEshortcut. Buildwork/build-native-server.ps1, work/build-desktop-setup.ps1; embeddedpayloadwork/exe-payload/payload.zip regenerated. Actualpayloadextract+runtimeverify0. Core3testsPASSafterNodehealthchange. No actualinstallDesktopshortcuttested, nosecondphysicalPCtest, remainsmedia-onlynotproductionAPI/Live. Old0.1.xbrowserpackages obsolete.
