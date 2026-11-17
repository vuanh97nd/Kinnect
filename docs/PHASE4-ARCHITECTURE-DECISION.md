# Phase 4 Architecture Decision Record: Multi-Platform Strategy (Kinnect)

> **Status:** Ratified Decision (`Do not migrate` — Keep Native iOS SwiftUI + Native Android Java + Web v2 in parallel, confirmed 2026-11-17)  
> **Assessment Skill:** `.agents/skills/assess-react-native-migration/SKILL.md` (read-only decision gate; no Expo/React Native implementation or PoC scaffolded)  
> **Related Audits:** `docs/IOS-ANDROID-PARITY-REPORT-2026-11-11.md`, `docs/MOBILE-QA-PARITY-20261112.md`

---

## 1. Recommendation

- **Decision:** **Do not migrate (`Do not migrate` — Path A: Maintain Native SwiftUI + Java Android + Web v2 in parallel on unified Backend & Design System contracts).**
- **Confidence:** **Medium-High** (technical evidence from both client codebases strongly favors staying Native; confidence is bounded to Medium-High solely because organizational metrics `[unknown]` — team staffing per stack and historical cross-platform feature lead time — have not been supplied).
- **Why now is not a good moment for React Native / Expo Brownfield:**
  1. **Heavy native product surface `[observed]`:** Kinnect's core differentiation relies on Camera/Media Studio (`AVFoundation`, `CoreImage`, `Vision`), Live WebRTC (`WebRTC 125.0.0` / `webrtc/classes.jar`), Game Live (`MediaProjection` + `AudioPlaybackCaptureConfiguration`, `TYPE_APPLICATION_OVERLAY`), VoIP calling (`PushKit` + `CallKit`, `MANAGE_OWN_CALLS` + `showWhenLocked`), and store billing (`StoreKit 2`, `Play Billing 9.1.0`). Every one of these boundaries must stay native even under a Brownfield architecture.
  2. **Android toolchain & package policy barrier `[observed]`:** Android compiles purely with `ecj.jar` + `android-35-ext15/android.jar` + `d8` (`scripts/build-apk.sh`) with **zero AndroidX**, **zero Kotlin UI**, and **zero Gradle/NDK**, while `scripts/test-native-design.py` (`test_application_has_no_web_container`) explicitly rejects APKs containing `.html`/`.js` assets or `WebView`. Introducing React Native/Expo requires replacing this minimal APK toolchain with Gradle/AGP + AndroidX + Hermes/Fabric native `.so` runtimes (`[assumed]` +12–20 MB APK footprint).
  3. **Historical parity gap largely closed natively `[observed]`:** Major Nov 11 gaps (`docs/IOS-ANDROID-PARITY-REPORT-2026-11-11.md`) such as iOS Admin Operations UI, Game Live mode, and StoreKit 2 are already present in `Kinnect-ios-qa` (`AdminOperationsView`, `CreateLiveRoomSheet(mode: "game")`, `StoreKitManager.swift`). Closing the small remaining native deltas is cheaper than maintaining **3 mobile UI stacks** (`SwiftUI` + `Java` + `React Native`) concurrently.

---

## 2. Evidence

### 2.1. Platform & Worktree Inventory

| Surface | Repo / Branch / Version Tag | Measured Code & Bundle Scale | Core Toolchain & Dependencies |
| :--- | :--- | :--- | :--- |
| **Backend & Web v2** `[observed]` `[measured]` | `Kinnect` (`ad1bc12`, `fix/kinnect-city-nhom-a`), `kinnect-live@0.3.1` | `public/v2.js` `297,080` B + `v2-auth-wall.js` `368,975` B + `v2-admin.js` `7,596` B + `v2-commerce.js` `5,362` B + `v2-icons.js` `39,181` B | Node ESM (`type: "module"`), `@apple/app-store-server-library: 3.1.0`, `ws: 8.22.0`, dev `@playwright/test: 1.56.1`, Postgres/Supabase + SQLite |
| **Android Native** `[observed]` `[measured]` | `Kinnect/android/app/src` (`versionCode="127"`, `versionName="1.2.15"`); QA worktree `kinnect-android-qa` at `3c9d089` (`versionCode 125`, `1.2.13`) | `90` `.java` files (`+ play/` flavor); `17,919` LOC measured pre-Phase 3C helpers; largest files: `MainActivity.java` (`7,001` L), `StudioActivity.java` (`1,808` L), `MediaEditActivity.java` (`1,055` L), `LiveActivity.java` (`662` L), `FarmGameDownloadActivity.java` (`218` L), `IncomingCallActivity.java` (`215` L), `MediaImageLoader.java` (`184` L), `WindowedListBinder.java` (`82` L) | `ecj.jar` + `android-35-ext15` + `d8` (`scripts/build-apk.sh`); `play-release/build.gradle`: `OkHttp 4.12.0`, `billing:9.1.0`, `webrtc/classes.jar`; **0 AndroidX, 0 Kotlin UI** |
| **iOS Native** `[observed]` `[measured]` | `Kinnect-ios-qa/ios/Kinnect` (`aff26bb`, `codex/ios-qa-20261113`; `MARKETING_VERSION: "1.2.12"`, `CURRENT_PROJECT_VERSION: "124"`; also `Kinnect-iphone` at `8c35a8d`) | `67` `.swift` files, `35,843` LOC total; `IPHONEOS_DEPLOYMENT_TARGET: "16.0"`, `TARGETED_DEVICE_FAMILY: "1,2"` | `SwiftUI` (45), `UIKit` (36), `AVFoundation` (22), `PhotosUI` (14), `AVKit` (12), `CoreImage` (7), `UserNotifications` (5), `ImageIO` (3), `CryptoKit` (3), `WebRTC` `125.0.0` (3), `AuthenticationServices` (2), `CoreLocation` (2), `StoreKit`, `PushKit`, `CallKit`, `Vision`, `Security` |

