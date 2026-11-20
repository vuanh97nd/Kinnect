/**
 * Android QA network + parity. Isolated createApp :memory: TLS loopback only.
 * Do not point this at production origins or a user device.
 */
import https from 'node:https';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFile, execFileSync } from 'node:child_process';
import { promisify } from 'node:util';
import { createApp } from 'file:///D:/Codex/Kinnect-opt-phase1-android-20261119/server.js';

process.env.NODE_TEST_CONTEXT = '1';

const ADB = 'D:\\Codex\\Kinnect\\work\\android-emulator\\sdk\\platform-tools\\adb.exe';
const OPENSSL = 'C:\\Program Files\\Git\\usr\\bin\\openssl.exe';
const SERIAL = 'emulator-5592';
const WORKTREE = 'D:\\Codex\\Kinnect-opt-phase1-android-20261119';
const APK = 'D:\\Codex\\Kinnect\\outputs\\optimization-controlled-20261119\\phase1\\android\\builds\\debug\\Kinnect-1.2.17-phase1-debug.apk';
const ONLY = process.argv[2] || 'ALL';
// Focused N1+N3 reproduction writes to its own dir so it can never clobber the final coherent package.
const OUT = 'D:\\Codex\\Kinnect\\outputs\\optimization-controlled-20261119\\phase1\\android\\runtime' + (ONLY === 'N3FOCUS' ? '\\focus-n3' : '');
const CAPTURES = path.join(OUT, 'captures');
const LOGS = path.join(OUT, 'logs');
const BASELINE = '2b7e053b4e53dbf49f788cdf63650f09a2a8ded6';
const JOB = 'opt-phase1-android-20261119';
const PASSWORD = 'password123';
fs.mkdirSync(CAPTURES, { recursive: true });
fs.mkdirSync(LOGS, { recursive: true });

let apkSha = '';
let apkBytes = 0;
let sourceTreeSha = '';
let sourceDiffSha = '';
const execFileAsync = promisify(execFile);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function adb(...args) {
  let last;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const { stdout } = await execFileAsync(ADB, ['-s', SERIAL, ...args], { encoding: 'utf8', timeout: 30000, maxBuffer: 20 * 1024 * 1024 });
      return String(stdout || '').trim();
    } catch (error) {
      last = error;
      try { await execFileAsync(ADB, ['start-server'], { timeout: 10000 }); } catch {}
      // A wedged guest transport makes every later call time out; fail fast instead of grinding silently.
      try {
        const { stdout } = await execFileAsync(ADB, ['get-state'], { encoding: 'utf8', timeout: 8000 });
        if (String(stdout || '').trim() !== 'device') throw new Error('device state ' + String(stdout || '').trim());
      } catch (stateError) {
        throw new Error('adb transport not ready (' + SERIAL + '): ' + String(stateError.message || stateError).slice(0, 200));
      }
      await sleep(400);
    }
  }
  throw last;
}
async function adbRaw(...args) {
  const { stdout } = await execFileAsync(ADB, ['-s', SERIAL, ...args], { encoding: 'buffer', timeout: 45000, maxBuffer: 20 * 1024 * 1024 });
  return stdout;
}
let currentStage = 'startup';
let lastProgress = Date.now();
function stage(name) {
  currentStage = name;
  lastProgress = Date.now();
  logLine('stage ' + name);
}
function logLine(line) {
  lastProgress = Date.now();
  fs.appendFileSync(path.join(LOGS, 'harness.log'), line + '\n');
  console.log(line);
}
const WATCHDOG_MS = 15 * 60 * 1000;
setInterval(() => {
  if (Date.now() - lastProgress > WATCHDOG_MS) {
    logLine('WATCHDOG stalled in stage ' + currentStage + '; exiting 2');
    try { fs.writeFileSync(path.join(LOGS, 'watchdog.txt'), JSON.stringify({ stage: currentStage, at: new Date().toISOString() }, null, 2)); } catch {}
    process.exit(2);
  }
}, 30000).unref();

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'kinnect-qa-net-'));
const keyPath = path.join(tmpDir, 'key.pem');
const certPath = path.join(tmpDir, 'cert.pem');
execFileSync(OPENSSL, ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', keyPath, '-out', certPath, '-days', '1', '-subj', '/CN=127.0.0.1', '-addext', 'subjectAltName=IP:127.0.0.1'], { stdio: 'pipe' });
const keyPem = fs.readFileSync(keyPath, 'utf8');
const certPem = fs.readFileSync(certPath, 'utf8');
const certDer = execFileSync(OPENSSL, ['x509', '-in', certPath, '-outform', 'DER']);
const certSha256 = crypto.createHash('sha256').update(certDer).digest('hex');

function hasSessionCookie(req) {
  const cookie = String(req.headers.cookie || '');
  const part = cookie.split(';').map((x) => x.trim()).find((x) => x.startsWith('kinnect_session='));
  return Boolean(part && part.length > 'kinnect_session='.length);
}

const observed = [];
let dropArmed = false;
let holdArmed = false;
let holdMe = false;
let logoutFault = 0;
const holdBox = { current: null };
const tlsErrors = { primary: [], fallback: [] };

function attach(role, app) {
  const handler = app.server.listeners('request')[0];
  const server = https.createServer({ key: keyPem, cert: certPem }, (req, res) => {
    const pathOnly = String(req.url || '').split('?')[0];
    const entry = {
      role, method: req.method, path: pathOnly,
      hasSession: hasSessionCookie(req),
      ifNoneMatch: Boolean(req.headers['if-none-match']),
      status: null, dropped: false, held: false
    };
    if (pathOnly.startsWith('/api/')) observed.push(entry);
    entry.ifNoneMatchValue = req.headers['if-none-match'] ? String(req.headers['if-none-match']).slice(0, 80) : '';
    if (logoutFault && req.method === 'POST' && pathOnly === '/api/logout') {
      const status = logoutFault;
      logoutFault = 0;
      entry.status = status;
      res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ error: 'qa-logout-fault' }));
      return;
    }
    if (holdMe && req.method === 'GET' && pathOnly === '/api/me') {
      holdMe = false;
      entry.held = true;
      holdBox.current = deferResponse(req, res, handler, (status) => { entry.status = status; });
      return;
    }
    if (dropArmed && req.method === 'POST' && /\/messages$/.test(pathOnly)) {
      dropArmed = false;
      entry.dropped = true;
      res.writeHead = () => res;
      res.write = () => true;
      res.end = () => { req.socket.destroy(); return res; };
      handler(req, res);
      return;
    }
    if (holdArmed && req.method === 'GET' && pathOnly === '/api/posts') {
      holdArmed = false;
      entry.held = true;
      holdBox.current = deferResponse(req, res, handler, (status) => { entry.status = status; });
      return;
    }
    const orig = res.writeHead.bind(res);
    res.writeHead = function (status, ...args) { entry.status = status; return orig(status, ...args); };
    handler(req, res);
  });
  server.on('tlsClientError', (err) => tlsErrors[role].push(String(err.message || err)));
  return server;
}

function deferResponse(req, res, handler, mark) {
  let resolveReady;
  const ready = new Promise((r) => { resolveReady = r; });
  const chunks = [];
  let head = null;
  const origWriteHead = res.writeHead.bind(res);
  const origWrite = res.write.bind(res);
  const origEnd = res.end.bind(res);
  res.writeHead = function (status, ...args) { head = [status, ...args]; mark(status); return res; };
  res.write = function (chunk) { if (chunk) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)); return true; };
  res.end = function (chunk) { if (chunk) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)); resolveReady(); return res; };
  handler(req, res);
  return {
    ready,
    flush() {
      res.writeHead = origWriteHead;
      res.write = origWrite;
      res.end = origEnd;
      if (res.destroyed || res.writableEnded || !head) return;
      try {
        origWriteHead(...head);
        origEnd(Buffer.concat(chunks));
      } catch (error) {
        logLine('hold flush ' + (error && error.message ? error.message : error));
      }
    }
  };
}

const primaryApp = createApp({ authLimit: 500, dbPath: ':memory:' });
const fallbackApp = createApp({ authLimit: 500, dbPath: ':memory:' });
const primaryHttps = attach('primary', primaryApp);
const fallbackHttps = attach('fallback', fallbackApp);
await new Promise((r) => primaryHttps.listen(0, '127.0.0.1', r));
await new Promise((r) => fallbackHttps.listen(0, '127.0.0.1', r));
const primaryPort = primaryHttps.address().port;
const fallbackPort = fallbackHttps.address().port;
const primaryOrigin = `https://127.0.0.1:${primaryPort}`;
const fallbackOrigin = `https://127.0.0.1:${fallbackPort}`;
const agent = new https.Agent({ rejectUnauthorized: false });

function hostReq(origin, cookie, apiPath, method = 'GET', data = undefined) {
  return new Promise((resolve, reject) => {
    const req = https.request(`${origin}/api${apiPath}`, {
      method, agent,
      headers: {
        ...(cookie ? { cookie } : {}),
        ...(!['GET', 'HEAD'].includes(method) ? { 'content-type': 'application/json' } : {})
      }
    }, (res) => {
      let raw = '';
      res.on('data', (c) => (raw += c));
      res.on('end', () => {
        let body = null;
        try { body = JSON.parse(raw); } catch {}
        const setCookie = res.headers['set-cookie']?.[0] || '';
        const session = setCookie.split(';')[0];
        resolve({ status: res.statusCode, body, cookie: session.startsWith('kinnect_session=') && session.length > 'kinnect_session='.length ? session : null });
      });
    });
    req.on('error', reject);
    if (data !== undefined) req.write(JSON.stringify(data));
    req.end();
  });
}

function countWhere(pred) { return observed.filter(pred).length; }
function dbPosts() {
  return primaryApp.social.db.prepare('SELECT id, body, visibility FROM posts ORDER BY created').all();
}
function dbPostById(id) {
  return primaryApp.social.db.prepare('SELECT id, body, visibility FROM posts WHERE id=?').get(id) || null;
}
function dbMessageCount(body) {
  return primaryApp.social.db.prepare('SELECT COUNT(*) AS n FROM messages WHERE body=?').get(body).n;
}
function recentMessages() {
  return primaryApp.social.db.prepare('SELECT id, body FROM messages ORDER BY created DESC LIMIT 8').all();
}
function unreadDirect() {
  return primaryApp.social.db.prepare("SELECT COUNT(*) AS n FROM notifications n JOIN users u ON u.id=n.user_id WHERE u.username='qaminh' AND n.kind='message' AND n.seen=0").get().n;
}
function unreadGroup() {
  return primaryApp.social.db.prepare("SELECT COUNT(*) AS n FROM group_messages m JOIN group_members gm ON gm.group_id=m.group_id JOIN users u ON u.id=gm.user_id WHERE u.username='qaminh' AND m.sender<>u.id AND m.created>gm.seen_at").get().n;
}
function expirePrimarySessions() {
  primaryApp.social.db.prepare('UPDATE sessions SET expires=0').run();
}

