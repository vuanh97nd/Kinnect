#!/usr/bin/env node
/**
 * Real-backend HTTPS QA harness for iOS network + parity tests.
 * Wraps the actual createApp({ dbPath: ':memory:', authLimit: 500 }) behind:
 *   1. Primary HTTPS server  (https://127.0.0.1:<PRIMARY_PORT>)
 *   2. Fallback HTTPS server (https://127.0.0.1:<FALLBACK_PORT>)
 *   3. Control HTTP server   (http://127.0.0.1:<CTRL_PORT>) for XCUITest orchestration
 *
 * Never logs passwords, session cookies, or auth tokens.
 */
import http from 'node:http';
import https from 'node:https';
import fs from 'node:fs';
import { writeFileSync, appendFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { createApp } from '../../server.js';

const keyPath = process.env.QA_TLS_KEY;
const certPath = process.env.QA_TLS_CERT;
const infoOut = process.env.QA_INFO_OUT;
const reqLogPath = process.env.QA_REQ_LOG || 'qa-server-requests.jsonl';
const testPassword = process.env.QA_TEST_PASSWORD;

if (!keyPath || !certPath || !testPassword) {
  console.error('Missing QA_TLS_KEY, QA_TLS_CERT, or QA_TEST_PASSWORD');
  process.exit(2);
}

mkdirSync(path.dirname(path.resolve(reqLogPath)), { recursive: true });
writeFileSync(reqLogPath, '', 'utf8');

const tlsOptions = {
  key: fs.readFileSync(keyPath),
  cert: fs.readFileSync(certPath),
};

let app = null;
let appPort = 0;
let seedState = null;

function createFaultState() {
  return {
    dropNextDirectPost: false,
    hangNextDirectPostMs: 0,
    return500NextDirectPost: false,
    return401NextFeedGet: false,
    return401NextMeGet: false,
    dropPrimaryFeedGet: 0,
  };
}

let faults = createFaultState();
let metrics = {
  requests: [],
  fallbackRequests: [],
  committedBeforeDrop: 0,
  committedBeforeTimeout: 0,
};

function logRequest(entry) {
  metrics.requests.push(entry);
  appendFileSync(reqLogPath, JSON.stringify(entry) + '\n', 'utf8');
}

async function rawUpstream(cookie, apiPath, method = 'GET', bodyObj) {
  const res = await fetch(`http://127.0.0.1:${appPort}/api${apiPath}`, {
    method,
    headers: {
      ...(cookie ? { Cookie: cookie } : {}),
      ...(bodyObj !== undefined ? { 'Content-Type': 'application/json' } : {}),
    },
    body: bodyObj !== undefined ? JSON.stringify(bodyObj) : undefined,
  });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(`Seed ${method} ${apiPath} failed (${res.status}): ${JSON.stringify(data)}`);
  }
  const setCookie = res.headers.get('set-cookie')?.split(';')[0] || '';
  return { data, cookie: setCookie };
}

async function teardownApp() {
  if (!app) return;
  for (const ws of app.wss.clients) ws.terminate();
  await new Promise((r) => app.wss.close(r));
  await new Promise((r) => app.server.close(r));
  app.social.close();
  app = null;
}

async function resetAndSeed() {
  await teardownApp();
  faults = createFaultState();
  metrics = {
    requests: [],
    fallbackRequests: [],
    committedBeforeDrop: 0,
    committedBeforeTimeout: 0,
  };

  app = createApp({ dbPath: ':memory:', authLimit: 500, allowEmailDelivery: false });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  appPort = app.server.address().port;

  // Exact seed-contract.json semantics
  const minh = await rawUpstream(null, '/register', 'POST', {
    username: 'qa_parity_minh',
    name: 'QA Minh',
    password: testPassword,
    agree18: true,
    acceptPrivacyNotice: true,
  });
  const lan = await rawUpstream(null, '/register', 'POST', {
    username: 'qa_parity_lan',
    name: 'QA Lan',
    password: testPassword,
    agree18: true,
    acceptPrivacyNotice: true,
  });
  const minhId = minh.data.user.id;
  const lanId = lan.data.user.id;

  await rawUpstream(minh.cookie, '/me', 'PATCH', { dmMode: 'everyone', bio: 'QA Parity Minh' });
  await rawUpstream(lan.cookie, '/me', 'PATCH', { dmMode: 'everyone', bio: 'QA Parity Lan' });

  // Seed feed post matching seed-contract.json
  const postRes = await rawUpstream(minh.cookie, '/posts', 'POST', {
    body: 'P1 parity post',
    visibility: 'public',
  });

  // Seed group + 2 unread direct + 3 unread group messages
  const groupRes = await rawUpstream(minh.cookie, '/groups', 'POST', {
    name: 'QA Parity Group',
    members: [lanId],
  });
  const groupId = groupRes.data.group.id;

  await rawUpstream(lan.cookie, `/users/${minhId}/messages`, 'POST', { body: 'Hello parity' });
  await rawUpstream(lan.cookie, `/users/${minhId}/messages`, 'POST', { body: 'Hello parity 2' });

  for (let i = 1; i <= 3; i++) {
    await rawUpstream(lan.cookie, `/groups/${groupId}/messages`, 'POST', {
      body: `Hello parity group ${i}`,
    });
  }

  seedState = {
    userId: minhId,
    username: 'qa_parity_minh',
    userName: 'QA Minh',
    peerId: lanId,
    peerName: 'QA Lan',
    groupId,
    groupName: 'QA Parity Group',
    postId: postRes.data.post?.id || '',
  };
}

