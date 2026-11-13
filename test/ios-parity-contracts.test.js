import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createApp } from "../server.js";

test("native wallet/store responses, inventory, and retry-safe consumable purchases", async () => {
  const app = createApp();
  await new Promise(resolve => app.server.listen(0, "127.0.0.1", resolve));
  const origin = "http://127.0.0.1:" + app.server.address().port;
  let cookie;
  const req = async (path, body) => {
    const res = await fetch(origin + "/api" + path, {
      method: body ? "POST" : "GET",
      headers: { ...(cookie ? { cookie } : {}), ...(body ? { "content-type": "application/json" } : {}) },
      body: body ? JSON.stringify(body) : undefined
    });
    if (!cookie) cookie = res.headers.get("set-cookie")?.split(";")[0];
    return { status: res.status, body: await res.json() };
  };
  try {
    assert.equal((await req("/register", {
      username: "ios_parity_contract", password: "abcdef", agree18: true, acceptPrivacyNotice: true
    })).status, 200);
    const wallet = (await req("/wallet")).body;
    assert.equal(wallet.wallet, undefined);
    assert.equal(wallet.totalUsableCoins, wallet.purchasedCoins + wallet.giftedCoins);
    assert.ok(wallet.giftedCoins > 0);
    assert.deepEqual((await req("/store")).body.giftInventory, []);

    const requestId = "pkg_ios_consumable_retry_001";
    const body = { productId: "gift_love", priceCoins: 300, requestId, coinSource: "gifted" };
    const first = await req("/store/packages/buy", body);
    assert.equal(first.status, 200);
    assert.equal(first.body.ok, undefined); // The native client must accept authoritative state, not an invented success flag.
    assert.ok(first.body.ownedPackages.includes("gift_love"));
    assert.equal(first.body.giftInventory.find(x => x.giftId === "rose").quantity, 6);
    const afterFirst = (await req("/wallet")).body;
    const retry = await req("/store/packages/buy", body);
    assert.equal(retry.status, 200);
    assert.equal(retry.body.duplicate, true);
    assert.equal(retry.body.giftInventory.find(x => x.giftId === "rose").quantity, 6);
    assert.equal((await req("/wallet")).body.giftedCoins, afterFirst.giftedCoins);

    const live = await req("/store/packages/buy", {
      productId: "live_chill", priceCoins: 500, coinSource: "gifted", requestId: "pkg_ios_live_apply_001"
    });
    assert.equal(live.status, 200);
    const applied = await req("/store/packages/apply", { productId: "live_chill" });
    assert.equal(applied.status, 200);
    assert.equal(applied.body.liveTheme, "live_chill");
    assert.equal(applied.body.ok, undefined);
    assert.equal((await req("/store/packages/apply", { productId: "" })).body.liveTheme, "");
  } finally {
    app.wss.close();
    app.server.closeAllConnections?.();
    await new Promise(resolve => app.server.close(resolve));
    app.social.close();
  }
});

test("native x2/x50 gift quantities reach wallet debit and broadcast unchanged", async () => {
  const { createLiveGifts } = await import("../lib/live-gifts.js");
  const { DatabaseSync } = await import("node:sqlite");
  const db = new DatabaseSync(":memory:");
  db.exec("CREATE TABLE blocks(actor TEXT,target TEXT,PRIMARY KEY(actor,target))");
  const sender = { id: "s", userId: "sender" };
  const host = { id: "h", userId: "host" };
  const room = { id: "room", host, members: new Map([["s", sender], ["h", host]]) };
  let time = 10000;
  const spends = [], sent = [];
  const gifts = createLiveGifts({
    social: {
      db, economy: { read: () => ({ config: { trialGiftsEnabled: true, giftPrices: { rose: 10 } } }),
        giftCatalog: () => ({ items: [] }) },
      wallet: { trialBalance: () => 2000, spendTrialGift: args => {
        spends.push(args);
        return { quantity: args.quantity, costCoins: args.quantity * 10, balance: 2000 - args.quantity * 10 };
      } }
    },
    send: (_, event) => sent.push(event), env: {}, now: () => time
  });
  try {
    for (const quantity of [2, 50, 99]) {
      gifts.handle(room, sender, { type: "live-reaction", kind: "rose", quantity,
        fundingSource: "gifted", priceVersion: 1, requestId: "gift_quantity_" + quantity }, { name: "Sender" });
      assert.equal(spends.at(-1).quantity, quantity);
      const event = sent.findLast(x => x.type === "live-reaction");
      assert.equal(event.quantity, quantity);
      assert.equal(event.costCoins, quantity * 10);
      time += 1300;
    }
  } finally { db.close(); }
});

