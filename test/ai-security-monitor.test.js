import { test } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createApp } from '../server.js';
import {
  createAiSecurityMonitor,
  sanitizeSecurityMetadata,
  sanitizeSecurityString,
  resolveTrustedClientIp,
  validateAndNormalizeAiAssessment
} from '../lib/ai-security-monitor.js';

async function startApp(options = {}) {
  const app = createApp({ dbPath: ':memory:', ...options });
  app.server.listen(0, '127.0.0.1');
  await once(app.server, 'listening');
  const url = `http://127.0.0.1:${app.server.address().port}`;
  return {
    ...app,
    url,
    async stop() {
      for (const ws of app.wss.clients) ws.terminate();
      await new Promise(r => app.wss.close(r));
      await new Promise(r => app.server.close(r));
      app.social.close();
    }
  };
}

async function apiRequest(app, path, { cookie, method = 'GET', body, headers = {} } = {}) {
  const r = await fetch(app.url + '/api' + path, {
    method,
    headers: {
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      ...(cookie ? { Cookie: cookie } : {}),
      ...headers
    },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  return {
    status: r.status,
    body: await r.json(),
    cookie: r.headers.get('set-cookie')?.split(';')[0],
    headers: r.headers
  };
}

async function registerUser(app, username, role = 'user') {
  const r = await apiRequest(app, '/register', {
    method: 'POST',
    body: {
      username,
      password: 'very-strong-password-123!',
      name: username,
      agree18: true,
      acceptPrivacyNotice: true
    }
  });
  assert.equal(r.status, 200);
  if (role === 'admin') {
    app.social.db.prepare("UPDATE users SET role='admin' WHERE id=?").run(r.body.user.id);
  }
  return { id: r.body.user.id, cookie: r.cookie, username };
}

test('secret & PII redaction removes passwords, tokens, cookies, API keys, emails, and phones before logging or sending to AI', () => {
  const raw = {
    username: 'victim_user',
    password: 'my-secret-password-999',
    token: 'kinnect_session=1234567890abcdef',
    authorization: 'Bearer sk-deepseek1234567890abcdef',
    nested: {
      apiKey: 'nvapi-9876543210abcdef',
      note: 'Contact me at test.user@example.com or +84912345678 with Bearer abc.def.ghi and sk-live1234567890123456'
    }
  };

  const cleaned = sanitizeSecurityMetadata(raw);
  const serialized = JSON.stringify(cleaned);

  assert.equal(cleaned.password, '[REDACTED]');
  assert.equal(cleaned.token, '[REDACTED]');
  assert.equal(cleaned.authorization, '[REDACTED]');
  assert.equal(cleaned.nested.apiKey, '[REDACTED]');
  assert.ok(!serialized.includes('my-secret-password-999'));
  assert.ok(!serialized.includes('sk-deepseek'));
  assert.ok(!serialized.includes('nvapi-'));
  assert.ok(!serialized.includes('test.user@example.com'));
  assert.ok(!serialized.includes('+84912345678'));
  assert.ok(serialized.includes('[REDACTED]'));
});

test('trusted proxy IP resolution rejects spoofed X-Forwarded-For and CF-Connecting-IP from untrusted public sockets', () => {
  const untrustedReq = {
    socket: { remoteAddress: '198.51.100.42' },
    headers: {
      'cf-connecting-ip': '1.2.3.4',
      'x-forwarded-for': '5.6.7.8'
    }
  };
  assert.equal(
    resolveTrustedClientIp(untrustedReq, { KINNECT_TRUSTED_PROXY_MODE: 'cloudflare-local' }),
    '198.51.100.42'
  );

  const localTunnelReq = {
    socket: { remoteAddress: '127.0.0.1' },
    headers: {
      'cf-connecting-ip': '203.0.113.88',
      'x-forwarded-for': '198.51.100.99'
    }
  };
  assert.equal(
    resolveTrustedClientIp(localTunnelReq, { KINNECT_TRUSTED_PROXY_MODE: 'cloudflare-local' }),
    '203.0.113.88'
  );

  const lanSpoofReq = {
    socket: { remoteAddress: '192.168.1.50' },
    headers: {
      'cf-connecting-ip': '1.1.1.1',
      'x-forwarded-for': '8.8.8.8'
    }
  };
  assert.equal(
    resolveTrustedClientIp(lanSpoofReq, { KINNECT_TRUSTED_PROXY_MODE: 'cloudflare-local' }),
    '192.168.1.50'
  );
  assert.equal(
    resolveTrustedClientIp(lanSpoofReq, { KINNECT_TRUSTED_PROXY_MODE: 'cloudflare-lan' }),
    '1.1.1.1'
  );
});

test('AI JSON schema validation enforces enums, evidence, and narrow allowed actions while rejecting malformed payloads', () => {
  assert.throws(() => validateAndNormalizeAiAssessment('not json at all'), /invalid_ai_json_envelope/);
  assert.throws(
    () => validateAndNormalizeAiAssessment(JSON.stringify({ threatType: 'sql_drop_db', severity: 'critical', summary: 'x', evidence: ['e1'] })),
    /invalid_ai_schema_enums/
  );

  const valid = validateAndNormalizeAiAssessment('```json\n' + JSON.stringify({
    threatType: 'data_exfiltration',
    severity: 'critical',
    confidence: 0.94,
    dataLeakRisk: true,
    summary: 'Phát hiện truy xuất hàng loạt danh sách người dùng.',
    evidence: ['GET /api/admin/users count=15'],
    recommendedActions: [
      { action: 'DROP_DATABASE_SHELL', targetType: 'ip', targetValue: '203.0.113.50', ttlSeconds: 600, reason: 'Malicious action' },
      { action: 'throttle_export', targetType: 'ip', targetValue: '203.0.113.50', ttlSeconds: 900, reason: 'Chặn trích xuất hàng loạt' }
    ]
  }) + '\n```');

  assert.equal(valid.threatType, 'data_exfiltration');
  assert.equal(valid.severity, 'critical');
  assert.equal(valid.dataLeakRisk, true);
  // Unknown action 'DROP_DATABASE_SHELL' is safely downgraded to 'monitor_only'
  assert.equal(valid.recommendedActions[0].action, 'monitor_only');
  assert.equal(valid.recommendedActions[1].action, 'throttle_export');
});

test('default monitor-only mode creates AI alerts on repeated failed logins & bulk data access without auto-blocking', async t => {
  const app = await startApp();
  t.after(() => app.stop());

  const admin = await registerUser(app, 'sec_admin_one', 'admin');
  const member = await registerUser(app, 'sec_member_one', 'user');

  // Non-admin cannot access security endpoints
  const forbidden = await apiRequest(app, '/admin/security', { cookie: member.cookie });
  assert.equal(forbidden.status, 403);

  // Verify default config has autoResponseEnabled = false
  const overview0 = await apiRequest(app, '/admin/security', { cookie: admin.cookie });
  assert.equal(overview0.status, 200);
  assert.equal(overview0.body.config.autoResponseEnabled, false);

  // Simulate data exfiltration scenario
  const sim = await apiRequest(app, '/admin/security/simulate', {
    cookie: admin.cookie,
    method: 'POST',
    body: { scenario: 'data_exfiltration', ip: '203.0.113.199', actorId: 'scraper_bot' }
  });
  assert.equal(sim.status, 200);
  assert.equal(sim.body.ok, true);
  assert.ok(sim.body.latestAlert);
  assert.equal(sim.body.latestAlert.threatType, 'data_exfiltration');
  assert.equal(sim.body.latestAlert.dataLeakRisk, true);

  // Because autoResponseEnabled is false by default, no active mitigation was auto-applied
  const mitigations = await apiRequest(app, '/admin/security/mitigations?active=1', { cookie: admin.cookie });
  assert.equal(mitigations.status, 200);
  assert.equal(mitigations.body.mitigations.length, 0);
});

test('independent policy engine blocks AI hallucinated mitigation when quantitative evidence threshold is not met, and enforces reversible TTL mitigation when enabled & verified', async t => {
  let aiCalls = 0;
  const app = await startApp({
    fetchImpl: async (url, opts) => {
      if (String(url).includes('deepseek.com')) {
        aiCalls++;
        const body = JSON.parse(opts.body);
        // Verify secrets were redacted before reaching external AI provider
        assert.ok(!opts.body.includes('super-secret-password'));
        assert.ok(body.messages[0].content.includes('UNTRUSTED_SECURITY_EVENTS_JSON'));
        return Response.json({
          choices: [{
            message: {
              content: JSON.stringify({
                threatType: 'credential_stuffing',
                severity: 'high',
                confidence: 0.99,
                dataLeakRisk: false,
                summary: 'AI đề xuất chặn tạm thời IP dò mật khẩu.',
                evidence: ['POST /api/login 401 repeated'],
                recommendedActions: [
                  { action: 'temp_block_ip', targetType: 'ip', targetValue: '203.0.113.55', ttlSeconds: 600, reason: 'Chặn IP brute-force' }
                ]
              })
            }
          }]
        });
      }
      throw new Error('Unexpected external fetch: ' + url);
    }
  });
  t.after(() => app.stop());

  const admin = await registerUser(app, 'sec_admin_two', 'admin');

  // Enable autoResponseEnabled and configure DeepSeek provider via env/db
  const monitor = createAiSecurityMonitor({
    db: app.social.db,
    env: {
      KINNECT_SECURITY_AI_PROVIDER: 'deepseek',
      KINNECT_SECURITY_AI_API_KEY: 'sk-test-simulated-deepseek-key-1234567890',
      KINNECT_SECURITY_AI_URL: 'https://api.deepseek.com/v1/chat/completions',
      KINNECT_SECURITY_AUTO_RESPONSE: '1'
    },
    fetchImpl: async (url, opts) => {
      aiCalls++;
      assert.ok(!opts.body.includes('super-secret-password'));
      return Response.json({
        choices: [{
          message: {
            content: JSON.stringify({
              threatType: 'credential_stuffing',
              severity: 'critical',
              confidence: 0.99,
              dataLeakRisk: false,
              summary: 'Phát hiện dò mật khẩu liên tiếp từ 203.0.113.55.',
              evidence: ['11 lần đăng nhập thất bại liên tiếp vào /api/login'],
              recommendedActions: [
                { action: 'temp_block_ip', targetType: 'ip', targetValue: '203.0.113.55', ttlSeconds: 600, reason: 'Chặn tạm thời IP tấn công' }
              ]
            })
          }
        }]
      });
    }
  });
  t.after(() => monitor.close());

  monitor.updateConfig({ autoResponseEnabled: true, provider: 'deepseek', failedLoginThreshold: 5 }, admin.username);

  // Case 1: Only 1 privilege_change event (failed_login = 0 < threshold 5).
  // Even though AI recommends temp_block_ip with confidence 0.99, Independent Policy Engine MUST REJECT auto-blocking!
  const alerts1 = await monitor.drainQueue();
  assert.ok(alerts1.length >= 1);
  assert.equal(alerts1[0].autoMitigation, null);
  assert.match(alerts1[0].policyDecision, /Bộ quy tắc độc lập từ chối thực thi/);

  // Case 2: Quantitative evidence crosses threshold (11 failed logins >= 2 * 5).
  // Independent Policy Engine verifies evidence and applies narrow reversible temp_block_ip mitigation.
  const sim = await monitor.simulateScenario('brute_force', { ip: '203.0.113.55', actorId: 'admin' });
  assert.equal(sim.ok, true);
  assert.ok(sim.latestAlert.autoMitigation);
  assert.equal(sim.latestAlert.autoMitigation.action, 'temp_block_ip');
  assert.equal(sim.latestAlert.autoMitigation.targetValue, '203.0.113.55');

  // Verify request gate blocks 203.0.113.55 with 429 + Retry-After
  const gated = monitor.evaluateRequestGate({
    socket: { remoteAddress: '127.0.0.1' },
    headers: { 'cf-connecting-ip': '203.0.113.55' },
    url: '/api/login'
  }, '/api/login');
  assert.equal(gated.allowed, false);
  assert.equal(gated.status, 429);

  // Revert mitigation and verify IP is immediately unblocked
  const reverted = monitor.revertMitigation(sim.latestAlert.autoMitigation.id, admin.username, 'Kiểm thử hoàn tác');
  assert.equal(reverted.active, false);

  const afterRevert = monitor.evaluateRequestGate({
    socket: { remoteAddress: '127.0.0.1' },
    headers: { 'cf-connecting-ip': '203.0.113.55' },
    url: '/api/login'
  }, '/api/login');
  assert.equal(afterRevert.allowed, true);
  assert.ok(aiCalls >= 2);
});

test('graceful degradation: when AI API errors, times out, or exceeds budget, application and security fallback continue seamlessly', async t => {
  const app = await startApp();
  t.after(() => app.stop());

  const monitor = createAiSecurityMonitor({
    db: app.social.db,
    env: {
      KINNECT_SECURITY_AI_PROVIDER: 'deepseek',
      KINNECT_SECURITY_AI_API_KEY: 'sk-test-broken-provider',
      KINNECT_SECURITY_AI_TIMEOUT_MS: '1500'
    },
    fetchImpl: async () => {
      return new Response(JSON.stringify({ error: 'quota_exceeded' }), { status: 429 });
    }
  });
  t.after(() => monitor.close());

  const sim = await monitor.simulateScenario('privilege_escalation', { ip: '203.0.113.99', actorId: 'intruder' });
  assert.equal(sim.ok, true);
  assert.ok(sim.latestAlert);
  assert.equal(sim.latestAlert.provider, 'fallback_heuristic');
  assert.equal(sim.latestAlert.threatType, 'privilege_escalation');
});

test('loading avatars, post media, and gate-emitted 429s never trigger bulk_data_access or self-reinforcing rate_limit_ip loops', async t => {
  const app = await startApp();
  t.after(() => app.stop());

  const monitor = createAiSecurityMonitor({
    db: app.social.db,
    env: { KINNECT_SECURITY_AUTO_RESPONSE: '1' }
  });
  t.after(() => monitor.close());
  monitor.updateConfig({ autoResponseEnabled: true, bulkAccessThreshold: 5, rateAnomalyThreshold: 5 }, 'admin');
  await monitor.drainQueue(); // drain privilege_change event from updateConfig

  const reqBase = {
    method: 'GET',
    socket: { remoteAddress: '127.0.0.1' },
    headers: { 'cf-connecting-ip': '203.0.113.77' }
  };

  // Loading 25 avatars and post media on home feed must never count as bulk_data_access
  for (let i = 0; i < 25; i++) {
    monitor.observeHttpExchange(
      { ...reqBase, url: `/api/users/11111111-2222-3333-4444-5555555555${String(i).padStart(2, '0')}/avatar` },
      { statusCode: 200 },
      { actorId: 'admin', actorRole: 'admin' }
    );
    monitor.observeHttpExchange(
      { ...reqBase, url: `/api/posts/11111111-2222-3333-4444-5555555555${String(i).padStart(2, '0')}/media` },
      { statusCode: 200 },
      { actorId: 'admin', actorRole: 'admin' }
    );
  }

  // Gate-emitted 429s (_securityGateBlocked = true) must never feed back into rate_limit_anomaly
  for (let i = 0; i < 15; i++) {
    monitor.observeHttpExchange(
      { ...reqBase, url: '/api/me' },
      { statusCode: 429, _securityGateBlocked: true },
      { actorId: 'admin', actorRole: 'admin' }
    );
  }

  const alerts = await monitor.drainQueue();
  assert.equal(alerts.length, 0);
  const events = app.social.db.prepare("SELECT COUNT(*) AS n FROM security_events WHERE ip = '203.0.113.77'").get();
  assert.equal(events.n, 0);
});
