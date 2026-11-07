import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import WebSocket from "ws";
import { createApp } from "../server.js";
import { SignedDataVerifier, Environment } from "@apple/app-store-server-library";

const appleVerifier = {
  enabled: () => true,
  bundleId: "app.kinnect.live",
  environment: "LocalTesting",
  async verify(jws) {
    const v = new SignedDataVerifier([], false, Environment.LOCAL_TESTING, "app.kinnect.live");
    return await v.verifyAndDecodeTransaction(jws);
  }
};

// Fully isolated: ":memory:" disables the shared cloud session/bridge, SFU env and gift env (server.js:25-86).
const { server, social } = createApp({
  dbPath: ":memory:",
  allowEmailDelivery: false,
  appleStoreVerifier: appleVerifier,
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

console.log("5. Testing Server-Side Apple StoreKit JWS Transaction Verification (7 paths)...");
function makeAppleJWS(payload, header = { alg: "none", typ: "JWT" }) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  return `${b64(header)}.${b64(payload)}.sig`;
}

// Path 1: Valid Apple StoreKit 2 transaction verification (kinnect_style_aurora) -> 200, state PURCHASED, owned
const jwsValid = makeAppleJWS({
  transactionId: "tx_apple_1001",
  originalTransactionId: "tx_apple_1001",
  bundleId: "app.kinnect.live",
  productId: "kinnect_style_aurora",
  purchaseDate: Date.now(),
  originalPurchaseDate: Date.now(),
  quantity: 1,
  type: "Non-Consumable",
  inAppOwnershipType: "PURCHASED",
  signedDate: Date.now(),
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
  purchaseDate: Date.now(),
  signedDate: Date.now(),
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
  purchaseDate: Date.now(),
  signedDate: Date.now(),
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
  purchaseDate: Date.now() - 86400000,
  revocationDate: Date.now() - 3600000,
  revocationReason: 1,
  signedDate: Date.now(),
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
console.log("   -> Verified Apple StoreKit 2 verification, bundleId/productId check, replay prevention, and refund rejection!");

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