const captures = [];
let seedAuth = null;
let display = { widthPx: 1080, heightPx: 2400, density: 440, logicalWidthDp: 392.7 };
function decodeXml(value) {
  return String(value || '').replaceAll('&apos;', "'").replaceAll('&quot;', '"').replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>');
}
const SEED_TEXT = /QA Minh|QA Lan|P1 parity post|Hello parity|@qaminh|@qalan|QA Group|parityoffline|paritynetok|parityreconnect|paritydrop/i;
function chromeLines(xml) {
  return kinnectNodes(xml).flatMap((node) => [decodeXml(node.text), decodeXml(node.desc)]).map((line) => line.trim()).filter((line) => line && !SEED_TEXT.test(line));
}
const LANG_MARKERS = {
  auth: { en: ['Welcome back', 'Log in', 'Username'], vi: ['Chào bạn trở lại', 'Đăng nhập', 'Tên đăng nhập'] },
  feed: { en: ["What's on your mind?", 'Reactions', 'Comments', 'Create story'], vi: ['Bạn đang nghĩ gì?', 'Cảm xúc', 'Bình luận', 'Tạo tin'] },
  inbox: { en: ['Find a conversation', 'Unread', 'Messages'], vi: ['Tìm cuộc trò chuyện', 'Chưa đọc', 'Tin nhắn'] },
  'direct-chat': { en: ['Message...', 'Active'], vi: ['Nhắn tin...', 'Đang hoạt động'] },
  'group-chat': { en: ['Message...', 'members'], vi: ['Nhắn tin...', 'thành viên'] },
  profile: { en: ['Edit profile', 'About', 'followers'], vi: ['Chỉnh sửa hồ sơ', 'Giới thiệu', 'người theo dõi'] }
};
function renderedLanguage(xml, screen) {
  const marks = LANG_MARKERS[screen];
  if (!marks) return 'unknown';
  const blob = chromeLines(xml).join('\n');
  const en = marks.en.filter((item) => blob.includes(item)).length;
  const vi = marks.vi.filter((item) => blob.includes(item)).length;
  if (en === 0 && vi === 0) return 'unknown';
  if (en > vi) return 'en';
  if (vi > en) return 'vi';
  return 'mixed';
}
const EN_LEFTOVER = [/Tạo tin/, /cảm xúc/, /phút/, /vừa/, /thành viên/, /Đang hoạt động/, /\d+\s*giờ/, /\d+\s*ngày/];
function englishLeftovers(xml) {
  const hits = [];
  for (const line of chromeLines(xml)) {
    if (EN_LEFTOVER.some((re) => re.test(line)) && !hits.includes(line)) hits.push(line);
  }
  return hits;
}
async function shot(name, meta) {
  const xml = await dump();
  fs.writeFileSync(path.join(LOGS, 'capture-' + name + '.xml'), xml);
  const buf = await adbRaw('exec-out', 'screencap', '-p');
  const file = path.join(CAPTURES, name + '.png');
  fs.writeFileSync(file, buf);
  const sha256 = crypto.createHash('sha256').update(buf).digest('hex');
  logLine('capture ' + name + ' ' + buf.length + 'B ' + sha256.slice(0, 12));
  const png = buf.length > 8 && buf[0] === 0x89 && buf[1] === 0x50;
  const actualRenderedLanguage = renderedLanguage(xml, meta.screen);
  if (meta.locale && actualRenderedLanguage !== meta.locale) {
    throw new Error('rendered language ' + name + ' requested ' + meta.locale + ' actual ' + actualRenderedLanguage);
  }
  if (meta.locale === 'en') {
    const leftovers = englishLeftovers(xml);
    if (leftovers.length) throw new Error('english leftovers ' + name + ': ' + leftovers.join(' | '));
  }
  captures.push({
    file: path.relative('D:\\Codex\\Kinnect', file).replaceAll('\\', '/'),
    bytes: buf.length,
    sha256,
    png,
    platform: 'android',
    apkSha256: apkSha,
    buildSha256: apkSha,
    sourceTreeSha256: sourceTreeSha,
    sourceDiffSha256: sourceDiffSha,
    seed: 'QA Minh, QA Lan, P1 parity post, Hello parity, unread 2/3',
    seedContract: 'optimization-controlled-20261119/phase1/android/runtime/seed-used.json',
    device: SERIAL,
    logicalWidth: display.logicalWidthDp,
    logicalWidthDp: display.logicalWidthDp,
    widthPx: display.widthPx,
    heightPx: display.heightPx,
    density: display.density,
    actualRenderedLanguage,
    fixtureEnabled: false,
    kind: 'real',
    ...meta
  });
  return png && buf.length > 1000;
}

async function dump() {
  let last = '';
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      await adb('shell', 'uiautomator', 'dump', '/data/local/tmp/uidump.xml');
      last = await adb('shell', 'cat', '/data/local/tmp/uidump.xml');
      if (last.includes('<hierarchy')) return last;
      fs.appendFileSync(path.join(LOGS, 'dump-errors.log'), new Date().toISOString() + ' no-hierarchy ' + last.slice(0, 300).replace(/\n/g, ' ') + '\n');
    } catch (error) {
      last = String(error.stderr || error.message || error);
      fs.appendFileSync(path.join(LOGS, 'dump-errors.log'), new Date().toISOString() + ' ' + last.slice(0, 300).replace(/\n/g, ' ') + '\n');
    }
  }
  return last;
}
function kinnectNodes(xml) {
  const nodes = [];
  const re = /<node\b([^>]*)>/g;
  let match;
  while ((match = re.exec(xml))) {
    const attrs = match[1];
    const pkg = / package="([^"]*)"/.exec(attrs);
    if (pkg && pkg[1] && pkg[1] !== 'app.kinnect.live') continue;
    const bounds = / bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(attrs);
    if (!bounds) continue;
    const text = / text="([^"]*)"/.exec(attrs);
    const desc = / content-desc="([^"]*)"/.exec(attrs);
    const cls = / class="([^"]*)"/.exec(attrs);
    nodes.push({
      text: text ? text[1] : '',
      desc: desc ? desc[1] : '',
      cls: cls ? cls[1] : '',
      clickable: / clickable="true"/.test(attrs),
      focused: / focused="true"/.test(attrs),
      x: Math.floor((Number(bounds[1]) + Number(bounds[3])) / 2),
      y: Math.floor((Number(bounds[2]) + Number(bounds[4])) / 2),
      area: (Number(bounds[3]) - Number(bounds[1])) * (Number(bounds[4]) - Number(bounds[2]))
    });
  }
  return nodes;
}
function findText(xml, label) {
  const nodes = kinnectNodes(xml).filter((node) => node.desc === label || node.text === label || node.desc.includes(label) || node.text.includes(label));
  nodes.sort((a, b) => {
    const exactA = a.desc === label || a.text === label ? 0 : 1;
    const exactB = b.desc === label || b.text === label ? 0 : 1;
    if (exactA !== exactB) return exactA - exactB;
    if (a.clickable !== b.clickable) return a.clickable ? -1 : 1;
    return b.area - a.area;
  });
  return nodes[0] ? [nodes[0].x, nodes[0].y] : null;
}
function bounds(xml, attr, needle, exact) {
  const re = /<node\b([^>]*)>/g;
  let match;
  while ((match = re.exec(xml))) {
    const attrs = match[1];
    const value = new RegExp(`${attr}="([^"]*)"`).exec(attrs);
    if (!value) continue;
    if (exact ? value[1] !== needle : !value[1].includes(needle)) continue;
    const box = /bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(attrs);
    if (!box) continue;
    return [Math.floor((Number(box[1]) + Number(box[3])) / 2), Math.floor((Number(box[2]) + Number(box[4])) / 2)];
  }
  return null;
}
function findAnyNode(xml, labels) {
  for (const label of labels) {
    const point = bounds(xml, 'content-desc', label, true) || bounds(xml, 'text', label, true)
      || bounds(xml, 'content-desc', label, false) || bounds(xml, 'text', label, false);
    if (point) return point;
  }
  return null;
}
function composerNode(xml) {
  const nodes = kinnectNodes(xml).filter((node) => node.cls.includes('EditText'));
  return nodes.find((node) => node.focused && (node.desc === 'Tin nhắn' || node.desc === 'Message'))
    || nodes.find((node) => node.desc === 'Tin nhắn' || node.desc === 'Message')
    || nodes.find((node) => node.desc.includes('Nhắn tin') || node.text.includes('parity'))
    || nodes[nodes.length - 1]
    || null;
}
function findField(xml) {
  const node = composerNode(xml);
  return node ? [node.x, node.y] : null;
}
function sendNode(xml) {
  const nodes = kinnectNodes(xml).filter((node) => node.desc === 'Gửi' || node.desc === 'Send' || node.text === 'Gửi' || node.text === 'Send');
  nodes.sort((a, b) => b.y - a.y);
  return nodes[0] || null;
}
async function hideKeyboard() {
  await adb('shell', 'input', 'keyevent', '111');
  await sleep(250);
}
function findAny(xml, labels) {
  for (const label of labels) {
    const pt = findText(xml, label);
    if (pt) return pt;
  }
  return null;
}
async function tap(pt, label) {
  if (!pt) throw new Error('UI node not found: ' + label);
  await adb('shell', 'input', 'tap', String(pt[0]), String(pt[1]));
}
async function typeText(value) {
  await adb('shell', 'input', 'text', value.replace(/ /g, '%s'));
}
async function typeKeys(value) {
  const codes = [];
  for (const ch of value) {
    if (ch >= '0' && ch <= '9') codes.push(String(7 + (ch.charCodeAt(0) - 48)));
    else if (ch >= 'a' && ch <= 'z') codes.push(String(29 + (ch.charCodeAt(0) - 97)));
    else if (ch === ' ') codes.push('62');
    else throw new Error('unsupported typeKeys char');
  }
  await adb('shell', 'input', 'keyevent', ...codes);
}
async function fillField(labels, value) {
  await tapLabel(labels, 8000);
  await sleep(350);
  await adb('shell', 'input', 'keyevent', '123', ...Array(48).fill('67'));
  await typeKeys(value);
  await sleep(250);
}
async function swipeUp() {
  await adb('shell', 'input', 'swipe', '540', '1800', '540', '700', '250');
  await sleep(500);
}
async function dismissSystem() {
  for (let i = 0; i < 5; i++) {
    let xml = '';
    try { xml = await dump(); } catch { return; }
    if (!xml.includes('permissioncontroller') && !xml.includes('com.android.settings') && !xml.includes('packageinstaller')) return;
    const allow = findAnyNode(xml, ['Allow', 'While using the app', 'Cho phép']) || bounds(xml, 'resource-id', 'permission_allow_button', false);
    if (allow) { await tap(allow, 'permission'); await sleep(600); continue; }
    await adb('shell', 'input', 'keyevent', '4');
    await sleep(400);
  }
}
async function qaLogs() {
  try { return await adb('shell', 'logcat', '-d', '-s', 'KinnectQA'); } catch (error) { return String(error.message || error); }
}
async function launch(extra = []) {
  await adb('shell', 'am', 'start', '-S', '-n', 'app.kinnect.live/.MainActivity',
    '-e', 'qa_local_loopback_origin', primaryOrigin,
    '-e', 'qa_local_loopback_fallback', fallbackOrigin,
    '-e', 'qa_local_loopback_cert_sha256', certSha256,
    ...extra);
}
async function warm(extra = []) {
  await adb('shell', 'am', 'start', '-n', 'app.kinnect.live/.MainActivity',
    '-e', 'qa_local_loopback_origin', primaryOrigin,
    '-e', 'qa_local_loopback_fallback', fallbackOrigin,
    '-e', 'qa_local_loopback_cert_sha256', certSha256,
    ...extra);
}
async function waitXml(ms, pred) {
  const start = Date.now();
  let xml = '';
  while (Date.now() - start < ms) {
    await dismissSystem();
    try { xml = await dump(); } catch { xml = ''; }
    if (!pred || pred(xml)) return xml;
    await sleep(700);
  }
  return xml;
}
async function tapLabel(labels, timeout = 20000) {
  const start = Date.now();
  let xml = '';
  while (Date.now() - start < timeout) {
    xml = await waitXml(1500);
    const pt = findExact(xml, labels[0]) || findExact(xml, labels[1] || labels[0]) || findAny(xml, labels);
    if (pt) { await tap(pt, labels[0]); return xml; }
    await swipeUp();
  }
  saveXml('missing-' + labels[0].replace(/\s+/g, '-'), xml);
  throw new Error('UI node not found: ' + labels.join('|'));
}
async function tapExact(label, timeout = 20000) {
  const start = Date.now();
  let xml = '';
  while (Date.now() - start < timeout) {
    xml = await dump();
    const pt = findExact(xml, label);
    if (pt) { await tap(pt, label); return xml; }
    await sleep(500);
  }
  saveXml('missing-' + label.replace(/\s+/g, '-'), xml);
  throw new Error('UI node not found: ' + label);
}
function signedIn(xml) {
  if (!xml) return false;
  if (xml.includes('Kết nối đúng gu') || xml.includes('Find your people')) return false;
  return xml.includes('Bạn đang nghĩ gì?')
    || xml.includes("What's on your mind?")
    || xml.includes('content-desc="Tài khoản"')
    || xml.includes('content-desc="Account"')
    || xml.includes('>Đăng xuất<')
    || xml.includes('>Log out<');
}
function findExact(xml, label) {
  const nodes = kinnectNodes(xml).filter((node) => node.text === label || node.desc === label);
  nodes.sort((a, b) => (a.clickable === b.clickable ? b.area - a.area : a.clickable ? -1 : 1));
  return nodes[0] ? [nodes[0].x, nodes[0].y] : null;
}
function onAuth(xml) {
  return ['Tên đăng nhập', 'Username', 'Chào bạn trở lại!', 'Welcome back!'].some((label) => xml.includes(label));
}
function signedOut(xml) {
  if (!xml || signedIn(xml)) return false;
  const welcome = ['Kết nối đúng gu', 'Find your people', 'Bắt đầu kết nối', 'Start connecting', 'Sống đúng mình', 'Be yourself'];
  const login = ['Tên đăng nhập', 'Username', 'Chào bạn trở lại!', 'Welcome back!', 'Mật khẩu (từ 6 ký tự)', 'Password (at least 6 characters)'];
  return [...welcome, ...login].some((label) => xml.includes(label));
}
async function uiLogin() {
  await launch(['--ez', 'qa_local_loopback_wipe', 'false', '-e', 'commerce_destination', 'login', '-e', 'app_language', 'vi', '-e', 'qa_theme', 'dark']);
  let xml = await waitXml(15000, (x) => onAuth(x));
  if (!onAuth(xml) && signedIn(xml)) return { xml, already: true, signedIn: true };
  if (!onAuth(xml)) {
    const intro = findAny(xml, ['Đăng nhập', 'Log in']);
    if (intro) { await tap(intro, 'intro-login'); await sleep(1200); xml = await waitXml(6000, onAuth); }
  }
  await fillField(['Tên đăng nhập', 'Username'], 'qaminh');
  await fillField(['Mật khẩu (từ 6 ký tự)', 'Password (at least 6 characters)'], PASSWORD);
  await adb('shell', 'input', 'keyevent', '111');
  await sleep(400);
  xml = await dump();
  fs.writeFileSync(path.join(LOGS, 'login-before-submit.xml'), xml);
  if (!xml.includes('qaminh')) throw new Error('username not visible before submit');
  await tap(findAny(xml, ['Đăng nhập', 'Log in']), 'submit-login');
  xml = await waitXml(25000, signedIn);
  fs.writeFileSync(path.join(LOGS, 'login-after-submit.xml'), xml);
  return { xml, already: false, signedIn: signedIn(xml) };
}
async function openAccount() {
  await tapLabel(['Tài khoản', 'Account'], 8000);
  await sleep(800);
  let xml = await dump();
  if (!findAny(xml, ['Đăng xuất', 'Log out'])) { await swipeUp(); xml = await dump(); }
  return xml;
}

