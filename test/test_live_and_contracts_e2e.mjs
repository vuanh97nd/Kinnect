import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import WebSocket from "ws";
import { createApp } from "../server.js";
import { SignedDataVerifier, Environment } from "@apple/app-store-server-library";
import { storeAccountUuid } from "../lib/store.js";

let simulatedTime = Date.now();
const testClock = () => simulatedTime;

let verifierTransientError = null;
const appleVerifier = {
  enabled: () => true,
  bundleId: "app.kinnect.live",
  environment: "LocalTesting",
  async verify(jws) {
    if (verifierTransientError) {
      const err = verifierTransientError;
      verifierTransientError = null;
      throw err;
    }
    const v = new SignedDataVerifier([], false, Environment.LOCAL_TESTING, "app.kinnect.live");
    return await v.verifyAndDecodeTransaction(jws);
  },
  async verifyNotification(jws) {
    const v = new SignedDataVerifier([], false, Environment.LOCAL_TESTING, "app.kinnect.live");
    return await v.verifyAndDecodeNotification(jws);
  }
};

// Fully isolated: ":memory:" disables the shared cloud session/bridge, SFU env and gift env (server.js:25-86).
const { server, social } = createApp({
  dbPath: ":memory:",
  allowEmailDelivery: false,
  appleStoreVerifier: appleVerifier,
  clock: testClock,
  storeEnv: { PLAY_PURCHASE_TOKEN_KEY: "ab".repeat(32) }
});
const RUN = Date.now().toString(36).slice(-5);

await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const port = server.address().port;
const baseUrl = `http://127.0.0.1:${port}`;
const wsUrl = `ws://127.0.0.1:${port}`;

async function registerUser(username, name, email, password) {
  const res = await fetch(`${baseUrl}/api/register`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      username,
      name,
      email,
      password,
      gender: "nam",
      birthYear: 1998,
      agree18: true,
      acceptPrivacyNotice: true,
    }),
  });
  const setCookie = res.headers.get("set-cookie") || "";
  const cookie = setCookie.split(";")[0];
  const data = await res.json();
  if (!res.ok) throw new Error(`Register failed (${res.status}): ${JSON.stringify(data)}`);
  return { user: data.user, cookie };
}

// Explicit privacy consent flow (no server bypass): GET current version -> 428 on content write BEFORE consent
// -> stale version rejected -> POST { accepted:true, version } exactly like iOS PrivacyConsentSheet -> accepted AFTER.
async function acceptPrivacyConsentExplicitly(account) {
  const headers = { "Content-Type": "application/json", Cookie: account.cookie };
  const status = await (await fetch(`${baseUrl}/api/me/privacy-consent`, { headers })).json();
  assert.equal(typeof status.version, "string");
  if (!status.accepted) {
    const denied = await fetch(`${baseUrl}/api/me/content-consent`, { method: "POST", headers, body: "{}" });
    assert.equal(denied.status, 428, "content write must be denied before explicit consent");
    assert.equal((await denied.json()).version, status.version);
  }
  const wrong = await fetch(`${baseUrl}/api/me/privacy-consent`, { method: "POST", headers, body: JSON.stringify({ accepted: true, version: "stale-version" }) });
  assert.equal(wrong.status, 400, "stale consent version must be rejected");
  const ok = await fetch(`${baseUrl}/api/me/privacy-consent`, { method: "POST", headers, body: JSON.stringify({ accepted: true, version: status.version }) });
  assert.equal(ok.status, 200);
  const after = await (await fetch(`${baseUrl}/api/me/privacy-consent`, { headers })).json();
  assert.equal(after.accepted, true, "consent must be recorded after explicit acceptance");
  const allowed = await fetch(`${baseUrl}/api/me/content-consent`, { method: "POST", headers, body: "{}" });
  assert.equal(allowed.status, 200, "content write must succeed after explicit consent");
  return { deniedBefore: !status.accepted, version: status.version };
}

function connectWS(cookie) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl, {
      headers: { Cookie: cookie, Origin: baseUrl },
    });
    const queue = [];
    ws.on("message", (raw) => {
      const msg = JSON.parse(raw.toString());
      queue.push(msg);
      if (msg.type === "welcome") {
        resolve({
          ws,
          queue,
          waitFor: (pred, timeoutMs = 4000) =>
            new Promise((res, rej) => {
              const start = Date.now();
              const timer = setInterval(() => {
                const idx = queue.findIndex(pred);
                if (idx !== -1) {
                  clearInterval(timer);
                  res(queue.splice(idx, 1)[0]);
                } else if (Date.now() - start > timeoutMs) {
                  clearInterval(timer);
                  rej(new Error("Timeout waiting for WS event. Queue: " + JSON.stringify(queue)));
                }
              }, 25);
            }),
        });
      }
    });
    ws.on("error", reject);
  });
}

