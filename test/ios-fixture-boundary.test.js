import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { STORE_PACKAGES } from '../lib/store-packages.js';
import { STORE_PRODUCTS } from '../lib/store.js';
import { LIVE_GIFTS } from '../lib/live-gifts.js';
import { DEFAULT_ECONOMY } from '../lib/economy.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const IOS_ROOT = path.join(ROOT, 'ios', 'Kinnect');

function walkSwiftFiles(dir) {
  let out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      out = out.concat(walkSwiftFiles(full));
    } else if (full.endsWith('.swift')) {
      out.push(full);
    }
  }
  return out;
}

function readIos(rel) {
  return fs.readFileSync(path.join(IOS_ROOT, rel), 'utf8');
}

function extractSwitchCaseBlock(source, caseAnchor) {
  const idx = source.indexOf(caseAnchor);
  assert.ok(idx >= 0, `Missing switch case anchor: ${caseAnchor}`);
  const rest = source.slice(idx + caseAnchor.length);
  const nextMatch = rest.search(/\r?\n        (?:case |default:)/);
  return nextMatch >= 0 ? source.slice(idx, idx + caseAnchor.length + nextMatch) : source.slice(idx);
}

test('all Swift files guard UIReviewFixture and --ui-review-* references under #if DEBUG', () => {
  const files = walkSwiftFiles(IOS_ROOT);
  assert.ok(files.length >= 40, `Expected >= 40 Swift files, found ${files.length}`);

  const violations = [];
  for (const file of files) {
    const rel = path.relative(ROOT, file).replace(/\\/g, '/');
    const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
    const stack = [];

    lines.forEach((line, idx) => {
      const trimmed = line.trim();
      if (/^#if\b/.test(trimmed)) {
        const expr = trimmed.slice(3).trim();
        const inDebug = /\bDEBUG\b/.test(expr) && !/!\s*DEBUG\b/.test(expr);
        stack.push({ inDebug, line: idx + 1 });
      } else if (/^#elseif\b/.test(trimmed)) {
        const expr = trimmed.slice(7).trim();
        const top = stack[stack.length - 1];
        if (top) top.inDebug = /\bDEBUG\b/.test(expr) && !/!\s*DEBUG\b/.test(expr);
      } else if (/^#else\b/.test(trimmed)) {
        const top = stack[stack.length - 1];
        if (top) top.inDebug = false;
      } else if (/^#endif\b/.test(trimmed)) {
        if (stack.length === 0) {
          violations.push(`${rel}:${idx + 1}: unmatched #endif`);
        } else {
          stack.pop();
        }
      } else if (rel !== 'ios/Kinnect/Core/UIReviewFixture.swift') {
        const isInsideDebug = stack.some((frame) => frame.inDebug);
        if (!isInsideDebug && (/UIReviewFixture/.test(line) || /--ui-review/.test(line))) {
          violations.push(`${rel}:${idx + 1}: unguarded reference -> ${trimmed}`);
        }
      }
    });

    if (stack.length > 0) {
      violations.push(`${rel}: unclosed #if stack (${stack.length})`);
    }
  }

  assert.deepEqual(violations, []);
});

test('UIReviewFixture.swift is wrapped in #if DEBUG with an inert Release #else stub', () => {
  const src = readIos('Core/UIReviewFixture.swift');
  const lines = src.split(/\r?\n/);
  const elseIdx = lines.findIndex((l) => l.trim() === '#else');
  const debugIdx = lines.findIndex((l) => l.trim() === '#if DEBUG');
  const endifIdx = lines.findLastIndex((l) => l.trim() === '#endif');

  assert.ok(debugIdx >= 0 && debugIdx <= 15, 'Expected #if DEBUG near top of UIReviewFixture.swift');
  assert.ok(elseIdx > debugIdx, 'Expected #else Release stub in UIReviewFixture.swift');
  assert.ok(endifIdx > elseIdx, 'Expected closing #endif at end of UIReviewFixture.swift');

  const releaseStub = lines.slice(elseIdx + 1, endifIdx).join('\n');
  assert.match(releaseStub, /static let isEnabled: Bool = false/);
  assert.match(releaseStub, /static let activeScreen: String\? = nil/);
  assert.doesNotMatch(releaseStub, /mockResponse/);
  assert.doesNotMatch(releaseStub, /--ui-review/);
  assert.doesNotMatch(releaseStub, /mockPosts/);
  assert.doesNotMatch(releaseStub, /samplePlayableVideoURL/);
  assert.doesNotMatch(releaseStub, /requiresDarkAppearance/);
});