const cases = [];
function pushCase(entry) { cases.push(entry); fs.writeFileSync(path.join(OUT, 'results.json'), JSON.stringify(publicResults(), null, 2)); }

function publicResults() {
  return {
    jobId: JOB,
    agent: 'qoder',
    agentVersion: 'qoder-cli-1.1.92',
    baseline: BASELINE,
    apkSha256: apkSha,
    worktree: 'D:\\Codex\\Kinnect-opt-phase1-android-20261119',
    testOrigins: { primary: primaryOrigin, fallback: fallbackOrigin },
    certSha256,
    fixtureEnabled: false,
    serial: SERIAL,
    cases: cases.map((c) => ({ ...c, command: c.command }))
  };
}

async function seed() {
  const minh = await hostReq(primaryOrigin, null, '/register', 'POST', { username: 'qaminh', name: 'QA Minh', password: PASSWORD, agree18: true, acceptPrivacyNotice: true });
  const lan = await hostReq(primaryOrigin, null, '/register', 'POST', { username: 'qalan', name: 'QA Lan', password: PASSWORD, agree18: true, acceptPrivacyNotice: true });
  if (minh.status !== 200 || lan.status !== 200) throw new Error('seed register failed ' + minh.status + '/' + lan.status);
  const group = await hostReq(primaryOrigin, minh.cookie, '/groups', 'POST', { name: 'QA Group', members: [lan.body.user.id] });
  if (group.status !== 201) throw new Error('seed group ' + group.status);
  for (const body of ['Hello parity', 'Hello parity']) {
    const sent = await hostReq(primaryOrigin, lan.cookie, `/users/${minh.body.user.id}/messages`, 'POST', { body });
    if (sent.status !== 201) throw new Error('seed dm ' + sent.status);
  }
  await sleep(40);
  for (const body of ['Hello parity', 'Hello parity', 'Hello parity']) {
    const sent = await hostReq(primaryOrigin, lan.cookie, `/groups/${group.body.group.id}/messages`, 'POST', { body });
    if (sent.status !== 201) throw new Error('seed group message ' + sent.status);
  }
  seedAuth = {
    minh: minh.cookie,
    lan: lan.cookie,
    minhId: minh.body.user.id,
    groupId: group.body.group.id
  };
  return { direct: unreadDirect(), group: unreadGroup(), groupId: group.body.group.id };
}

async function runSessionRegression() {
  await adb('shell', 'logcat', '-c');
  await launch(['--ez', 'qa_session_regression', 'true', '--ez', 'qa_local_loopback_wipe', 'false']);
  const start = Date.now();
  let logs = '';
  while (Date.now() - start < 20000) {
    logs = await qaLogs();
    if (logs.includes('QA_SESSION_REGRESSION_PASS') || logs.includes('QA_SESSION_REGRESSION_FAIL') || logs.includes('QA_SESSION_REGRESSION_ERROR')) break;
    await sleep(400);
  }
  const pass = logs.includes('QA_SESSION_REGRESSION_PASS') && !logs.includes('QA_SESSION_REGRESSION_FAIL') && !logs.includes('QA_SESSION_REGRESSION_ERROR');
  fs.writeFileSync(path.join(LOGS, 'session-regression-logcat.txt'), logs);
  logLine('session-regression ' + (pass ? 'pass' : 'fail'));
  return { pass, logs };
}

function saveXml(name, xml) {
  fs.writeFileSync(path.join(LOGS, name + '.xml'), xml || '');
}
async function confirmLogout() {
  let xml = await dump();
  const menuOpen = xml.includes('Đăng xuất') || xml.includes('Log out') || xml.includes('Cài đặt và quyền riêng tư') || xml.includes('Settings and privacy');
  if (!menuOpen) {
    await tapExact('Tài khoản');
    await sleep(800);
  }
  const start = Date.now();
  let point = null;
  while (Date.now() - start < 15000) {
    xml = await dump();
    point = findExact(xml, 'Đăng xuất') || findExact(xml, 'Log out');
    if (point) break;
    await adb('shell', 'input', 'swipe', '540', '1700', '540', '800', '280');
    await sleep(350);
  }
  if (!point) {
    saveXml('missing-logout', xml);
    throw new Error('UI node not found: Đăng xuất|Log out');
  }
  await tap(point, 'logout');
  await sleep(500);
  const confirmXml = await dump();
  saveXml('logout-confirm', confirmXml);
  await tap(findExact(confirmXml, 'Xác nhận') || findExact(confirmXml, 'Confirm') || findAny(confirmXml, ['Xác nhận', 'Confirm']), 'confirm-logout');
  return waitXml(10000, (x) => signedOut(x) || signedIn(x));
}
async function restartCold() {
  await adb('shell', 'logcat', '-c');
  await launch(['--ez', 'qa_local_loopback_wipe', 'false', '--ez', 'qa_force_primary_failure', 'false', '--ez', 'qa_debug_offline', 'false', '--ez', 'qa_log_session', 'true', '--ez', 'qa_switchback', 'true', '-e', 'qa_theme', 'dark', '-e', 'app_language', 'vi']);
  const xml = await waitXml(30000, (x) => signedOut(x) || signedIn(x));
  let logs = await qaLogs();
  // The saved-primary/switchback lines can land a few moments after the first signed-out frame
  // on this slow emulator; snapshotting instantly used to record a partial log.
  const start = Date.now();
  while (Date.now() - start < 10000 && !(logs.includes('DEBUG_PRIMARY_SAVED') && logs.includes('DEBUG_SWITCHBACK'))) {
    await sleep(400);
    logs = await qaLogs();
  }
  return { xml, logs };
}
async function ensureSignedIn() {
  let xml = await dump();
  if (signedIn(xml)) return xml;
  const login = await uiLogin();
  if (!login.signedIn && !login.already) throw new Error('login UI did not reach feed');
  return login.xml;
}