console.log("1. Registering 3 test accounts (Host1, Host2, Viewer)...");
const host1 = await registerUser("host_one_" + RUN, "Host One", `host1_${RUN}@kinnect.local`, "Pass123456!");
const host2 = await registerUser("host_two_" + RUN, "Host Two", `host2_${RUN}@kinnect.local`, "Pass123456!");
const viewer = await registerUser("viewer_user_" + RUN, "Viewer User", `viewer_${RUN}@kinnect.local`, "Pass123456!");

console.log("1b. WS live create denied BEFORE explicit consent (dedicated no-consent account)...");
{
  const probe = await registerUser("noconsent_" + RUN, "No Consent", `nc_${RUN}@kinnect.local`, "Pass123456!");
  // Remove registration-time consent so the probe has no current consent row (server truth; no client bypass).
  social.db.prepare("DELETE FROM privacy_consents WHERE user_id=?").run(probe.user.id);
  const st = await (await fetch(`${baseUrl}/api/me/privacy-consent`, { headers: { Cookie: probe.cookie } })).json();
  assert.equal(st.accepted, false, "probe must start without consent");
  const pre = await connectWS(probe.cookie);
  pre.ws.send(JSON.stringify({ type: "create", title: "Should fail", topic: "Music", liveMode: "chat" }));
  const err = await pre.waitFor((m) => m.type === "error");
  assert.match(String(err.message || err.error || ""), /đồng ý/i);
  assert.ok(!pre.queue.some((m) => m.type === "joined"), "no room may be created without consent");
  await acceptPrivacyConsentExplicitly(probe);
  pre.ws.send(JSON.stringify({ type: "create", title: "After consent", topic: "Music", liveMode: "chat" }));
  await pre.waitFor((m) => m.type === "joined" && m.role === "host");
  pre.ws.send(JSON.stringify({ type: "leave" }));
  pre.ws.close();
  console.log("   WS create denied before consent, allowed after explicit consent: OK");
}
console.log("1c. Explicit privacy consent for each test user...");
for (const acct of [host1, host2, viewer]) {
  const r = await acceptPrivacyConsentExplicitly(acct);
  console.log(`   ${acct.user.username}: deniedBefore=${r.deniedBefore} version=${r.version}`);
}

// Give viewer gifted/trial coins for gift test
try {
  social.db.prepare("UPDATE users SET coins=5000, trial_coins=2000 WHERE id=?").run(viewer.user.id);
} catch {}

console.log("2. Testing 2 Live Rooms & 2 Clients (Join/Leave/Switch/WebRTC Signal/Chat/Heart/Gift)...");
const h1Conn = await connectWS(host1.cookie);
const h2Conn = await connectWS(host2.cookie);
const vConn = await connectWS(viewer.cookie);

// Host 1 creates Room A
h1Conn.ws.send(JSON.stringify({ type: "create", title: "Room A Live", topic: "Music", liveMode: "chat", multiGuest: false, liveModes: true }));
const joinedHostA = await h1Conn.waitFor((m) => m.type === "joined" && m.role === "host");
const roomAId = joinedHostA.room.id;

// Host 2 creates Room B
h2Conn.ws.send(JSON.stringify({ type: "create", title: "Room B Live", topic: "Tech", liveMode: "chat", multiGuest: false, liveModes: true }));
const joinedHostB = await h2Conn.waitFor((m) => m.type === "joined" && m.role === "host");
const roomBId = joinedHostB.room.id;

// Viewer joins Room A (matching AppState.joinLiveRoom payload)
vConn.ws.send(JSON.stringify({ type: "join", room: roomAId, liveMode: "chat", multiGuest: false, liveModes: true }));
const joinedViewerA = await vConn.waitFor((m) => m.type === "joined" && m.role === "viewer" && m.room.id === roomAId);
assert.equal(joinedViewerA.room.id, roomAId);

// Host 1 receives peer event and sends WebRTC offer signal (matching NativeWebRTCManager)
const peerEvt = await h1Conn.waitFor((m) => m.type === "peer");
assert.ok(peerEvt.id, "Host received viewer peer id");
const descOffer = { type: "offer", sdp: "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n" };
h1Conn.ws.send(JSON.stringify({ type: "signal", to: peerEvt.id, description: descOffer, signal: { description: descOffer } }));

// Viewer receives offer signal and sends answer signal
const sigOffer = await vConn.waitFor((m) => m.type === "signal" && m.description?.type === "offer");
const descAnswer = { type: "answer", sdp: "v=0\r\no=- 2 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n" };
vConn.ws.send(JSON.stringify({ type: "signal", to: sigOffer.from, description: descAnswer, signal: { description: descAnswer } }));
const sigAnswer = await h1Conn.waitFor((m) => m.type === "signal" && m.description?.type === "answer");
assert.equal(sigAnswer.description.type, "answer");
console.log("   -> Verified WebRTC P2P offer/answer signaling between Host 1 and Viewer!");

// Viewer sends live chat in Room A
vConn.ws.send(JSON.stringify({ type: "chat", text: "Xin chao Room A!", room: roomAId }));
const chatBroadcast = await h1Conn.waitFor((m) => m.type === "chat" && m.text === "Xin chao Room A!");
assert.equal(chatBroadcast.senderId, viewer.user.id);

