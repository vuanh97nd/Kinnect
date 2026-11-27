import { test } from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../server.js";
import { openSocial } from "../lib/social.js";
import { computeTotp } from "../lib/two-factor.js";
import { selectPublishedApk } from "../lib/apk-releases.js";
import { startSupabaseSecondarySync } from "../lib/supabase-secondary-sync.js";

async function startTestApp(t, opts = {}) {
  const app = createApp({ dbPath: ":memory:", authLimit: 200, ...opts });
  await new Promise((r) => app.server.listen(0, "127.0.0.1", r));
  const base = "http://127.0.0.1:" + app.server.address().port;
  t.after(async () => {
    for (const ws of app.wss.clients) ws.terminate();
    app.wss.close();
    app.server.closeAllConnections();
    await new Promise((r) => app.server.close(r));
    app.social.close();
  });
  const req = async (path, { method = "GET", cookie, body, redirect = "manual" } = {}) => {
    const r = await fetch(base + path, {
      method,
      redirect,
      headers: {
        ...(cookie ? { Cookie: cookie } : {}),
        ...(body ? { "Content-Type": "application/json" } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await r.text();
    let json = null;
    try { json = JSON.parse(text); } catch {}
    return { status: r.status, headers: r.headers, text, json, cookie: r.headers.get("set-cookie")?.split(";")[0] || "" };
  };
  return { app, base, req };
}

test("Wave 3 [P0-1]: Supabase secondary sync purges deleted accounts and blocks resurrection on restart", async (t) => {
  const social = openSocial(":memory:");
  const db = social.db;
  t.after(() => social.close());
  db.prepare("INSERT INTO users(id,username,password,salt,name,birth_date,created,role) VALUES(?,?,?,?,?,?,?,?)").run("u-keep", "keep", "p", "s", "Keep", "", 1000, "user");

  const deletedQueries = [];
  const makePool = (kind) => {
    const runQuery = async (sql, params) => {
      if (sql.trim().startsWith("DELETE")) deletedQueries.push({ kind, sql, params });
      if (kind === "core" && sql.includes("FROM kinnect_core.users")) {
        return {
          rows: [
            { id: "u-deleted", username: "ghost", password: "p", salt: "s", name: "Ghost", profile: "{}", suspended: false, created: 2000, role: "user" },
            { id: "u-new", username: "fresh", password: "p", salt: "s", name: "Fresh", profile: "{}", suspended: false, created: 3000, role: "user" },
          ],
        };
      }
      if (kind === "chat" && sql.includes("FROM kinnect_chat.chat_messages")) {
        return {
          rows: [
            { id: "m-ghost", sender_id: "u-deleted", conversation_id: "dm-1", body: "resurrected?", created_at: 2500, peer_id: "u-keep" },
            { id: "m-valid", sender_id: "u-new", conversation_id: "dm-2", body: "hello!", created_at: 3500, peer_id: "u-keep" },
          ],
        };
      }
      return { rows: [] };
    };
    return {
      on: () => {},
      end: async () => {},
      query: runQuery,
      connect: async () => ({ release: () => {}, query: runQuery }),
    };
  };

  const sync = startSupabaseSecondarySync({
    db,
    intervalMs: 999999,
    initialDelayMs: 999999,
    corePool: makePool("core"),
    chatPool: makePool("chat"),
  });
  t.after(() => sync.stop());

  await sync.purgeAccount("u-deleted");
  assert.ok(deletedQueries.some((q) => q.sql.includes("DELETE FROM kinnect_core.users") && q.params[0] === "u-deleted"));
  assert.ok(deletedQueries.some((q) => q.sql.includes("DELETE FROM kinnect_chat.chat_messages") && q.params[0] === "u-deleted"));

  await sync.syncNow();
  assert.equal(db.prepare("SELECT id FROM users WHERE id='u-deleted'").get(), undefined, "deleted user must NOT resurrect");
  assert.equal(db.prepare("SELECT id FROM messages WHERE id='m-ghost'").get(), undefined, "deleted user's DM must NOT resurrect");
  assert.ok(db.prepare("SELECT id FROM users WHERE id='u-new'").get(), "legitimate remote user still syncs");
  assert.ok(db.prepare("SELECT id FROM messages WHERE id='m-valid'").get(), "legitimate remote message still syncs");
});

test("Wave 3 [P0-2, P0-6, P1-1, P1-3, P1-6, P2-4]: Share cards, CSP, TOTP anti-replay, gift-sender deletion wallet safety, and APK gating", async (t) => {
  const { app, req } = await startTestApp(t);

  // 1. P2-4: /delete-account strict CSP is NOT overwritten
  const delPage = await req("/delete-account");
  assert.equal(delPage.status, 200);
  assert.match(delPage.headers.get("content-security-policy") || "", /frame-ancestors 'none'/);
  assert.equal(delPage.headers.get("x-frame-options"), "DENY");
  assert.match(delPage.text, /totpCode/);

  // 2. P0-6: /share/post/:id, /share/short/:id, /share/live/:id return 200 OK while bare / returns 410
  assert.equal((await req("/")).status, 410);
  const legShare = await req("/?post=abc123");
  assert.equal(legShare.status, 302);
  assert.equal(legShare.headers.get("location"), "/share/post/abc123");
  const shareCard = await req("/share/post/abc123");
  assert.equal(shareCard.status, 200);
  assert.match(shareCard.text, /kinnect:\/\/post\/abc123/);

  // 3. P1-6: Unauthenticated /download/play-bundle & /download/aab blocked; APK selector accepts -b134-release.apk & rejects -debug.apk
  assert.equal((await req("/download/play-bundle")).status, 404);
  assert.equal((await req("/download/aab")).status, 404);
  const relDebug = {
    tag_name: "v1.2.21",
    draft: false,
    prerelease: false,
    assets: [{ name: "Kinnect-1.2.21-debug.apk", size: 100, browser_download_url: "https://github.com/vuanh97nd/Kinnect/releases/download/v1.2.21/Kinnect-1.2.21-debug.apk" }],
  };
  const relPlay = {
    tag_name: "v1.2.21",
    draft: false,
    prerelease: false,
    assets: [{ name: "Kinnect-1.2.21-b134-release.apk", size: 100, browser_download_url: "https://github.com/vuanh97nd/Kinnect/releases/download/v1.2.21/Kinnect-1.2.21-b134-release.apk" }],
  };
  assert.equal(selectPublishedApk([relDebug]), null);
  assert.equal(selectPublishedApk([relPlay])?.version, "v1.2.21");

  // 4. P1-1: TOTP replay within same 30s step is rejected
  const u1 = await req("/api/register", { method: "POST", body: { username: "totp_replay_u", password: "password123", name: "TOTP User", agree18: true, acceptPrivacyNotice: true } });
  assert.equal(u1.status, 200);
  const setup = await req("/api/me/2fa/setup", { method: "POST", cookie: u1.cookie, body: { password: "password123" } });
  const otp = computeTotp(setup.json.secret);
  assert.equal((await req("/api/me/2fa/enable", { method: "POST", cookie: u1.cookie, body: { code: otp } })).status, 200);
  const login1 = await req("/api/login", { method: "POST", body: { username: "totp_replay_u", password: "password123", totpCode: otp } });
  assert.equal(login1.status, 200);
  const loginReplay = await req("/api/login", { method: "POST", body: { username: "totp_replay_u", password: "password123", totpCode: otp } });
  assert.equal(loginReplay.status, 401, "Replayed TOTP code in the same 30s window must be rejected");

  // 5. P1-3: Gift recipient wallet never turns negative when gift sender deletes their account
  const sender = await req("/api/register", { method: "POST", body: { username: "gift_sender", password: "password123", name: "Sender", agree18: true, acceptPrivacyNotice: true } });
  const recv = await req("/api/register", { method: "POST", body: { username: "gift_recv", password: "password123", name: "Receiver", agree18: true, acceptPrivacyNotice: true } });
  app.social.db.prepare("INSERT INTO wallet_entries VALUES('grant1', ?, 'admin:test', 'admin_trial', 500, 0, 0, 0, ?)").run(sender.json.user.id, Date.now());
  const ver = app.social.economy.read().version;
  app.social.wallet.spendTrialGift({
    userId: sender.json.user.id,
    requestId: "req_gift_wave3_00001",
    roomId: "room1",
    giftId: "rose",
    quantity: 5,
    version: ver,
    recipientId: recv.json.user.id,
  });
  const beforeDel = (await req("/api/wallet", { cookie: recv.cookie })).json;
  assert.ok(beforeDel.trialCoins > 0);
  const delRes = await req("/api/me/account-deletion", {
    method: "DELETE",
    cookie: sender.cookie,
    body: { confirmUsername: "gift_sender", confirmDelete: true },
  });
  assert.equal(delRes.status, 200);
  const afterDel = (await req("/api/wallet", { cookie: recv.cookie })).json;
  assert.equal(afterDel.trialCoins, beforeDel.trialCoins, "Recipient trial balance must remain intact after sender deletes account");
  assert.ok(afterDel.coins >= 0, "Ledger sum must never turn negative");
});