test("iOS Release boundary guards UIReviewFixture, ShortsVideoView and LiveStreamView", () => {
  const fixtureSrc = readFileSync(new URL("../ios/Kinnect/Core/UIReviewFixture.swift", import.meta.url), "utf8");
  const shortsSrc = readFileSync(new URL("../ios/Kinnect/Views/ShortsVideoView.swift", import.meta.url), "utf8");
  const liveSrc = readFileSync(new URL("../ios/Kinnect/Views/LiveStreamView.swift", import.meta.url), "utf8");
  assert.match(fixtureSrc, /static var activeScreen: String\? \{\s*#if DEBUG[\s\S]*?#else\s*return nil\s*#endif\s*\}/);
  assert.match(fixtureSrc, /static var isEnabled: Bool \{\s*#if DEBUG\s*return activeScreen != nil\s*#else\s*return false\s*#endif\s*\}/);
  assert.match(fixtureSrc, /static var forceLightMode: Bool \{\s*#if DEBUG/);
  assert.match(fixtureSrc, /static var forceMaxDynamicType: Bool \{\s*#if DEBUG/);
  assert.match(fixtureSrc, /static func writeDocument\([^)]+\) \{\s*#if DEBUG\s*guard isEnabled,/);
  assert.match(fixtureSrc, /static func samplePlayableVideoURL\(\) -> URL\? \{\s*#if DEBUG\s*guard isEnabled else \{ return nil \}/);
  assert.match(fixtureSrc, /static func sampleSecondPlayableVideoURL\(\) -> URL\? \{\s*#if DEBUG\s*guard isEnabled else \{ return nil \}/);
  assert.match(fixtureSrc, /private static func makeSampleVideoURL\([^)]+\) -> URL\? \{\s*#if DEBUG\s*guard isEnabled else \{ return nil \}/);
  assert.match(shortsSrc, /guard let remoteURL = ServerConfig\.url\(for: path, origin: origin\) else \{\s*#if DEBUG\s*if UIReviewFixture\.isEnabled, let fixtureURL = UIReviewFixture\.samplePlayableVideoURL\(\)/);
  assert.match(shortsSrc, /failed = true\s*loading = false/);
  assert.doesNotMatch(liveSrc, /welcome-feed-demo\.mp4/);
  assert.match(liveSrc, /else if UIReviewFixture\.isEnabled[\s\S]*?UIReviewFixture\.samplePlayableVideoURL\(\)/);
  assert.match(liveSrc, /appState\.currentLiveRoom\?\.id == room\.id, appState\.isCurrentLiveHost, let localTrack/);
  assert.match(liveSrc, /appState\.currentLiveRoom\?\.id == room\.id, let remoteTrack/);
  assert.match(liveSrc, /guard let list = res\["rooms"\] as\? \[\[String: Any\]\] else/);
  const adminOpsSrc = readFileSync(new URL("../ios/Kinnect/Views/AdminOperationsView.swift", import.meta.url), "utf8");
  assert.match(adminOpsSrc, /canPresentTemporarySecret\(/);
  assert.match(adminOpsSrc, /UIApplication\.shared\.applicationState == \.active/);
  assert.match(adminOpsSrc, /guard accountId == activeAccountId, role == "admin" else/);
  const appStateSrc = readFileSync(new URL("../ios/Kinnect/Core/AppState.swift", import.meta.url), "utf8");
  assert.match(appStateSrc, /func clearSessionState\(\)[\s\S]*?AccountCache\.shared\.wipeAllCaches\(\)\s*KinnectAuthenticatedFile\.wipe\(\)/);
  assert.match(fixtureSrc, /#if DEBUG[\s\S]*?case "admin-operations-ready":[\s\S]*?adminDict\["role"\] = "admin"[\s\S]*?#endif/);
  assert.doesNotMatch(liveSrc, /liveTopLobbyBar|categoryFilter/);
  assert.match(liveSrc, /private func liveVerticalActionButtonLabel[\s\S]*?\.frame\(width:\s*56\)/);
  assert.match(liveSrc, /struct CreateLiveRoomSheet:[\s\S]*?preLiveBackdrop[\s\S]*?LiveCameraPreviewView[\s\S]*?preLiveGameSetupDeck[\s\S]*?previewController\.stop\(\)[\s\S]*?startLiveHostBroadcast\(\)/);
  assert.match(fixtureSrc, /case "create-live-chat":[\s\S]*?CreateLiveRoomSheet\(initialLiveMode:\s*"chat"\)/);
  assert.match(fixtureSrc, /case "create-live-game":[\s\S]*?CreateLiveRoomSheet\(initialLiveMode:\s*"game"\)/);
});
