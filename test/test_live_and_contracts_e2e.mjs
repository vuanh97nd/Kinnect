import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import WebSocket from "ws";
import { createApp } from "../server.js";

const tmp = mkdtempSync(join(tmpdir(), "kinnect-ios-e2e-"));
const dbPath = join(tmp, "test.sqlite");
// Fully isolated: ":memory:" disables the shared cloud session/bridge, SFU env and gift env (server.js:25-86).
const { server, social } = createApp({ dbPath: ":memory:", allowEmailDelivery: false });
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

h1Conn.ws.close();
h2Conn.ws.close();
vConn.ws.close();
server.close();
console.log("ALL END-TO-END FUNCTIONAL TESTS PASSED 100%!");
process.exit(0);
