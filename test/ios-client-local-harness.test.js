import { test } from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../server.js";

async function startIsolatedApp() {
  const app = createApp({ dbPath: ":memory:", allowEmailDelivery: false });
  await new Promise((resolve) => app.server.listen(0, "127.0.0.1", resolve));
  const origin = "http://127.0.0.1:" + app.server.address().port;
  const req = async (path, { method = "GET", body, cookie } = {}) => {
    const res = await fetch(origin + "/api" + path, {
      method,
      headers: {
        Origin: origin,
        ...(cookie ? { Cookie: cookie } : {}),
        ...(method !== "GET" && method !== "HEAD" ? { "Content-Type": "application/json" } : {})
      },
      body: method !== "GET" && method !== "HEAD" ? JSON.stringify(body ?? {}) : undefined
    });
    const setCookie = res.headers.get("set-cookie")?.split(";")[0] || null;
    return { status: res.status, cookie: setCookie, body: await res.json() };
  };
  const close = async () => {
    app.wss.close();
    app.server.closeAllConnections?.();
    await new Promise((resolve) => app.server.close(resolve));
    app.social.close();
  };
  return { origin, req, close };
}

test("iOS client local harness: POST /api/me/password validates current, preserves current session, revokes others", async () => {
  const { req, close } = await startIsolatedApp();
  try {
    const first = await req("/register", {
      method: "POST",
      body: { username: "ios_pw_harness", password: "oldpass123", agree18: true, acceptPrivacyNotice: true }
    });
    assert.equal(first.status, 200);
    const second = await req("/login", {
      method: "POST",
      body: { username: "ios_pw_harness", password: "oldpass123" }
    });
    assert.equal(second.status, 200);

    // Wrong current password returns 400 (never 401 so iOS does not log out active session).
    const bad = await req("/me/password", {
      method: "POST",
      cookie: first.cookie,
      body: { current: "wrongpass", next: "newpass123" }
    });
    assert.equal(bad.status, 400);
    assert.equal((await req("/me", { cookie: second.cookie })).status, 200);

    // Exact iOS payload from AccountMenuView.swift / ProfileView.swift
    const ok = await req("/me/password", {
      method: "POST",
      cookie: first.cookie,
      body: { current: "oldpass123", next: "newpass123" }
    });
    assert.equal(ok.status, 200);
    assert.equal(ok.body.ok, true);

    // Current session stays valid; secondary session is revoked; old password cannot log in; new password works.
    assert.equal((await req("/me", { cookie: first.cookie })).status, 200);
    assert.equal((await req("/me", { cookie: second.cookie })).status, 401);
    const oldLogin = await req("/login", {
      method: "POST",
      body: { username: "ios_pw_harness", password: "oldpass123" }
    });
    assert.ok(oldLogin.status === 400 || oldLogin.status === 401);
    const newLogin = await req("/login", {
      method: "POST",
      body: { username: "ios_pw_harness", password: "newpass123" }
    });
    assert.equal(newLogin.status, 200);
  } finally {
    await close();
  }
});

test("iOS client local harness: PATCH /api/me dmMode round-trip, validation rejection, and non-friend enforcement", async () => {
  const { req, close } = await startIsolatedApp();
  try {
    const alice = await req("/register", {
      method: "POST",
      body: { username: "ios_dm_alice", password: "password123", agree18: true, acceptPrivacyNotice: true }
    });
    const bob = await req("/register", {
      method: "POST",
      body: { username: "ios_dm_bob", password: "password123", agree18: true, acceptPrivacyNotice: true }
    });
    const aliceId = alice.body.user.id;
    assert.equal(alice.body.user.dmMode, "everyone");

    // Invalid dmMode rejected with 400, server state remains unchanged ("everyone")
    const badDm = await req("/me", {
      method: "PATCH",
      cookie: alice.cookie,
      body: { dmMode: "invalid_mode" }
    });
    assert.equal(badDm.status, 400);
    assert.equal((await req("/me", { cookie: alice.cookie })).body.user.dmMode, "everyone");

    // Switch to friends using PrivacySettingsView / PrivacySettingsSheet payload
    const friendsPatch = await req("/me", {
      method: "PATCH",
      cookie: alice.cookie,
      body: {
        discoverable: true,
        showDistance: true,
        showActivity: true,
        dmMode: "friends",
        cloudChatSync: true
      }
    });
    assert.equal(friendsPatch.status, 200);
    assert.equal(friendsPatch.body.user.dmMode, "friends");

    // Stranger Bob cannot DM Alice while dmMode === "friends"
    const deniedMsg = await req("/users/" + aliceId + "/messages", {
      method: "POST",
      cookie: bob.cookie,
      body: { body: "Xin chao" }
    });
    assert.equal(deniedMsg.status, 403);

    // Switch back to everyone -> Bob can DM Alice
    const everyonePatch = await req("/me", {
      method: "PATCH",
      cookie: alice.cookie,
      body: { dmMode: "everyone" }
    });
    assert.equal(everyonePatch.status, 200);
    assert.equal(everyonePatch.body.user.dmMode, "everyone");

    const allowedMsg = await req("/users/" + aliceId + "/messages", {
      method: "POST",
      cookie: bob.cookie,
      body: { body: "Xin chao lai" }
    });
    assert.equal(allowedMsg.status, 201);
  } finally {
    await close();
  }
});

test("iOS client local harness: GET/DELETE /api/me/sessions matches ActiveSessionsSheet requestId & current-session guard", async () => {
  const { req, close } = await startIsolatedApp();
  try {
    const primary = await req("/register", {
      method: "POST",
      body: { username: "ios_sess_user", password: "password123", agree18: true, acceptPrivacyNotice: true }
    });
    const secondary = await req("/login", {
      method: "POST",
      body: { username: "ios_sess_user", password: "password123" }
    });

    const listRes = await req("/me/sessions", { cookie: primary.cookie });
    assert.equal(listRes.status, 200);
    assert.equal(listRes.body.sessions.length, 2);
    for (const s of listRes.body.sessions) {
      assert.equal(typeof s.id, "string");
      assert.equal(s.id.length, 32);
      assert.equal("token" in s, false);
      assert.equal("device_hash" in s, false);
    }

    const current = listRes.body.sessions.find((s) => s.current);
    const other = listRes.body.sessions.find((s) => !s.current);
    assert.ok(current && other);

    // Cannot revoke current session even with requestId body
    const denySelf = await req("/me/sessions/" + current.id, {
      method: "DELETE",
      cookie: primary.cookie,
      body: { requestId: "revoke_" + current.id }
    });
    assert.equal(denySelf.status, 400);

    // Exact ProfileView.swift revokeSession DELETE body shape
    const revokeOther = await req("/me/sessions/" + other.id, {
      method: "DELETE",
      cookie: primary.cookie,
      body: { requestId: "revoke_" + other.id }
    });
    assert.equal(revokeOther.status, 200);
    assert.equal(revokeOther.body.ok, true);

    assert.equal((await req("/me", { cookie: secondary.cookie })).status, 401);
    assert.equal((await req("/me", { cookie: primary.cookie })).status, 200);
  } finally {
    await close();
  }
});
