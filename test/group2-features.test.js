import test from "node:test";
import assert from "node:assert/strict";
import { WebSocket } from "ws";
import { createApp } from "../server.js";
import { computeTotp } from "../lib/two-factor.js";

function cookieOf(res) {
  const set = res.headers.getSetCookie ? res.headers.getSetCookie() : [];
  return set.map((c) => c.split(";")[0]).filter((c) => c.startsWith("kinnect_session="))[0] || "";
}

async function api(base, path, { method = "GET", body, cookie } = {}) {
  const res = await fetch(base + path, {
    method,
    headers: {
      ...(body !== undefined ? { "Content-Type": "application/json" } : {}),
      ...(cookie ? { Cookie: cookie } : {}),
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {}
  return { status: res.status, json, cookie: cookieOf(res), headers: res.headers };
}

async function registerUser(base, username, name) {
  const r = await api(base, "/api/register", {
    method: "POST",
    body: { username, password: "password123", name, agree18: true, acceptPrivacyNotice: true },
  });
  assert.equal(r.status, 200, "register " + username);
  return { user: r.json.user, cookie: r.cookie };
}

function connectWs(base, cookie) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(base.replace("http://", "ws://") + "/ws", { headers: { Cookie: cookie } });
    const queue = [];
    const waiters = [];
    ws.on("message", (raw) => {
      const msg = JSON.parse(raw.toString());
      const idx = waiters.findIndex((w) => w.pred(msg));
      if (idx >= 0) {
        const [w] = waiters.splice(idx, 1);
        clearTimeout(w.timer);
        w.resolve(msg);
      } else {
        queue.push(msg);
      }
    });
    ws.nextMessage = (pred, timeoutMs = 4000) => {
      const idx = queue.findIndex(pred);
      if (idx >= 0) return Promise.resolve(queue.splice(idx, 1)[0]);
      return new Promise((res, rej) => {
        const timer = setTimeout(() => rej(new Error("WS wait timeout")), timeoutMs);
        waiters.push({ pred, resolve: res, timer });
      });
    };
    ws.once("open", () => resolve(ws));
    ws.once("error", reject);
  });
}

test("Group 2: 2FA/TOTP setup, login gate, recovery code, and disable", async () => {
  const { server, social } = createApp({ dbPath: ":memory:" });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const base = "http://127.0.0.1:" + server.address().port;
  try {
    const alice = await registerUser(base, "alice_2fa", "Alice");

    const st0 = await api(base, "/api/me/2fa", { cookie: alice.cookie });
    assert.equal(st0.status, 200);
    assert.equal(st0.json.enabled, false);

    // Wrong password rejected
    const badSetup = await api(base, "/api/me/2fa/setup", { method: "POST", cookie: alice.cookie, body: { password: "wrong" } });
    assert.equal(badSetup.status, 401);

    // Start setup
    const setup = await api(base, "/api/me/2fa/setup", { method: "POST", cookie: alice.cookie, body: { password: "password123" } });
    assert.equal(setup.status, 200);
    assert.ok(setup.json.secret.length >= 16);
    assert.ok(setup.json.otpauthUri.startsWith("otpauth://totp/"));
    assert.equal(setup.json.backupCodes.length, 8);

    // Enable with wrong code fails
    const badEnable = await api(base, "/api/me/2fa/enable", { method: "POST", cookie: alice.cookie, body: { code: "000000" } });
    assert.equal(badEnable.status, 400);

    // Enable with valid TOTP succeeds
    const validCode = computeTotp(setup.json.secret);
    const enabled = await api(base, "/api/me/2fa/enable", { method: "POST", cookie: alice.cookie, body: { code: validCode } });
    assert.equal(enabled.status, 200);
    assert.equal(enabled.json.enabled, true);

    // Login without totpCode returns 403 requires2fa and NO session cookie
    const noCodeLogin = await api(base, "/api/login", { method: "POST", body: { username: "alice_2fa", password: "password123" } });
    assert.equal(noCodeLogin.status, 403);
    assert.equal(noCodeLogin.json.requires2fa, true);
    assert.equal(noCodeLogin.cookie, "");

    // Login with valid TOTP succeeds
    const okLogin = await api(base, "/api/login", { method: "POST", body: { username: "alice_2fa", password: "password123", totpCode: computeTotp(setup.json.secret) } });
    assert.equal(okLogin.status, 200);
    assert.equal(okLogin.json.user.twoFactorEnabled, true);
    assert.ok(okLogin.cookie.startsWith("kinnect_session="));

    // Login with one-time backup code succeeds once, then fails on reuse
    const backup = setup.json.backupCodes[0];
    const backupLogin1 = await api(base, "/api/login", { method: "POST", body: { username: "alice_2fa", password: "password123", totpCode: backup } });
    assert.equal(backupLogin1.status, 200);
    const backupLogin2 = await api(base, "/api/login", { method: "POST", body: { username: "alice_2fa", password: "password123", totpCode: backup } });
    assert.equal(backupLogin2.status, 401);

    // Disable 2FA
    const dis = await api(base, "/api/me/2fa/disable", {
      method: "POST",
      cookie: alice.cookie,
      body: { password: "password123", code: computeTotp(setup.json.secret) },
    });
    assert.equal(dis.status, 200);
    assert.equal(dis.json.enabled, false);

    // Plain login works again
    const plain = await api(base, "/api/login", { method: "POST", body: { username: "alice_2fa", password: "password123" } });
    assert.equal(plain.status, 200);
  } finally {
    social.close();
    server.close();
  }
});

