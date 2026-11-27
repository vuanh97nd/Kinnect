import http from "node:http";
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { registerHooks } from "node:module";
import { DatabaseSync } from "node:sqlite";
import { WebSocket } from "ws";

import { createApp } from "../server.js";
import { openSocial } from "../lib/social.js";
import { createAdminConsole } from "../lib/admin-console.js";
import { createOpsMonitorService } from "../lib/ops-monitor-service.js";
import { createAiSecurityMonitor } from "../lib/ai-security-monitor.js";
import {
  analyzeAccountViolation,
  evaluateImageContentPolicy,
} from "../lib/ai-violation-reporter.js";
import { dispatchTicketWithAI } from "../lib/ai-dispatcher.js";
import { createCalls } from "../lib/calls.js";
import { createLiveGifts } from "../lib/live-gifts.js";
import { createAppleStore, appleSignedDataVerifier, appleAccountUuid } from "../lib/apple-store.js";
import { storeAccountId } from "../lib/store.js";

const TINY_PNG =
  "data:image/png;base64," +
  Buffer.from([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
    0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
    0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
    0x42, 0x60, 0x82,
  ]).toString("base64");

async function startApp(t, opts = {}) {
  const app = createApp({ authLimit: 1000, ...opts });
  await new Promise((resolve) => app.server.listen(0, "127.0.0.1", resolve));
  const origin = "http://127.0.0.1:" + app.server.address().port;
  t.after(async () => {
    const peers = [...app.wss.clients];
    await Promise.all(peers.map((ws) => new Promise((r) => { ws.once("close", r); ws.terminate(); })));
    app.wss.close();
    app.server.closeAllConnections?.();
    await new Promise((resolve) => app.server.close(resolve));
    app.social.close();
  });

  async function api(path, { method = "GET", body, cookie, headers = {} } = {}) {
    const isWrite = ["POST", "PATCH", "PUT"].includes(method);
    const payload = body !== undefined ? JSON.stringify(body) : isWrite ? "{}" : undefined;
    const res = await fetch(origin + "/api" + path, {
      method,
      headers: {
        ...(cookie ? { Cookie: cookie } : {}),
        ...(payload !== undefined ? { "Content-Type": "application/json" } : {}),
        ...headers,
      },
      body: payload,
    });
    const text = await res.text();
    let parsed = text;
    try { parsed = JSON.parse(text); } catch {}
    return {
      status: res.status,
      body: parsed,
      headers: res.headers,
      cookie: res.headers.get("set-cookie")?.split(";")[0],
    };
  }

  async function register(username, extra = {}) {
    const r = await api("/register", {
      method: "POST",
      body: {
        username,
        name: extra.name || "User " + username,
        password: extra.password || "strong-pass-123",
        agree18: true,
        acceptPrivacyNotice: true,
        acceptTerms: true,
        ...extra,
      },
    });
    assert.equal(r.status, 200, `register ${username} failed: ${JSON.stringify(r.body)}`);
    return { user: r.body.user, cookie: r.cookie };
  }

  async function connectWs(cookie) {
    const ws = new WebSocket(origin.replace("http:", "ws:"), { headers: { Cookie: cookie } });
    t.after(() => ws.terminate());
    const queue = [];
    ws.on("message", (raw) => queue.push(JSON.parse(raw.toString())));
    await new Promise((resolve, reject) => {
      ws.once("open", resolve);
      ws.once("error", reject);
    });
    async function next(predicate, timeoutMs = 2000) {
      const fn = typeof predicate === "string" ? (m) => m.type === predicate : predicate;
      const deadline = Date.now() + timeoutMs;
      while (Date.now() < deadline) {
        const idx = queue.findIndex(fn);
        if (idx >= 0) return queue.splice(idx, 1)[0];
        await new Promise((r) => setTimeout(r, 10));
      }
      throw new Error("Timed out waiting for WS message; queued=" + JSON.stringify(queue));
    }
    await next("welcome");
    return { ws, queue, next, send: (data) => ws.send(JSON.stringify(data)) };
  }

  return { ...app, origin, api, register, connectWs };
}

function rawHttpRequest(origin, path, { method = "GET", headers = {}, body } = {}) {
  return new Promise((resolve, reject) => {
    const payload = body === undefined ? null : typeof body === "string" ? body : JSON.stringify(body);
    const req = http.request(
      origin + path,
      {
        method,
        headers: {
          ...(payload !== null && !headers["Content-Type"]
            ? { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(payload) }
            : {}),
          ...headers,
        },
      },
      (res) => {
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => {
          const text = Buffer.concat(chunks).toString("utf8");
          let parsed = text;
          if (res.headers["content-type"]?.includes("application/json")) {
            try { parsed = JSON.parse(text); } catch {}
          }
          resolve({
            status: res.statusCode,
            headers: res.headers,
            text,
            body: parsed,
            cookie: res.headers["set-cookie"]?.[0]?.split(";")[0],
          });
        });
      }
    );
    req.on("error", reject);
    if (payload !== null) req.write(payload);
    req.end();
  });
}

// ---------------------------------------------------------------------------
// 1. delete-account.html single valid document + HTTP security headers
// ---------------------------------------------------------------------------
test("Wave2 [delete-account.html]: single valid HTML document served with strict no-frame headers", async (t) => {
  const html = await readFile(new URL("../public/delete-account.html", import.meta.url), "utf8");
  assert.equal((html.match(/<!doctype\s+html>/gi) || []).length, 1);
  assert.equal((html.match(/<html\b/gi) || []).length, 1);
  assert.equal((html.match(/<\/html>/gi) || []).length, 1);
  assert.equal((html.match(/<head\b/gi) || []).length, 1);
  assert.equal((html.match(/<\/head>/gi) || []).length, 1);
  assert.equal((html.match(/<body\b/gi) || []).length, 1);
  assert.equal((html.match(/<\/body>/gi) || []).length, 1);
  assert.equal((html.match(/<main\b/gi) || []).length, 1);
  assert.equal((html.match(/<\/main>/gi) || []).length, 1);

  const app = await startApp(t);
  const res = await fetch(app.origin + "/delete-account");
  assert.equal(res.status, 200);
  const served = await res.text();
  assert.equal((served.match(/<!doctype\s+html>/gi) || []).length, 1);
  assert.equal(res.headers.get("x-frame-options"), "DENY");
  assert.match(res.headers.get("content-security-policy") || "", /frame-ancestors 'none'/);
  assert.equal(res.headers.get("cache-control"), "no-store");
});

