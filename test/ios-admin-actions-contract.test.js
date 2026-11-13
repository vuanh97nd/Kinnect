import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createApp } from "../server.js";

async function startAdminTestApp() {
  const app = createApp({ dbPath: ":memory:", allowEmailDelivery: false });
  await new Promise((resolve) => app.server.listen(0, "127.0.0.1", resolve));
  const origin = "http://127.0.0.1:" + app.server.address().port;
  const req = async (path, { method = "GET", body, cookie } = {}) => {
    const res = await fetch(origin + path, {
      method,
      headers: {
        Origin: origin,
        Host: new URL(origin).host,
        ...(cookie ? { Cookie: cookie } : {}),
        ...(method !== "GET" && method !== "HEAD" ? { "Content-Type": "application/json" } : {})
      },
      body: method !== "GET" && method !== "HEAD" ? JSON.stringify(body ?? {}) : undefined
    });
    const setCookie = res.headers.get("set-cookie")?.split(";")[0] || null;
    return { status: res.status, cookie: setCookie, body: await res.json() };
  };
  const registerUser = async (username, role = "member") => {
    const res = await req("/api/register", {
      method: "POST",
      body: { username, password: "password123", agree18: true, acceptPrivacyNotice: true }
    });
    assert.equal(res.status, 200);
    if (role === "admin") {
      app.social.db.prepare("UPDATE users SET role='admin' WHERE id=?").run(res.body.user.id);
    }
    return { user: res.body.user, cookie: res.cookie };
  };
  const close = async () => {
    app.wss.close();
    app.server.closeAllConnections?.();
    await new Promise((resolve) => app.server.close(resolve));
    app.social.close();
  };
  return { app, req, registerUser, close };
}

test("iOS admin economy contract: role gate, payload validation, optimistic lock 409, and version increment", async () => {
  const { req, registerUser, close } = await startAdminTestApp();
  try {
    const member = await registerUser("ios_econ_member", "member");
    const admin = await registerUser("ios_econ_admin", "admin");

    // Non-admin blocked cleanly
    assert.equal((await req("/api/admin/economy", { cookie: member.cookie })).status, 403);
    assert.equal(
      (await req("/api/admin/economy", { method: "PATCH", cookie: member.cookie, body: {} })).status,
      403
    );

    const initial = await req("/api/admin/economy", { cookie: admin.cookie });
    assert.equal(initial.status, 200);
    assert.equal(initial.body.version, 1);
    const nextConfig = structuredClone(initial.body.config);
    nextConfig.giftPrices.rose = 75;

    // Invalid partial config rejected with 400
    assert.equal(
      (
        await req("/api/admin/economy", {
          method: "PATCH",
          cookie: admin.cookie,
          body: { version: 1, config: { vndPerCoin: 100 } }
        })
      ).status,
      400
    );

    // Valid optimistic update increments version
    const saved = await req("/api/admin/economy", {
      method: "PATCH",
      cookie: admin.cookie,
      body: { version: initial.body.version, config: nextConfig }
    });
    assert.equal(saved.status, 200);
    assert.equal(saved.body.version, 2);
    assert.equal(saved.body.config.giftPrices.rose, 75);

    // Stale version conflict returns 409 without overwriting server config
    nextConfig.giftPrices.rose = 999;
    const conflict = await req("/api/admin/economy", {
      method: "PATCH",
      cookie: admin.cookie,
      body: { version: 1, config: nextConfig }
    });
    assert.equal(conflict.status, 409);
    const afterConflict = await req("/api/admin/economy", { cookie: admin.cookie });
    assert.equal(afterConflict.body.config.giftPrices.rose, 75);
  } finally {
    await close();
  }
});