test("Group 2: Edit sent direct & group chat messages (including iOS PATCH alias) and permissions", async () => {
  const { server, social } = createApp({ dbPath: ":memory:" });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const base = "http://127.0.0.1:" + server.address().port;
  try {
    const alice = await registerUser(base, "alice_ed", "Alice");
    const bob = await registerUser(base, "bob_ed", "Bob");

    // Direct message
    const sent = await api(base, `/api/users/${bob.user.id}/messages`, {
      method: "POST",
      cookie: alice.cookie,
      body: { body: "Xin chao ban" },
    });
    assert.equal(sent.status, 201);
    const msgId = sent.json.message.id;

    // Bob cannot edit Alice's message
    const forbidden = await api(base, `/api/chat-messages/direct/${msgId}`, {
      method: "PATCH",
      cookie: bob.cookie,
      body: { body: "Hack" },
    });
    assert.equal(forbidden.status, 403);

    // Alice edits via canonical route
    const edited = await api(base, `/api/chat-messages/direct/${msgId}`, {
      method: "PATCH",
      cookie: alice.cookie,
      body: { body: "Xin chào bạn nhé!" },
    });
    assert.equal(edited.status, 200);
    assert.equal(edited.json.message.body, "Xin chào bạn nhé!");
    assert.ok(edited.json.message.editedAt > 0);

    // Alice edits via iOS alias route PATCH /api/users/:peerId/messages/:msgId
    const editedIos = await api(base, `/api/users/${bob.user.id}/messages/${msgId}`, {
      method: "PATCH",
      cookie: alice.cookie,
      body: { body: "Nội dung đã cập nhật lần 2" },
    });
    assert.equal(editedIos.status, 200);
    assert.equal(editedIos.json.message.body, "Nội dung đã cập nhật lần 2");

    // Verify GET thread returns edited body & editedAt
    const thread = await api(base, `/api/users/${alice.user.id}/messages`, { cookie: bob.cookie });
    assert.equal(thread.json.messages[0].body, "Nội dung đã cập nhật lần 2");
    assert.ok(thread.json.messages[0].editedAt > 0);

    // Group message edit
    const grp = await api(base, "/api/groups", { method: "POST", cookie: alice.cookie, body: { name: "Nhóm thử", members: [bob.user.id] } });
    const gid = grp.json.group.id;
    const gSent = await api(base, `/api/groups/${gid}/messages`, { method: "POST", cookie: alice.cookie, body: { body: "Tin nhóm gốc" } });
    const gMid = gSent.json.message.id;
    const gEdited = await api(base, `/api/groups/${gid}/messages/${gMid}`, { method: "PATCH", cookie: alice.cookie, body: { body: "Tin nhóm đã sửa" } });
    assert.equal(gEdited.status, 200);
    assert.equal(gEdited.json.message.body, "Tin nhóm đã sửa");
    assert.ok(gEdited.json.message.editedAt > 0);
  } finally {
    social.close();
    server.close();
  }
});