function queryDbSnapshot() {
  if (!app || !seedState) return {};
  const { userId, peerId, groupId } = seedState;
  const db = app.social.db;
  const directMessagesTotal = db.prepare(
    'SELECT COUNT(*) AS c FROM messages WHERE (sender=? AND recipient=?) OR (sender=? AND recipient=?)'
  ).get(userId, peerId, peerId, userId).c;
  const directSentByMinh = db.prepare(
    'SELECT COUNT(*) AS c FROM messages WHERE sender=? AND recipient=?'
  ).get(userId, peerId).c;
  const directUnread = db.prepare(
    "SELECT COUNT(*) AS c FROM notifications WHERE user_id=? AND actor=? AND kind IN ('message','missed_call') AND seen=0"
  ).get(userId, peerId).c;
  const directSeenNotifications = db.prepare(
    "SELECT COUNT(*) AS c FROM notifications WHERE user_id=? AND actor=? AND kind IN ('message','missed_call') AND seen=1"
  ).get(userId, peerId).c;
  const groupMessagesTotal = db.prepare(
    'SELECT COUNT(*) AS c FROM group_messages WHERE group_id=?'
  ).get(groupId).c;
  const groupUnread = db.prepare(
    'SELECT COUNT(*) AS c FROM group_messages WHERE group_id=? AND sender<>? AND created>(SELECT seen_at FROM group_members WHERE group_id=? AND user_id=?)'
  ).get(groupId, userId, groupId, userId).c;
  const groupSeenAt = db.prepare(
    'SELECT seen_at FROM group_members WHERE group_id=? AND user_id=?'
  ).get(groupId, userId)?.seen_at ?? 0;

  return {
    directMessagesTotal,
    directSentByMinh,
    directUnread,
    directSeenNotifications,
    groupMessagesTotal,
    groupUnread,
    groupSeenAt,
  };
}

function readReqBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

