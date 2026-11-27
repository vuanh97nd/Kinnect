import http from "node:http";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../server.js";
import { computeTotp } from "../lib/two-factor.js";

test("Admin Console enforces 2FA for Admin login, reports live telemetry, creates VACUUM INTO backup, and rotates oversized logs", async () => {
  const dir = mkdtempSync(join(tmpdir(), "kinnect-admin-ops-"));
  const dbPath = join(dir, "kinnect.sqlite");
  const app = createApp({ dbPath, authLimit: 100 });
  await new Promise((r) => app.server.listen(0, "127.0.0.1", r));
  const base = "http://127.0.0.1:" + app.server.address().port;

  const consoleReq = (path, { portal = "admin", method = "GET", data, cookie } = {}) => {
    const host = portal + ".kinnect.io.vn";
    const payload = data ? JSON.stringify(data) : null;
    return new Promise((resolve, reject) => {
      const request = http.request(
        base + path,
        {
          method,
          headers: {
            Host: host,
            ...(cookie ? { Cookie: cookie } : {}),
            ...(payload ? { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(payload) } : {}),
            ...(method === "POST" ? { Origin: "https://" + host } : {}),
          },
        },
        (r) => {
          const chunks = [];
          r.on("data", (c) => chunks.push(c));
          r.on("end", () => {
            const txt = Buffer.concat(chunks).toString();
            resolve({
              status: r.statusCode,
              body: r.headers["content-type"]?.includes("application/json") ? JSON.parse(txt) : txt,
              cookie: r.headers["set-cookie"]?.[0]?.split(";")[0],
            });
          });
        },
      );
      request.on("error", reject);
      request.end(payload);
    });
  };

  try {
    // Register & promote Admin
    const reg = await fetch(base + "/api/register", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username: "ops_admin", password: "strong-admin-password!", name: "Ops Admin", agree18: true, acceptPrivacyNotice: true }),
    });
    assert.equal(reg.status, 200);
    const appCookie = reg.headers.get("set-cookie").split(";")[0];
    const adminUser = (await reg.json()).user;
    app.social.db.prepare("UPDATE users SET role='admin' WHERE id=?").run(adminUser.id);

    // Enable 2FA for Admin
    const setupRes = await fetch(base + "/api/me/2fa/setup", {
      method: "POST",
      headers: { "Content-Type": "application/json", Cookie: appCookie },
      body: JSON.stringify({ password: "strong-admin-password!" }),
    });
    const setup = await setupRes.json();
    assert.equal(setupRes.status, 200);
    const enableRes = await fetch(base + "/api/me/2fa/enable", {
      method: "POST",
      headers: { "Content-Type": "application/json", Cookie: appCookie },
      body: JSON.stringify({ code: computeTotp(setup.secret) }),
    });
    assert.equal(enableRes.status, 200);

    // Console login without totpCode returns 403 requires2fa
    const no2fa = await consoleReq("/api/console/login", {
      method: "POST",
      data: { username: "ops_admin", password: "strong-admin-password!" },
    });
    assert.equal(no2fa.status, 403);
    assert.equal(no2fa.body.requires2fa, true);

    // Console login with wrong totpCode returns 401
    const bad2fa = await consoleReq("/api/console/login", {
      method: "POST",
      data: { username: "ops_admin", password: "strong-admin-password!", totpCode: "000000" },
    });
    assert.equal(bad2fa.status, 401);

    // Console login with valid TOTP succeeds
    const ok2fa = await consoleReq("/api/console/login", {
      method: "POST",
      data: { username: "ops_admin", password: "strong-admin-password!", totpCode: computeTotp(setup.secret) },
    });
    assert.equal(ok2fa.status, 200);
    const adminCookie = ok2fa.cookie;

    // Create manual backup via operations action
    const bk = await consoleReq("/api/console/operations/action", {
      method: "POST",
      cookie: adminCookie,
      data: { action: "create-backup" },
    });
    assert.equal(bk.status, 200);
    assert.ok(bk.body.file.startsWith("manual-backup-"));
    assert.ok(bk.body.sizeMb > 0);

    // Create an oversized 3 MB log file and rotate it
    const bigLog = join(dir, "oversized.log");
    writeFileSync(bigLog, Buffer.alloc(3 * 1024 * 1024, "x"));
    const rot = await consoleReq("/api/console/operations/action", {
      method: "POST",
      cookie: adminCookie,
      data: { action: "rotate-logs" },
    });
    assert.equal(rot.status, 200);
    assert.equal(rot.body.rotated, 1);

    // Operations telemetry returns disk, backups, media, and watchdog service state
    const ops = await consoleReq("/api/console/operations", { cookie: adminCookie });
    assert.equal(ops.status, 200);
    assert.ok(ops.body.disk && ops.body.disk.totalGb > 0);
    assert.ok(ops.body.backups.length >= 1);
    assert.ok(ops.body.media !== null);
    assert.ok(ops.body.services.watchdog);
  } finally {
    for (const ws of app.wss.clients) ws.terminate();
    await new Promise((r) => app.wss.close(r));
    app.server.closeAllConnections?.();
    await new Promise((r) => app.server.close(r));
    app.social.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