test("Group 2: Group polls (create, single/multi vote, close, delete, permissions) & account deletion", async () => {
  const { server, social } = createApp({ dbPath: ":memory:" });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const base = "http://127.0.0.1:" + server.address().port;
  try {
    const alice = await registerUser(base, "alice_pl", "Alice");
    const bob = await registerUser(base, "bob_pl", "Bob");
    const outsider = await registerUser(base, "out_pl", "Outsider");

    const grp = await api(base, "/api/groups", { method: "POST", cookie: alice.cookie, body: { name: "Đi chơi", members: [bob.user.id] } });
    const gid = grp.json.group.id;

    // Outsider denied
    const deny = await api(base, `/api/groups/${gid}/polls`, { cookie: outsider.cookie });
    assert.equal(deny.status, 404);

    // Create single-choice poll
    const created = await api(base, `/api/groups/${gid}/polls`, {
      method: "POST",
      cookie: alice.cookie,
      body: { question: "Cuối tuần đi đâu?", options: ["Đà Lạt", "Vũng Tàu", "Phú Quốc"], multiple: false },
    });
    assert.equal(created.status, 201);
    const poll = created.json.poll;
    assert.equal(poll.options.length, 3);

    // Multi-vote rejected on single-choice poll
    const badVote = await api(base, `/api/groups/${gid}/polls/${poll.id}/vote`, {
      method: "POST",
      cookie: bob.cookie,
      body: { optionIds: [poll.options[0].id, poll.options[1].id] },
    });
    assert.equal(badVote.status, 400);

    // Bob votes option 0, Alice votes option 1
    const vBob = await api(base, `/api/groups/${gid}/polls/${poll.id}/vote`, {
      method: "POST",
      cookie: bob.cookie,
      body: { optionId: poll.options[0].id },
    });
    assert.equal(vBob.status, 200);
    assert.equal(vBob.json.poll.totalVoters, 1);

    const vAlice = await api(base, `/api/groups/${gid}/polls/${poll.id}/vote`, {
      method: "POST",
      cookie: alice.cookie,
      body: { optionId: poll.options[1].id },
    });
    assert.equal(vAlice.json.poll.totalVoters, 2);

    // Bob (regular member, not creator) cannot close Alice's poll
    const bobClose = await api(base, `/api/groups/${gid}/polls/${poll.id}/close`, { method: "POST", cookie: bob.cookie, body: {} });
    assert.equal(bobClose.status, 403);

    // Alice closes poll; further votes fail
    const closed = await api(base, `/api/groups/${gid}/polls/${poll.id}/close`, { method: "POST", cookie: alice.cookie, body: {} });
    assert.equal(closed.status, 200);
    assert.equal(closed.json.poll.closed, true);

    const lateVote = await api(base, `/api/groups/${gid}/polls/${poll.id}/vote`, {
      method: "POST",
      cookie: bob.cookie,
      body: { optionId: poll.options[2].id },
    });
    assert.equal(lateVote.status, 400);

    // Hard delete Alice's account cleanly purges polls without FK violation
    const del = await api(base, "/api/me/account-deletion", {
      method: "DELETE",
      cookie: alice.cookie,
      body: { confirmUsername: "alice_pl", confirmDelete: true },
    });
    assert.equal(del.status, 200);
    assert.deepEqual(social.db.prepare("PRAGMA foreign_key_check").all(), []);
  } finally {
    social.close();
    server.close();
  }
});

