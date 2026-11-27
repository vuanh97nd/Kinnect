import test from "node:test";
import assert from "node:assert/strict";
import { WebSocket } from "ws";
import { createSecurityNotifier } from "../lib/security-notifier.js";
import { createApp } from "../server.js";

test("Security notifier sends Email + Telegram for high/critical alerts with cooldown and skips low severity", async () => {
  const emails = [];
  const telegrams = [];
  let now = 1_700_000_000_000;
  const notifier = createSecurityNotifier({
    env: {
      SECURITY_ALERT_EMAIL: "owner@kinnect.io.vn",
      KINNECT_TELEGRAM_BOT_TOKEN: "12345:TEST_TOKEN",
      KINNECT_TELEGRAM_CHAT_ID: "-100999",
    },
    sendEmail: async (payload) => { emails.push(payload); return true; },
    mailReady: () => true,
    fetchImpl: async (url, init) => {
      telegrams.push({ url, body: JSON.parse(init.body) });
      return { ok: true, status: 200 };
    },
    clock: () => now,
    cooldownMs: 300_000,
  });

  // Low severity skipped
  const r0 = await notifier.notify({ severity: "low", threatType: "benign_anomaly", subjectIp: "1.2.3.4", summary: "noise" });
  assert.equal(r0.sent, false);
  assert.equal(emails.length, 0);

  // High severity sends to both email and telegram
  const r1 = await notifier.notify({
    severity: "high",
    threatType: "brute_force",
    subjectIp: "203.0.113.9",
    summary: "10 failed logins in 60s",
    evidence: ["failed_login x10"],
    autoActionId: "mit-1",
  });
  assert.equal(r1.sent, true);
  assert.deepEqual(r1.channels, ["email", "telegram"]);
  assert.equal(emails.length, 1);
  assert.equal(telegrams.length, 1);
  assert.ok(emails[0].subject.includes("203.0.113.9"));
  assert.equal(telegrams[0].body.chat_id, "-100999");

  // Duplicate within cooldown skipped
  const r2 = await notifier.notify({ severity: "critical", threatType: "brute_force", subjectIp: "203.0.113.9", summary: "again" });
  assert.equal(r2.sent, false);
  assert.equal(r2.reason, "cooldown");

  // After cooldown passes, sends again
  now += 301_000;
  const r3 = await notifier.notify({ severity: "critical", threatType: "brute_force", subjectIp: "203.0.113.9", summary: "continued" });
  assert.equal(r3.sent, true);
  assert.equal(emails.length, 2);
});

test("WebSocket connection closes with 4429 when client IP is actively temp_block_ip mitigated", async () => {
  const { server, wss, social } = createApp({ dbPath: ":memory:" });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const base = "http://127.0.0.1:" + server.address().port;
  try {
    const reg = await fetch(base + "/api/register", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username: "ws_blocked_user", password: "password123", name: "User", agree18: true, acceptPrivacyNotice: true }),
    });
    const cookie = reg.headers.get("set-cookie").split(";")[0];

    social.securityMonitor.applyMitigation({
      action: "temp_block_ip",
      targetType: "ip",
      targetValue: "127.0.0.1",
      ttlSeconds: 300,
      reason: "Test WS block",
      createdBy: "test",
    });

    const closeCode = await new Promise((resolve, reject) => {
      const ws = new WebSocket(base.replace("http://", "ws://") + "/ws", { headers: { Cookie: cookie } });
      ws.once("close", (code) => resolve(code));
      ws.once("error", reject);
    });
    assert.equal(closeCode, 4429);
  } finally {
    for (const c of wss.clients) c.terminate();
    await new Promise((r) => wss.close(r));
    server.closeAllConnections?.();
    await new Promise((r) => server.close(r));
    social.close();
  }
});