test('no exposed fixture/technical strings or moving purple placeholder dot remain in Swift UI literals', () => {
  const forbiddenInNonComments = [
    '[Fixture',
    'iOS Simulator',
    '@minhanh_demo',
    '44pt chuẩn iOS',
    'iOS Native SwiftUI',
    '40 icon vector',
    'AVPlayer native',
    'Báo cáo UGC',
    'Báo cáo / Chặn UGC',
    'CSAE/CSAM',
    'ui_review_sample_shorts.mp4',
    'fixture_user_me'
  ];

  const hits = [];
  for (const file of walkSwiftFiles(IOS_ROOT)) {
    const rel = path.relative(ROOT, file).replace(/\\/g, '/');
    const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
    lines.forEach((line, idx) => {
      if (/^\s*\/\//.test(line)) return;
      for (const token of forbiddenInNonComments) {
        if (line.includes(token)) {
          hits.push(`${rel}:${idx + 1}: contains "${token}"`);
        }
      }
    });
  }
  assert.deepEqual(hits, []);

  const fixtureSrc = readIos('Core/UIReviewFixture.swift');
  const videoStart = fixtureSrc.indexOf('static func samplePlayableVideoURL()');
  assert.ok(videoStart >= 0);
  const videoEnd = fixtureSrc.indexOf('\n    static func ', videoStart + 10);
  const videoBlock = fixtureSrc.slice(videoStart, videoEnd >= 0 ? videoEnd : undefined);
  assert.doesNotMatch(videoBlock, /fillEllipse/);
  assert.match(videoBlock, /ui_review_sample_shorts_v2\.mp4/);
});

test('UIReviewFixture aligns with backend Contract 1 user, wallet, store, and live gift catalogs', () => {
  const fixtureSrc = readIos('Core/UIReviewFixture.swift');

  // User identities u1..u4 & group
  assert.match(fixtureSrc, /"Nguyễn Minh Anh"/);
  assert.match(fixtureSrc, /"minhanh"/);
  assert.match(fixtureSrc, /"Lê Hoàng Nam"/);
  assert.match(fixtureSrc, /"Trần Thanh Trúc"/);
  assert.match(fixtureSrc, /"Linh Nhi"/);
  assert.match(fixtureSrc, /"Nhóm Thiết Kế Kinnect"/);

  // /api/me & /api/auth/me alias
  assert.match(fixtureSrc, /case "\/api\/me", "\/api\/auth\/me":/);

  // /api/wallet flat keys + 8500 purchased + 4000 gifted = 12500 usable
  const walletBlock = extractSwitchCaseBlock(fixtureSrc, 'case "/api/wallet":');
  assert.match(walletBlock, /"availableBalance": 12500/);
  assert.match(walletBlock, /"totalUsableCoins": 12500/);
  assert.match(walletBlock, /"purchasedCoins": 8500/);
  assert.match(walletBlock, /"giftedCoins": 4000/);
  assert.match(walletBlock, /"trialCoins": 4000/);
  assert.match(walletBlock, /"vndPerCoin": 100/);

  // /api/store packages & products vs backend lib/store-packages.js and lib/store.js
  const storeBlock = extractSwitchCaseBlock(fixtureSrc, 'case "/api/store":');
  assert.match(storeBlock, /"purchasedCoins": 8500/);
  assert.match(storeBlock, /"giftedCoins": 4000/);
  for (const pkg of STORE_PACKAGES) {
    if (pkg.id.startsWith('studio_')) {
      assert.match(storeBlock, /"studio_\\\(line\)_\\\(days\)"/);
      assert.match(storeBlock, new RegExp(`\\(${pkg.days}, ${pkg.priceCoins}, "${pkg.tier}"`));
    } else {
      assert.ok(storeBlock.includes(`"${pkg.id}"`), `Missing store package id ${pkg.id} in /api/store fixture`);
    }
  }
  for (const prod of STORE_PRODUCTS) {
    assert.ok(storeBlock.includes(`"${prod.id}"`), `Missing store product id ${prod.id} in /api/store fixture`);
  }

  // /api/live/gifts vs backend lib/live-gifts.js & DEFAULT_ECONOMY
  const giftsBlock = extractSwitchCaseBlock(fixtureSrc, 'case "/api/live/gifts":');
  assert.match(giftsBlock, /"balance": 4000/);
  assert.match(giftsBlock, /"inventory": \[\]/);
  assert.match(giftsBlock, /"purchasedCoins": 8500/);
  assert.match(giftsBlock, /"giftedCoins": 4000/);
  assert.match(giftsBlock, /"quantities": \[1, 5, 10, 99\]/);
  assert.match(giftsBlock, /LiveGiftCatalogItem\.defaultCatalog\.map/);
  const modelsSrc = readIos('Core/Models.swift');
  const catalogStart = modelsSrc.indexOf('static let defaultCatalog: [LiveGiftCatalogItem]');
  const catalogEnd = modelsSrc.indexOf('\n    ]', catalogStart);
  const catalogBlock = modelsSrc.slice(catalogStart, catalogEnd);
  assert.equal(LIVE_GIFTS.length, Object.keys(DEFAULT_ECONOMY.giftPrices).length);
  for (const gift of LIVE_GIFTS) {
    assert.ok(catalogBlock.includes(`id: "${gift.id}"`), `Missing live gift id ${gift.id} in LiveGiftCatalogItem.defaultCatalog`);
  }

  // Comment count synced between /api/posts, mockPosts, and /comments
  assert.match(fixtureSrc, /"commentsCount": 2/);
  const commentsBlock = extractSwitchCaseBlock(fixtureSrc, 'case _ where cleanPath.hasSuffix("/comments"):');
  const commentIds = commentsBlock.match(/"id": "fixture_c_\d+"/g) || [];
  assert.equal(commentIds.length, 2);
});

test('iOS parity UI routing, Shop tabs, Live lobby/viewer HUD, and comment report controls match spec', () => {
  const fixtureSrc = readIos('Core/UIReviewFixture.swift');
  const discoverSrc = readIos('Views/DiscoverView.swift');
  const storeSrc = readIos('Views/StoreView.swift');
  const liveSrc = readIos('Views/LiveStreamView.swift');
  const rootSrc = readIos('Views/RootMainView.swift');
  const notifSrc = readIos('Views/NotificationsView.swift');
  const feedSrc = readIos('Views/FeedView.swift');

  // Discover search separation
  assert.match(discoverSrc, /init\(initialSearchQuery: String = ""/);
  assert.doesNotMatch(discoverSrc, /UIReviewFixture/);
  const discoverSearchBlock = extractSwitchCaseBlock(fixtureSrc, 'case "discover", "discover-empty", "discover-search":');
  assert.doesNotMatch(discoverSearchBlock, /initialSearchQuery:\s*"cà phê"/);
  const discoverResultsBlock = extractSwitchCaseBlock(fixtureSrc, 'case "discover-results":');
  assert.match(discoverResultsBlock, /DiscoverView\(initialSearchQuery: "cà phê"/);

  // Screen routing for live-room, feed-narrow, studio-music-picker, ugc-report
  assert.match(fixtureSrc, /case "live-room":/);
  assert.match(fixtureSrc, /LiveRoomFullScreenView\(\)/);
  assert.match(fixtureSrc, /case "feed-narrow":/);
  assert.match(fixtureSrc, /\.frame\(width: 320\)/);
  assert.match(fixtureSrc, /\.environment\(\\\.horizontalSizeClass, \.compact\)/);
  assert.match(fixtureSrc, /case "studio-music-picker":/);
  assert.match(fixtureSrc, /StudioMusicPickerSheet/);
  assert.match(fixtureSrc, /case "ugc-report":/);
  assert.match(fixtureSrc, /UGCReportSheet/);

  // StoreView 6 ordered tabs and hero gated to .style below category strip
  const enumStart = storeSrc.indexOf('enum StoreCategoryFilter');
  const enumEnd = storeSrc.indexOf('\n}', enumStart);
  const enumBlock = storeSrc.slice(enumStart, enumEnd);
  const rawTitles = [...enumBlock.matchAll(/case \w+ = "([^"]+)"/g)].map((m) => m[1]);
  assert.deepEqual(rawTitles, ['Phong cách', 'Studio', 'Live', 'Quà', 'Thành viên', 'Của tôi']);
  assert.ok(storeSrc.indexOf('categoryFilterStrip') < storeSrc.indexOf('if storeFilter == .style'));

  // RootMainView renders LiveRoomFullScreenView for both host & viewer
  assert.match(rootSrc, /if appState\.currentLiveRoom != nil \{/);
  assert.doesNotMatch(rootSrc, /appState\.currentLiveRoom != nil && appState\.isCurrentLiveHost/);

  // LiveStreamView Lobby first, no "Phát Live" inside liveStreamPage, and LiveGiftDrawerSheet uses gifted/trial balance
  assert.match(liveSrc, /liveRoomsLobbyView/);
  const streamPageStart = liveSrc.indexOf('private func liveStreamPage(');
  assert.ok(streamPageStart >= 0, 'Missing private func liveStreamPage(');
  const streamPageEnd = liveSrc.indexOf('\n    private func handleIncomingReactionEvent', streamPageStart);
  assert.ok(streamPageEnd > streamPageStart, 'Missing end anchor for liveStreamPage');
  const streamPageBlock = liveSrc.slice(streamPageStart, streamPageEnd);
  assert.doesNotMatch(streamPageBlock, /"Phát Live"/);

  const giftDrawerStart = liveSrc.indexOf('struct LiveGiftDrawerSheet: View {');
  assert.ok(giftDrawerStart >= 0, 'Missing LiveGiftDrawerSheet');
  const giftDrawerEnd = liveSrc.indexOf('\n// MARK: - Floating Reaction Model', giftDrawerStart);
  assert.ok(giftDrawerEnd > giftDrawerStart, 'Missing end anchor for LiveGiftDrawerSheet');
  const giftDrawerBlock = liveSrc.slice(giftDrawerStart, giftDrawerEnd);
  assert.match(giftDrawerBlock, /L10n\.tr\("Xu tặng"\)/);
  assert.doesNotMatch(giftDrawerBlock, /appState\.currentUser\?\.coins\b/);
  assert.doesNotMatch(giftDrawerBlock, /Button\("Đóng"\)/);
  assert.match(giftDrawerBlock, /L10n\.tr\("Đóng"\)/);
  assert.match(giftDrawerBlock, /KinnectTheme\.textPrimary/);
  assert.match(giftDrawerBlock, /minHeight:\s*44/);

  // CreateLiveRoomSheet (SCR-24): outer dark NavigationStack, white principal title, fitted 4-chip LazyVGrid
  const createSheetStart = liveSrc.indexOf('struct CreateLiveRoomSheet: View {');
  assert.ok(createSheetStart >= 0, 'Missing CreateLiveRoomSheet');
  const createSheetEnd = liveSrc.indexOf('\nstruct LiveRoomFullScreenView: View {', createSheetStart);
  assert.ok(createSheetEnd > createSheetStart, 'Missing end anchor for CreateLiveRoomSheet');
  const createSheetBlock = liveSrc.slice(createSheetStart, createSheetEnd);
  assert.ok(
    createSheetBlock.lastIndexOf('.preferredColorScheme(.dark)') > createSheetBlock.indexOf('.toolbar {'),
    'CreateLiveRoomSheet must apply .preferredColorScheme(.dark) outside NavigationStack'
  );
  assert.match(createSheetBlock, /\.toolbarColorScheme\(\.dark,\s*for:\s*\.navigationBar\)/);
  assert.match(createSheetBlock, /ToolbarItem\(placement:\s*\.principal\)/);
  assert.match(createSheetBlock, /L10n\.tr\("Bắt đầu phát Live"\)/);
  assert.match(createSheetBlock, /\.foregroundColor\(\.white\)/);
  assert.match(createSheetBlock, /L10n\.tr\("Hủy"\)/);

  const deckStart = createSheetBlock.indexOf('private var darkControlDeck: some View {');
  assert.ok(deckStart >= 0, 'Missing darkControlDeck in CreateLiveRoomSheet');
  const chipFuncStart = createSheetBlock.indexOf('\n    private func setupChipButton(', deckStart);
  assert.ok(chipFuncStart > deckStart, 'Missing setupChipButton in CreateLiveRoomSheet');
  const deckBlock = createSheetBlock.slice(deckStart, chipFuncStart);
  assert.match(deckBlock, /LazyVGrid\(/);
  assert.doesNotMatch(deckBlock, /ScrollView\(\.horizontal/);
  for (const chipLabel of ['Micro', 'Bình luận', 'Lật cam', 'Làm đẹp']) {
    assert.ok(deckBlock.includes(`L10n.tr("${chipLabel}")`), `Missing chip label ${chipLabel} in darkControlDeck`);
  }
  const chipFuncBlock = createSheetBlock.slice(chipFuncStart);
  assert.match(chipFuncBlock, /minHeight:\s*44/);

  // StoryDetailSheet (SCR-07) & #if DEBUG dark-canvas appearance guard
  const storySheetStart = feedSrc.indexOf('struct StoryDetailSheet: View {');
  assert.ok(storySheetStart >= 0, 'Missing StoryDetailSheet');
  const storySheetEnd = feedSrc.indexOf('\n    private var storyProgressBars: some View {', storySheetStart);
  assert.ok(storySheetEnd > storySheetStart, 'Missing end anchor for StoryDetailSheet');
  const storySheetBlock = feedSrc.slice(storySheetStart, storySheetEnd);
  assert.match(storySheetBlock, /\.preferredColorScheme\(\.dark\)/);

  const fullScreenCoverIdx = feedSrc.indexOf('.fullScreenCover(item: $activeStorySession)');
  assert.ok(fullScreenCoverIdx >= 0, 'Missing StoryDetailSheet fullScreenCover');
  const fullScreenCoverEnd = feedSrc.indexOf('.sheet(item: $activeCommentPost)', fullScreenCoverIdx);
  assert.ok(fullScreenCoverEnd > fullScreenCoverIdx, 'Missing end anchor for StoryDetailSheet fullScreenCover');
  const fullScreenCoverSnippet = feedSrc.slice(fullScreenCoverIdx, fullScreenCoverEnd);
  assert.match(fullScreenCoverSnippet, /\.preferredColorScheme\(\.dark\)/);

  const debugSection = fixtureSrc.slice(0, fixtureSrc.indexOf('\n#else'));
  assert.match(debugSection, /static func requiresDarkAppearance\(for screenName: String\) -> Bool/);
  for (const darkSlug of ['feed-story', 'live-setup', 'live-setup-game', 'live-room', 'live-gifts', 'studio-music-picker']) {
    assert.ok(debugSection.includes(`"${darkSlug}"`), `Missing dark-canvas slug "${darkSlug}" in UIReviewFixture`);
  }
  const sceneSrc = readIos('SceneDelegate.swift');
  assert.match(sceneSrc, /UIReviewFixture\.requiresDarkAppearance\(for:/);

  // StudioMusicPickerSheet (SCR-31): themed accessible "Đóng" button
  const cameraSrc = readIos('Views/CameraStudioView.swift');
  const musicSheetStart = cameraSrc.indexOf('struct StudioMusicPickerSheet: View {');
  assert.ok(musicSheetStart >= 0, 'Missing StudioMusicPickerSheet');
  const musicSheetEnd = cameraSrc.indexOf('\n    private func loadCatalog() async {', musicSheetStart);
  assert.ok(musicSheetEnd > musicSheetStart, 'Missing end anchor for StudioMusicPickerSheet');
  const musicSheetBlock = cameraSrc.slice(musicSheetStart, musicSheetEnd);
  assert.match(musicSheetBlock, /L10n\.tr\("Đóng"\)/);
  assert.match(musicSheetBlock, /KinnectTheme\.textPrimary/);
  assert.match(musicSheetBlock, /minHeight:\s*44/);

  // Explicit comment report buttons and >= 44pt touch targets in NotificationsView and FeedView
  assert.match(notifSrc, /Label\(L10n\.tr\("Báo cáo"\), systemImage: "flag"\)/);
  assert.doesNotMatch(notifSrc, /minHeight:\s*36/);
  assert.match(feedSrc, /L10n\.tr\("Báo cáo"\)/);
  const feedReportIdx = feedSrc.indexOf('Label(L10n.tr("Báo cáo"), systemImage: "flag")');
  assert.ok(feedReportIdx >= 0);
  const feedReportSnippet = feedSrc.slice(feedReportIdx, feedReportIdx + 300);
  assert.match(feedReportSnippet, /minHeight:\s*44/);

  // Zero CameraSessionController references anywhere in ios/
  const cameraControllerHits = [];
  for (const file of walkSwiftFiles(IOS_ROOT)) {
    const content = fs.readFileSync(file, 'utf8');
    if (content.includes('CameraSessionController')) {
      cameraControllerHits.push(path.relative(ROOT, file).replace(/\\/g, '/'));
    }
  }
  assert.deepEqual(cameraControllerHits, []);
});

test('LocalizationManager has zero duplicate keys and covers all L10n.tr keys in modified views', () => {
  const locSrc = readIos('Core/LocalizationManager.swift');
  const dictStart = locSrc.indexOf('private let translations:');
  assert.ok(dictStart >= 0);
  const dictBody = locSrc.slice(dictStart);

  const keyRegex = /^\s*"((?:[^"\\]|\\.)+)":\s*\[/gm;
  const keys = new Set();
  const duplicates = [];
  let m;
  while ((m = keyRegex.exec(dictBody)) !== null) {
    if (keys.has(m[1])) duplicates.push(m[1]);
    keys.add(m[1]);
  }
  assert.deepEqual(duplicates, [], `Duplicate keys in LocalizationManager.swift: ${duplicates.join(', ')}`);

  const checkedViews = [
    'Views/StoreView.swift',
    'Views/LiveStreamView.swift',
    'Views/DiscoverView.swift',
    'Views/CameraStudioView.swift',
    'Views/NotificationsView.swift',
    'Views/FeedView.swift',
    'Views/RootMainView.swift',
    'Views/AccountMenuView.swift'
  ];

  const missing = [];
  const trRegex = /L10n\.tr\(\s*"((?:[^"\\]|\\.)+)"\s*\)/g;
  for (const rel of checkedViews) {
    const src = readIos(rel);
    let tm;
    while ((tm = trRegex.exec(src)) !== null) {
      if (!keys.has(tm[1])) {
        missing.push(`${rel}: "${tm[1]}"`);
      }
    }
  }
  const requiredDynamicKeys = [
    'Phong cách',
    'Studio',
    'Quà',
    'Của tôi',
    'Camera trước',
    'Camera sau',
    'Tiếp tục Game',
    'Tạm ẩn Game',
    'Rời phòng Live',
    'Xu tặng'
  ];
  for (const dynKey of requiredDynamicKeys) {
    if (!keys.has(dynKey)) {
      missing.push(`Dynamic key missing: "${dynKey}"`);
    }
  }
  assert.deepEqual(missing, []);
});