test("iOS admin music contract: isolated MUSIC_DIR upload/delete with role gate & validation", async () => {
  const prevMusicDir = process.env.MUSIC_DIR;
  const tempMusicDir = mkdtempSync(join(tmpdir(), "kinnect-ios-music-test-"));
  process.env.MUSIC_DIR = tempMusicDir;
  const { req, registerUser, close } = await startAdminTestApp();
  try {
    const member = await registerUser("ios_music_member", "member");
    const admin = await registerUser("ios_music_admin", "admin");
    const sampleAudioDataUrl = "data:audio/mpeg;base64," + Buffer.from("ID3sampleaudio").toString("base64");

    // Non-admin cannot upload or delete
    assert.equal(
      (
        await req("/api/music", {
          method: "POST",
          cookie: member.cookie,
          body: { title: "Test", artist: "A", license: "CC0", rights: true, data: sampleAudioDataUrl }
        })
      ).status,
      403
    );

    // Rights flag must be explicit true
    assert.equal(
      (
        await req("/api/music", {
          method: "POST",
          cookie: admin.cookie,
          body: { title: "Test", artist: "A", license: "CC0", rights: false, data: sampleAudioDataUrl }
        })
      ).status,
      400
    );

    // Valid upload appears in GET /api/music inside isolated temp dir
    const uploaded = await req("/api/music", {
      method: "POST",
      cookie: admin.cookie,
      body: {
        title: "Test Track",
        artist: "Kinnect QA",
        license: "CC0",
        source: "https://example.invalid/track",
        rights: true,
        data: sampleAudioDataUrl
      }
    });
    assert.equal(uploaded.status, 201);
    assert.equal(uploaded.body.ok, true);
    assert.ok(uploaded.body.file.endsWith(".mp3"));

    const listed = await req("/api/music", { cookie: admin.cookie });
    assert.equal(listed.status, 200);
    assert.ok(listed.body.tracks.some((t) => t.file === uploaded.body.file && t.title === "Test Track"));

    // Path traversal rejected on DELETE
    assert.equal(
      (
        await req("/api/music", {
          method: "DELETE",
          cookie: admin.cookie,
          body: { file: "../evil.mp3" }
        })
      ).status,
      400
    );

    // Valid DELETE removes file
    const deleted = await req("/api/music", {
      method: "DELETE",
      cookie: admin.cookie,
      body: { file: uploaded.body.file }
    });
    assert.equal(deleted.status, 200);
    assert.equal(deleted.body.ok, true);

    const listedAfter = await req("/api/music", { cookie: admin.cookie });
    assert.equal(listedAfter.body.tracks.some((t) => t.file === uploaded.body.file), false);
  } finally {
    await close();
    if (prevMusicDir === undefined) delete process.env.MUSIC_DIR;
    else process.env.MUSIC_DIR = prevMusicDir;
    rmSync(tempMusicDir, { recursive: true, force: true });
  }
});

test("iOS admin AI credentials contract: never exposes raw secrets and enforces password re-auth & allowlist", async () => {
  const { req, registerUser, close } = await startAdminTestApp();
  try {
    const member = await registerUser("ios_ai_member", "member");
    const admin = await registerUser("ios_ai_admin", "admin");

    assert.equal((await req("/api/admin/ai", { cookie: member.cookie })).status, 403);

    const statusRes = await req("/api/admin/ai", { cookie: admin.cookie });
    assert.equal(statusRes.status, 200);
    assert.equal(typeof statusRes.body.credentials.tokenSaved, "boolean");
    assert.equal(typeof statusRes.body.credentials.nvidiaKeySaved, "boolean");
    assert.equal("token" in statusRes.body.credentials, false);
    assert.equal("nvidiaKey" in statusRes.body.credentials, false);

    // Wrong admin password rejected with 401 before touching credentials file
    const wrongPw = await req("/api/admin/ai/credentials", {
      method: "PATCH",
      cookie: admin.cookie,
      body: { password: "wrong_password", workerUrl: "https://kinnect-ai.vuanh97nd.workers.dev" }
    });
    assert.equal(wrongPw.status, 401);

    // Correct password + disallowed worker URL rejected with 400 (zero live mutation)
    const badUrl = await req("/api/admin/ai/credentials", {
      method: "PATCH",
      cookie: admin.cookie,
      body: { password: "password123", workerUrl: "https://evil.example.com" }
    });
    assert.equal(badUrl.status, 400);

    // Unknown AI test provider rejected with 400
    const badProvider = await req("/api/admin/ai/test", {
      method: "POST",
      cookie: admin.cookie,
      body: { provider: "unknown" }
    });
    assert.equal(badProvider.status, 400);
  } finally {
    await close();
  }
});