### 2.2. Eight-Dimension Architecture Matrix

1. **Product `[observed]`:** Rich media social app (Feed, Shorts, Discover, Direct/Group Chat, Live Stream + Host + Gift, VoIP Calls, Camera Studio, Wallet/Store, Admin Operations; Farm API & manifest entry were retired `2026-11-13` while legacy `FarmGameDownloadActivity.java` source file remains unreferenced on disk). Remaining gaps (`LiveGiftExperience` SoundPool, iOS group deputy UI, APNs backend sender) are bounded feature modules, not a CRUD parity crisis.
2. **Native surface `[observed]`:** Extensive direct OS API usage on both platforms (`ImageIO` + `AccountCache` 64 MB disk cap + `StoreKit 2` + `PushKit`/`CallKit` + `KeychainStore` on iOS; `MediaProjection`/`AudioPlaybackCaptureConfiguration` + `TYPE_APPLICATION_OVERLAY` + `MANAGE_OWN_CALLS` + `PlayStoreBilling` + `MediaImageLoader`/`WindowedListBinder` on Android).
3. **Continuity `[observed]`:** Isolated native session stores (`KeychainStore.swift`/`AppState.swift` on iOS; `SessionStore.java`/`MainActivity.clearClientSessionCaches()` on Android) plus HTTP `428` consent handling. Brownfield would introduce dual-sided token bridging and coordinated logout cache eviction across native and JS storage.
4. **Verification `[observed]` `[measured]`:** Strong native checks exist today: `229/229` Node tests passing across `test/*.test.js` in `Kinnect` (including fail-closed `lib/admin-console.js` authority checks, `call-config.test.js` STUN fallback, and `farm.test.js` retirement guards), `ecj.jar` compile (88 `.java` files) + `MediaImageLoaderTest`, `scripts/test-native-vector-parser.py` (`paths=616 failures=0`), `scripts/test-native-design.py` (`5/6` pass; `1` pre-existing `public/v2.css` SHA256 drift vs `android/design/web-reference.json`), `31/31` Node tests in `Kinnect-ios-qa`, `ios-release.yml` (`44029914951`, ~4m22s `success`), `ios-qa-simulator.yml` (`44029914985`, ~37m53s `success`, `31/31` runtime evidence + `30/30` Swift harness).
5. **Release `[observed]`:** Independent store release trains (`iOS 1.2.12 (124)` vs `Android QA 1.2.13 (125)` / `Android main 1.2.15 (127)`). Native changes to billing, calling, or WebRTC still require App Store / Play Store reviews; JS OTA introduces bundle-vs-native skew risk.
6. **Ownership `[observed]` / `[unknown]`:** Multiple active branches/worktrees exist (`[observed]`), while exact engineer counts across Swift/Java/TypeScript remain `[unknown]`.
7. **Agent governance `[observed]`:** `.agents/skills/` is installed (Expo, Callstack RN, Vercel, Supabase/Postgres) alongside single-source `design/tokens.json` contract tests. Scaling governance artifacts (`MIGRATION.md`, `SCREENS.tsv`, `STATE_AND_STORAGE.tsv`, `DEPENDENCIES.tsv`, `EVENTS.tsv`, `PARITY_CHECKS.md`) are intentionally absent at assessment time (`assess-react-native-migration/SKILL.md`).
8. **Delivery baseline `[measured]` / `[unknown]`:** Architecture quality upgrades from Phases 1–3 are measured (`-56%` `v2.js`, 16 iOS modular view files, DB indexes, `MediaImageLoader` + `WindowedListBinder`). Organizational metrics (release frequency, change lead time, cross-platform feature lead time, escaped parity defect rate, production FPS/RAM) remain `[unknown]`.

---

## 3. Assumptions and Blockers

