import { test } from "node:test";
import assert from "node:assert/strict";
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