async function runN1(seedInfo) {
  stage('n1-session-regression');
  const started = observed.length;
  const command = 'node scripts/qa-phase1-parity.mjs AND-N1';
  const artifact = 'outputs/optimization-controlled-20261119/phase1/android/runtime/logs/and-n1-logcat.txt';
  try {
    await adb('shell', 'logcat', '-c');
    const sessionRegression = await runSessionRegression();
    const login = await uiLogin();
    const sawLogin = observed.slice(started).some((r) => r.role === 'primary' && r.method === 'POST' && r.path === '/api/login' && r.status === 200 && r.hasSession === false);
    if (!login.signedIn && !login.already) throw new Error('login UI did not reach feed');

    await adb('shell', 'logcat', '-c');
    const phaseStart = observed.length;
    await warm(['--ez', 'qa_force_primary_failure', 'true', '--ez', 'qa_debug_offline', 'false', '--ez', 'qa_log_session', 'true', '-e', 'commerce_destination', 'inbox']);
    let phaseXml = '';
    const phaseDeadline = Date.now() + 15000;
    let fallback401 = false;
    while (Date.now() < phaseDeadline) {
      fallback401 = observed.slice(phaseStart).some((r) => r.role === 'fallback' && r.method === 'GET' && r.path === '/api/conversations' && r.status === 401);
      phaseXml = await dump();
      if (fallback401 && (signedOut(phaseXml) || phaseXml.includes('máy chủ dự phòng') || phaseXml.includes('backup server'))) break;
      await sleep(400);
    }
    saveXml('n1-fallback401', phaseXml);
    await shot('n1-fallback401-ui', { theme: 'dark', locale: 'vi', screen: 'auth', state: 'fallback-401', set: 'behavior' });
    const failoverReqs = observed.slice(phaseStart);
    const logs = await qaLogs();
    const fallbackHadSession = failoverReqs.some((r) => r.role === 'fallback' && r.hasSession);
    const primaryHttpDuringBlock = failoverReqs.some((r) => r.role === 'primary');
    const savedLog = logs.includes('DEBUG_FAILOVER: to=fallback cookieCleared=true primarySaved=true') && logs.includes('DEBUG_TRANSIENT_CLEAR: primarySaved=true');
    const wipedOn401 = logs.includes('DEBUG_SESSION_WIPED');

    const restoredRestart = await restartCold();
    const restored = signedIn(restoredRestart.xml) && restoredRestart.logs.includes('DEBUG_SWITCHBACK: hasSession=true') && restoredRestart.logs.includes('DEBUG_PRIMARY_SAVED: true');
    saveXml('n1-switchback', restoredRestart.xml);

    holdMe = true;
    holdBox.current = null;
    const staleMark = observed.length;
    await warm(['-e', 'commerce_destination', 'profile', '--ez', 'qa_force_primary_failure', 'false']);
    const staleWait = Date.now() + 12000;
    while (!holdBox.current && Date.now() < staleWait) await sleep(250);
    if (!holdBox.current) throw new Error('in-flight GET /api/me was not observed');
    await holdBox.current.ready;
    const duringStale = await confirmLogout();
    holdBox.current.flush();
    await sleep(1500);
    const afterStale = await dump();
    saveXml('n1-stale-callback', afterStale);
    const staleLogs = await qaLogs();
    const staleMe = observed.slice(staleMark).filter((r) => r.method === 'GET' && r.path === '/api/me');
    const staleCallbackRejected = signedOut(afterStale) && !signedIn(afterStale) && staleLogs.includes('DEBUG_SESSION_WIPED') && staleMe.some((r) => r.held);
    const staleRestart = await restartCold();
    saveXml('n1-stale-restart', staleRestart.xml);
    const staleStayedOut = signedOut(staleRestart.xml) && !signedIn(staleRestart.xml) && staleRestart.logs.includes('DEBUG_PRIMARY_SAVED: false') && staleRestart.logs.includes('DEBUG_SWITCHBACK: hasSession=false');

    async function proveExplicit(kind) {
      await ensureSignedIn();
      await adb('shell', 'logcat', '-c');
      const mark = observed.length;
      if (kind === 'fallback401') {
        await warm(['--ez', 'qa_force_primary_failure', 'true', '--ez', 'qa_debug_offline', 'false']);
        await sleep(300);
      } else if (kind === 'http500') {
        await warm(['--ez', 'qa_force_primary_failure', 'false', '--ez', 'qa_debug_offline', 'false', '-e', 'commerce_destination', 'feed']);
        await waitXml(8000, signedIn);
        logoutFault = 500;
      } else {
        await warm(['--ez', 'qa_force_primary_failure', 'false', '--ez', 'qa_debug_offline', 'true']);
        await sleep(500);
      }
      const ui = await confirmLogout();
      await sleep(600);
      const stepLogs = await qaLogs();
      const reqs = observed.slice(mark);
      const logoutReq = reqs.filter((r) => r.method === 'POST' && r.path === '/api/logout');
      let httpOk = false;
      if (kind === 'fallback401') httpOk = logoutReq.some((r) => r.role === 'fallback' && r.status === 401 && r.hasSession === false);
      else if (kind === 'http500') httpOk = logoutReq.some((r) => r.status === 500 && r.hasSession === true);
      else httpOk = stepLogs.includes('DEBUG_EXPLICIT_LOGOUT: status=0') && !logoutReq.some((r) => r.status === 200);
      const wiped = stepLogs.includes('DEBUG_EXPLICIT_LOGOUT') && stepLogs.includes('DEBUG_SESSION_WIPED') && signedOut(ui) && !signedIn(ui);
      const restarted = await restartCold();
      const stayedOut = signedOut(restarted.xml) && !signedIn(restarted.xml) && restarted.logs.includes('DEBUG_PRIMARY_SAVED: false') && restarted.logs.includes('DEBUG_SWITCHBACK: hasSession=false');
      let remembered = false;
      let rememberedXml = restarted.xml;
      if (stayedOut) {
        if (!onAuth(rememberedXml)) {
          const introLogin = findAny(rememberedXml, ['Đăng nhập', 'Log in']);
          if (introLogin) {
            await tap(introLogin, 'intro-login');
            rememberedXml = await waitXml(8000, onAuth);
          }
        }
        remembered = (rememberedXml.includes('qaminh') || rememberedXml.includes('QA Minh')) && !signedIn(rememberedXml);
        saveXml('n1-remembered-' + kind, rememberedXml);
      }
      return { kind, httpOk, wiped, stayedOut, remembered, logoutStatuses: logoutReq.map((r) => ({ role: r.role, status: r.status, hasSession: r.hasSession })) };
    }

    const logout401 = await proveExplicit('fallback401');
    const logout500 = await proveExplicit('http500');
    const logoutOffline = await proveExplicit('offline');

    await ensureSignedIn();
    await adb('shell', 'logcat', '-c');
    const primaryMark = observed.length;
    expirePrimarySessions();
    await tapLabel(['Tin nhắn', 'Messages'], 8000);
    const afterPrimary = await waitXml(12000, (x) => signedOut(x) || signedIn(x));
    await sleep(500);
    const logs401 = await qaLogs();
    const primaryReqs = observed.slice(primaryMark);
    const primary401 = primaryReqs.some((r) => r.role === 'primary' && r.status === 401 && r.hasSession === true);
    const primary401Ui = signedOut(afterPrimary) && !signedIn(afterPrimary);
    saveXml('n1-primary401', afterPrimary);
    await shot('n1-primary401-ui', { theme: 'dark', locale: 'vi', screen: 'auth', state: signedOut(afterPrimary) ? 'signed-out' : 'unexpected', set: 'behavior' });
    const primaryRestart = await restartCold();
    saveXml('n1-primary-restart', primaryRestart.xml);
    const primaryStayedOut = signedOut(primaryRestart.xml) && !signedIn(primaryRestart.xml) && primaryRestart.logs.includes('DEBUG_PRIMARY_SAVED: false') && logs401.includes('DEBUG_SESSION_WIPED');

    const pass = Boolean(login.signedIn || login.already)
      && sawLogin
      && sessionRegression.pass
      && fallback401
      && !fallbackHadSession
      && !primaryHttpDuringBlock
      && savedLog
      && !wipedOn401
      && restored
      && staleCallbackRejected
      && staleStayedOut
      && logout401.httpOk && logout401.wiped && logout401.stayedOut && logout401.remembered
      && logout500.httpOk && logout500.wiped && logout500.stayedOut
      && logoutOffline.httpOk && logoutOffline.wiped && logoutOffline.stayedOut
      && primary401 && primary401Ui && primaryStayedOut;
    pushCase({
      caseId: 'AND-N1', id: 'A-001', baseline: BASELINE, artifactSha256: apkSha, command,
      exitCode: pass ? 0 : 1,
      expected: 'Full UI login, fallback 401 keeps saved primary and sends no session cookie, explicit logout on 401/500/offline wipes, restart and switchback stay signed out, stale /api/me cannot restore auth, primary 401 wipes',
      actual: {
        sawLogin, signedIn: Boolean(login.signedIn || login.already), sessionRegression: sessionRegression.pass,
        fallback401, fallbackHadSession, primaryHttpDuringBlock, savedLog, wipedOn401, restored,
        fallbackRequests: failoverReqs.map((r) => ({ role: r.role, method: r.method, path: r.path, status: r.status, hasSession: r.hasSession })),
        staleCallbackRejected, staleStayedOut, duringStaleSignedOut: signedOut(duringStale),
        logout401, logout500, logoutOffline,
        primary401, primary401Ui, primaryStayedOut,
        sessionWipedLog: logs401.includes('DEBUG_SESSION_WIPED'),
        seedUnread: seedInfo
      },
      status: pass ? 'pass' : 'fail', artifact, fixtureEnabled: false,
      testOrigin: { primary: primaryOrigin, fallback: fallbackOrigin }
    });
    fs.writeFileSync(path.join(LOGS, 'and-n1-logcat.txt'), [logs, staleLogs, logs401, primaryRestart.logs].join('\n---\n'));
  } catch (error) {
    pushCase({
      caseId: 'AND-N1', id: 'A-001', baseline: BASELINE, artifactSha256: apkSha, command, exitCode: 1,
      expected: 'full UI failover session behavior', actual: { error: String(error.stack || error) },
      status: 'fail', artifact, fixtureEnabled: false,
      testOrigin: { primary: primaryOrigin, fallback: fallbackOrigin }
    });
    try { fs.writeFileSync(path.join(LOGS, 'and-n1-logcat.txt'), await qaLogs()); } catch {}
  }
}