Ranked `[unknown]` items capable of reversing this recommendation if organizational evidence contradicts technical evidence:
1. **[Highest impact] Team skill composition & staffing `[unknown]`** — ratio of sustained Swift vs Java/Kotlin vs React/TS capacity.
2. **[High impact] Cross-platform feature lead time & escaped parity bug rate `[unknown]`** — measured engineering hours duplicated on CRUD UI vs real user bugs from dual implementations.
3. **[Medium impact] 6–12 month roadmap mix `[unknown]`** — share of pure UI/commerce/CRUD screens vs native real-time camera/live/game/billing work.
4. **[Medium impact] Android APK ceiling & build-pipeline appetite `[observed]` + `[unknown]`** — maximum acceptable APK growth on target devices and willingness to replace `ecj.jar + d8` with AGP + AndroidX + NDK.
5. **[Low-Medium impact] OTA UI iteration requirements `[unknown]`** — whether store review cadence actually blocks non-native UI iteration.

---

## 4. Checkpoint (Bounded Brownfield Trial — ONLY if Path B is Explicitly Approved)

Do **not** select `expo-brownfield` vs bare React Native unless Path B is approved (`assess-react-native-migration/SKILL.md`). If stakeholders override `Do not migrate`, constrain trial scope to **3 representative flows** across **2 passes** (`faithful` parity -> `idiomatic` refactor):
1. **Data / List / Theme flow:** Feed/Discover list slice (`/api/posts`, loading/empty/error/content states, HTTP `428` consent, `design/tokens.json` styling) benchmarked against `ImageIO` (iOS) and `MediaImageLoader` + `WindowedListBinder` (Android).
2. **Auth / Session Continuity flow:** Secure token bridge (`KeychainStore.swift` / `SessionStore.java`) and coordinated multi-layer cache eviction on logout (`AccountCache`, `ImageMemoryCache`, `AppCache`, `MediaImageLoader`, JS storage).
3. **High-Risk Native Boundary flow:** Hosting the surface inside native navigation without regressing `PushKit`/`CallKit`, `IncomingCallActivity`, `StoreKitManager`/`PlayStoreBilling`, or `LiveActivity`/`LiveRoomHostAndGiftViews` (`WebRTC` + `MediaProjection`).

**Required Missing Artifacts Before Any Scaling Beyond Checkpoint:**
Assign owners for `MIGRATION.md`, `SCREENS.tsv`, `STATE_AND_STORAGE.tsv`, `DEPENDENCIES.tsv`, `EVENTS.tsv`, and `PARITY_CHECKS.md`.

**Hard Kill Criteria (stop & revert immediately if any trigger fires):**
1. APK/AAB size budget breach or rejection of `test-native-design.py` policy relaxation.
2. Regressed cold start, RAM, or list scroll smoothness vs Phase 3 native baseline.
3. Bridge instability affecting `CallKit`/`IncomingCallActivity`, billing, or WebRTC/`MediaProjection`.
4. CI/build-system maintenance delaying >=2 release cycles without offsetting feature delivery gain.
5. No measured improvement in cross-platform feature lead time over baseline after the bounded 2-week trial.

---

## 5. Baseline and ROI

- **Measured Inputs `[measured]` / `[observed]`:** `53,762+` native LOC (`35,843` Swift + `17,919+` Java); iOS CI (`~4m22s` Release, `~37m53s` Simulator QA); Android sub-minute local `ecj` compile (`15m` CI build timeout, `60m` emulator QA); `229` Node tests (`Kinnect`) + `31` iOS contract tests (`Kinnect-ios-qa`) + `616` vector graphics checks.
- **Missing Inputs `[unknown]`:** release frequency, change lead time, feature engineering hours, production telemetry percentiles.
- **Option Comparison:**
  - **Path A — Keep Native Parallel (Recommended):** Near-zero migration tax, lean Android APK, zero risk to WebRTC/`MediaProjection`/`PushKit`/`CallKit`; leverages shared Postgres/Supabase schema + `design/tokens.json` + contract tests.
  - **Path B — Brownfield React Native:** High migration tax (re-architecting Android build to AGP/AndroidX/Hermes, 3 active UI stacks, dual store releases still mandatory); positive ROI only if roadmap shifts predominantly to CRUD UI AND JS staffing dominates native staffing.
  - **Path C — Full Rewrite (Rejected):** Unacceptable delivery freeze and regression risk across `1.2.12–1.2.15` production trains.

---

## 6. Next Decision

- **Decision Owner:** Product / Tech Lead / Engineering Owner.
- **Accepting Path A (Recommended):** Close concrete remaining native hygiene items (`public/v2.css` hash sync in `android/design/web-reference.json`, iOS `"??"` comment reaction placeholder in `PostCardAndCommentsView.swift`, targeted parity modules such as `LiveGiftExperience` SoundPool and group deputy UI). Re-evaluate in **3–6 months** or earlier if **>=2 re-open triggers** occur (sustained native staffing shortage, >60% CRUD roadmap shift, or measured parity overhead exceeding bridge cost).
- **Overriding to Path B:** Supply the 4 `[unknown]` organizational inputs above, approve replacing `ecj.jar` + `test_application_has_no_web_container`, assign owners for the 6 governance artifacts (`MIGRATION.md`, `SCREENS.tsv`, `STATE_AND_STORAGE.tsv`, `DEPENDENCIES.tsv`, `EVENTS.tsv`, `PARITY_CHECKS.md`), and authorize the 3-flow Checkpoint.