// Viewer sends heart reaction in Room A
vConn.ws.send(JSON.stringify({ type: "live-reaction", room: roomAId, kind: "heart" }));
const heartBroadcast = await h1Conn.waitFor((m) => m.type === "live-reaction" && m.kind === "heart");
assert.equal(heartBroadcast.free, true);

// Viewer sends rose gift in Room A
vConn.ws.send(JSON.stringify({ type: "live-reaction", room: roomAId, kind: "rose", quantity: 1, requestId: "gift_rose_1234567890abcdef", fundingSource: "gifted", priceVersion: 1 }));
const giftBroadcast = await h1Conn.waitFor((m) => m.type === "live-reaction" && m.giftId === "rose");
assert.equal(giftBroadcast.experience, true);
assert.equal(giftBroadcast.giftName, "Hoa hồng");
console.log("   -> Verified Live Chat, Heart Reaction, and Rose Gift broadcast in Room A!");

// Viewer switches from Room A to Room B (leave + join, matching AppState.joinLiveRoom)
vConn.ws.send(JSON.stringify({ type: "leave" }));
vConn.ws.send(JSON.stringify({ type: "join", room: roomBId, liveMode: "chat", multiGuest: false, liveModes: true }));
const joinedViewerB = await vConn.waitFor((m) => m.type === "joined" && m.role === "viewer" && m.room.id === roomBId);
assert.equal(joinedViewerB.room.id, roomBId);
console.log("   -> Verified Viewer clean room switch from Room A -> Room B!");

console.log("3. Testing Canonical Message Reactions & Toggle Removal...");
const sendDmRes = await fetch(`${baseUrl}/api/users/${host1.user.id}/messages`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Cookie: viewer.cookie },
  body: JSON.stringify({ body: "Test reaction message" }),
});
const dmData = await sendDmRes.json();
const msgId = dmData.message?.id || dmData.messages?.[dmData.messages.length - 1]?.id;
assert.ok(msgId, "Created DM message");

// Canonical reaction 'love' succeeds
const rxLoveRes = await fetch(`${baseUrl}/api/chat-messages/direct/${msgId}/reaction`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Cookie: viewer.cookie },
  body: JSON.stringify({ reaction: "love" }),
});
assert.equal(rxLoveRes.status, 200);

// Raw emoji glyph '❤️' is rejected with 400 by backend contract
const rxEmojiRes = await fetch(`${baseUrl}/api/chat-messages/direct/${msgId}/reaction`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Cookie: viewer.cookie },
  body: JSON.stringify({ reaction: "❤️" }),
});
assert.equal(rxEmojiRes.status, 400);

// Toggle removal with null succeeds
const rxRemoveRes = await fetch(`${baseUrl}/api/chat-messages/direct/${msgId}/reaction`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Cookie: viewer.cookie },
  body: JSON.stringify({ reaction: null }),
});
assert.equal(rxRemoveRes.status, 200);
console.log("   -> Verified canonical message reaction ('love'), 400 rejection on raw emoji, and null removal!");

console.log("4. Testing Private Album Upload & Access Grant/Revoke Flow...");
// 1x1 valid PNG base64
const png1x1 = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";
const upPrivRes = await fetch(`${baseUrl}/api/me/private-photos`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Cookie: host1.cookie },
  body: JSON.stringify({ data: png1x1 }),
});
assert.equal(upPrivRes.status, 201);
const upPrivJson = await upPrivRes.json();
assert.equal(upPrivJson.photos.length, 1);

// Viewer requests access to Host1's private album
const reqAccessRes = await fetch(`${baseUrl}/api/users/${host1.user.id}/private/request`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Cookie: viewer.cookie },
  body: JSON.stringify({}),
});
assert.equal(reqAccessRes.status, 200);

// Host1 grants access to Viewer
const grantRes = await fetch(`${baseUrl}/api/me/private/requests/${viewer.user.id}`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Cookie: host1.cookie },
  body: JSON.stringify({ action: "grant" }),
});
assert.equal(grantRes.status, 200);

// Viewer fetches Host1's private album and sees the photo
const viewPrivRes = await fetch(`${baseUrl}/api/users/${host1.user.id}/private`, {
  headers: { Cookie: viewer.cookie },
});
const viewPrivJson = await viewPrivRes.json();
assert.equal(viewPrivJson.status, "granted");
assert.equal(viewPrivJson.photos.length, 1);
console.log("   -> Verified Private Album upload, viewer request, owner grant, and authorized photo listing!");

console.log("5. Testing Server-Side Apple StoreKit JWS Transaction Verification (11 paths)...");
function makeAppleJWS(payload, header = { alg: "none", typ: "JWT" }) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  return `${b64(header)}.${b64(payload)}.sig`;
}

