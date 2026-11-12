import { test } from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { generateKeyPairSync, verify } from "node:crypto";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createApp } from "../server.js";
import { createCalls } from "../lib/calls.js";
import { createApplePush } from "../lib/apple-push.js";
import { appleAccountUuid } from "../lib/apple-store.js";

test("Apple transactions are account-bound, replay-safe and stay revoked after refund", async () => {
  const transactions = new Map(), notifications = new Map();
  const verifier = { enabled: () => true,
    verifyTransaction: async jws => { if (!transactions.has(jws)) throw Error("bad signature"); return transactions.get(jws); },
    verifyNotification: async jws => { if (!notifications.has(jws)) throw Error("bad signature"); return notifications.get(jws); } };
  const app = createApp({ appleStoreVerifier: verifier });
  await new Promise(resolve => app.server.listen(0, "127.0.0.1", resolve));
  const origin = "http://127.0.0.1:" + app.server.address().port;
  const req = async (path, body, cookie) => {
    const res = await fetch(origin + "/api" + path, { method: body ? "POST" : "GET",
      headers: { ...(body ? { "content-type": "application/json" } : {}), ...(cookie ? { cookie } : {}) },
      body: body ? JSON.stringify(body) : undefined });
    return { status: res.status, body: await res.json(), cookie: res.headers.get("set-cookie")?.split(";")[0] };
  };
  try {
    const alice = await req("/register", { username: "apple_buyer", password: "abcdef", agree18: true, acceptPrivacyNotice: true });
    const bob = await req("/register", { username: "apple_other", password: "abcdef", agree18: true, acceptPrivacyNotice: true });
    const jws = "signed_transaction_fixture_0001";
    const transaction = { bundleId: "app.kinnect.live", productId: "kinnect_studio_pro",
      transactionId: "123456789", quantity: 1, type: "Non-Consumable",
      signedDate: Date.now(), appAccountToken: appleAccountUuid(alice.body.user.id) };
    transactions.set(jws, transaction);
    const body = { platform: "ios", productId: transaction.productId, purchaseToken: jws };
    const store = (await req("/store", null, alice.cookie)).body;
    assert.equal(store.appleBillingReady, true);
    assert.equal(store.accountUuid, transaction.appAccountToken);
    assert.equal((await req("/store/verify", body, bob.cookie)).status, 403);
    assert.equal((await req("/store/verify", { ...body, purchaseToken: "untrusted_jws_fixture_0000" }, alice.cookie)).status, 422);
    for (let i = 0; i < 2; i++) {
      const result = await req("/store/verify", body, alice.cookie);
      assert.equal(result.status, 200);
      assert.deepEqual(result.body.owned, ["kinnect_studio_pro"]);
    }
    assert.equal(app.social.db.prepare("SELECT count(*) n FROM apple_store_transactions").get().n, 1);
    const refundJws = "signed_transaction_refund_0001";
    transactions.set(refundJws, { ...transaction, revocationDate: Date.now() });
    notifications.set("signed_notification_refund", { notificationType: "REFUND", data: { signedTransactionInfo: refundJws } });
    assert.equal((await req("/store/apple-notifications", { signedPayload: "forged_notification" })).status, 422);
    assert.equal((await req("/store/apple-notifications", { signedPayload: "signed_notification_refund" })).status, 200);
    const replay = await req("/store/verify", body, alice.cookie);
    assert.equal(replay.body.state, "CANCELLED");
    assert.deepEqual(replay.body.owned, []);
    // A refund arriving before the first device verification must also block an old signed purchase.
    const early = { ...transaction, transactionId: "987654321" };
    transactions.set("signed_early_purchase_fixture", early);
    transactions.set("signed_early_refund_fixture", { ...early, revocationDate: Date.now() });
    notifications.set("signed_early_refund_notification", {
      notificationType: "REFUND", data: { signedTransactionInfo: "signed_early_refund_fixture" }
    });
    assert.equal((await req("/store/apple-notifications", { signedPayload: "signed_early_refund_notification" })).status, 200);
    const earlyReplay = await req("/store/verify", { ...body, purchaseToken: "signed_early_purchase_fixture" }, alice.cookie);
    assert.equal(earlyReplay.body.state, "CANCELLED");
    assert.deepEqual(earlyReplay.body.owned, []);
    const token = "ab".repeat(32);
    assert.equal((await req("/devices/push", { kind: "voip", token }, alice.cookie)).status, 200);
    assert.equal((await req("/devices/push", { kind: "voip", token }, bob.cookie)).status, 200);
    assert.deepEqual(app.social.db.prepare("SELECT user_id FROM push_devices WHERE token=?").all(token).map(x => x.user_id), [bob.body.user.id]);
  } finally {
    app.wss.close(); app.server.closeAllConnections?.();
    await new Promise(resolve => app.server.close(resolve)); app.social.close();
  }
});