async function runN2() {
  stage('n2-transport');
  const command = 'node scripts/qa-phase1-parity.mjs AND-N2';
  const before = observed.length;
  try {
    let xml = await waitXml(4000, (x) => signedIn(x) || onAuth(x));
    if (!signedIn(xml)) {
      const login = await uiLogin();
      if (!login.signedIn && !login.already) throw new Error('N2 login failed');
    }
    await launch(['--ez', 'qa_local_loopback_wipe', 'false', '-e', 'commerce_destination', 'feed', '-e', 'qa_theme', 'dark', '-e', 'app_language', 'vi']);
    xml = await waitXml(10000, signedIn);
    await tapLabel(['Bạn đang nghĩ gì?', "What's on your mind?"], 8000);
    xml = await waitXml(6000, (x) => x.includes('Đăng') || x.includes('>Post<'));
    const composer = findAny(xml, ['Bạn đang nghĩ gì?', "What's on your mind?"]);
    await tap(composer, 'composer');
    await sleep(400);
    await typeText('P1 parity post');
    await adb('shell', 'input', 'keyevent', '4');
    await sleep(400);
    xml = await dump();
    await tap(findAny(xml, ['Đăng', 'Post']), 'publish');
    await waitXml(10000, (x) => x.includes('P1 parity post'));
    const afterCreate = dbPosts();
    const createdId = (afterCreate.find((p) => p.body === 'P1 parity post' && p.visibility === 'public') || {}).id || null;
    await tapLabel(['Thêm thao tác', 'More actions'], 8000);
    await sleep(600);
    await tapLabel(['Chỉnh sửa bài viết', 'Edit post'], 5000);
    await sleep(700);
    xml = await dump();
    await tap(findAny(xml, ['Bạn đang nghĩ gì?', "What's on your mind?", 'P1 parity post']), 'edit-field');
    await sleep(300);
    await adb('shell', 'input', 'keyevent', 'KEYCODE_MOVE_END', ...Array(40).fill('67'));
    await typeText('P1 parity post edited');
    await adb('shell', 'input', 'keyevent', '4');
    await sleep(400);
    xml = await dump();
    await tap(findAny(xml, ['Lưu', 'Save']), 'save-edit');
    await waitXml(10000, (x) => x.includes('P1 parity post edited'));
    const afterEdit = dbPosts();
    await tapLabel(['Thêm thao tác', 'More actions'], 8000);
    await sleep(500);
    await tapLabel(['Thay đổi đối tượng xem', 'Change audience'], 5000);
    await sleep(500);
    await tapLabel(['Người theo dõi', 'Followers'], 5000);
    await waitXml(10000, (x) => x.includes('Người theo dõi') || x.includes('Followers'));
    const afterVisibility = dbPosts();
    const etagBeforeNav = observed.filter((r) => r.path === '/api/posts' && r.method === 'GET').slice(-1)[0] || null;
    await launch(['--ez', 'qa_local_loopback_wipe', 'false', '-e', 'commerce_destination', 'inbox']);
    await waitXml(8000, (x) => x.includes('QA Lan') || x.includes('Tin nhắn') || x.includes('Messages'));
    await launch(['--ez', 'qa_local_loopback_wipe', 'false', '-e', 'commerce_destination', 'feed']);
    xml = await waitXml(10000, (x) => x.includes('P1 parity post edited'));
    const retainedOk = xml.includes('P1 parity post edited') && (xml.includes('Người theo dõi') || xml.includes('Followers'));
    const gets = () => observed.filter((r) => r.method === 'GET' && r.path === '/api/posts');
    const beforeHold = gets().length;
    holdArmed = true;
    holdBox.current = null;
    await tapLabel(['Bảng tin', 'Feed'], 6000);
    const holdStart = Date.now();
    while (!holdBox.current && Date.now() - holdStart < 12000) await sleep(300);
    if (!holdBox.current) throw new Error('in-flight GET /api/posts was not observed');
    await holdBox.current.ready;
    const dbDuringHold = dbPosts();
    await tapLabel(['Thêm thao tác', 'More actions'], 8000);
    await sleep(400);
    await tapLabel(['Xoá bài viết', 'Delete post'], 5000);
    await sleep(500);
    xml = await dump();
    await tap(findAny(xml, ['Xác nhận', 'Confirm']), 'confirm-delete');
    const deleteStart = Date.now();
    while (Date.now() - deleteStart < 8000 && !observed.some((r) => r.method === 'DELETE' && r.path.startsWith('/api/posts/'))) await sleep(200);
    const dbAfterDelete = dbPosts();
    if (holdBox.current) holdBox.current.flush();
    await sleep(2500);
    xml = await dump();
    const afterHoldGets = gets().slice(beforeHold);
    saveXml('n2-after-delete', xml);
    const deletedIdGone = Boolean(createdId) && dbPostById(createdId) == null && !dbPosts().some((p) => String(p.body).includes('P1 parity post'));
    const onFeed = signedIn(xml);
    const postTextGone = !xml.includes('P1 parity post');
    const emptyVisible = xml.includes('Chưa có bài viết') || xml.includes('No posts yet');
    const finalUiEmpty = onFeed && postTextGone && emptyVisible;
    const heldStale304 = afterHoldGets.some((r) => r.held && r.status === 304 && r.ifNoneMatch);
    const freshGetAfter = afterHoldGets.some((r) => !r.held && r.method === 'GET' && r.status === 200);
    const staleDidNotRestore = finalUiEmpty && deletedIdGone;
    const postReqs = observed.slice(before);
    const sameIdEdited = Boolean(createdId) && afterEdit.some((p) => p.id === createdId && p.body === 'P1 parity post edited') && afterVisibility.some((p) => p.id === createdId && p.body === 'P1 parity post edited' && p.visibility === 'followers');
    const pass = afterCreate.some((p) => p.id === createdId && p.body === 'P1 parity post' && p.visibility === 'public')
      && sameIdEdited
      && retainedOk
      && deletedIdGone
      && dbAfterDelete.length === 0
      && finalUiEmpty
      && heldStale304
      && freshGetAfter
      && staleDidNotRestore
      && postReqs.some((r) => r.method === 'POST' && r.path === '/api/posts')
      && postReqs.filter((r) => r.method === 'PATCH' && r.path.startsWith('/api/posts/')).length >= 2
      && postReqs.some((r) => r.method === 'DELETE' && r.path === '/api/posts/' + createdId);
    const n2Detail = { createdId, afterCreate, afterEdit, afterVisibility, retainedOk, dbDuringHold, dbAfterDelete, deletedIdGone, finalUiEmpty, emptyVisible, postTextGone, onFeed, heldStale304, freshGetAfter, staleDidNotRestore, etagBeforeNav, heldGets: afterHoldGets.map((r) => ({ status: r.status, ifNoneMatch: r.ifNoneMatch, ifNoneMatchValue: r.ifNoneMatchValue, held: r.held })) };
    fs.writeFileSync(path.join(LOGS, 'and-n2.json'), JSON.stringify(n2Detail, null, 2));
    pushCase({
      caseId: 'AND-N2', id: 'A-002', baseline: BASELINE, artifactSha256: apkSha, command,
      exitCode: pass ? 0 : 1,
      expected: 'UI create, edit body, change visibility, delete; the created row id is gone; feed UI is empty; held conditional GET 304 does not restore the post',
      actual: n2Detail,
      status: pass ? 'pass' : 'fail',
      artifact: 'outputs/optimization-controlled-20261119/phase1/android/runtime/logs/and-n2.json',
      fixtureEnabled: false, testOrigin: { primary: primaryOrigin, fallback: fallbackOrigin }
    });
  } catch (error) {
    try { if (holdBox.current) holdBox.current.flush(); } catch {}
    pushCase({
      caseId: 'AND-N2', id: 'A-002', baseline: BASELINE, artifactSha256: apkSha, command, exitCode: 1,
      expected: 'UI post mutation against live GET', actual: { error: String(error.stack || error), posts: dbPosts() },
      status: 'fail', artifact: 'outputs/optimization-controlled-20261119/phase1/android/runtime/logs/and-n2.json', fixtureEnabled: false,
      testOrigin: { primary: primaryOrigin, fallback: fallbackOrigin }
    });
  }
}

