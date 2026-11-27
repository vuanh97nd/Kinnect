import { test } from 'node:test'; import assert from 'node:assert/strict'; import http from 'node:http'; import { createHmac, scryptSync } from 'node:crypto'; import { Readable } from 'node:stream';
import { openSocial } from '../lib/social.js'; import { createAdminConsole } from '../lib/admin-console.js'; import { createAdminCloudBridge } from '../lib/admin-cloud-bridge.js';
const secret = 'isolated-cloud-console-bridge-test-key-2026';
test('cloud outbox replays once before replicas, protects ownership and skips unchanged table writes', async t => {
    const social = openSocial(':memory:'); const route = createAdminConsole(social); t.after(() => { route.close(); social.close(); });
    social.db.prepare("INSERT INTO users(id,username,name,password,salt,created,role,birth_date) VALUES('member','member','Fixture','','',1,'user','')").run();
    const event = { id: 'event-1', action: 'reputation-deduct', target: 'member', payload: { points: 5, reason: 'Isolated synchronization test', actor: 'QA' } };
    const requests = []; let expose = true;
    const bridge = createAdminCloudBridge(social, {
        connection: { origin: 'https://cloud.example', secret }, automatic: false, fetchImpl: async (url, init) => {
            const path = new URL(url).pathname.split('/').at(-1), body = init.body ? JSON.parse(init.body) : null; requests.push({ path, body });
            if (path === 'status') return Response.json({ ready: true }); if (path === 'actions') { const actions = expose ? [event] : []; expose = false; return Response.json({ actions }); } return Response.json({ ok: true });
        }
    }); t.after(() => bridge.close());
    await bridge.sync(); assert.equal(social.db.prepare("SELECT reputation_score FROM users WHERE id='member'").get().reputation_score, 95); assert(bridge.status().lastSuccess);
    assert(requests.findIndex(r => r.path === 'ack') < requests.findIndex(r => r.path === 'replica'));
    for (const request of requests.filter(r => r.path === 'replica')) for (const table of request.body.tables) assert(!table.name.startsWith('console_'));
    const first = requests.length; expose = true; await bridge.sync(); assert.equal(social.db.prepare("SELECT reputation_score FROM users WHERE id='member'").get().reputation_score, 95); assert.equal(social.db.prepare('SELECT count(*) n FROM reputation_logs').get().n, 1);
    const later = requests.slice(first); assert.equal(later.filter(r => r.path === 'replica' && r.body.tables.length).length, 0); assert.equal(later.filter(r => r.path === 'prune').length, 0);
});
test('internal PC controls require the secret, an allowed actor and a fixed operation endpoint', async t => {
    const social = openSocial(':memory:'); t.after(() => social.close()); let dispatched = 0; let bridge;
    bridge = createAdminCloudBridge(social, { connection: { origin: 'https://cloud.example', secret }, automatic: false, dispatch: async (req, res) => { dispatched++; assert.equal(req.url, '/api/console/operations/action'); assert.equal(bridge.trustedPrincipal(req).team, 'operations'); res.writeHead(200); res.end('{}'); return true; } }); t.after(() => bridge.close());
    const call = async (token, actor, action = 'check-integrity') => { const req = Readable.from([Buffer.from(JSON.stringify({ actor, action }))]); req.url = '/internal/admin/action'; req.method = 'POST'; req.headers = { authorization: 'Bearer ' + token }; req.socket = {}; const res = { writeHead(s) { this.status = s; }, end() { } }; await bridge.handle(req, res); return res.status; };
    const tech = { id: 'qa', username: 'qa_tech', role: 'support', team: 'operations' };
    assert.equal(await call('wrong', tech), 401); assert.equal(await call(secret, { ...tech, team: 'finance' }), 403); assert.equal(await call(secret, tech, 'arbitrary-shell'), 403); assert.equal(await call(secret, tech), 200); assert.equal(dispatched, 1);
    assert.equal(bridge.trustedPrincipal({ headers: { 'x-console-internal': '1', authorization: 'Bearer ' + secret } }), undefined);
});