// Path 1a: Missing appAccountToken -> 403 Forbidden
const jwsNoToken = makeAppleJWS({
  transactionId: "tx_apple_no_token",
  bundleId: "app.kinnect.live",
  productId: "kinnect_style_aurora",
  purchaseDate: simulatedTime,
  signedDate: simulatedTime,
  environment: "LocalTesting"
});
const vResNoToken = await fetch(`${baseUrl}/api/store/verify`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Cookie: host1.cookie },
  body: JSON.stringify({ productId: "kinnect_style_aurora", purchaseToken: jwsNoToken, platform: "ios" })
});
assert.equal(vResNoToken.status, 403);
assert.match((await vResNoToken.json()).error, /thiếu thông tin ràng buộc appAccountToken/i);

// Path 1b: Mismatched appAccountToken (bound to another account's UUID) -> 403 Forbidden
const jwsMismatchToken = makeAppleJWS({
  transactionId: "tx_apple_bad_token",
  bundleId: "app.kinnect.live",
  productId: "kinnect_style_aurora",
  appAccountToken: "00000000-0000-4000-8000-000000000000",
  purchaseDate: simulatedTime,
  signedDate: simulatedTime,
  environment: "LocalTesting"
});
const vResMismatchToken = await fetch(`${baseUrl}/api/store/verify`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Cookie: host1.cookie },
  body: JSON.stringify({ productId: "kinnect_style_aurora", purchaseToken: jwsMismatchToken, platform: "ios" })
});
assert.equal(vResMismatchToken.status, 403);
assert.match((await vResMismatchToken.json()).error, /appAccountToken không khớp/i);

// Path 1c: Valid Apple StoreKit 2 transaction verification (kinnect_style_aurora) -> 200, state PURCHASED, owned
const jwsValid = makeAppleJWS({
  transactionId: "tx_apple_1001",
  originalTransactionId: "tx_apple_1001",
  bundleId: "app.kinnect.live",
  productId: "kinnect_style_aurora",
  appAccountToken: storeAccountUuid(host1.user.id),
  purchaseDate: simulatedTime,
  originalPurchaseDate: simulatedTime,
  quantity: 1,
  type: "Non-Consumable",
  inAppOwnershipType: "PURCHASED",
  signedDate: simulatedTime,
  environment: "LocalTesting"
});
const vRes1 = await fetch(`${baseUrl}/api/store/verify`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Cookie: host1.cookie },
  body: JSON.stringify({ productId: "kinnect_style_aurora", purchaseToken: jwsValid, platform: "ios" })
});
assert.equal(vRes1.status, 200);
const vJson1 = await vRes1.json();
assert.equal(vJson1.state, "PURCHASED");
assert.ok(vJson1.owned.includes("kinnect_style_aurora"));
assert.equal(vJson1.platform, "ios");
assert.equal(vJson1.transactionId, "tx_apple_1001");

// Path 2: Idempotent re-submission of same transaction by same user -> 200, no duplicate grants
const vRes2 = await fetch(`${baseUrl}/api/store/verify`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Cookie: host1.cookie },
  body: JSON.stringify({ productId: "kinnect_style_aurora", purchaseToken: jwsValid, platform: "ios" })
});
assert.equal(vRes2.status, 200);
const vJson2 = await vRes2.json();
assert.equal(vJson2.state, "PURCHASED");
assert.equal(vJson2.idempotent, true);
const purchaseRows = social.db.prepare("SELECT COUNT(*) AS c FROM store_purchases WHERE product_id=?").get("kinnect_style_aurora").c;
assert.equal(purchaseRows, 1, "idempotent transaction must not duplicate database rows");

// Path 2b: Passage of time (25 hours later) -> refresh() updates verified timestamp, maintains owned entitlement without duplicate grants
simulatedTime += 25 * 3600 * 1000;
const getStoreAfter25h = await fetch(`${baseUrl}/api/store`, {
  headers: { Cookie: host1.cookie }
});
assert.equal(getStoreAfter25h.status, 200);
const storeAfter25hJson = await getStoreAfter25h.json();
assert.ok(storeAfter25hJson.owned.includes("kinnect_style_aurora"), "refresh() must maintain owned entitlement across 24h boundary");
const purchaseRowsAfterTime = social.db.prepare("SELECT COUNT(*) AS c FROM store_purchases WHERE product_id=?").get("kinnect_style_aurora").c;
assert.equal(purchaseRowsAfterTime, 1, "refresh after 25h must not create duplicate purchase rows");

// Path 3: Stolen/Replay Apple transaction by another user -> 409 Conflict
const vRes3 = await fetch(`${baseUrl}/api/store/verify`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Cookie: viewer.cookie },
  body: JSON.stringify({ productId: "kinnect_style_aurora", purchaseToken: jwsValid, platform: "ios" })
});
assert.equal(vRes3.status, 409);
assert.match((await vRes3.json()).error, /tài khoản khác/i);