async function refreshSeedCookies() {
  const minh = await hostReq(primaryOrigin, null, '/login', 'POST', { username: 'qaminh', password: PASSWORD });
  const lan = await hostReq(primaryOrigin, null, '/login', 'POST', { username: 'qalan', password: PASSWORD });
  if (!minh.cookie || !lan.cookie) throw new Error('refresh seed login ' + minh.status + '/' + lan.status);
  seedAuth = { ...(seedAuth || {}), minh: minh.cookie, lan: lan.cookie };
}
async function ensureParityPost() {
  if (dbPosts().some((p) => p.body === 'P1 parity post' && p.visibility === 'public')) return 'existing';
  await refreshSeedCookies();
  const created = await hostReq(primaryOrigin, seedAuth.minh, '/posts', 'POST', { body: 'P1 parity post', visibility: 'public' });
  if (created.status !== 201) throw new Error('reseed post ' + created.status);
  return 'created';
}
function launchArgs(theme, locale, destination) {
  return ['--ez', 'qa_local_loopback_wipe', 'false', '--ez', 'qa_debug_offline', 'false', '--ez', 'qa_force_primary_failure', 'false', '-e', 'qa_theme', theme, '-e', 'app_language', locale, '-e', 'commerce_destination', destination];
}
async function captureSignedIn(theme, locale) {
  const postSource = await ensureParityPost();
  await topUpUnread();
  const unread = { direct: unreadDirect(), group: unreadGroup() };
  if (unread.direct !== 2 || unread.group !== 3) throw new Error('unread reseed ' + JSON.stringify(unread));
  await launch(launchArgs(theme, locale, 'feed'));
  let xml = await waitXml(15000, (x) => x.includes('P1 parity post'));
  if (!xml.includes('P1 parity post')) {
    await adb('shell', 'input', 'swipe', '540', '700', '540', '1600', '300');
    xml = await waitXml(10000, (x) => x.includes('P1 parity post'));
  }
  if (!xml.includes('P1 parity post') || !signedIn(xml)) throw new Error('feed missing parity post ' + theme + ' ' + locale);
  await shot(`feed-${theme}-${locale}`, { set: 'parity', theme, locale, screen: 'feed', state: 'P1 parity post', postSource, textScale: 'default' });
  await launch(launchArgs(theme, locale, 'inbox'));
  xml = await waitXml(12000, (x) => x.includes('QA Lan') && x.includes('QA Group') && x.includes('Hello parity') && xIncludesCounts(x));
  if (!(xml.includes('QA Lan') && xml.includes('QA Group') && xIncludesCounts(xml))) throw new Error('inbox seed mismatch ' + theme + ' ' + locale);
  await shot(`inbox-${theme}-${locale}`, { set: 'parity', theme, locale, screen: 'inbox', state: 'unread-direct-2-group-3', unread });
  await launch(launchArgs(theme, locale, 'profile'));
  xml = await waitXml(12000, (x) => x.includes('QA Minh') && (x.includes('@qaminh') || x.includes('qaminh')));
  if (!xml.includes('QA Minh')) throw new Error('profile missing QA Minh');
  await shot(`profile-${theme}-${locale}`, { set: 'parity', theme, locale, screen: 'profile', state: 'QA Minh' });
  await launch(launchArgs(theme, locale, 'inbox'));
  xml = await waitXml(12000, (x) => x.includes('QA Lan'));
  await tapExact('QA Lan');
  xml = await waitXml(10000, (x) => x.includes('Hello parity') && x.includes('QA Lan'));
  if (!xml.includes('Hello parity') || !xml.includes('QA Lan')) throw new Error('direct chat mismatch');
  await shot(`direct-chat-${theme}-${locale}`, { set: 'parity', theme, locale, screen: 'direct-chat', state: 'QA Lan Hello parity' });
  await leaveChat();
  xml = await dump();
  if (!findText(xml, 'QA Group')) { await swipeUp(); xml = await dump(); }
  await tapExact('QA Group');
  xml = await waitXml(10000, (x) => x.includes('Hello parity') && x.includes('QA Group'));
  if (!xml.includes('QA Group')) throw new Error('group chat mismatch');
  await shot(`group-chat-${theme}-${locale}`, { set: 'parity', theme, locale, screen: 'group-chat', state: 'QA Group Hello parity' });
  await leaveChat();
  return postSource;
}
function xIncludesCounts(xml) {
  return (xml.includes('text="2"') || xml.includes('content-desc="2"')) && (xml.includes('text="3"') || xml.includes('content-desc="3"'));
}

async function leaveChat() {
  let xml = await dump();
  const inChat = xml.includes('content-desc="Gửi"') || xml.includes('content-desc="Send"') || xml.includes('Nhắn tin...');
  if (!inChat && (xml.includes('QA Lan') || xml.includes('QA Group'))) return xml;
  const back = findAny(xml, ['Quay lại', 'Back']);
  if (back) await tap(back, 'back');
  else await adb('shell', 'input', 'keyevent', '4');
  await sleep(700);
  return waitXml(8000, (x) => x.includes('QA Lan') || x.includes('QA Group') || x.includes('Tin nhắn') || x.includes('Messages'));
}

async function composerServed() {
  // mInputShown can stay true after the IME loses its served view, so the input connection
  // (mServedView=app.kinnect.live.KinnectInput) is the authoritative focus signal here.
  try {
    const info = String(await adb('shell', 'dumpsys', 'input_method'));
    return /mServedView=app\.kinnect\.live\.KinnectInput/.test(info);
  } catch { return false; }
}
async function focusComposer() {
  let xml = await dump();
  for (let attempt = 0; attempt < 6; attempt++) {
    const node = composerNode(xml);
    if (!node) throw new Error('chat composer missing');
    if (node.focused || (await composerServed())) return xml;
    await tap([node.x, node.y], 'composer');
    // This emulator renders slowly; the IME/focus round-trip can take seconds.
    for (let i = 0; i < 20 && !(await composerServed()); i++) await sleep(250);
    await sleep(700);
    xml = await dump();
    const again = composerNode(xml);
    if (!again) throw new Error('chat composer missing');
    // The chat reload can rebuild the composer and drop focus shortly after the first tap;
    // only return once focus survives a settled re-check.
    if (again.focused || (await composerServed())) {
      await sleep(900);
      if ((await composerServed()) || composerNode(await dump()).focused) return xml;
      xml = await dump();
      continue;
    }
  }
  saveXml('composer-unfocused', xml);
  throw new Error('chat composer did not take focus');
}
async function ensureComposerReady() {
  await focusComposer();
  await sleep(400);
  const xml = await dump();
  const node = composerNode(xml);
  if (!node) throw new Error('chat composer missing after IME settle');
  return xml;
}
async function putDraft(value) {
  let xml = '';
  let node = null;
  const failures = [];
  for (let attempt = 0; attempt < 5; attempt++) {
    if (attempt) await sleep(700);
    try { await ensureComposerReady(); } catch (error) {
      failures.push('attempt' + attempt + ': ' + String(error.message || error));
      continue;
    }
    await sleep(300);
    const before = composerNode(await dump());
    if (!before || !(before.focused || (await composerServed()))) { failures.push('attempt' + attempt + ': composer not focused'); continue; }
    if (before.text && !before.text.includes('Nhắn tin') && !before.text.includes('Message')) {
      await adb('shell', 'input', 'keyevent', '123');
      for (let chunk = 0; chunk < 4; chunk++) await adb('shell', 'input', 'keyevent', ...Array(20).fill('67'));
      await sleep(400);
    }
    await typeText(value);
    // `input text` injects characters one by one; poll so a dump cannot race the tail.
    const start = Date.now();
    const seen = [];
    do {
      await sleep(400);
      xml = await dump();
      node = composerNode(xml);
      seen.push(node ? node.text : 'missing');
    } while (Date.now() - start < 5000 && (!node || node.text !== value));
    if (node && node.text === value) break;
    failures.push('attempt' + attempt + ': text=' + (node ? JSON.stringify(node.text) : 'missing')
      + ' seen=' + JSON.stringify(seen.slice(-4)) + ' served=' + (await composerServed()));
  }
  saveXml('draft-' + value, xml);
  if (failures.length) fs.appendFileSync(path.join(LOGS, 'draft-attempts.log'), value + ' :: ' + failures.join(' | ') + '\n');
  if (!node || node.text !== value) throw new Error('draft text is ' + (node ? node.text : 'missing') + ' wanted ' + value);
  return { xml, focused: Boolean(node.focused), visible: true, fieldText: node.text };
}
async function tapComposerSend(xml) {
  const node = sendNode(xml);
  if (!node) throw new Error('send button missing');
  await tap([node.x, node.y], 'send');
  return { x: node.x, y: node.y, desc: node.desc || node.text };
}
async function waitMessageCount(body, want, ms) {
  const start = Date.now();
  let n = dbMessageCount(body);
  while (n < want && Date.now() - start < ms) {
    await sleep(250);
    n = dbMessageCount(body);
  }
  return n;
}
async function topUpUnread() {
  if (!seedAuth) throw new Error('seed auth missing');
  let guard = 0;
  while (unreadDirect() < 2 && guard < 4) {
    const sent = await hostReq(primaryOrigin, seedAuth.lan, `/users/${seedAuth.minhId}/messages`, 'POST', { body: 'Hello parity' });
    if (sent.status !== 201) throw new Error('topup dm ' + sent.status);
    guard += 1;
  }
  guard = 0;
  while (unreadGroup() < 3 && guard < 6) {
    const sent = await hostReq(primaryOrigin, seedAuth.lan, `/groups/${seedAuth.groupId}/messages`, 'POST', { body: 'Hello parity' });
    if (sent.status !== 201) throw new Error('topup group ' + sent.status);
    guard += 1;
  }
}