test('signed cloud-admin bridge headers authenticate portal host behind Cloudflare and reject forged headers', async t => {
    const social = openSocial(':memory:');
    const bridge = createAdminCloudBridge(social, { connection: { origin: 'https://cloud.example', secret }, automatic: false });
    const route = createAdminConsole(social, { verifyConsoleProxy: req => bridge.verifyConsoleProxy(req) });
    const salt = 'bridge-salt', password = 'Bridge-Strong-Password-2026!', hash = scryptSync(password, salt, 64).toString('hex');
    social.db.prepare("INSERT INTO users(id,username,name,password,salt,role,suspended,created,birth_date) VALUES('admin-1','bridge_admin','Bridge Admin',?,?,'admin',0,1,'')").run(hash, salt);
    social.db.prepare("INSERT INTO console_staff(id,username,name,password,salt,suspended,must_change,created,team) VALUES('sup-1','bridge_sup','Support',?,?,0,0,1,'support')").run(hash, salt);
    social.db.prepare("INSERT INTO console_staff(id,username,name,password,salt,suspended,must_change,created,team) VALUES('ops-1','bridge_ops','Ops',?,?,0,0,1,'operations')").run(hash, salt);
    social.db.prepare("INSERT INTO console_staff(id,username,name,password,salt,suspended,must_change,created,team) VALUES('fin-1','bridge_fin','Finance',?,?,0,0,1,'finance')").run(hash, salt);
    const server = http.createServer(async (req, res) => { if (!await route(req, res)) { res.writeHead(404); res.end(); } });
    await new Promise(r => server.listen(0, '127.0.0.1', r));
    t.after(async () => { bridge.close(); route.close(); server.closeAllConnections(); await new Promise(r => server.close(r)); social.close(); });
    const port = server.address().port;
    const sendReq = (path, { method = 'GET', headers = {}, body } = {}) => new Promise((resolve, reject) => {
        const data = body ? JSON.stringify(body) : null;
        const req = http.request({ host: '127.0.0.1', port, path, method, headers: { ...headers, ...(data ? { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) } : {}) } }, res => {
            const chunks = []; res.on('data', c => chunks.push(c));
            res.on('end', () => { const txt = Buffer.concat(chunks).toString(); let parsed = txt; try { parsed = JSON.parse(txt); } catch { } resolve({ status: res.statusCode, headers: res.headers, body: parsed, cookie: res.headers['set-cookie']?.[0]?.split(';')[0] }); });
        });
        req.on('error', reject); req.end(data);
    });
    // 1. Unsigned CF-proxied request claiming X-Console-Portal must fail 404
    const forged = await sendReq('/api/console/me', { headers: { Host: 'app.kinnect.io.vn', 'cf-connecting-ip': '198.51.100.9', 'cf-ray': 'abc123', 'x-console-portal': 'admin.kinnect.io.vn' } });
    assert.equal(forged.status, 404);
    // 2. Tampered signature must fail 404
    const tsNow = String(Date.now());
    const tampered = await sendReq('/api/console/me', { headers: { Host: 'app.kinnect.io.vn', 'cf-connecting-ip': '198.51.100.9', 'cf-ray': 'abc123', 'x-console-portal': 'admin.kinnect.io.vn', 'x-console-bridge-ts': tsNow, 'x-console-bridge-sig': '0'.repeat(64) } });
    assert.equal(tampered.status, 404);
    // 3. Valid signed bridge requests work for all 4 portals behind CF
    for (const [portalHost, username] of [['admin.kinnect.io.vn', 'bridge_admin'], ['hotro.kinnect.io.vn', 'bridge_sup'], ['kythuat.kinnect.io.vn', 'bridge_ops'], ['taichinh.kinnect.io.vn', 'bridge_fin']]) {
        const ts = String(Date.now());
        const sig = createHmac('sha256', secret).update(portalHost + ':' + ts).digest('hex');
        const bridgeHeaders = { Host: 'app.kinnect.io.vn', 'cf-connecting-ip': '198.51.100.9', 'cf-ray': 'ray-' + portalHost, 'x-console-portal': portalHost, 'x-console-bridge-ts': ts, 'x-console-bridge-sig': sig };
        const meUnauth = await sendReq('/api/console/me', { headers: bridgeHeaders });
        assert.equal(meUnauth.status, 401, portalHost);
        const login = await sendReq('/api/console/login', { method: 'POST', headers: { ...bridgeHeaders, Origin: 'https://' + portalHost }, body: { username, password } });
        assert.equal(login.status, 200, portalHost + ': ' + JSON.stringify(login.body));
        const meAuth = await sendReq('/api/console/me', { headers: { ...bridgeHeaders, Cookie: login.cookie } });
        assert.equal(meAuth.status, 200); assert.equal(meAuth.body.user.username, username);
    }
    // 4. Loopback /console redirects 302 -> /admin
    const redir = await sendReq('/console', { headers: { Host: '127.0.0.1:' + port } });
    assert.equal(redir.status, 302); assert.equal(redir.headers.location, '/admin');
});