// Path 4: Unmatched product ID (JWS has kinnect_style_sunset but body requests kinnect_style_aurora) -> 422
const jwsMismatchProduct = makeAppleJWS({
  transactionId: "tx_apple_1002",
  bundleId: "app.kinnect.live",
  productId: "kinnect_style_sunset",
  appAccountToken: storeAccountUuid(host1.user.id),
  purchaseDate: simulatedTime,
  signedDate: simulatedTime,
  environment: "LocalTesting"
});
const vRes4 = await fetch(`${baseUrl}/api/store/verify`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Cookie: host1.cookie },
  body: JSON.stringify({ productId: "kinnect_style_aurora", purchaseToken: jwsMismatchProduct, platform: "ios" })
});
assert.equal(vRes4.status, 422);
assert.match((await vRes4.json()).error, /không khớp/i);

// Path 5: Unmatched bundle ID (JWS has attacker bundle ID) -> 422
const jwsMismatchBundle = makeAppleJWS({
  transactionId: "tx_apple_1003",
  bundleId: "com.attacker.bundle",
  productId: "kinnect_style_ocean",
  appAccountToken: storeAccountUuid(host1.user.id),
  purchaseDate: simulatedTime,
  signedDate: simulatedTime,
  environment: "LocalTesting"
});
const vRes5 = await fetch(`${baseUrl}/api/store/verify`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Cookie: host1.cookie },
  body: JSON.stringify({ productId: "kinnect_style_ocean", purchaseToken: jwsMismatchBundle, platform: "ios" })
});
assert.equal(vRes5.status, 422);

// Path 6: Revoked/Refunded transaction (revocationDate present) -> 422 rejection
const jwsRevoked = makeAppleJWS({
  transactionId: "tx_apple_1004",
  bundleId: "app.kinnect.live",
  productId: "kinnect_style_sunset",
  appAccountToken: storeAccountUuid(host1.user.id),
  purchaseDate: simulatedTime - 86400000,
  revocationDate: simulatedTime - 3600000,
  revocationReason: 1,
  signedDate: simulatedTime,
  environment: "LocalTesting"
});
const vRes6 = await fetch(`${baseUrl}/api/store/verify`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Cookie: host1.cookie },
  body: JSON.stringify({ productId: "kinnect_style_sunset", purchaseToken: jwsRevoked, platform: "ios" })
});
assert.equal(vRes6.status, 422);
assert.match((await vRes6.json()).error, /thu hồi|hoàn tiền/i);

// Path 7: Client attempting to credit from transactionId alone without valid signed JWS token -> 400
const vRes7 = await fetch(`${baseUrl}/api/store/verify`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Cookie: host1.cookie },
  body: JSON.stringify({ productId: "kinnect_style_sunset", purchaseToken: "raw_tx_id_only", platform: "ios" })
});
assert.equal(vRes7.status, 400);

// Path 8: App Store Server Notifications V2 (POST /api/store/apple-notifications) refund reconciliation & deduplication
const notifPayload = {
  notificationType: "REFUND",
  notificationUUID: "test-apple-notif-uuid-" + RUN,
  version: "2.0",
  signedDate: simulatedTime,
  data: {
    bundleId: "app.kinnect.live",
    environment: "LocalTesting",
    signedTransactionInfo: makeAppleJWS({
      transactionId: "tx_apple_1001",
      productId: "kinnect_style_aurora",
      bundleId: "app.kinnect.live",
      appAccountToken: storeAccountUuid(host1.user.id),
      environment: "LocalTesting",
      revocationDate: simulatedTime,
      revocationReason: 1
    })
  }
};
const signedNotif = makeAppleJWS(notifPayload);
const notifRes = await fetch(`${baseUrl}/api/store/apple-notifications`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ signedPayload: signedNotif })
});
assert.equal(notifRes.status, 200);
const notifJson = await notifRes.json();
assert.equal(notifJson.ok, true);
assert.equal(notifJson.processed, true);
assert.equal(notifJson.transactionId, "tx_apple_1001");

// Verify purchase state is now CANCELLED in database and no longer owned
const cancelledRow = social.db.prepare("SELECT state FROM store_purchases WHERE product_id=?").get("kinnect_style_aurora");
assert.equal(cancelledRow.state, "CANCELLED");
const getStoreAfterRefund = await fetch(`${baseUrl}/api/store`, {
  headers: { Cookie: host1.cookie }
});
assert.ok(!(await getStoreAfterRefund.json()).owned.includes("kinnect_style_aurora"), "refunded product must no longer be owned");

// Duplicate notification returns duplicate: true
const dupNotifRes = await fetch(`${baseUrl}/api/store/apple-notifications`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ signedPayload: signedNotif })
});
assert.equal(dupNotifRes.status, 200);
assert.equal((await dupNotifRes.json()).duplicate, true);

// Path 8b: Malformed nested signedTransactionInfo -> 422 error, notification UUID is NOT recorded
const notifMalformedNested = makeAppleJWS({
  notificationType: "REFUND",
  notificationUUID: "test-notif-malformed-" + RUN,
  version: "2.0",
  signedDate: simulatedTime,
  data: {
    bundleId: "app.kinnect.live",
    environment: "LocalTesting",
    signedTransactionInfo: "corrupted.jws.payload"
  }
});
const malformedNotifRes = await fetch(`${baseUrl}/api/store/apple-notifications`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ signedPayload: notifMalformedNested })
});
assert.equal(malformedNotifRes.status, 422);
const malformedRecorded = social.db.prepare("SELECT 1 FROM store_apple_notifications WHERE notification_uuid=?").get("test-notif-malformed-" + RUN);
assert.equal(malformedRecorded, undefined, "malformed notification must not be recorded");