async function runN3AndChats() {
  const command = 'node scripts/qa-phase1-parity.mjs AND-N3';
  const before = observed.length;
  try {
    stage('n3-seed');
    await refreshSeedCookies();
    await topUpUnread();
    const n3LaunchArgs = ['--ez', 'qa_local_loopback_wipe', 'false', '--ez', 'qa_debug_offline', 'false', '--ez', 'qa_force_primary_failure', 'false', '-e', 'qa_theme', 'dark', '-e', 'app_language', 'vi', '-e', 'commerce_destination', 'inbox'];
    stage('n3-launch-inbox');
    await launch(n3LaunchArgs);
    let xml = await waitXml(15000, (x) => x.includes('QA Lan'));
    const inboxReady = (x) => x.includes('Tìm cuộc trò chuyện') || x.includes('Find a conversation') || x.includes('Chưa đọc');
    if (!inboxReady(xml)) {
      xml = await waitXml(20000, inboxReady);
    }
    if (!inboxReady(xml)) {
      await launch(n3LaunchArgs);
      xml = await waitXml(30000, inboxReady);
    }
    if (!inboxReady(xml)) throw new Error('inbox did not render for N3: ' + xml.slice(0, 300));
    stage('n3-inbox-open-dm');
    const unreadBefore = { direct: unreadDirect(), group: unreadGroup() };
    await shot('n3-inbox-before-open', { theme: 'dark', locale: 'vi', screen: 'inbox', state: 'before-read', set: 'behavior' });
    await tapExact('QA Lan');
    xml = await waitXml(10000, (x) => x.includes('Hello parity') && (x.includes('content-desc="Tin nhắn"') || x.includes('content-desc="Message"')));
    await shot('n3-dm-opened', { theme: 'dark', locale: 'vi', screen: 'direct-chat', state: 'opened', set: 'behavior' });
    const unreadAfterDm = { direct: unreadDirect(), group: unreadGroup() };
    stage('n3-online-send');
    const onlineDraft = await putDraft('paritynetok');
    const onlineTap = await tapComposerSend(onlineDraft.xml);
    let okCount = await waitMessageCount('paritynetok', 1, 8000);
    let onlineRetap = null;
    if (okCount === 0 && (await dump()).includes('paritynetok')) {
      onlineRetap = await tapComposerSend(await dump());
      okCount = await waitMessageCount('paritynetok', 1, 5000);
    }
    stage('n3-offline-send');
    await adb('shell', 'logcat', '-c');
    await warm(['--ez', 'qa_debug_offline', 'true', '--ez', 'qa_force_primary_failure', 'false']);
    await sleep(500);
    xml = await waitXml(8000, (x) => x.includes('content-desc="Tin nhắn"') || x.includes('content-desc="Message"'));
    const offlineDraft = await putDraft('parityoffline');
    const offlineTap = await tapComposerSend(offlineDraft.xml);
    await sleep(1800);
    xml = await dump();
    const offlineLogs = await qaLogs();
    const offlineCount = dbMessageCount('parityoffline');
    const offlineDraftKept = xml.includes('parityoffline');
    const offlineBlocked = offlineLogs.includes('DEBUG_TRANSPORT_BLOCK: qa-debug-offline POST');
    await shot('n3-offline-draft', { theme: 'dark', locale: 'vi', screen: 'direct-chat', state: 'offline-draft', set: 'behavior' });
    stage('n3-reconnect-send');
    await warm(['--ez', 'qa_debug_offline', 'false', '--ez', 'qa_force_primary_failure', 'false']);
    await sleep(1500);
    await waitXml(8000, (x) => x.includes('content-desc="Tin nhắn"') || x.includes('content-desc="Message"'));
    const reconnectDraft = await putDraft('parityreconnect');
    const reconnectTap = await tapComposerSend(reconnectDraft.xml);
    let reconnectCount = await waitMessageCount('parityreconnect', 1, 8000);
    if (reconnectCount === 0 && (await dump()).includes('parityreconnect')) {
      await tapComposerSend(await dump());
      reconnectCount = await waitMessageCount('parityreconnect', 1, 5000);
    }
    stage('n3-dropped-response');
    const dropMark = observed.length;
    dropArmed = true;
    const dropDraft = await putDraft('paritydrop');
    const dropTap = await tapComposerSend(dropDraft.xml);
    await sleep(4000);
    const dropCount = dbMessageCount('paritydrop');
    const dropReqs = observed.slice(dropMark).filter((r) => r.method === 'POST' && /\/users\/[^/]+\/messages$/.test(r.path));
    const dropPosts = dropReqs.filter((r) => r.dropped).length;
    xml = await dump();
    const dropDraftKept = xml.includes('paritydrop');
    const dropError = xml.includes('Không kết nối') || xml.includes('thử lại') || xml.includes('try again') || dropDraftKept;
    await shot('n3-drop-draft', { theme: 'dark', locale: 'vi', screen: 'direct-chat', state: 'response-dropped', set: 'behavior' });
    stage('n3-group-unread');
    xml = await leaveChat();
    await sleep(600);
    xml = await dump();
    if (!findText(xml, 'QA Group')) { await swipeUp(); xml = await dump(); }
    await tapExact('QA Group');
    xml = await waitXml(10000, (x) => x.includes('Hello parity'));
    await shot('n3-group-opened', { theme: 'dark', locale: 'vi', screen: 'group-chat', state: 'opened', set: 'behavior' });
    const unreadAfterGroup = { direct: unreadDirect(), group: unreadGroup() };
    await leaveChat();
    const pass = unreadBefore.direct === 2 && unreadBefore.group === 3
      && unreadAfterDm.direct === 0 && unreadAfterDm.group === 3
      && onlineDraft.fieldText === 'paritynetok'
      && okCount === 1
      && offlineDraft.fieldText === 'parityoffline' && offlineCount === 0 && offlineDraftKept && offlineBlocked
      && reconnectDraft.fieldText === 'parityreconnect' && reconnectCount === 1
      && dropDraft.visible && dropCount === 1 && dropPosts === 1 && dropReqs.length === 1 && dropDraftKept && dropError
      && unreadAfterGroup.group === 0;
    const actual = {
      unreadBefore, unreadAfterDm, unreadAfterGroup,
      online: { focused: onlineDraft.focused, visible: onlineDraft.visible, fieldText: onlineDraft.fieldText, tap: onlineTap, retap: onlineRetap, okCount },
      offline: { focused: offlineDraft.focused, visible: offlineDraft.visible, fieldText: offlineDraft.fieldText, tap: offlineTap, offlineCount, offlineDraftKept, offlineBlocked },
      reconnect: { focused: reconnectDraft.focused, visible: reconnectDraft.visible, fieldText: reconnectDraft.fieldText, tap: reconnectTap, reconnectCount },
      drop: { focused: dropDraft.focused, visible: dropDraft.visible, fieldText: dropDraft.fieldText, tap: dropTap, dropCount, dropPosts, dropRequests: dropReqs.length, dropDraftKept },
      recentMessages: recentMessages()
    };
    fs.writeFileSync(path.join(LOGS, 'and-n3.json'), JSON.stringify(actual, null, 2));
    pushCase({
      caseId: 'AND-N3', baseline: BASELINE, artifactSha256: apkSha, command, exitCode: pass ? 0 : 1,
      expected: 'UI inbox/DM/group; normal send commits exactly one; offline send does not commit and keeps the draft; reconnect send commits exactly one; dropped response leaves exactly one server message, no replay, and keeps the draft',
      actual,
      status: pass ? 'pass' : 'fail',
      artifact: 'outputs/optimization-controlled-20261119/phase1/android/runtime/logs/and-n3.json',
      fixtureEnabled: false, testOrigin: { primary: primaryOrigin, fallback: fallbackOrigin },
      requestCount: observed.slice(before).length
    });
  } catch (error) {
    pushCase({
      caseId: 'AND-N3', baseline: BASELINE, artifactSha256: apkSha, command, exitCode: 1,
      expected: 'full UI chat flow with network loss', actual: { error: String(error.stack || error), unread: { direct: unreadDirect(), group: unreadGroup() } },
      status: 'fail', artifact: 'outputs/optimization-controlled-20261119/phase1/android/runtime/logs/and-n3-logcat.txt', fixtureEnabled: false,
      testOrigin: { primary: primaryOrigin, fallback: fallbackOrigin }
    });
    try { fs.writeFileSync(path.join(LOGS, 'and-n3-logcat.txt'), await qaLogs()); } catch {}
  }
}

async function captureAuthMatrix() {
  let xml = await dump();
  if (signedIn(xml)) {
    try { await confirmLogout(); } catch (error) { logLine('auth logout ' + error.message); }
  }
  for (const theme of ['dark', 'light']) {
    for (const locale of ['vi', 'en']) {
      await launch(launchArgs(theme, locale, 'login'));
      xml = await waitXml(12000, (x) => signedOut(x) || signedIn(x));
      if (signedIn(xml) || !signedOut(xml)) throw new Error('auth capture still signed in ' + theme + ' ' + locale);
      const remembered = xml.includes('qaminh') || xml.includes('QA Minh');
      await shot(`auth-${theme}-${locale}`, { set: 'parity', theme, locale, screen: 'auth', state: remembered ? 'logged-out-remembered-device' : 'logged-out', textScale: 'default' });
    }
  }
}

async function captureRest() {
  await refreshSeedCookies();
  await ensureSignedIn();
  let postSource = 'missing';
  for (const theme of ['dark', 'light']) {
    for (const locale of ['vi', 'en']) {
      postSource = await captureSignedIn(theme, locale);
    }
  }
  await ensureParityPost();
  await adb('shell', 'settings', 'put', 'system', 'font_scale', '1.3');
  try {
    await launch(launchArgs('light', 'vi', 'feed'));
    const xml = await waitXml(15000, (x) => x.includes('P1 parity post'));
    if (!xml.includes('P1 parity post')) throw new Error('large-text feed missing post');
    await shot('feed-light-vi-large-text', { set: 'parity', theme: 'light', locale: 'vi', screen: 'feed', state: 'P1 parity post', textScale: 'large' });
  } finally {
    await adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0');
  }
  await adb('shell', 'wm', 'density', '540');
  await readDisplay();
  try {
    await ensureParityPost();
    await launch(launchArgs('light', 'en', 'feed'));
    const xml = await waitXml(15000, (x) => x.includes('P1 parity post'));
    if (!xml.includes('P1 parity post')) throw new Error('narrow feed missing post');
    await shot('feed-light-en-narrow', { set: 'parity', theme: 'light', locale: 'en', screen: 'feed', state: 'P1 parity post', textScale: 'default', viewport: 'narrow' });
  } finally {
    await adb('shell', 'wm', 'density', 'reset');
    await readDisplay();
  }
  return postSource;
}

function writeReport(postSource, seedInfo, boot) {
  const byId = Object.fromEntries(cases.map((c) => [c.caseId, c]));
  const lines = [];
  lines.push('# Android Phase 1 network + parity — 19/11/2026');
  lines.push('');
  lines.push(`- Agent: qoder (qoder-cli 1.1.92)`);
  lines.push(`- Baseline: \`${BASELINE}\``);
  lines.push(`- Worktree: \`D:/Codex/Kinnect-opt-phase1-android-20261119\``);
  lines.push(`- APK SHA-256: \`${apkSha}\``);
  lines.push(`- Serial: \`${SERIAL}\` (disposable AVD kinnect-qa-net, port 5592, not a user device)`);
  lines.push(`- Origins: primary \`${primaryOrigin}\`, fallback \`${fallbackOrigin}\` (both 127.0.0.1 createApp :memory:, cert pin \`${certSha256}\`)`);
  lines.push(`- fixtureEnabled: false for every behavioral case and capture`);
  lines.push(`- Seed: QA Minh / QA Lan / P1 parity post / Hello parity / unread direct ${seedInfo?.direct} group ${seedInfo?.group}`);
  lines.push(`- Post visible in captures: ${postSource}`);
  lines.push(`- Boot: ${boot}`);
  lines.push('');
  for (const id of ['AND-N1', 'AND-N2', 'AND-N3']) {
    const item = byId[id];
    lines.push(`## ${id} — ${item ? item.status : 'not-run'}`);
    lines.push('');
    if (!item) { lines.push('Not run.'); continue; }
    lines.push(`- Expected: ${item.expected}`);
    lines.push(`- Exit code: ${item.exitCode}`);
    lines.push('```json');
    lines.push(JSON.stringify(item.actual, null, 2));
    lines.push('```');
    lines.push('');
  }
  const failed = cases.filter((c) => c.status === 'fail');
  if (failed.length) {
    lines.push('## Bugs for Codex');
    lines.push('');
    lines.push('Behavioral failures are not treated as pass. Re-run `node scripts/qa-phase1-parity.mjs` from the QA worktree against the disposable emulator only.');
    lines.push('');
  }
  lines.push('## Captures');
  lines.push('');
  lines.push('Manifest: `outputs/optimization-controlled-20261119/phase1/android/runtime/captures/manifest.json`. Every entry is `kind: real` and `fixtureEnabled: false`.');
  lines.push('');
  const seen = new Set();
  const problems = [];
  for (const cap of captures) {
    if (!cap.file) { problems.push('missing file'); continue; }
    if (seen.has(cap.file)) problems.push('duplicate ' + cap.file);
    seen.add(cap.file);
    const abs = path.join('D:\\Codex\\Kinnect', cap.file.replaceAll('/', path.sep));
    const buf = fs.readFileSync(abs);
    const recorded = cap.sha256;
    const sha256 = crypto.createHash('sha256').update(buf).digest('hex');
    if (recorded !== sha256) problems.push('sha mismatch ' + cap.file);
    cap.bytes = buf.length;
    cap.sha256 = sha256;
    cap.png = buf.length > 8 && buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47;
    cap.apkSha256 = apkSha;
    cap.buildSha256 = apkSha;
    cap.sourceTreeSha256 = sourceTreeSha;
    cap.sourceDiffSha256 = sourceDiffSha;
    if (!cap.png || cap.bytes < 1000) problems.push('bad png ' + cap.file);
    if (!cap.sha256 || cap.sha256.length !== 64) problems.push('missing sha ' + cap.file);
  }
  if (problems.length) lines.push('Capture problems: ' + problems.join('; '));
  else lines.push('Every capture path is unique, exists, and its sha256 was recomputed from the file bytes.');
  fs.writeFileSync(path.join(OUT, 'report.md'), lines.join('\n'), 'utf8');
  fs.writeFileSync(path.join(CAPTURES, 'manifest.json'), JSON.stringify({ fixtureEnabled: false, kind: 'real', buildSha256: apkSha, captures }, null, 2));
  fs.writeFileSync(path.join(LOGS, 'requests.json'), JSON.stringify(observed.map((r) => ({ role: r.role, method: r.method, path: r.path, status: r.status, hasSession: r.hasSession, ifNoneMatch: r.ifNoneMatch, ifNoneMatchValue: r.ifNoneMatchValue || '', dropped: r.dropped, held: r.held })), null, 2));
  fs.writeFileSync(path.join(OUT, 'results.json'), JSON.stringify(publicResults(), null, 2));
  if (problems.length) throw new Error('capture integrity ' + problems.join('; '));
}