// 1. Primary HTTPS proxy -> createApp
const primaryServer = https.createServer(tlsOptions, async (clientReq, clientRes) => {
  const started = Date.now();
  const urlPath = (clientReq.url || '/').split('?')[0];
  const method = clientReq.method || 'GET';
  const cookieHeader = clientReq.headers.cookie || '';
  const hasSessionCookie = cookieHeader.includes('kinnect_session=');
  const hasDeviceCookie = cookieHeader.includes('kinnect_device=');

  const isDirectPost = method === 'POST' && /^\/api\/users\/[^/]+\/messages$/.test(urlPath);
  const isFeedGet = method === 'GET' && urlPath === '/api/posts';
  const isMeGet = method === 'GET' && urlPath === '/api/me';

  if (isMeGet && faults.return401NextMeGet) {
    faults.return401NextMeGet = false;
    logRequest({
      ts: new Date().toISOString(),
      origin: 'primary',
      method,
      path: urlPath,
      status: 401,
      hasSessionCookie,
      hasDeviceCookie,
      fault: 'return401NextMeGet',
      durationMs: Date.now() - started,
    });
    clientRes.writeHead(401, { 'Content-Type': 'application/json' });
    clientRes.end(JSON.stringify({ error: 'QA injected primary 401 on /api/me' }));
    return;
  }

  if (isDirectPost && faults.return500NextDirectPost) {
    faults.return500NextDirectPost = false;
    logRequest({
      ts: new Date().toISOString(),
      origin: 'primary',
      method,
      path: urlPath,
      status: 500,
      hasSessionCookie,
      hasDeviceCookie,
      fault: 'return500NextDirectPost',
      durationMs: Date.now() - started,
    });
    clientRes.writeHead(500, { 'Content-Type': 'application/json' });
    clientRes.end(JSON.stringify({ error: 'QA injected HTTP 500' }));
    return;
  }

  if (isFeedGet && faults.return401NextFeedGet) {
    faults.return401NextFeedGet = false;
    logRequest({
      ts: new Date().toISOString(),
      origin: 'primary',
      method,
      path: urlPath,
      status: 401,
      hasSessionCookie,
      hasDeviceCookie,
      fault: 'return401NextFeedGet',
      durationMs: Date.now() - started,
    });
    clientRes.writeHead(401, { 'Content-Type': 'application/json' });
    clientRes.end(JSON.stringify({ error: 'QA injected HTTP 401' }));
    return;
  }

  if (isFeedGet && faults.dropPrimaryFeedGet > 0) {
    faults.dropPrimaryFeedGet -= 1;
    logRequest({
      ts: new Date().toISOString(),
      origin: 'primary',
      method,
      path: urlPath,
      status: 0,
      hasSessionCookie,
      hasDeviceCookie,
      fault: 'dropPrimaryFeedGet',
      durationMs: Date.now() - started,
    });
    clientReq.socket.destroy();
    return;
  }

  const bodyBuf = await readReqBody(clientReq);
  const dropAfterCommit = isDirectPost && faults.dropNextDirectPost;
  if (dropAfterCommit) faults.dropNextDirectPost = false;

  const hangMs = isDirectPost && faults.hangNextDirectPostMs > 0 ? faults.hangNextDirectPostMs : 0;
  if (hangMs > 0) faults.hangNextDirectPostMs = 0;

  const headers = { ...clientReq.headers, host: `127.0.0.1:${appPort}` };
  // Keep Origin matching backend host so CSRF check passes cleanly
  if (headers.origin) headers.origin = `http://127.0.0.1:${appPort}`;

  const upstreamReq = http.request(
    {
      hostname: '127.0.0.1',
      port: appPort,
      path: clientReq.url,
      method,
      headers,
    },
    (upstreamRes) => {
      const chunks = [];
      upstreamRes.on('data', (c) => chunks.push(c));
      upstreamRes.on('end', () => {
        const respBuf = Buffer.concat(chunks);
        const status = upstreamRes.statusCode || 500;

        if (dropAfterCommit) {
          if (status === 201) metrics.committedBeforeDrop += 1;
          logRequest({
            ts: new Date().toISOString(),
            origin: 'primary',
            method,
            path: urlPath,
            status,
            hasSessionCookie,
            hasDeviceCookie,
            fault: 'dropNextDirectPost_afterCommit',
            durationMs: Date.now() - started,
          });
          // Destroy real TLS socket AFTER createApp committed DB INSERT!
          clientReq.socket.destroy();
          return;
        }

        if (hangMs > 0) {
          if (status === 201) metrics.committedBeforeTimeout += 1;
          logRequest({
            ts: new Date().toISOString(),
            origin: 'primary',
            method,
            path: urlPath,
            status,
            hasSessionCookie,
            hasDeviceCookie,
            fault: `hangNextDirectPost_${hangMs}ms_afterCommit`,
            durationMs: Date.now() - started,
          });
          setTimeout(() => {
            if (!clientRes.writableEnded && !clientReq.socket.destroyed) {
              clientRes.writeHead(status, upstreamRes.headers);
              clientRes.end(respBuf);
            }
          }, hangMs);
          return;
        }

        logRequest({
          ts: new Date().toISOString(),
          origin: 'primary',
          method,
          path: urlPath,
          status,
          hasSessionCookie,
          hasDeviceCookie,
          fault: null,
          durationMs: Date.now() - started,
        });
        if (!clientRes.writableEnded && !clientReq.socket.destroyed) {
          clientRes.writeHead(status, upstreamRes.headers);
          clientRes.end(respBuf);
        }
      });
    }
  );

  upstreamReq.on('error', (err) => {
    logRequest({
      ts: new Date().toISOString(),
      origin: 'primary',
      method,
      path: urlPath,
      status: 502,
      hasSessionCookie,
      hasDeviceCookie,
      fault: `upstreamError:${err.code || err.message}`,
      durationMs: Date.now() - started,
    });
    if (!clientRes.writableEnded && !clientReq.socket.destroyed) {
      clientRes.writeHead(502, { 'Content-Type': 'application/json' });
      clientRes.end(JSON.stringify({ error: 'Upstream error' }));
    }
  });

  if (bodyBuf.length > 0) upstreamReq.write(bodyBuf);
  upstreamReq.end();
});