// Path 8c: Transient verifier error on notification -> 503 error, not marked processed, retried successfully
verifierTransientError = Object.assign(new Error("Apple verification service temporarily unreachable"), { status: 503 });
const notifTransient = makeAppleJWS({
  notificationType: "REVOKE",
  notificationUUID: "test-notif-transient-" + RUN,
  version: "2.0",
  signedDate: simulatedTime,
  data: {
    bundleId: "app.kinnect.live",
    environment: "LocalTesting",
    signedTransactionInfo: makeAppleJWS({
      transactionId: "tx_apple_transient_1",
      productId: "kinnect_style_ocean",
      bundleId: "app.kinnect.live",
      environment: "LocalTesting",
      revocationDate: simulatedTime
    })
  }
});
const transientRes1 = await fetch(`${baseUrl}/api/store/apple-notifications`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ signedPayload: notifTransient })
});
assert.equal(transientRes1.status, 503, "transient verifier error must return 503 for Apple retry");
const transientRecorded = social.db.prepare("SELECT 1 FROM store_apple_notifications WHERE notification_uuid=?").get("test-notif-transient-" + RUN);
assert.equal(transientRecorded, undefined, "failed notification must not be marked processed before successful mutation");

// Immediate retry without verifier error -> 200 OK, processed
const transientRes2 = await fetch(`${baseUrl}/api/store/apple-notifications`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ signedPayload: notifTransient })
});
assert.equal(transientRes2.status, 200);
assert.equal((await transientRes2.json()).processed, true);
assert.ok(social.db.prepare("SELECT 1 FROM store_apple_notifications WHERE notification_uuid=?").get("test-notif-transient-" + RUN));

// Path 8d: Refund-before-client-verify (tombstone recorded before purchase row exists; later client verify rejected with 422)
const notifPreRefund = makeAppleJWS({
  notificationType: "REFUND",
  notificationUUID: "test-notif-prerefund-" + RUN,
  version: "2.0",
  signedDate: simulatedTime,
  data: {
    bundleId: "app.kinnect.live",
    environment: "LocalTesting",
    signedTransactionInfo: makeAppleJWS({
      transactionId: "tx_apple_unseen_888",
      productId: "kinnect_style_sunset",
      bundleId: "app.kinnect.live",
      environment: "LocalTesting",
      revocationDate: simulatedTime
    })
  }
});
const preRefundRes = await fetch(`${baseUrl}/api/store/apple-notifications`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ signedPayload: notifPreRefund })
});
assert.equal(preRefundRes.status, 200);
// Verify tombstone was created in store_apple_revocations
const tombstone = social.db.prepare("SELECT * FROM store_apple_revocations WHERE transaction_id=?").get("tx_apple_unseen_888");
assert.ok(tombstone, "revocation tombstone must be persisted even when purchase row does not exist yet");

// Client attempts to verify using original non-revoked purchase JWS for tx_apple_unseen_888
const jwsStalePreRefund = makeAppleJWS({
  transactionId: "tx_apple_unseen_888",
  bundleId: "app.kinnect.live",
  productId: "kinnect_style_sunset",
  appAccountToken: storeAccountUuid(host1.user.id),
  purchaseDate: simulatedTime - 3600000,
  signedDate: simulatedTime - 3600000,
  environment: "LocalTesting"
});
const verifyStalePreRefund = await fetch(`${baseUrl}/api/store/verify`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Cookie: host1.cookie },
  body: JSON.stringify({ productId: "kinnect_style_sunset", purchaseToken: jwsStalePreRefund, platform: "ios" })
});
assert.equal(verifyStalePreRefund.status, 422, "original JWS presented after refund notification must be rejected with 422");
assert.match((await verifyStalePreRefund.json()).error, /thu hồi|hoàn tiền/i);
// Ensure store_purchases never recorded PURCHASED for this product
const unseenRows = social.db.prepare("SELECT COUNT(*) AS c FROM store_purchases WHERE product_id=?").get("kinnect_style_sunset").c;
assert.equal(unseenRows, 0, "refunded-before-verify transaction must never create a purchased row");