// ---------------------------------------------------------------------------
// 2. /api/console/reputation/adjust for local user AND cloud-only user (birth_date NOT NULL)
// ---------------------------------------------------------------------------
test("Wave2 [reputation/adjust]: works for both local user and cloud-only user with NOT NULL birth_date", async (t) => {
  const social = openSocial(":memory:");
  t.after(() => social.close());

  const now = Date.now();
  const localId = "local_member_001";
  const cloudId = "cloud_only_member_002";
  social.db
    .prepare(
      "INSERT INTO users(id,username,password,salt,name,role,birth_date,created) VALUES(?,?,?,?,?,?,?,?)"
    )
    .run(localId, "local_user", "hash", "salt", "Local User", "user", "2000-01-01", now);

  const authority = {
    user: async (id) =>
      id === cloudId
        ? { id: cloudId, username: "cloud_member", name: "Cloud Member", role: "user", suspended: 0 }
        : null,
  };

  const adminHandler = createAdminConsole(social, {
    authority,
    trustedPrincipal: () => ({
      id: "root_admin",
      username: "root_admin",
      name: "Root Admin",
      role: "admin",
      team: "admin",
    }),
  });

  const server = http.createServer(async (req, res) => {
    const handled = await adminHandler(req, res);
    if (!handled && !res.headersSent) {
      res.writeHead(404);
      res.end();
    }
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(async () => {
    server.closeAllConnections?.();
    await new Promise((resolve) => server.close(resolve));
  });
  const origin = "http://127.0.0.1:" + server.address().port;

  // Local user deduct + restore
  const localDeduct = await rawHttpRequest(origin, "/api/console/reputation/adjust", {
    method: "POST",
    headers: { Host: "admin.kinnect.io.vn", Origin: "https://admin.kinnect.io.vn" },
    body: { userId: localId, action: "deduct", points: 15, reason: "Vi phạm nhẹ bài viết công khai" },
  });
  assert.equal(localDeduct.status, 200);
  assert.equal(localDeduct.body.ok, true);
  assert.equal(localDeduct.body.result.remainingScore, 85);

  // Cloud-only user (not yet in local SQLite `users` table where `birth_date TEXT NOT NULL`)
  const cloudDeduct = await rawHttpRequest(origin, "/api/console/reputation/adjust", {
    method: "POST",
    headers: { Host: "admin.kinnect.io.vn", Origin: "https://admin.kinnect.io.vn" },
    body: { userId: cloudId, action: "deduct", points: 20, reason: "Điều chỉnh điểm từ hồ sơ cloud" },
  });
  assert.equal(cloudDeduct.status, 200);
  assert.equal(cloudDeduct.body.ok, true);
  assert.equal(cloudDeduct.body.result.remainingScore, 80);

  const inserted = social.db.prepare("SELECT id, username, birth_date, reputation_score FROM users WHERE id=?").get(cloudId);
  assert.equal(inserted.username, "cloud_member");
  assert.equal(inserted.birth_date, "");
  assert.equal(inserted.reputation_score, 80);
});

// ---------------------------------------------------------------------------
// 3. ops-monitor-service SQL `SELECT id AS user_id FROM users`
// ---------------------------------------------------------------------------
test("Wave2 [ops-monitor-service]: counts active users using users.id AS user_id without SQL error", async (t) => {
  const db = new DatabaseSync(":memory:");
  t.after(() => db.close());
  db.exec(`
    CREATE TABLE users(id TEXT PRIMARY KEY, last_active INTEGER NOT NULL, suspended INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE sessions(token TEXT PRIMARY KEY, user_id TEXT NOT NULL, expires INTEGER NOT NULL);
  `);
  const now = Date.now();
  // 2 recently active users (no sessions) + 1 user with valid session + 1 suspended user (must be excluded)
  db.prepare("INSERT INTO users VALUES(?,?,?)").run("u1", now - 10000, 0);
  db.prepare("INSERT INTO users VALUES(?,?,?)").run("u2", now - 20000, 0);
  db.prepare("INSERT INTO users VALUES(?,?,?)").run("u_suspended", now - 5000, 1);
  db.prepare("INSERT INTO sessions VALUES(?,?,?)").run("tok3", "u3", now + 60000);

  const handler = createOpsMonitorService({ db, audit: () => {}, sessions: new Map() });
  let response = null;
  await handler({
    path: "/api/console/ops/metrics",
    method: "GET",
    body: {},
    me: { id: "ops1", username: "ops", role: "staff", team: "operations" },
    send: (status, body) => { response = { status, body }; },
  });

  assert.equal(response.status, 200);
  const appServer = response.body.servers.find((s) => s.id === "app-1");
  assert.ok(appServer, "app-1 server metric must exist");
  // u1, u2 (from users.id) + u3 (from sessions.user_id) => 3 active users
  assert.equal(appServer.activeUsers, 3);
});

// ---------------------------------------------------------------------------
// 4. cloud-admin/worker.js sanitized /api/console/health?target=pc
// ---------------------------------------------------------------------------
test("Wave2 [cloud-admin/worker]: /api/console/health?target=pc returns sanitized payload only", async (t) => {
  const hook = registerHooks({
    resolve(specifier, context, nextResolve) {
      if (specifier === "cloudflare:workers") {
        return { url: "data:text/javascript,export class DurableObject {}", shortCircuit: true };
      }
      return nextResolve(specifier, context);
    },
  });
  t.after(() => hook.deregister());

  const workerMod = await import("../cloud-admin/worker.js");
  const worker = workerMod.default;

  // Mock PC origin server returning sensitive telemetry fields
  let pcResponse = {
    status: 200,
    body: {
      ok: true,
      instanceId: "inst-pc-999",
      pid: 42424,
      telemetry: { heapMb: 512, rssMb: 900, activeConnections: 99 },
      liveSfu: { secret: "internal-sfu" },
    },
  };
  const pcServer = http.createServer((req, res) => {
    if (req.url === "/health") {
      res.writeHead(pcResponse.status, { "Content-Type": "application/json" });
      res.end(JSON.stringify(pcResponse.body));
      return;
    }
    res.writeHead(404);
    res.end();
  });
  await new Promise((resolve) => pcServer.listen(0, "127.0.0.1", resolve));
  t.after(async () => {
    pcServer.closeAllConnections?.();
    await new Promise((resolve) => pcServer.close(resolve));
  });
  const pcOrigin = "http://127.0.0.1:" + pcServer.address().port;

  // Healthy PC response: sanitized, strips pid/telemetry/liveSfu
  const okRes = await worker.fetch(
    new Request("https://admin.kinnect.io.vn/api/console/health?target=pc"),
    { PC_ORIGIN: pcOrigin }
  );
  assert.equal(okRes.status, 200);
  const okJson = await okRes.json();
  assert.deepEqual(okJson, { ok: true, status: 200, target: "pc", instanceId: "inst-pc-999" });
  assert.equal("pid" in okJson, false);
  assert.equal("telemetry" in okJson, false);
  assert.equal("liveSfu" in okJson, false);

  // Unhealthy 500 PC response: returns 500 sanitized without upstream body leakage
  pcResponse = { status: 500, body: { error: "SQLITE_INTERNAL_STACK_TRACE", dbPath: "D:\\secret" } };
  const errRes = await worker.fetch(
    new Request("https://admin.kinnect.io.vn/api/console/health?target=pc"),
    { PC_ORIGIN: pcOrigin }
  );
  assert.equal(errRes.status, 500);
  const errJson = await errRes.json();
  assert.deepEqual(errJson, { ok: false, status: 500, target: "pc" });

  // Unreachable PC origin: returns 503 sanitized without leaking PC_ORIGIN
  const downRes = await worker.fetch(
    new Request("https://admin.kinnect.io.vn/api/console/health?target=pc"),
    { PC_ORIGIN: "http://127.0.0.1:1" }
  );
  assert.equal(downRes.status, 503);
  const downJson = await downRes.json();
  assert.deepEqual(downJson, { ok: false, status: 503, target: "pc" });
});

// ---------------------------------------------------------------------------
// 5. ai-security-monitor: autoActionId persisted + loopback IP never auto-blocked
// ---------------------------------------------------------------------------
test("Wave2 [ai-security-monitor]: persists autoActionId for public attacker and blocks loopback auto-mitigation", async (t) => {
  const db = new DatabaseSync(":memory:");
  t.after(() => db.close());

  const monitor = createAiSecurityMonitor({
    db,
    env: {},
    fetchImpl: async () => ({
      ok: true,
      json: async () => ({
        choices: [
          {
            message: {
              content: JSON.stringify({
                threat_detected: true,
                category: "brute_force",
                severity: "high",
                confidence: 0.96,
                data_leak_risk: false,
                summary: "Repeated login brute force",
                reasoning: "Multiple failed logins from single IP",
                evidence: ["failed_login spike"],
                recommended_actions: [
                  { action: "block_ip", target_type: "ip", target_value: "198.51.100.42", ttl_seconds: 600, reason: "Brute force" },
                ],
              }),
            },
          },
        ],
      }),
    }),
  });
  monitor.updateConfig(
    {
      enabled: true,
      autoResponseEnabled: true,
      failedLoginThreshold: 3,
    },
    "admin"
  );
  // Drain the self-audited privilege_change event emitted by updateConfig
  await monitor.drainQueue();

  // Case A: Public attacker IP -> auto-mitigated and autoActionId matches mitigation ID
  for (let i = 0; i < 5; i++) {
    monitor.recordEvent({
      kind: "failed_login",
      ip: "198.51.100.42",
      actorId: "victim",
      method: "POST",
      path: "/api/login",
      statusCode: 401,
    });
  }
  const alertsPublic = await monitor.drainQueue();
  assert.equal(alertsPublic.length, 1);
  assert.ok(alertsPublic[0].autoActionId, "autoActionId must be populated on auto-mitigated alert");
  assert.equal(alertsPublic[0].autoActionId, alertsPublic[0].autoMitigation?.id);
  const stored = monitor.listAlerts({ limit: 5 }).find((a) => a.id === alertsPublic[0].id);
  assert.equal(stored.autoActionId, alertsPublic[0].autoActionId);

  // Case B: Loopback IP (127.0.0.1 and ::1) -> NEVER auto-blocked even when threshold exceeded
  for (const loopbackIp of ["127.0.0.1", "::1"]) {
    for (let i = 0; i < 5; i++) {
      monitor.recordEvent({
        kind: "failed_login",
        ip: loopbackIp,
        actorId: "local_probe",
        method: "POST",
        path: "/api/login",
        statusCode: 401,
      });
    }
  }
  const alertsLoopback = await monitor.drainQueue();
  assert.ok(alertsLoopback.length >= 1);
  for (const a of alertsLoopback) {
    assert.equal(a.autoActionId, "");
    assert.equal(a.autoMitigation, null);
    assert.match(a.policyDecision, /loopback/i);
  }
  const activeMitigations = monitor.listMitigations({ activeOnly: true });
  assert.ok(!activeMitigations.some((m) => m.targetValue === "127.0.0.1" || m.targetValue === "::1"));
});

// ---------------------------------------------------------------------------
// 6. ai-violation-reporter: Vietnamese Unicode regex + needs_review + caption non-override
// ---------------------------------------------------------------------------
test("Wave2 [ai-violation-reporter]: Unicode boundaries, benign needs_review, and caption cannot override Vision AI", () => {
  // Vietnamese diacritic keywords match cleanly
  const vCsam = analyzeAccountViolation({ content: "Cảnh báo nội dung ấu dâm trên mạng", userId: "u1" });
  assert.equal(vCsam.violationType, "csam_csae");
  assert.equal(vCsam.penaltyPoints, 50);

  const vSpam = analyzeAccountViolation({ content: "Chơi tài xỉu nổ hũ uy tín", userId: "u1" });
  assert.equal(vSpam.violationType, "spam");
  assert.equal(vSpam.penaltyPoints, 2);

  // Benign Vietnamese text without violation keywords returns needs_review with 0 penalty (never false harassment)
  const benign = analyzeAccountViolation({
    content: "Hôm nay đi uống cà phê với bạn bè thật vui",
    userId: "u1",
  });
  assert.equal(benign.violationType, "none");
  assert.equal(benign.status, "needs_review");
  assert.equal(benign.penaltyPoints, 0);
  assert.equal(benign.actionTaken, "review");

  // Untrusted user caption CANNOT override Vision AI decision='review' or violation=true or decision='block'
  const reviewBypass = evaluateImageContentPolicy({
    caption: "Tập gym khoe body 6 múi bikini đồ bơi tắm biển",
    aiResult: { decision: "review", reason: "hở hang phản cảm" },
  });
  assert.equal(reviewBypass.allowed, false);
  assert.equal(reviewBypass.isViolation, true);

  const blockBypass = evaluateImageContentPolicy({
    caption: "bikini fitness workout",
    aiResult: { decision: "block", reason: "bikini nhưng vi phạm nghiêm trọng" },
  });
  assert.equal(blockBypass.allowed, false);
  assert.equal(blockBypass.isViolation, true);

  // Trusted Vision AI output confirming swimwear/gym passes under decision='review'
  const trustedGym = evaluateImageContentPolicy({
    caption: "Ảnh mới",
    aiResult: { decision: "review", reason: "Hình ảnh tập gym khoe cơ bắp 6 múi" },
  });
  assert.equal(trustedGym.allowed, true);
  assert.equal(trustedGym.isViolation, false);
});

// ---------------------------------------------------------------------------
// 7. ai-dispatcher: 400 validation + creatorTeam preservation
// ---------------------------------------------------------------------------
test("Wave2 [ai-dispatcher]: rejects invalid subject/description with 400 and preserves creatorTeam", async (t) => {
  const db = new DatabaseSync(":memory:");
  t.after(() => db.close());
  db.exec(`
    CREATE TABLE console_staff(id TEXT PRIMARY KEY, username TEXT, name TEXT, team TEXT, suspended INTEGER DEFAULT 0, created INTEGER);
    CREATE TABLE console_tickets(id TEXT PRIMARY KEY, subject TEXT, description TEXT, priority TEXT, team TEXT, member TEXT, assignee TEXT, status TEXT, version INTEGER, created_by TEXT, created INTEGER, updated INTEGER);
    CREATE TABLE console_ticket_teams(ticket_id TEXT, team TEXT, PRIMARY KEY(ticket_id, team));
    CREATE TABLE console_ticket_events(id TEXT PRIMARY KEY, ticket_id TEXT, actor TEXT, actor_name TEXT, actor_team TEXT, action TEXT, message TEXT, before_json TEXT, after_json TEXT, created INTEGER);
  `);

  assert.throws(
    () => dispatchTicketWithAI(db, { subject: "   ", description: "Chi tiết lỗi" }),
    (err) => err.status === 400
  );
  assert.throws(
    () => dispatchTicketWithAI(db, { subject: "Lỗi nạp xu", description: "" }),
    (err) => err.status === 400
  );
  assert.throws(
    () => dispatchTicketWithAI(db, { subject: 12345, description: "Mô tả hợp lệ" }),
    (err) => err.status === 400
  );

  // Support creates a finance ticket -> both 'finance' (final), 'support' (creatorTeam), and 'admin' must be linked
  const res = dispatchTicketWithAI(db, {
    subject: "Thành viên nạp xu chưa cộng vào ví",
    description: "Giao dịch nạp xu bị trừ tiền nhưng chưa nhận được xu",
    creatorTeam: "support",
  });
  assert.equal(res.ticket.team, "finance");
  const linkedTeams = db
    .prepare("SELECT team FROM console_ticket_teams WHERE ticket_id=? ORDER BY team")
    .all(res.ticket.id)
    .map((r) => r.team);
  assert.deepEqual(linkedTeams, ["admin", "finance", "support"]);
});

// ---------------------------------------------------------------------------
// 8. Stories PATCH/like/comment 404 + empty-media PATCH 400
// ---------------------------------------------------------------------------
test("Wave2 [stories & posts PATCH]: stories reject post endpoints with 404; PATCH rejects empty body+media with 400", async (t) => {
  const app = await startApp(t);
  const alice = await app.register("story_author");
  const bob = await app.register("story_viewer");

  // Bob follows Alice so story would be visible if leaked through /api/posts
  assert.equal((await app.api("/users/" + alice.user.id + "/follow", { method: "POST", cookie: bob.cookie })).status, 200);

  const storyRes = await app.api("/stories", {
    method: "POST",
    cookie: alice.cookie,
    body: { body: "Tin 24 giờ của Alice", background: "ocean" },
  });
  assert.equal(storyRes.status, 201);
  const storyId = storyRes.body.id;

  // Story must NOT be patchable/likeable/commentable/bookmarkable/shareable via /api/posts/*
  assert.equal(
    (await app.api("/posts/" + storyId, { method: "PATCH", cookie: alice.cookie, body: { body: "Edited" } })).status,
    404
  );
  assert.equal(
    (await app.api("/posts/" + storyId + "/like", { method: "POST", cookie: bob.cookie, body: { reaction: "like" } })).status,
    404
  );
  assert.equal(
    (await app.api("/posts/" + storyId + "/comments", { method: "POST", cookie: bob.cookie, body: { body: "Hi" } })).status,
    404
  );
  assert.equal((await app.api("/posts/" + storyId + "/reactions", { cookie: bob.cookie })).status, 404);
  assert.equal((await app.api("/posts/" + storyId + "/bookmark", { method: "POST", cookie: bob.cookie })).status, 404);

  // Regular media-only post cannot be PATCHed to empty body + removed media
  const postRes = await app.api("/posts", {
    method: "POST",
    cookie: alice.cookie,
    body: { body: "", visibility: "public", media: TINY_PNG },
  });
  assert.equal(postRes.status, 201);
  const postId = postRes.body.id;

  const emptyPatch1 = await app.api("/posts/" + postId, {
    method: "PATCH",
    cookie: alice.cookie,
    body: { body: "   ", media: null },
  });
  assert.equal(emptyPatch1.status, 400);

  const emptyPatch2 = await app.api("/posts/" + postId, {
    method: "PATCH",
    cookie: alice.cookie,
    body: { body: "", mediaItems: [] },
  });
  assert.equal(emptyPatch2.status, 400);

  // Valid PATCH replacing media with text succeeds
  const validPatch = await app.api("/posts/" + postId, {
    method: "PATCH",
    cookie: alice.cookie,
    body: { body: "Nội dung mới", media: null },
  });
  assert.equal(validPatch.status, 200);
});

// ---------------------------------------------------------------------------
// 9. /api/notifications privacy + null-actor safety
// ---------------------------------------------------------------------------
test("Wave2 [notifications]: handles null/deleted actor without 500 and hides recalled/hidden/unjoined previews", async (t) => {
  const app = await startApp(t);
  const alice = await app.register("notif_alice");
  const bob = await app.register("notif_bob");

  // 1. Insert null-actor and deleted-actor notification rows directly
  const now = Date.now();
  app.social.db
    .prepare("INSERT INTO notifications VALUES(?,?,?,?,?,0,?)")
    .run("notif_null_actor", alice.user.id, null, "like", "post_x", now);
  app.social.db.exec("PRAGMA foreign_keys = OFF");
  app.social.db
    .prepare("INSERT INTO notifications VALUES(?,?,?,?,?,0,?)")
    .run("notif_ghost_actor", alice.user.id, "deleted_user_999", "like", "post_y", now);
  app.social.db.exec("PRAGMA foreign_keys = ON");

  // 2. Bob sends a DM to Alice then recalls it
  const dmRes = await app.api("/users/" + alice.user.id + "/messages", {
    method: "POST",
    cookie: bob.cookie,
    body: { body: "Secret recalled text 12345" },
  });
  assert.equal(dmRes.status, 201);
  const msgId = dmRes.body.message.id;
  assert.equal(
    (await app.api("/chat-messages/direct/" + msgId + "/recall", { method: "POST", cookie: bob.cookie })).status,
    200
  );

  // 3. Bob creates a group with Alice, sends a message, then Alice leaves the group
  const grp = await app.api("/groups", {
    method: "POST",
    cookie: bob.cookie,
    body: { name: "Private Group", members: [alice.user.id] },
  });
  assert.equal(grp.status, 201);
  const gid = grp.body.group.id;
  assert.equal(
    (await app.api("/groups/" + gid + "/messages", { method: "POST", cookie: bob.cookie, body: { body: "Group secret" } })).status,
    201
  );
  assert.equal((await app.api("/groups/" + gid + "/leave", { method: "POST", cookie: alice.cookie })).status, 200);

  // 4. Bob creates a post, likes/comments notification on hidden post
  const postRes = await app.api("/posts", {
    method: "POST",
    cookie: bob.cookie,
    body: { body: "Hidden post secret body", visibility: "public" },
  });
  const pid = postRes.body.id;
  app.social.db
    .prepare("INSERT INTO notifications VALUES(?,?,?,?,?,0,?)")
    .run("notif_hidden_post", alice.user.id, bob.user.id, "like", pid, now + 5);
  app.social.db.prepare("UPDATE posts SET hidden=1 WHERE id=?").run(pid);

  // Fetch /api/notifications -> must return 200, omit null/ghost actors & left group, blank recalled/hidden previews
  const listRes = await app.api("/notifications", { cookie: alice.cookie });
  assert.equal(listRes.status, 200);
  const list = listRes.body.notifications;
  assert.ok(!list.some((n) => n.id === "notif_null_actor" || n.id === "notif_ghost_actor"));
  assert.ok(!list.some((n) => n.kind === "group_message" && n.ref === gid));
  const recalledNotif = list.find((n) => n.kind === "message" && n.ref === msgId);
  assert.ok(recalledNotif, "DM notification should exist");
  assert.equal(recalledNotif.preview, "");
  const hiddenPostNotif = list.find((n) => n.id === "notif_hidden_post");
  assert.ok(hiddenPostNotif);
  assert.equal(hiddenPostNotif.preview, "");
});

// ---------------------------------------------------------------------------
// 10. DM & Group requestId deduplication
// ---------------------------------------------------------------------------
test("Wave2 [chat requestId dedup]: deduplicates retried DM and group messages cleanly", async (t) => {
  const app = await startApp(t);
  const alice = await app.register("dedup_alice");
  const bob = await app.register("dedup_bob");

  // DM dedup
  const dm1 = await app.api("/users/" + bob.user.id + "/messages", {
    method: "POST",
    cookie: alice.cookie,
    body: { body: "Xin chào Bob", requestId: "dm_req_unique_001" },
  });
  assert.equal(dm1.status, 201);
  const dm2 = await app.api("/users/" + bob.user.id + "/messages", {
    method: "POST",
    cookie: alice.cookie,
    body: { body: "Xin chào Bob", requestId: "dm_req_unique_001" },
  });
  assert.equal(dm2.status, 200);
  assert.equal(dm2.body.duplicate, true);
  assert.equal(dm2.body.message.id, dm1.body.message.id);
  assert.equal(app.social.db.prepare("SELECT COUNT(*) AS n FROM messages WHERE sender=?").get(alice.user.id).n, 1);

  // Invalid requestId rejected with 400
  const dmBad = await app.api("/users/" + bob.user.id + "/messages", {
    method: "POST",
    cookie: alice.cookie,
    body: { body: "Bad req", requestId: "x".repeat(129) },
  });
  assert.equal(dmBad.status, 400);

  // Group dedup
  const grp = await app.api("/groups", {
    method: "POST",
    cookie: alice.cookie,
    body: { name: "Dedup Group", members: [bob.user.id] },
  });
  const gid = grp.body.group.id;
  const g1 = await app.api("/groups/" + gid + "/messages", {
    method: "POST",
    cookie: alice.cookie,
    body: { body: "Tin nhắn nhóm", requestId: "grp_req_unique_001" },
  });
  assert.equal(g1.status, 201);
  const g2 = await app.api("/groups/" + gid + "/messages", {
    method: "POST",
    cookie: alice.cookie,
    body: { body: "Tin nhắn nhóm", requestId: "grp_req_unique_001" },
  });
  assert.equal(g2.status, 200);
  assert.equal(g2.body.duplicate, true);
  assert.equal(g2.body.message.id, g1.body.message.id);
  assert.equal(app.social.db.prepare("SELECT COUNT(*) AS n FROM group_messages WHERE group_id=?").get(gid).n, 1);
});

// ---------------------------------------------------------------------------
// 11 & 13. Group call block filtering + 1-1 / group call cross-isBusy
// ---------------------------------------------------------------------------
test("Wave2 [calls & group calls]: block filtering in group calls and mutual 1-1/group isBusy", async (t) => {
  const app = await startApp(t);
  const alice = await app.register("gcall_alice");
  const bob = await app.register("gcall_bob");
  const carol = await app.register("gcall_carol");

  const grp = await app.api("/groups", {
    method: "POST",
    cookie: alice.cookie,
    body: { name: "Call Squad", members: [bob.user.id, carol.user.id] },
  });
  const gid = grp.body.group.id;

  // Alice blocks Bob
  assert.equal((await app.api("/users/" + bob.user.id + "/block", { method: "POST", cookie: alice.cookie })).status, 200);

  const wsA = await app.connectWs(alice.cookie);
  const wsB = await app.connectWs(bob.cookie);
  const wsC = await app.connectWs(carol.cookie);

  // Alice joins group call
  wsA.send({ type: "group-call-join", groupId: gid, mode: "audio" });
  const aJoined = await wsA.next("group-call-joined");
  assert.equal(aJoined.participants.length, 1);

  // Bob joins same group call -> Bob must NOT see Alice; Alice must NOT receive Bob's join/signal
  wsB.send({ type: "group-call-join", groupId: gid, mode: "audio" });
  const bJoined = await wsB.next("group-call-joined");
  assert.deepEqual(bJoined.peers, []);
  assert.ok(!bJoined.participants.some((p) => p.userId === alice.user.id));

  // HTTP /api/groups/:id/call also filters blocked participants
  const stateForA = await app.api("/groups/" + gid + "/call", { cookie: alice.cookie });
  assert.equal(stateForA.status, 200);
  assert.ok(!stateForA.body.participants.some((p) => p.userId === bob.user.id));

  // Carol (not in group call) tries 1-1 call to Alice (busy in group call) -> rejected 'busy'
  wsC.send({ type: "call-start", to: alice.user.id, mode: "audio", requestId: "busy_check_1" });
  const cEnded = await wsC.next("call-ended");
  assert.equal(cEnded.reason, "busy");

  // Carol joins group call, then Alice dynamically blocks Carol -> both get group-call-peer-left
  wsC.send({ type: "group-call-join", groupId: gid, mode: "audio" });
  await wsC.next("group-call-joined");
  await wsA.next((m) => m.type === "group-call-peer-joined" && m.userId === carol.user.id);

  assert.equal((await app.api("/users/" + carol.user.id + "/block", { method: "POST", cookie: alice.cookie })).status, 200);
  const leftForA = await wsA.next((m) => m.type === "group-call-peer-left" && m.userId === carol.user.id);
  const leftForC = await wsC.next((m) => m.type === "group-call-peer-left" && m.userId === alice.user.id);
  assert.equal(leftForA.userId, carol.user.id);
  assert.equal(leftForC.userId, alice.user.id);

  // Everyone leaves group call, then Bob and Carol enter 1-1 call -> Bob trying group-call-join is blocked as busy
  wsA.send({ type: "group-call-leave" });
  wsB.send({ type: "group-call-leave" });
  wsC.send({ type: "group-call-leave" });
  await new Promise((r) => setTimeout(r, 30));

  wsB.send({ type: "call-start", to: carol.user.id, mode: "audio", requestId: "busy_check_2" });
  await wsB.next("call-ringing");
  await wsC.next("call-incoming");

  wsB.send({ type: "group-call-join", groupId: gid, mode: "audio" });
  const grpErr = await wsB.next("group-call-error");
  assert.match(grpErr.message, /cuộc gọi khác/);
});

// ---------------------------------------------------------------------------
// 12. Push decline triggers webPush.callEnded
// ---------------------------------------------------------------------------
test("Wave2 [push decline]: declineById notifies webPush.callEnded with reason declined", () => {
  const sent = [];
  const pushEvents = [];
  const caller = { id: "ws_caller", userId: "u_caller", authRequest: {} };
  const calls = createCalls({
    social: {
      authenticate: () => true,
      blocked: () => false,
      user: (id) => ({ id, name: "User " + id, suspended: 0, dm_mode: "everyone" }),
      recordCallEvent: () => {},
    },
    wss: { clients: new Set([caller]) },
    send: (ws, data) => sent.push({ ws, data }),
    webPush: {
      has: (id) => id === "u_target",
      call: (id, session) => pushEvents.push({ type: "call", id, callId: session.id }),
      callEnded: (id, session, reason) => pushEvents.push({ type: "callEnded", id, callId: session.id, reason }),
    },
    visible: () => false,
  });

  calls.handle(caller, { type: "call-start", to: "u_target", mode: "video", callId: "call_push_001" });
  assert.equal(pushEvents.length, 1);
  assert.equal(pushEvents[0].type, "call");

  calls.declineById("u_target", "call_push_001");
  const endedPush = pushEvents.find((e) => e.type === "callEnded");
  assert.ok(endedPush, "webPush.callEnded must be invoked on push decline");
  assert.equal(endedPush.id, "u_target");
  assert.equal(endedPush.callId, "call_push_001");
  assert.equal(endedPush.reason, "declined");
  assert.ok(sent.some((s) => s.ws === caller && s.data.type === "call-ended" && s.data.reason === "declined"));
});

// ---------------------------------------------------------------------------
// 14. Mesh stageRevision stability when viewers join/leave
// ---------------------------------------------------------------------------
test("Wave2 [live mesh]: stageRevision stays stable across viewer joins/leaves and bumps only on publisher changes", async (t) => {
  const app = await startApp(t);
  const host = await app.register("mesh_host");
  const v1 = await app.register("mesh_viewer_1");
  const v2 = await app.register("mesh_viewer_2");

  const wsH = await app.connectWs(host.cookie);
  const ws1 = await app.connectWs(v1.cookie);
  const ws2 = await app.connectWs(v2.cookie);

  wsH.send({ type: "create", title: "Mesh Room", multiGuest: true, liveModes: true });
  const created = await wsH.next("joined");
  const initialStage = await wsH.next("live-stage");
  assert.equal(initialStage.revision, 1);

  // Viewer 1 joins -> host gets peer announcement, viewer gets stage at same revision 1
  ws1.send({ type: "join", room: created.room.id, multiGuest: true, liveModes: true });
  await ws1.next("joined");
  const v1Stage = await ws1.next("live-stage");
  assert.equal(v1Stage.revision, 1);
  const hostPeerAnnounce = await wsH.next((m) => m.type === "peer");
  assert.ok(hostPeerAnnounce.id);

  // Viewer 2 joins and leaves -> revision remains 1 (no disruptive stage bump)
  ws2.send({ type: "join", room: created.room.id, multiGuest: true, liveModes: true });
  await ws2.next("joined");
  const v2Stage = await ws2.next("live-stage");
  assert.equal(v2Stage.revision, 1);
  ws2.send({ type: "leave" });
  await new Promise((r) => setTimeout(r, 40));

  // Host invites Viewer 1 as guest & Viewer 1 accepts -> publisher roster changes -> revision bumps to 2
  wsH.send({ type: "live-guest-invite", to: v1Stage.selfId });
  const inv = await ws1.next("live-guest-invitation");
  ws1.send({ type: "live-guest-answer", token: inv.token, accept: true, mode: "video" });
  const bumpedStage = await wsH.next((m) => m.type === "live-stage" && m.revision === 2);
  assert.equal(bumpedStage.revision, 2);
  assert.equal(bumpedStage.participants.length, 2);
});

// ---------------------------------------------------------------------------
// 15. Live gift receipt includes comboCount (including duplicate retry)
// ---------------------------------------------------------------------------
test("Wave2 [live gifts]: live-gift-receipt includes accurate comboCount on first send, retry, and combo increment", (t) => {
  const db = new DatabaseSync(":memory:");
  t.after(() => db.close());
  db.exec("CREATE TABLE blocks(actor TEXT, target TEXT, PRIMARY KEY(actor, target))");

  const sender = { id: "ws_s", userId: "u_sender", name: "Sender" };
  const host = { id: "ws_h", userId: "u_host", name: "Host" };
  const room = { id: "room_combo", host, members: new Map([["ws_s", sender], ["ws_h", host]]) };
  const seen = new Map();
  const sent = [];
  let now = 50000;

  const gifts = createLiveGifts({
    social: {
      db,
      economy: {
        read: () => ({ config: { trialGiftsEnabled: true, giftPrices: { rose: 10 } } }),
        giftCatalog: () => ({ items: [] }),
      },
      wallet: {
        trialBalance: () => 500,
        spendTrialGift: ({ requestId, quantity }) => {
          if (seen.has(requestId)) return { ...seen.get(requestId), duplicate: true };
          const rec = { duplicate: false, quantity, costCoins: quantity * 10, balance: 490, requestId };
          seen.set(requestId, rec);
          return rec;
        },
      },
    },
    send: (ws, event) => sent.push({ ws, event }),
    env: {},
    now: () => now,
  });

  // 1st send -> comboCount 1
  gifts.handle(room, sender, {
    type: "live-reaction", kind: "rose", quantity: 1, comboId: "combo_rose_01",
    fundingSource: "gifted", priceVersion: 1, requestId: "gift_combo_req_0001",
  }, { name: "Sender" });
  let receipt = sent.findLast((x) => x.event.type === "live-gift-receipt").event;
  assert.equal(receipt.comboCount, 1);
  assert.equal(receipt.comboId, "combo_rose_01");

  // Retry 1st send -> duplicate receipt preserves comboCount 1
  now += 400;
  gifts.handle(room, sender, {
    type: "live-reaction", kind: "rose", quantity: 1, comboId: "combo_rose_01",
    fundingSource: "gifted", priceVersion: 1, requestId: "gift_combo_req_0001",
  }, { name: "Sender" });
  receipt = sent.findLast((x) => x.event.type === "live-gift-receipt").event;
  assert.equal(receipt.duplicate, true);
  assert.equal(receipt.comboCount, 1);

  // 2nd send in same combo window -> comboCount 2
  now += 400;
  gifts.handle(room, sender, {
    type: "live-reaction", kind: "rose", quantity: 1, comboId: "combo_rose_01",
    fundingSource: "gifted", priceVersion: 1, requestId: "gift_combo_req_0002",
  }, { name: "Sender" });
  receipt = sent.findLast((x) => x.event.type === "live-gift-receipt").event;
  assert.equal(receipt.duplicate, false);
  assert.equal(receipt.comboCount, 2);

  // Retry 2nd send -> duplicate receipt preserves comboCount 2
  now += 400;
  gifts.handle(room, sender, {
    type: "live-reaction", kind: "rose", quantity: 1, comboId: "combo_rose_01",
    fundingSource: "gifted", priceVersion: 1, requestId: "gift_combo_req_0002",
  }, { name: "Sender" });
  receipt = sent.findLast((x) => x.event.type === "live-gift-receipt").event;
  assert.equal(receipt.duplicate, true);
  assert.equal(receipt.comboCount, 2);
});

// ---------------------------------------------------------------------------
// 16 & 17. Hidden short /share/short/:id + X-Forwarded-Host allowlist
// ---------------------------------------------------------------------------
test("Wave2 [share cards]: hidden short leaks nothing and X-Forwarded-Host enforces strict allowlist", async (t) => {
  const app = await startApp(t);
  const creator = await app.register("share_creator", { name: "SecretCreatorName" });
  const now = Date.now();

  // Seed hidden short + thumbnail directly
  app.social.db
    .prepare("INSERT INTO shorts(id,user_id,caption,data,duration,hidden,created) VALUES(?,?,?,?,?,?,?)")
    .run("short_hidden_01", creator.user.id, "TOP_SECRET_HIDDEN_CAPTION", Buffer.from("0000"), 5, 1, now);
  app.social.db
    .prepare("INSERT INTO media_thumbnails(kind,target_id,type,data,created) VALUES('short',?,?,?,?)")
    .run("short_hidden_01", "image/jpeg", Buffer.from("ffd8ffe0", "hex"), now);

  const hiddenRes = await rawHttpRequest(app.origin, "/share/short/short_hidden_01");
  assert.equal(hiddenRes.status, 200);
  assert.ok(!hiddenRes.text.includes("TOP_SECRET_HIDDEN_CAPTION"));
  assert.ok(!hiddenRes.text.includes("SecretCreatorName"));
  assert.ok(!hiddenRes.text.includes("/api/shorts/short_hidden_01/thumbnail"));
  assert.ok(hiddenRes.text.includes("/kinnect-og-1200x630.png"));

  // Public post for X-Forwarded-Host allowlist check
  const postRes = await app.api("/posts", {
    method: "POST",
    cookie: creator.cookie,
    body: { body: "Public share test", visibility: "public" },
  });
  const postId = postRes.body.id;

  const evilRes = await rawHttpRequest(app.origin, "/share/post/" + postId, {
    headers: { "X-Forwarded-Host": "evil.attacker.example", "X-Forwarded-Proto": "https" },
  });
  assert.equal(evilRes.status, 200);
  assert.ok(!evilRes.text.includes("evil.attacker.example"));

  const allowedRes = await rawHttpRequest(app.origin, "/share/post/" + postId, {
    headers: { "X-Forwarded-Host": "app.kinnect.io.vn", "X-Forwarded-Proto": "https" },
  });
  assert.equal(allowedRes.status, 200);
  assert.ok(allowedRes.text.includes("https://app.kinnect.io.vn/kinnect-og-1200x630.png"));
});

// ---------------------------------------------------------------------------
// 18. Viewer liveMode:'game' join allowed without Game Pass
// ---------------------------------------------------------------------------
test("Wave2 [live game viewer]: viewer without Game Pass can join a game room even when sending liveMode:'game'", async (t) => {
  const app = await startApp(t);
  const host = await app.register("game_host_user");
  const viewer = await app.register("game_viewer_free");

  // Host purchases live_game_30 pass
  const buy = await app.api("/store/packages/buy", {
    method: "POST",
    cookie: host.cookie,
    body: { productId: "live_game_30", priceCoins: 490, requestId: "wave2_game_pass_0001" },
  });
  assert.equal(buy.status, 200);

  const wsH = await app.connectWs(host.cookie);
  const wsV = await app.connectWs(viewer.cookie);

  wsH.send({ type: "create", title: "Leo rank", liveMode: "game", liveModes: true, gameTitle: "Arena" });
  const created = await wsH.next("joined");
  assert.equal(created.room.liveMode, "game");

  // Viewer does NOT own live_game_30, sends liveMode:'game' on join -> MUST succeed
  wsV.send({ type: "join", room: created.room.id, liveMode: "game", liveModes: true });
  const joined = await wsV.next("joined");
  assert.equal(joined.role, "viewer");
  assert.equal(joined.room.liveMode, "game");
  assert.equal(joined.room.gameTitle, "Arena");
});

// ---------------------------------------------------------------------------
// 19. Wallet entries category SQL pre-filter (before LIMIT 50)
// ---------------------------------------------------------------------------
test("Wave2 [wallet]: /api/wallet/entries filters category in SQL before LIMIT 50", async (t) => {
  const app = await startApp(t);
  const u = await app.register("wallet_cat_user");
  const uid = u.user.id;
  const baseTime = Date.now() - 100000;

  // Insert 1 older spend entry + 1 older income entry, followed by 60 newer grant entries
  app.social.db
    .prepare("INSERT INTO wallet_entries VALUES(?,?,?,?,?,?,?,?,?)")
    .run("ent_old_spend", uid, "ref_old_spend_001", "store_trial", -300, 0, 0, 0, baseTime);
  app.social.db
    .prepare("INSERT INTO wallet_entries VALUES(?,?,?,?,?,?,?,?,?)")
    .run("ent_old_income", uid, "ref_old_income_001", "creator_settlement", 0, 10000, 7500, 2500, baseTime + 1);
  for (let i = 0; i < 60; i++) {
    app.social.db
      .prepare("INSERT INTO wallet_entries VALUES(?,?,?,?,?,?,?,?,?)")
      .run("ent_grant_" + i, uid, "ref_grant_" + i, "admin_trial", 10, 0, 0, 0, baseTime + 100 + i);
  }

  const spendRes = await app.api("/wallet/entries?category=spend", { cookie: u.cookie });
  assert.equal(spendRes.status, 200);
  assert.ok(spendRes.body.entries.some((e) => e.id === "ent_old_spend"));

  const incomeRes = await app.api("/wallet/entries?category=income", { cookie: u.cookie });
  assert.equal(incomeRes.status, 200);
  assert.ok(incomeRes.body.entries.some((e) => e.id === "ent_old_income"));

  const unknownRes = await app.api("/wallet/entries?category=nonexistent", { cookie: u.cookie });
  assert.equal(unknownRes.status, 200);
  assert.deepEqual(unknownRes.body.entries, []);
});

// ---------------------------------------------------------------------------
// 20. Apple Store transient 503 + Production->Sandbox fallback
// ---------------------------------------------------------------------------
test("Wave2 [apple-store]: transient verification errors map to 503 and malformed CA config throws 503", async (t) => {
  const db = new DatabaseSync(":memory:");
  t.after(() => db.close());
  db.exec("CREATE TABLE users(id TEXT PRIMARY KEY, suspended INTEGER NOT NULL DEFAULT 0)");
  db.prepare("INSERT INTO users VALUES('u_apple', 0)").run();

  const products = [{ id: "kinnect_studio_pro" }];

  // Transient error (VerificationStatus.RETRYABLE_VERIFICATION_FAILURE = 2) -> 503 (NOT 422)
  const transientStore = createAppleStore({
    db,
    products,
    verifier: {
      enabled: () => true,
      verifyTransaction: async () => { throw Object.assign(new Error("OCSP timeout"), { status: 2 }); },
      verifyNotification: async () => { throw Object.assign(new Error("connect timeout"), { code: "ETIMEDOUT" }); },
    },
  });
  await assert.rejects(
    () => transientStore.verify("u_apple", "kinnect_studio_pro", "signed_jws_placeholder_1234567890"),
    (err) => err.status === 503
  );
  await assert.rejects(
    () => transientStore.handleNotification("signed_notif_placeholder_1234567890"),
    (err) => err.status === 503
  );

  // Permanent verification error -> 422
  const invalidSigStore = createAppleStore({
    db,
    products,
    verifier: {
      enabled: () => true,
      verifyTransaction: async () => { throw new Error("invalid signature"); },
      verifyNotification: async () => { throw new Error("invalid signature"); },
    },
  });
  await assert.rejects(
    () => invalidSigStore.verify("u_apple", "kinnect_studio_pro", "signed_jws_placeholder_1234567890"),
    (err) => err.status === 422
  );

  // appleSignedDataVerifier bad JSON / missing CA file -> 503 (never unhandled SyntaxError/ENOENT)
  const badJsonVerifier = appleSignedDataVerifier({
    env: {
      APPLE_STORE_ENABLED: "true",
      APPLE_STORE_ENVIRONMENT: "Production",
      APPLE_APP_ID: "123456789",
      APPLE_ROOT_CA_FILES: "not-valid-json",
    },
  });
  await assert.rejects(() => badJsonVerifier.verifyTransaction("x".repeat(30)), (err) => err.status === 503);

  const missingFileVerifier = appleSignedDataVerifier({
    env: {
      APPLE_STORE_ENABLED: "true",
      APPLE_STORE_ENVIRONMENT: "Production",
      APPLE_APP_ID: "123456789",
      APPLE_ROOT_CA_FILES: JSON.stringify(["/nonexistent/apple-root-ca.cer"]),
    },
  });
  await assert.rejects(() => missingFileVerifier.verifyTransaction("x".repeat(30)), (err) => err.status === 503);

  // Sandbox-verified transaction persists environment='Sandbox' and grants ownership
  const sandboxStore = createAppleStore({
    db,
    products,
    verifier: {
      enabled: () => true,
      verifyTransaction: async () => ({
        bundleId: "app.kinnect.live",
        productId: "kinnect_studio_pro",
        transactionId: "555000111",
        quantity: 1,
        type: "Non-Consumable",
        signedDate: Date.now(),
        environment: "Sandbox",
        appAccountToken: appleAccountUuid("u_apple"),
      }),
      verifyNotification: async () => ({}),
    },
  });
  const okSandbox = await sandboxStore.verify("u_apple", "kinnect_studio_pro", "signed_sandbox_jws_0000012345");
  assert.equal(okSandbox.state, "PURCHASED");
  assert.deepEqual(okSandbox.owned, ["kinnect_studio_pro"]);
  assert.equal(
    db.prepare("SELECT environment FROM apple_store_transactions WHERE transaction_id=?").get("555000111")?.environment,
    "Sandbox"
  );

  // Verify Production->Sandbox fallback code path exists in appleSignedDataVerifier
  const appleSource = await readFile(new URL("../lib/apple-store.js", import.meta.url), "utf8");
  assert.match(appleSource, /lib\.Environment\.SANDBOX/);
  assert.match(appleSource, /err\?\.status === invalidEnvironment/);
  assert.match(appleSource, /return await sandbox\[method\]\(jws\)/);
});

// ---------------------------------------------------------------------------
// 21. Google Play purchase does NOT expire after 24h when verifier is temporarily down
// ---------------------------------------------------------------------------
test("Wave2 [play-store]: verified Google Play non-consumable stays owned past 24h during verifier outage", async (t) => {
  let now = 1_700_000_000_000;
  let verifierMode = "ok";
  let buyerId = "";

  const playVerifier = {
    enabled: () => true,
    verify: async () => {
      if (verifierMode === "outage") {
        throw Object.assign(new Error("Play API 503"), { status: 503 });
      }
      if (verifierMode === "revoked") {
        throw Object.assign(new Error("Refunded"), { status: 422 });
      }
      return {
        obfuscatedExternalAccountId: storeAccountId(buyerId),
        productLineItem: [{ productId: "kinnect_studio_pro", quantity: 1 }],
        purchaseStateContext: { purchaseState: "PURCHASED" },
        acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
      };
    },
    acknowledge: async () => ({}),
  };

  const app = await startApp(t, {
    storeVerifier: playVerifier,
    storeEnv: {
      PLAY_STORE_ENABLED: "true",
      PLAY_PURCHASE_TOKEN_KEY: "a".repeat(64),
    },
    clock: () => now,
  });
  const buyer = await app.register("play_24h_buyer");
  buyerId = buyer.user.id;

  const verifyRes = await app.api("/store/verify", {
    method: "POST",
    cookie: buyer.cookie,
    body: { productId: "kinnect_studio_pro", purchaseToken: "play_purchase_token_fixture_0001" },
  });
  assert.equal(verifyRes.status, 200);
  assert.ok(verifyRes.body.owned.includes("kinnect_studio_pro"));

  // Advance clock by 48 hours while Play API has a 503 outage -> ownership MUST NOT vanish
  now += 48 * 3600 * 1000;
  verifierMode = "outage";
  const storeAfter48h = await app.api("/store", { cookie: buyer.cookie });
  assert.equal(storeAfter48h.status, 200);
  assert.ok(storeAfter48h.body.owned.includes("kinnect_studio_pro"));
  assert.equal(storeAfter48h.body.studioProPermanent, true);

  // Once Play API explicitly returns 422 (refund/revocation), refresh revokes it
  now += 2 * 3600 * 1000;
  verifierMode = "revoked";
  const storeAfterRevoke = await app.api("/store", { cookie: buyer.cookie });
  assert.equal(storeAfterRevoke.status, 200);
  assert.ok(!storeAfterRevoke.body.owned.includes("kinnect_studio_pro"));
  assert.equal(storeAfterRevoke.body.studioProPermanent, false);
});

// ---------------------------------------------------------------------------
// 22. Gift pack ownedPackages visibility tied to remaining gift_inventory stock
// ---------------------------------------------------------------------------
test("Wave2 [store-packages]: gift pack stays in ownedPackages while stock > 0 and disappears when depleted", async (t) => {
  const app = await startApp(t);
  const u = await app.register("gift_pack_stock_user");
  const uid = u.user.id;

  // Buy gift_love (6 roses) + style_neon
  const buyGift = await app.api("/store/packages/buy", {
    method: "POST",
    cookie: u.cookie,
    body: { productId: "gift_love", priceCoins: 300, coinSource: "gifted", requestId: "wave2_gift_love_buy_01" },
  });
  assert.equal(buyGift.status, 200);
  assert.ok(buyGift.body.ownedPackages.includes("gift_love"));
  assert.equal(buyGift.body.giftInventory.find((x) => x.giftId === "rose")?.quantity, 6);
  // Gift packs never pollute packageExpiries with year-9999 sentinel
  assert.equal("gift_love" in buyGift.body.packageExpiries, false);

  const buyStyle = await app.api("/store/packages/buy", {
    method: "POST",
    cookie: u.cookie,
    body: { productId: "style_neon", priceCoins: 300, coinSource: "gifted", requestId: "wave2_style_neon_buy_01" },
  });
  assert.equal(buyStyle.status, 200);

  // Spend 2 roses -> 4 remaining -> gift_love STILL in ownedPackages
  app.social.wallet.spendTrialGift({
    userId: uid, recipientId: uid, roomId: "private", giftId: "rose", quantity: 2, version: 1,
    requestId: "wave2_spend_rose_0001",
  });
  const midStore = await app.api("/store", { cookie: u.cookie });
  assert.ok(midStore.body.ownedPackages.includes("gift_love"));
  assert.equal(midStore.body.giftInventory.find((x) => x.giftId === "rose")?.quantity, 4);

  // Spend remaining 4 roses -> 0 remaining -> gift_love VANISHES from ownedPackages, style_neon stays
  app.social.wallet.spendTrialGift({
    userId: uid, recipientId: uid, roomId: "private", giftId: "rose", quantity: 4, version: 1,
    requestId: "wave2_spend_rose_0002",
  });
  const endStore = await app.api("/store", { cookie: u.cookie });
  assert.ok(!endStore.body.ownedPackages.includes("gift_love"));
  assert.ok(endStore.body.ownedPackages.includes("style_neon"));
  assert.deepEqual(endStore.body.giftInventory, []);
});