test("Group 2: Group voice/video call WS signaling lifecycle and membership guard", async () => {
  const { server, wss, social } = createApp({ dbPath: ":memory:" });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const base = "http://127.0.0.1:" + server.address().port;
  let wsAlice, wsBob, wsOut;
  try {
    const alice = await registerUser(base, "alice_gc", "Alice");
    const bob = await registerUser(base, "bob_gc", "Bob");
    const outsider = await registerUser(base, "out_gc", "Outsider");

    const grp = await api(base, "/api/groups", { method: "POST", cookie: alice.cookie, body: { name: "Call Team", members: [bob.user.id] } });
    const gid = grp.json.group.id;

    // Initial REST status inactive
    const st0 = await api(base, `/api/groups/${gid}/call`, { cookie: alice.cookie });
    assert.equal(st0.status, 200);
    assert.equal(st0.json.active, false);

    // Outsider REST denied
    const stOut = await api(base, `/api/groups/${gid}/call`, { cookie: outsider.cookie });
    assert.equal(stOut.status, 404);

    wsAlice = await connectWs(base, alice.cookie);
    wsBob = await connectWs(base, bob.cookie);
    wsOut = await connectWs(base, outsider.cookie);
    await wsAlice.nextMessage((m) => m.type === "welcome");
    await wsBob.nextMessage((m) => m.type === "welcome");
    await wsOut.nextMessage((m) => m.type === "welcome");

    // Outsider cannot join group call
    wsOut.send(JSON.stringify({ type: "group-call-join", groupId: gid, mode: "audio" }));
    const errMsg = await wsOut.nextMessage((m) => m.type === "group-call-error");
    assert.ok(errMsg.message.includes("không phải thành viên"));

    // Alice joins audio call
    wsAlice.send(JSON.stringify({ type: "group-call-join", groupId: gid, mode: "audio" }));
    const aJoined = await wsAlice.nextMessage((m) => m.type === "group-call-joined");
    assert.equal(aJoined.groupId, gid);
    assert.equal(aJoined.participants.length, 1);

    // Bob receives live group-call-state notification
    const bState = await wsBob.nextMessage((m) => m.type === "group-call-state" && m.active === true);
    assert.equal(bState.participants.length, 1);

    // Bob joins video call (upgrades room mode and receives Alice as peer to offer)
    wsBob.send(JSON.stringify({ type: "group-call-join", groupId: gid, mode: "video" }));
    const bJoined = await wsBob.nextMessage((m) => m.type === "group-call-joined");
    assert.equal(bJoined.mode, "video");
    assert.deepEqual(bJoined.peers, [aJoined.selfId]);

    // Bob relays SDP offer to Alice
    wsBob.send(JSON.stringify({ type: "group-call-signal", groupId: gid, to: aJoined.selfId, description: { type: "offer", sdp: "v=0\r\n" } }));
    const sig = await wsAlice.nextMessage((m) => m.type === "group-call-signal");
    assert.equal(sig.from, bJoined.selfId);
    assert.equal(sig.description.type, "offer");

    // REST status shows 2 participants
    const st1 = await api(base, `/api/groups/${gid}/call`, { cookie: alice.cookie });
    assert.equal(st1.json.active, true);
    assert.equal(st1.json.participants.length, 2);

    // Bob leaves, Alice notified
    wsBob.send(JSON.stringify({ type: "group-call-leave", groupId: gid }));
    const left = await wsAlice.nextMessage((m) => m.type === "group-call-peer-left");
    assert.equal(left.peerId, bJoined.selfId);

    // Alice disconnects -> room becomes inactive
    wsAlice.close();
    const endedState = await wsBob.nextMessage((m) => m.type === "group-call-state" && m.active === false);
    assert.equal(endedState.participants.length, 0);
  } finally {
    wsAlice?.terminate();
    wsBob?.terminate();
    wsOut?.terminate();
    for (const c of wss.clients) c.terminate();
    await new Promise((r) => wss.close(r));
    server.closeAllConnections?.();
    await new Promise((r) => server.close(r));
    await new Promise((r) => setTimeout(r, 25));
    social.close();
  }
});