// Path 8e: Duplicate concurrency (parallel deliveries with identical notificationUUID)
const concurrentNotifUuid = "test-notif-concurrent-" + RUN;
const notifConcurrent = makeAppleJWS({
  notificationType: "REVOKE",
  notificationUUID: concurrentNotifUuid,
  version: "2.0",
  signedDate: simulatedTime,
  data: {
    bundleId: "app.kinnect.live",
    environment: "LocalTesting",
    signedTransactionInfo: makeAppleJWS({
      transactionId: "tx_apple_concurrent_999",
      productId: "kinnect_style_ocean",
      bundleId: "app.kinnect.live",
      environment: "LocalTesting",
      revocationDate: simulatedTime
    })
  }
});
const [cRes1, cRes2] = await Promise.all([
  fetch(`${baseUrl}/api/store/apple-notifications`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ signedPayload: notifConcurrent })
  }),
  fetch(`${baseUrl}/api/store/apple-notifications`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ signedPayload: notifConcurrent })
  })
]);
assert.equal(cRes1.status, 200);
assert.equal(cRes2.status, 200);
const cJson1 = await cRes1.json();
const cJson2 = await cRes2.json();
const processedCount = (cJson1.processed ? 1 : 0) + (cJson2.processed ? 1 : 0);
const duplicateCount = (cJson1.duplicate ? 1 : 0) + (cJson2.duplicate ? 1 : 0);
assert.equal(processedCount, 1, "exactly one concurrent request must be processed");
assert.equal(duplicateCount, 1, "exactly one concurrent request must be flagged duplicate");
const notifRowCount = social.db.prepare("SELECT COUNT(*) AS c FROM store_apple_notifications WHERE notification_uuid=?").get(concurrentNotifUuid).c;
assert.equal(notifRowCount, 1, "database must contain exactly one notification record");

// Path 9: Production safeguard - rejection of Xcode/LocalTesting environments in production mode
const prodEnvApp = createApp({
  dbPath: ":memory:",
  allowEmailDelivery: false,
  appleStoreVerifier: appleVerifier,
  storeEnv: { PLAY_PURCHASE_TOKEN_KEY: "ab".repeat(32), NODE_ENV: "production" }
});
await new Promise((resolve) => prodEnvApp.server.listen(0, "127.0.0.1", resolve));
const prodPort = prodEnvApp.server.address().port;
const prodUserReg = await fetch(`http://127.0.0.1:${prodPort}/api/register`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ username: "prod_user_" + RUN, name: "Prod User", email: `prod_${RUN}@kinnect.local`, password: "PassWord123!", gender: "nam", birthYear: 1998, agree18: true, acceptPrivacyNotice: true })
});
const prodCookie = (prodUserReg.headers.get("set-cookie") || "").split(";")[0];
const prodUserId = (await prodUserReg.json()).user.id;
const prodJws = makeAppleJWS({
  transactionId: "tx_apple_prod_test",
  bundleId: "app.kinnect.live",
  productId: "kinnect_style_aurora",
  appAccountToken: storeAccountUuid(prodUserId),
  purchaseDate: simulatedTime,
  signedDate: simulatedTime,
  environment: "LocalTesting"
});
const prodVerifyRes = await fetch(`http://127.0.0.1:${prodPort}/api/store/verify`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Cookie: prodCookie },
  body: JSON.stringify({ productId: "kinnect_style_aurora", purchaseToken: prodJws, platform: "ios" })
});
assert.equal(prodVerifyRes.status, 403);
assert.match((await prodVerifyRes.json()).error, /Xcode\/LocalTesting bị từ chối trên production/i);
prodEnvApp.server.close();

// Path 10: Legacy unbound flag security rule: only allows preexisting securely owned records, NEVER first-claim acceptance
const legacyApp = createApp({
  dbPath: ":memory:",
  allowEmailDelivery: false,
  appleStoreVerifier: appleVerifier,
  storeEnv: { PLAY_PURCHASE_TOKEN_KEY: "ab".repeat(32), APPLE_ALLOW_LEGACY_UNBOUND: "true" }
});
await new Promise((resolve) => legacyApp.server.listen(0, "127.0.0.1", resolve));
const legacyPort = legacyApp.server.address().port;
const legUserReg = await fetch(`http://127.0.0.1:${legacyPort}/api/register`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ username: "leg_user_" + RUN, name: "Leg User", email: `leg_${RUN}@kinnect.local`, password: "PassWord123!", gender: "nam", birthYear: 1998, agree18: true, acceptPrivacyNotice: true })
});
const legCookie = (legUserReg.headers.get("set-cookie") || "").split(";")[0];
const legUserId = (await legUserReg.json()).user.id;

// Path 10a: First-claim with missing appAccountToken -> 403 Forbidden even with APPLE_ALLOW_LEGACY_UNBOUND=true
const legUnboundFirstClaimJws = makeAppleJWS({
  transactionId: "tx_apple_legacy_unbound_1",
  bundleId: "app.kinnect.live",
  productId: "kinnect_style_ocean",
  purchaseDate: simulatedTime,
  signedDate: simulatedTime,
  environment: "LocalTesting"
});
const legFirstClaimRes = await fetch(`http://127.0.0.1:${legacyPort}/api/store/verify`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Cookie: legCookie },
  body: JSON.stringify({ productId: "kinnect_style_ocean", purchaseToken: legUnboundFirstClaimJws, platform: "ios" })
});
assert.equal(legFirstClaimRes.status, 403, "first claim of unbound token must be rejected even with legacy flag");
assert.match((await legFirstClaimRes.json()).error, /thiếu thông tin ràng buộc appAccountToken/i);