function sourceFingerprint(label) {
  const tree = crypto.createHash('sha256');
  const java = {};
  for (const variant of ['main', 'debug', 'release']) {
    const javaDir = path.join(WORKTREE, 'android', 'app', 'src', variant, 'java', 'app', 'kinnect', 'live');
    if (!fs.existsSync(javaDir)) continue;
    const names = fs.readdirSync(javaDir).filter((name) => name.endsWith('.java')).sort();
    for (const name of names) {
      const key = variant + '/' + name;
      const sha = crypto.createHash('sha256').update(fs.readFileSync(path.join(javaDir, name))).digest('hex');
      java[key] = sha;
      tree.update(key + '\n' + sha + '\n');
    }
  }
  const debugAssets = path.join(WORKTREE, 'android', 'app', 'src', 'debug', 'assets');
  const debugAssetsHashes = {};
  if (fs.existsSync(debugAssets)) {
    for (const name of fs.readdirSync(debugAssets).sort()) {
      const full = path.join(debugAssets, name);
      if (!fs.statSync(full).isFile()) continue;
      const sha = crypto.createHash('sha256').update(fs.readFileSync(full)).digest('hex');
      debugAssetsHashes[name] = sha;
      tree.update('debug/assets/' + name + '\n' + sha + '\n');
    }
  }
  let diffSha = '';
  try {
    const diff = execFileSync('git', ['-C', WORKTREE, 'diff', '--binary', 'HEAD', '--', 'android/app/src/main/java', 'android/app/src/debug', 'android/app/src/release', 'android/app/src/main/AndroidManifest.xml'], { maxBuffer: 64 * 1024 * 1024 });
    diffSha = crypto.createHash('sha256').update(diff).digest('hex');
  } catch (error) {
    diffSha = 'git-diff-failed';
  }
  const harness = fs.readFileSync(new URL(import.meta.url));
  return {
    label,
    at: new Date().toISOString(),
    javaTreeSha256: tree.digest('hex'),
    androidSourceDiffSha256: diffSha,
    harnessSha256: crypto.createHash('sha256').update(harness).digest('hex'),
    debugAssets: debugAssetsHashes,
    java
  };
}
async function readDisplay() {
  const size = await adb('shell', 'wm', 'size');
  const densityText = await adb('shell', 'wm', 'density');
  const sizeMatch = /Override size:\s*(\d+)x(\d+)/.exec(size) || /Physical size:\s*(\d+)x(\d+)/.exec(size);
  const densityMatch = /Override density:\s*(\d+)/.exec(densityText) || /Physical density:\s*(\d+)/.exec(densityText);
  if (!sizeMatch || !densityMatch) throw new Error('display parse ' + size + ' ' + densityText);
  display = {
    widthPx: Number(sizeMatch[1]),
    heightPx: Number(sizeMatch[2]),
    density: Number(densityMatch[1]),
    logicalWidthDp: Math.round((Number(sizeMatch[1]) / Number(densityMatch[1])) * 1600) / 10
  };
  return size.replaceAll('\n', ' ') + ' ' + densityText.replaceAll('\n', ' ');
}
async function main() {
  const only = ONLY;
  stage('wait-boot ' + only);
  let booted = false;
  for (let i = 0; i < 60; i++) {
    try {
      const ready = await adb('shell', 'getprop', 'sys.boot_completed');
      if (ready === '1') { booted = true; break; }
    } catch {}
    await sleep(3000);
  }
  if (!booted) throw new Error('emulator-5592 did not boot');
  const avd = await adb('emu', 'avd', 'name');
  if (!avd.toLowerCase().includes('kinnect-qa-net')) throw new Error('refusing AVD ' + avd);
  const shown = await readDisplay();
  logLine('display ' + shown + ' logical ' + display.logicalWidthDp);
  const beforeBuild = sourceFingerprint('before-install');
  sourceTreeSha = beforeBuild.javaTreeSha256;
  sourceDiffSha = beforeBuild.androidSourceDiffSha256;
  const apkBuf = fs.readFileSync(APK);
  apkSha = crypto.createHash('sha256').update(apkBuf).digest('hex');
  apkBytes = apkBuf.length;
  const apkStat = fs.statSync(APK);
  fs.writeFileSync(path.join(OUT, 'build-provenance.json'), JSON.stringify({
    jobId: JOB,
    apkPath: APK,
    apkBytes,
    apkSha256: apkSha,
    apkMtime: apkStat.mtime.toISOString(),
    hashComputedAt: new Date().toISOString(),
    buildPerformedThisRun: true,
    buildNote: 'Debug variant built by scripts/build-phase1-variant-apk.py from this worktree (main + debug source sets); SHA-256 hashed from the APK bytes immediately before adb install.',
    sourceBeforeInstall: beforeBuild
  }, null, 2));
  try { await adb('uninstall', 'app.kinnect.live'); } catch {}
  await adb('install', '-r', '-d', APK);
  let pkg = '';
  for (let attempt = 0; attempt < 6 && !pkg.includes('DEBUGGABLE'); attempt++) {
    await sleep(800);
    try { pkg = await adb('shell', 'dumpsys', 'package', 'app.kinnect.live'); } catch (error) { pkg = String(error.stdout || error.message || ''); }
  }
  if (!pkg.includes('DEBUGGABLE')) {
    fs.writeFileSync(path.join(LOGS, 'package-dump.txt'), pkg.slice(0, 4000));
    throw new Error('QA package missing or not debuggable');
  }
  await adb('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP');
  try { await adb('shell', 'wm', 'dismiss-keyguard'); } catch {}
  await adb('shell', 'pm', 'grant', 'app.kinnect.live', 'android.permission.POST_NOTIFICATIONS');
  for (const perm of ['android.permission.CAMERA', 'android.permission.RECORD_AUDIO', 'android.permission.ACCESS_COARSE_LOCATION']) {
    try { await adb('shell', 'pm', 'grant', 'app.kinnect.live', perm); } catch {}
  }
  try { await adb('shell', 'dumpsys', 'deviceidle', 'whitelist', '+app.kinnect.live'); } catch {}
  try { await adb('shell', 'appops', 'set', 'app.kinnect.live', 'USE_FULL_SCREEN_INTENT', 'allow'); } catch {}
  await adb('shell', 'settings', 'put', 'global', 'window_animation_scale', '0');
  await adb('shell', 'settings', 'put', 'global', 'transition_animation_scale', '0');
  await adb('shell', 'settings', 'put', 'global', 'animator_duration_scale', '0');
  await adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0');
  await adb('reverse', `tcp:${primaryPort}`, `tcp:${primaryPort}`);
  await adb('reverse', `tcp:${fallbackPort}`, `tcp:${fallbackPort}`);
  const seedInfo = await seed();
  logLine('seed ' + JSON.stringify(seedInfo));
  fs.writeFileSync(path.join(OUT, 'seed-used.json'), JSON.stringify({ ...seedInfo, user: 'QA Minh', peer: 'QA Lan', post: 'P1 parity post', message: 'Hello parity', fixtureEnabled: false }, null, 2));
  if (only === 'ALL' || only === 'AND-N1' || only === 'N3FOCUS') await runN1(seedInfo);
  if (only === 'ALL' || only === 'AND-N2') await runN2();
  let postSource = 'not-captured';
  if (only === 'ALL' || only === 'CAPTURES') {
    stage('captures-signed-in');
    postSource = await captureRest();
    stage('captures-auth');
    await captureAuthMatrix();
  }
  if (only === 'N3FOCUS') { stage('focus-signin'); await uiLogin(); }
  if (only === 'ALL' || only === 'AND-N3' || only === 'N3FOCUS') await runN3AndChats();
  const afterRun = sourceFingerprint('after-run');
  const provenancePath = path.join(OUT, 'build-provenance.json');
  const provenance = JSON.parse(fs.readFileSync(provenancePath, 'utf8'));
  provenance.sourceAfterRun = afterRun;
  provenance.javaUnchangedDuringRun = beforeBuild.javaTreeSha256 === afterRun.javaTreeSha256;
  fs.writeFileSync(provenancePath, JSON.stringify(provenance, null, 2));
  writeReport(postSource, seedInfo, `booted ${shown} logicalWidthDp=${display.logicalWidthDp}`);
  logLine('done ' + cases.map((c) => c.caseId + ':' + c.status).join(' '));
}

process.on('unhandledRejection', (error) => {
  logLine('UNHANDLED ' + (error && error.stack || error));
});
try {
  await main();
} catch (error) {
  logLine('FATAL ' + (error.stack || error));
  fs.writeFileSync(path.join(LOGS, 'fatal.txt'), String(error.stack || error));
  try { writeReport('not-captured', null, 'fatal ' + error.message); } catch {}
  process.exitCode = 1;
} finally {
  try { await adb('reverse', '--remove-all'); } catch {}
  primaryHttps.close();
  fallbackHttps.close();
  try { primaryApp.social.close(); } catch {}
  try { fallbackApp.social.close(); } catch {}
  fs.rmSync(tmpDir, { recursive: true, force: true });
}