test("APNs signs real ES256 headers, separates VoIP from alerts and removes dead tokens", async () => {
  const dir = await mkdtemp(join(tmpdir(), "kinnect-apns-test-"));
  const db = new DatabaseSync(":memory:");
  db.exec("CREATE TABLE push_devices(user_id TEXT,kind TEXT,token TEXT,updated INTEGER)");
  const token = "ab".repeat(32);
  db.prepare("INSERT INTO push_devices VALUES(?,?,?,?)").run("user", "voip", token, Date.now());
  db.prepare("INSERT INTO push_devices VALUES(?,?,?,?)").run("user", "apns", token, Date.now());
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const keyFile = join(dir, "test.p8");
  await writeFile(keyFile, privateKey.export({ type: "pkcs8", format: "pem" }));
  const sent = [];
  let response = { status: 200, body: {} };
  const push = createApplePush({
    social: { db, user: id => ({ id, suspended: 0 }), blocked: () => false },
    env: { APNS_ENABLED: "true", APNS_KEY_FILE: keyFile, APNS_KEY_ID: "ABCDEFGHIJ",
      APNS_TEAM_ID: "0123456789", APNS_ENVIRONMENT: "sandbox" },
    transport: async (...args) => { sent.push(args); return response; }
  });
  try {
    assert.equal(push.hasVoip("user"), true);
    await push.deliver("user", "voip", { aps: { "content-available": 1 }, callId: "call123" }, { ttl: 0 });
    const [origin, headers] = sent[0];
    assert.equal(origin, "https://api.sandbox.push.apple.com");
    assert.equal(headers["apns-push-type"], "voip");
    assert.equal(headers["apns-topic"], "app.kinnect.live.voip");
    assert.equal(headers["apns-expiration"], "0");
    const jwt = headers.authorization.slice(7).split(".");
    assert.equal(verify("sha256", Buffer.from(jwt[0] + "." + jwt[1]),
      { key: publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(jwt[2], "base64url")), true);
    await push.deliver("user", "apns", { aps: { "content-available": 1 } }, { silent: true });
    assert.equal(sent[1][1]["apns-push-type"], "background");
    assert.equal(sent[1][1]["apns-priority"], "5");
    response = { status: 410, body: { reason: "Unregistered" } };
    await push.deliver("user", "voip", {});
    assert.equal(push.hasVoip("user"), false);
    assert.equal(db.prepare("SELECT count(*) n FROM push_devices WHERE kind='apns'").get().n, 1);
  } finally { db.close(); await rm(dir, { recursive: true, force: true }); }
});

test("offline native calls wait for VoIP wakeup, then accept only the authenticated target", () => {
  const clients = new Set(), sent = [], pushed = [];
  const social = { authenticate: req => req?.valid, blocked: () => false,
    user: id => ({ id, name: id }), recordCallEvent() {} };
  const calls = createCalls({ social, wss: { clients }, visible: () => false,
    send: (peer, message) => sent.push({ peer, ...message }),
    webPush: { has: id => id === "target", call: (...args) => pushed.push(args), callEnded() {} } });
  const caller = { userId: "caller", authRequest: { valid: true } }; clients.add(caller);
  calls.handle(caller, { type: "call-start", to: "target", mode: "audio", requestId: "wake123" });
  const ringing = sent.find(x => x.type === "call-ringing");
  assert.ok(ringing);
  assert.equal(pushed.length, 1);
  const forged = { userId: "target", authRequest: { valid: false } };
  calls.join(forged);
  assert.ok(!sent.some(x => x.peer === forged));
  const target = { userId: "target", authRequest: { valid: true } }; clients.add(target);
  calls.join(target);
  assert.ok(sent.some(x => x.peer === target && x.type === "call-incoming"));
  calls.handle(target, { type: "call-accept", callId: ringing.callId });
  assert.ok(sent.some(x => x.peer === caller && x.type === "call-accepted"));
  calls.handle(caller, { type: "call-end", callId: ringing.callId });
});