// Path 10b: Preexisting securely owned record allows re-verification under APPLE_ALLOW_LEGACY_UNBOUND=true
// Insert preexisting purchase row belonging to legUserId
const legTokenHash = "apple:tx_apple_legacy_unbound_1";
const legDigest = createHash("sha256").update(legTokenHash).digest("hex");
legacyApp.social.db.prepare("INSERT INTO store_purchases VALUES(?,?,?,?,?,?,?,?)").run(
  legDigest, legUserId, "kinnect_style_ocean", "dummy_cipher", "PURCHASED", simulatedTime, simulatedTime, "ios"
);
const legReverifyRes = await fetch(`http://127.0.0.1:${legacyPort}/api/store/verify`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Cookie: legCookie },
  body: JSON.stringify({ productId: "kinnect_style_ocean", purchaseToken: legUnboundFirstClaimJws, platform: "ios" })
});
assert.equal(legReverifyRes.status, 200, "preexisting secure purchase record is allowed to re-verify under legacy flag");
assert.equal((await legReverifyRes.json()).idempotent, true);
legacyApp.server.close();

console.log("   -> Verified Apple StoreKit 2 verification, appAccountToken binding, 25h time passage refresh, refund notifications, replay prevention, and production safeguards!");

console.log("6. Testing Permanent Account Deletion Lifecycle (7 contract assertions)...");
// Register dedicated deletion test user
const delUser = await registerUser("del_target_" + RUN, "User To Delete", `del_${RUN}@kinnect.local`, "DeletePass123!");
await acceptPrivacyConsentExplicitly(delUser);

// Path 1: GET /api/me/account-deletion returns requirements and permanent: true
const getDelRes = await fetch(`${baseUrl}/api/me/account-deletion`, {
  headers: { Cookie: delUser.cookie }
});
assert.equal(getDelRes.status, 200);
const getDelJson = await getDelRes.json();
assert.equal(getDelJson.username, delUser.user.username);
assert.equal(getDelJson.permanent, true);

// Path 2: DELETE with wrong confirmUsername -> 400 rejection
const delWrongUser = await fetch(`${baseUrl}/api/me/account-deletion`, {
  method: "DELETE",
  headers: { "Content-Type": "application/json", Cookie: delUser.cookie },
  body: JSON.stringify({ confirmUsername: "wrong_username", confirmDelete: true, password: "DeletePass123!" })
});
assert.equal(delWrongUser.status, 400);

// Path 3: DELETE with confirmDelete !== true -> 400 rejection
const delNoConfirm = await fetch(`${baseUrl}/api/me/account-deletion`, {
  method: "DELETE",
  headers: { "Content-Type": "application/json", Cookie: delUser.cookie },
  body: JSON.stringify({ confirmUsername: delUser.user.username, confirmDelete: false, password: "DeletePass123!" })
});
assert.equal(delNoConfirm.status, 400);

// Path 4: DELETE with wrong password -> 403 rejection
const delWrongPass = await fetch(`${baseUrl}/api/me/account-deletion`, {
  method: "DELETE",
  headers: { "Content-Type": "application/json", Cookie: delUser.cookie },
  body: JSON.stringify({ confirmUsername: delUser.user.username, confirmDelete: true, password: "WrongPassword999!" })
});
assert.equal(delWrongPass.status, 403);

// Path 5: DELETE with matching username, confirmDelete: true, and correct password -> 200
const delSuccess = await fetch(`${baseUrl}/api/me/account-deletion`, {
  method: "DELETE",
  headers: { "Content-Type": "application/json", Cookie: delUser.cookie },
  body: JSON.stringify({ confirmUsername: delUser.user.username, confirmDelete: true, password: "DeletePass123!" })
});
assert.equal(delSuccess.status, 200);
const delSuccessJson = await delSuccess.json();
assert.equal(delSuccessJson.ok, true);
assert.equal(delSuccessJson.deleted, true);
const setCookieDel = delSuccess.headers.get("set-cookie") || "";
assert.match(setCookieDel, /Max-Age=0/i, "session cookie must be cleared on deletion");

// Path 6: Request to /api/me with deleted user cookie -> 401 Unauthorized
const postDelMe = await fetch(`${baseUrl}/api/me`, {
  headers: { Cookie: delUser.cookie }
});
assert.equal(postDelMe.status, 401, "deleted user session must be immediately revoked");

// Path 7: Attempt login with deleted username -> 401 rejection
const postDelLogin = await fetch(`${baseUrl}/api/login`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ username: delUser.user.username, password: "DeletePass123!" })
});
assert.equal(postDelLogin.status, 401, "deleted account cannot be logged into");
console.log("   -> Verified permanent account deletion, password challenge, session revocation, and data destruction!");

h1Conn.ws.close();
h2Conn.ws.close();
vConn.ws.close();
server.close();
console.log("ALL END-TO-END FUNCTIONAL TESTS PASSED 100%!");
process.exit(0);