// 2. Fallback HTTPS server (completely isolated origin)
const fallbackServer = https.createServer(tlsOptions, async (req, res) => {
  const started = Date.now();
  const urlPath = (req.url || '/').split('?')[0];
  const method = req.method || 'GET';
  const cookieHeader = req.headers.cookie || '';
  const hasSessionCookie = cookieHeader.includes('kinnect_session=');
  const hasDeviceCookie = cookieHeader.includes('kinnect_device=');
  await readReqBody(req);

  // Fallback origin is isolated and unauthenticated; it must return 401 rather than 200 via leaked cookies.
  const status = 401;
  const entry = {
    ts: new Date().toISOString(),
    origin: 'fallback',
    method,
    path: urlPath,
    status,
    hasSessionCookie,
    hasDeviceCookie,
    fault: null,
    durationMs: Date.now() - started,
  };
  metrics.fallbackRequests.push(entry);
  logRequest(entry);

  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Fallback unauthorized' }));
});

// 3. Control HTTP server for XCUITest orchestration
const ctrlServer = http.createServer(async (req, res) => {
  const urlPath = (req.url || '/').split('?')[0];
  const sendJson = (code, obj) => {
    res.writeHead(code, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(obj));
  };
  try {
    if (req.method === 'GET' && urlPath === '/_qa/info') {
      return sendJson(200, {
        primaryOrigin: `https://127.0.0.1:${primaryServer.address().port}`,
        fallbackOrigin: `https://127.0.0.1:${fallbackServer.address().port}`,
        seed: seedState,
      });
    }
    if (req.method === 'POST' && urlPath === '/_qa/reset') {
      await resetAndSeed();
      return sendJson(200, { ok: true, seed: seedState, db: queryDbSnapshot() });
    }
    if (req.method === 'POST' && urlPath === '/_qa/fault') {
      const raw = (await readReqBody(req)).toString('utf8');
      const patch = raw ? JSON.parse(raw) : {};
      Object.assign(faults, patch);
      return sendJson(200, { ok: true, faults });
    }
    if (req.method === 'GET' && urlPath === '/_qa/metrics') {
      const countsByEndpoint = {};
      for (const r of metrics.requests) {
        const k = `${r.origin} ${r.method} ${r.path}`;
        countsByEndpoint[k] = (countsByEndpoint[k] || 0) + 1;
      }
      const recentPrimaryFeedGets = metrics.requests
        .filter((r) => r.origin === 'primary' && r.method === 'GET' && r.path === '/api/posts')
        .slice(-5);
      return sendJson(200, {
        totalRequests: metrics.requests.length,
        countsByEndpoint,
        fallbackRequests: metrics.fallbackRequests,
        recentPrimaryFeedGets,
        committedBeforeDrop: metrics.committedBeforeDrop,
        committedBeforeTimeout: metrics.committedBeforeTimeout,
        db: queryDbSnapshot(),
        faults,
      });
    }
    return sendJson(404, { error: 'not found' });
  } catch (err) {
    return sendJson(500, { error: String(err) });
  }
});

await resetAndSeed();
primaryServer.on('tlsClientError', (err) => {
  console.error('PRIMARY_TLS_CLIENT_ERROR:', err?.code || err?.message || String(err));
});
fallbackServer.on('tlsClientError', (err) => {
  console.error('FALLBACK_TLS_CLIENT_ERROR:', err?.code || err?.message || String(err));
});
await new Promise((r) => primaryServer.listen(0, '127.0.0.1', r));
await new Promise((r) => fallbackServer.listen(0, '127.0.0.1', r));
await new Promise((r) => ctrlServer.listen(0, '127.0.0.1', r));

const readyInfo = {
  primaryOrigin: `https://127.0.0.1:${primaryServer.address().port}`,
  fallbackOrigin: `https://127.0.0.1:${fallbackServer.address().port}`,
  ctrlOrigin: `http://127.0.0.1:${ctrlServer.address().port}`,
  seed: seedState,
  initialDb: queryDbSnapshot(),
};

if (infoOut) {
  writeFileSync(infoOut, JSON.stringify(readyInfo, null, 2), 'utf8');
}
console.log('QA_SERVER_READY ' + JSON.stringify(readyInfo));

async function shutdown() {
  ctrlServer.close();
  primaryServer.close();
  fallbackServer.close();
  await teardownApp();
  process.exit(0);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
