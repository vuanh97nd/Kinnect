if (!process.env.UV_THREADPOOL_SIZE) process.env.UV_THREADPOOL_SIZE = '16';
import { createServerRestart } from './lib/server-restart.js';
import { createAdminCloudBridge } from './lib/admin-cloud-bridge.js';
import { createAdminAuthority } from './lib/admin-authority.js';
import { createAdminConsole } from './lib/admin-console.js';
import { startSupabaseSecondarySync } from './lib/supabase-secondary-sync.js';
import { createLiveGifts } from './lib/live-gifts.js';
import { createPcCloudBridge } from './lib/pc-cloud-bridge.js';
import { createSharedSession } from './lib/shared-session.js';
import { liveRoomBlocks } from './lib/live-access.js';
import { createLiveSFU } from './lib/live-sfu.js';
import { createLiveGuests } from './lib/live-guests.js';
import { createLiveModes } from './lib/live-modes.js';
import { createApkDownload } from './lib/apk-download.js';
import { publishedApk } from './lib/apk-releases.js';
import { createTyping } from './lib/typing.js';
import { createCalls } from "./lib/calls.js";
import { createGroupCalls } from "./lib/group-calls.js";
import { createWebPush } from "./lib/webpush.js";
import { createApplePush } from "./lib/apple-push.js";
import { createFirebasePush } from "./lib/firebase-push.js";
import http from "node:http";
import { execFile } from "node:child_process";
import { mkdirSync, createReadStream, statSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { openSocial } from "./lib/social.js";
import { loadMailEnv, mailConfigured, smtpConfigured, sendMail } from "./lib/mailer.js";
import { readFile, readdir, stat, writeFile, unlink } from "node:fs/promises";
import { createHash, timingSafeEqual } from "node:crypto";
import { brotliCompressSync, gzipSync, constants as zlibConstants } from "node:zlib";
import { randomUUID } from "node:crypto";
import { WebSocketServer, WebSocket } from "ws";
import { fileURLToPath } from "node:url";

export function createApp({ dbPath = ":memory:", fetchImpl, authLimit, emailSender, emailReady, allowEmailDelivery = false, allowBrowserApp = false, storeVerifier, appleStoreVerifier, appleKeyResolver, storeEnv, liveEnv, clock, mediaCompression, internalSecret, apkDirectory = fileURLToPath(new URL("./dist/", import.meta.url)) } = {}) {
  if (dbPath !== ":memory:" && !process.env.NODE_TEST_CONTEXT) loadMailEnv(".env");
  loadMailEnv();
  loadMailEnv("oauth.env");
  loadMailEnv("turn.env");
  loadMailEnv("sfu.env");
  loadMailEnv("ai.env");
  loadMailEnv("billing.env");
  loadMailEnv("push.env");
  // Test/in-memory apps must never inherit the workstation's live SMTP delivery.
  const isolatedMail = !allowEmailDelivery || dbPath === ":memory:" || !!process.env.NODE_TEST_CONTEXT;
  const deliverEmail = emailSender ?? (isolatedMail ? async () => false : sendMail);
  const emailAvailable = emailReady ?? (isolatedMail ? () => false : smtpConfigured);
  const downloadApk = createApkDownload(apkDirectory, new URL("./dist/published-apk.json", import.meta.url));
  let notifyAIStream = () => { };
  let notifyNotifications = () => { };
  let pushNotification = () => { };
  let notifyCallMessage = () => { };
  let supabaseSyncRef = null;
  const social = openSocial(dbPath, {
    onNotification: ({ userId, id }) => { notifyNotifications(userId); if (id) pushNotification(userId, id); },
    onAIStream: event => notifyAIStream(event),
    onCallMessage: ({ userIds }) => notifyCallMessage(userIds),
    onAccountDeleted: userId => { supabaseSyncRef?.purgeAccount?.(userId)?.catch?.(() => { }); },
    fetchImpl, authLimit, storeVerifier, appleStoreVerifier, appleKeyResolver, storeEnv, clock,
    mediaCompression: mediaCompression ?? ((dbPath === ":memory:" || process.env.NODE_TEST_CONTEXT) ? { enabled: false } : undefined),
    sharedSession: (dbPath === ":memory:" || process.env.NODE_TEST_CONTEXT) ? null : createSharedSession(),
    sendEmail: deliverEmail, mailReady: emailAvailable,
    // Báo về email quản trị khi có người gửi yêu cầu quên mật khẩu.
    onResetRequest: (r) => {
      const when = new Date().toLocaleString("vi-VN", { timeZone: "Asia/Ho_Chi_Minh" });
      console.log(`[quen-mat-khau] ${when} Đã tiếp nhận yêu cầu khôi phục.`);
      if (!mailConfigured()) return;
      deliverEmail({
        to: process.env.RESET_NOTIFY_EMAIL,
        subject: `Kinnect: yêu cầu quên mật khẩu @${r.username}`,
        text: [
          "Có yêu cầu đặt lại mật khẩu trên Kinnect.",
          "",
          `Tên đăng nhập: @${r.username}${r.exists ? "" : " (KHÔNG có tài khoản này)"}`,
          `Liên hệ: ${r.contact}`,
          `Ghi chú: ${r.note || "(không có)"}`,
          `Thời gian: ${when}`,
          "",
          "Xử lý: đăng nhập https://app.kinnect.io.vn bằng tài khoản quản trị → tab Quản trị → Yêu cầu quên mật khẩu → Cấp mật khẩu tạm,",
          "rồi gửi mật khẩu tạm cho người dùng qua thông tin liên hệ ở trên. Hãy xác minh đúng chủ tài khoản trước khi gửi.",
        ].join("\n"),
      }).catch((e) => console.error("[quen-mat-khau] Không gửi được email:", e.message));
    },
  });
  const rooms = new Map();
  // Mã phiên bản chung của giao diện: đổi khi bất kỳ file trong public/ thay đổi.
  let versionCache = { at: 0, value: "" };
  const compressedStatic = new Map();
  async function buildVersion() {
    if (Date.now() - versionCache.at < 5000) return versionCache.value;
    const dir = new URL("./public/", import.meta.url);
    const h = createHash("sha1");
    for (const name of (await readdir(dir)).sort()) {
      const st = await stat(new URL(name, dir));
      if (st.isFile()) h.update(name + st.size + ":" + st.mtimeMs);
    }
    versionCache = { at: Date.now(), value: h.digest("hex").slice(0, 10) };
    return versionCache.value;
  }
  let latestApk = null;
  const supabaseSecondarySync = (dbPath === ':memory:' || process.env.NODE_TEST_CONTEXT) ? null : startSupabaseSecondarySync({ db: social.db, intervalMs: 60000 });
  supabaseSyncRef = supabaseSecondarySync;
  const sharedCoreBridge = null;
  const consoleInstanceId = randomUUID();
  const restartServer = (dbPath === ':memory:' || process.env.NODE_TEST_CONTEXT) ? null : createServerRestart({ serverFile: fileURLToPath(import.meta.url), dbPath, port: () => server.address().port, shutdown: () => { server.close(); for (const ws of wss.clients) ws.terminate(); setTimeout(() => { server.closeAllConnections(); social.close(); process.exit(0); }, 500); } });
  const probes = { sockets: () => 0, rooms: () => 0, sfu: () => ({ configured: false, ready: false, maxViewers: 0, maxRooms: 0 }) };
  const appStatus = () => { const mem = process.memoryUsage(); let databaseMb = null; if (dbPath && dbPath !== ':memory:') { try { databaseMb = Math.round(statSync(dbPath).size / 1048576 * 10) / 10; } catch { } } const ai = social.ai.status(), now = Date.now(); const q = (sql, ...v) => { try { return social.db.prepare(sql).get(...v); } catch { return null; } }; return { ok: true, maintenance: !!global.__KINNECT_MAINTENANCE_MODE, uptime: Math.floor(process.uptime()), memoryMb: Math.round(mem.rss / 1048576), heapUsedMb: Math.round(mem.heapUsed / 1048576), heapTotalMb: Math.round(mem.heapTotal / 1048576), platform: process.platform + ' ' + process.arch, node: process.version, pid: process.pid, sockets: probes.sockets(), liveRooms: probes.rooms(), sfu: probes.sfu(), databaseMb, aiQueue: ai.queue || 0, aiFailed: ai.failed || 0, mediaCompression: social.mediaCompressor.status(), visitors: { online: q('SELECT count(*) n FROM users WHERE last_active>? AND suspended=0', now - 90000)?.n ?? 0, sessions: q('SELECT count(*) n FROM sessions WHERE expires>?', now)?.n ?? 0, members: q("SELECT count(*) n FROM users WHERE role='user'")?.n ?? 0, suspended: q('SELECT count(*) n FROM users WHERE suspended=1')?.n ?? 0 } }; };
  const adminCloud = (dbPath === ':memory:' || process.env.NODE_TEST_CONTEXT) ? null : createAdminCloudBridge(social, { dispatch: (req, res) => adminConsole(req, res), appStatus });
  let watchdogCache = { at: 0, value: null };
  const getWatchdogStatus = () => new Promise((resolveStatus) => {
    const now = Date.now();
    if (watchdogCache.value && now - watchdogCache.at < 15000) return resolveStatus(watchdogCache.value);
    if (dbPath === ':memory:' || process.env.NODE_TEST_CONTEXT || process.platform !== 'win32') return resolveStatus(null);
    execFile('tasklist', ['/FI', 'IMAGENAME eq KinnectServerManager.exe', '/FO', 'CSV', '/NH'], { windowsHide: true, timeout: 2000 }, (err, stdout) => {
      if (err || !stdout) return resolveStatus(null);
      const line = stdout.split(/\r?\n/).find((l) => l.includes('KinnectServerManager.exe'));
      if (!line) {
        watchdogCache = { at: Date.now(), value: null };
        return resolveStatus(null);
      }
      const cols = line.split('","').map((s) => s.replace(/^"|"$/g, ''));
      const pid = Number(cols[1]);
      const val = Number.isInteger(pid) && pid > 0 ? { status: 'operational', pid } : null;
      watchdogCache = { at: Date.now(), value: val };
      resolveStatus(val);
    });
  });
  const adminConsole = createAdminConsole(social, {
    trustedPrincipal: req => adminCloud?.trustedPrincipal(req),
    verifyConsoleProxy: req => adminCloud?.verifyConsoleProxy?.(req) || null,
    getWatchdogStatus,
    onAccessChanged: () => enforceAccess(),
    restartServer, databasePath: dbPath, instanceId: consoleInstanceId, runtimeStatus: () => ({ sockets: probes.sockets(), liveRooms: probes.rooms(), sfu: probes.sfu() }),
    authority: createAdminAuthority(dbPath),
    getPcTelemetry: () => ({
      activeConnections: wss ? wss.clients.size : 0,
      activeUsers: wss ? new Set([...wss.clients].map(c => c.userId).filter(Boolean)).size : 0,
      heapMb: Math.round(process.memoryUsage().heapUsed / 1048576),
      uptime: Math.round(process.uptime())
    }),
    loginAdmin: async (username, password) => {
      const base = 'http://127.0.0.1:' + server.address().port;
      const response = await fetch(base + '/api/login', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password }), signal: AbortSignal.timeout(20000),
      });
      if (!response.ok) return null;
      const result = await response.json();
      const cookie = response.headers.get('set-cookie')?.split(';')[0];
      if (cookie) await fetch(base + '/api/logout', { method: 'POST', headers: { Cookie: cookie }, signal: AbortSignal.timeout(10000) }).catch(() => { });
      return result.user?.role === 'admin' ? result.user : null;
    },
  });
  let wss = null;
  const pushRateLimits = new Map();
  const pipeFileStream = (file, res, opts) => {
    const stream = createReadStream(file, opts);
    stream.on("error", () => {
      if (!res.headersSent) {
        res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" });
        res.end("Not Found");
      } else {
        res.destroy();
      }
    });
    res.on("close", () => stream.destroy());
    return stream.pipe(res);
  };
  const server = http.createServer(async (req, res) => {
    try {
      res.setHeader("X-Content-Type-Options", "nosniff");
      if (
        process.env.SECURE_COOKIES === "1" ||
        String(req.headers["x-forwarded-proto"] || "").split(",")[0].trim() === "https" ||
        String(req.headers["cf-visitor"] || "").includes('"https"')
      ) {
        res.setHeader("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
      }
      if (adminCloud && await adminCloud.handle(req, res)) return;

      const path = new URL(req.url, "http://localhost").pathname;
      if (path === "/internal/admin/invalidate-auth" && req.method === "POST") {
        const remote = String(req.socket?.remoteAddress || "");
        const isLoopback = remote === "127.0.0.1" || remote === "::1" || remote === "::ffff:127.0.0.1";
        if (!isLoopback || req.headers["x-forwarded-for"] || req.headers["cf-connecting-ip"]) {
          res.writeHead(403, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
          res.end(JSON.stringify({ error: "Forbidden" }));
          return;
        }
        const secret = typeof internalSecret === "string" && internalSecret ? internalSecret : String(process.env.MIGRATION_SECRET || "");
        const provided = String(req.headers["x-kinnect-internal"] || "");
        const secretOk = secret.length >= 16 && provided.length > 0 && timingSafeEqual(
          createHash("sha256").update(secret).digest(),
          createHash("sha256").update(provided).digest()
        );
        if (!secretOk) {
          res.writeHead(401, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
          res.end(JSON.stringify({ error: "Unauthorized" }));
          return;
        }
        const chunks = [];
        let size = 0;
        for await (const c of req) {
          size += c.length;
          if (size > 4096) {
            res.writeHead(413, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
            res.end(JSON.stringify({ error: "Payload too large" }));
            return;
          }
          chunks.push(c);
        }
        let payload = null;
        try { payload = JSON.parse(Buffer.concat(chunks).toString("utf8")); } catch {}
        const uid = typeof payload?.userId === "string" ? payload.userId.trim() : "";
        if (!uid) {
          res.writeHead(400, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
          res.end(JSON.stringify({ error: "Missing userId" }));
          return;
        }
        social.invalidateAuth?.(uid);
        if (wss) {
          for (const client of wss.clients) {
            if (client.userId === uid) {
              try { leave(client); } catch {}
              try { client.close(4401, "Session invalidated"); } catch {}
            }
          }
        }
        enforceAccess();
        res.writeHead(200, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
        res.end(JSON.stringify({ ok: true }));
        return;
      }

    if (await adminConsole(req, res)) return;
    if(sharedCoreBridge&&await sharedCoreBridge(req,res))return;
    if (global.__KINNECT_MAINTENANCE_MODE && path !== '/health') {
      res.writeHead(503, { "Content-Type": "application/json; charset=utf-8", "Retry-After": "120" });
      res.end(JSON.stringify({
        error: "Hệ thống đang được nâng cấp bảo trì bởi Bộ phận Kỹ thuật Kinnect. Vui lòng quay lại sau ít phút.",
        maintenance: true,
        timestamp: Date.now()
      }));
      return;
    }
    // Public native-handoff share cards (/share/post/:id, /share/short/:id, /share/live/:id)
    const shareMatch = (req.method === "GET" || req.method === "HEAD") ? path.match(/^\/share\/(post|short|live)\/([a-zA-Z0-9_-]{1,64})$/) : null;
    if (shareMatch) {
      const [, kind, targetId] = shareMatch;
      const esc = (s) => String(s || "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
      let title = "Kinnect — Kết nối đúng gu. Sống đúng mình.";
      let desc = "Mở nội dung này trong ứng dụng Kinnect trên iPhone hoặc Android.";
      const protoHeader = String(req.headers["x-forwarded-proto"] || "").split(",")[0].trim().toLowerCase();
      let defaultShareHost = "app.kinnect.io.vn";
      let publicUrlHost = "";
      if (process.env.PUBLIC_URL) {
        try {
          const pub = new URL(process.env.PUBLIC_URL);
          if (pub.protocol === "http:" || pub.protocol === "https:") {
            publicUrlHost = pub.host.toLowerCase();
            defaultShareHost = publicUrlHost;
          }
        } catch {}
      }
      const allowedShareHost = (raw) => {
        const candidate = String(raw || "").split(",")[0].trim().toLowerCase();
        if (!candidate || !/^[a-z0-9.:\[\]-]+$/.test(candidate)) return "";
        try {
          const u = new URL("https://" + candidate);
          if (u.username || u.password || u.pathname !== "/" || u.search || u.hash) return "";
          const h = u.hostname.toLowerCase();
          if (
            h === "kinnect.io.vn" ||
            h.endsWith(".kinnect.io.vn") ||
            h === "localhost" ||
            h === "127.0.0.1" ||
            h === "[::1]" ||
            h === "::1" ||
            (publicUrlHost && u.host.toLowerCase() === publicUrlHost)
          ) {
            return u.host.toLowerCase();
          }
        } catch {}
        return "";
      };
      const hostHeader = allowedShareHost(req.headers["x-forwarded-host"]) || allowedShareHost(req.headers.host) || defaultShareHost;
      const baseOrigin = (protoHeader === "http" ? "http://" : "https://") + hostHeader;
      let img = `${baseOrigin}/kinnect-og-1200x630.png`;
      try {
        if (kind === "post") {
          const p = social.db.prepare("SELECT p.id,p.body,p.visibility,p.hidden,u.name,u.suspended FROM posts p JOIN users u ON u.id=p.user_id WHERE p.id=?").get(targetId);
          if (p && !p.hidden && !p.suspended && p.visibility === "public") {
            title = (p.name || "Thành viên Kinnect") + " trên Kinnect";
            desc = String(p.body || "Bài viết trên Kinnect").replace(/\s+/g, " ").trim().slice(0, 160) || desc;
            if (social.db.prepare("SELECT 1 FROM media_thumbnails WHERE kind='post' AND target_id=?").get(p.id)) img = `${baseOrigin}/api/posts/${encodeURIComponent(p.id)}/thumbnail`;
            else if (social.db.prepare("SELECT 1 FROM post_media WHERE post_id=? AND type LIKE 'image/%'").get(p.id)) img = `${baseOrigin}/api/posts/${encodeURIComponent(p.id)}/media`;
          }
        } else if (kind === "short") {
          const s = social.db.prepare("SELECT s.id,s.caption,s.hidden,u.name,u.suspended FROM shorts s JOIN users u ON u.id=s.user_id WHERE s.id=?").get(targetId);
          if (s && !s.hidden && !s.suspended) {
            title = "Video ngắn của " + (s.name || "Kinnect");
            desc = String(s.caption || "Xem video ngắn trên ứng dụng Kinnect").replace(/\s+/g, " ").trim().slice(0, 160) || desc;
            if (social.db.prepare("SELECT 1 FROM media_thumbnails WHERE kind='short' AND target_id=?").get(s.id)) img = `${baseOrigin}/api/shorts/${encodeURIComponent(s.id)}/thumbnail`;
          }
        } else if (kind === "live") {
          const r = rooms.get(targetId);
          if (r) {
            title = (r.host?.name || "Kinnect") + " đang phát trực tiếp trên Kinnect";
            desc = String(r.title || "Tham gia phòng Live trên ứng dụng Kinnect").slice(0, 160);
          }
        }
      } catch {}
      const deepLink = `kinnect://${kind}/${encodeURIComponent(targetId)}`;
      const ua = String(req.headers["user-agent"] || "");
      const isMobileUa = /Android|iPhone|iPad|iPod/i.test(ua);
      const actionMarkup = isMobileUa
        ? `<a class="btn primary" href="${esc(deepLink)}">Mở trong ứng dụng Kinnect</a><a class="btn secondary" href="/download/android">Tải ứng dụng Android (APK)</a><p class="hint">iOS: Ra mắt trên App Store ngày 01/12 · Chưa cài app? Tải bản Android hoặc xem tại kinnect.io.vn</p>`
        : `<p class="desktop-note">Nội dung này mở trực tiếp trên ứng dụng di động Kinnect (iOS &amp; Android).</p><a class="btn primary" href="/download/android">Tải ứng dụng Android (APK)</a><a class="btn secondary" href="https://kinnect.io.vn">Khám phá Kinnect (iOS ra mắt 01/12)</a>`;
      const html = `<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(title)}</title><meta property="og:type" content="website"><meta property="og:site_name" content="Kinnect"><meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(desc)}"><meta property="og:image" content="${esc(img)}"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta property="al:ios:url" content="${esc(deepLink)}"><meta property="al:android:url" content="${esc(deepLink)}"><meta property="al:android:package" content="app.kinnect.live"><meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="${esc(title)}"><meta name="twitter:description" content="${esc(desc)}"><meta name="twitter:image" content="${esc(img)}"><meta name="robots" content="noindex"><style>*{box-sizing:border-box;font-family:system-ui,-apple-system,sans-serif}body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:linear-gradient(160deg,#f7f4ff 0%,#ede7ff 100%);color:#1f1d2b;padding:24px}.card{max-width:440px;width:100%;background:#ffffff;border:1px solid rgba(108,71,224,.16);border-radius:28px;padding:32px 28px;text-align:center;box-shadow:0 20px 56px rgba(67,40,148,.12)}h1{font-size:21px;line-height:1.3;margin:16px 0 10px;color:#1f1d2b}p{color:#5c556d;font-size:15px;line-height:1.55;margin:0 0 22px}.desktop-note{background:#f4f0ff;color:#4c2db3;border-radius:14px;padding:12px 14px;font-size:14px;font-weight:600;margin-bottom:18px}.hint{font-size:13px;color:#6a6478;margin:6px 0 0}.btn{display:flex;align-items:center;justify-content:center;min-height:48px;width:100%;padding:13px 18px;border-radius:999px;text-decoration:none;font-weight:700;font-size:15px;margin-bottom:10px}.primary{background:linear-gradient(135deg,#7c3aed,#db2777);color:#fff}.secondary{background:#f3effc;color:#4c2db3;border:1px solid rgba(124,58,237,.22)}.foot{display:inline-block;margin-top:14px;font-size:14px;color:#6d28d9;text-decoration:underline;text-underline-offset:3px}</style></head><body><main class="card"><img src="/kinnect-logo-v106.svg" width="60" height="60" alt="Biểu trưng Kinnect"><h1>${esc(title)}</h1><p>${esc(desc)}</p>${actionMarkup}<a class="foot" href="https://kinnect.io.vn">Trang chủ kinnect.io.vn</a></main></body></html>`;
      const buf = Buffer.from(html, "utf8");
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Content-Length": buf.length, "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "X-Frame-Options": "DENY", "Content-Security-Policy": "default-src 'none'; img-src 'self' https://kinnect.io.vn data:; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'" });
      return res.end(req.method === "HEAD" ? undefined : buf);
    }

    // Retire browser app entrypoints in production; native APIs, downloads, share cards and account deletion stay available.
    const browserAppEnabled = allowBrowserApp || process.env.KINNECT_ALLOW_BROWSER_APP === "1";
    const browserAppPaths = new Set(["/", "/index.html", "/ios", "/ios/", "/v2", "/v2/", "/v2.html", "/login", "/login/", "/register", "/register/", "/signup", "/signup/", "/native-welcome.html", "/install-ios", "/install-ios/", "/install-ios.html", "/install-ios-manifest", "/install-ios-manifest.html", "/Kinnect.mobileconfig", "/offline.html"]);
    if (!browserAppEnabled && (req.method === "GET" || req.method === "HEAD") && browserAppPaths.has(path)) {
      const urlObj = new URL(req.url, "http://localhost");
      const legacyPost = urlObj.searchParams.get("post");
      const legacyVideo = urlObj.searchParams.get("video");
      if (legacyPost && /^[a-zA-Z0-9_-]{1,64}$/.test(legacyPost)) {
        res.writeHead(302, { Location: "/share/post/" + encodeURIComponent(legacyPost), "Cache-Control": "no-store" });
        return res.end();
      }
      if (legacyVideo && /^[a-zA-Z0-9_-]{1,64}$/.test(legacyVideo)) {
        res.writeHead(302, { Location: "/share/short/" + encodeURIComponent(legacyVideo), "Cache-Control": "no-store" });
        return res.end();
      }
      const msg = "Kinnect - Ứng dụng web đã ngừng hỗ trợ. Vui lòng tải ứng dụng di động chính thức.";
      res.writeHead(410, { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store", "Content-Length": Buffer.byteLength(msg), "X-Robots-Tag": "noindex, nofollow" });
      return res.end(req.method === "HEAD" ? undefined : msg);
    }

    // Danh sách buổi live đang phát (cho tab "Trực tiếp" ở trang Video, web và app).
      if (path === "/api/live/rooms" && req.method === "GET") {
        const me = social.authenticate(req);
        res.writeHead(me ? 200 : 401, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
        if (!me) return res.end(JSON.stringify({ error: "Vui lòng đăng nhập." }));
        const list = [...rooms.values()]
          .filter((r) => social.user(r.host.userId)?.suspended === 0 && !social.blocked(me.id, r.host.userId))
          .map((r) => {
            const host = social.user(r.host.userId);
            return { id: r.id, title: r.title, liveMode: r.mode || 'chat', gameTitle: r.gameTitle || '', host: r.host.name, hostId: r.host.userId, hostUsername: host?.username || "", avatar: host?.avatar ? "/api/users/" + host.id + "/avatar" : null, viewers: r.members.size - 1, started: r.created || Date.now() };
          })
          .sort((a, b) => b.viewers - a.viewers || b.started - a.started);
        return res.end(JSON.stringify({ rooms: list }));
      }
      const groupCallMatch = path.match(/^\/api\/groups\/([a-zA-Z0-9-]+)\/call$/);
      if (groupCallMatch && req.method === "GET") {
        const me = social.authenticate(req);
        const out = (status, data) => { res.writeHead(status, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" }); res.end(JSON.stringify(data)); };
        if (!me) return out(401, { error: "Vui lòng đăng nhập." });
        const gid = groupCallMatch[1];
        if (!social.db.prepare("SELECT 1 FROM group_members WHERE group_id=? AND user_id=?").get(gid, me.id)) {
          return out(404, { error: "Không tìm thấy nhóm." });
        }
        return out(200, groupCalls.state(gid, me.id));
      }
      if (path.startsWith("/api/push/")) {
        const out = (status, data) => { res.writeHead(status, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" }); res.end(JSON.stringify(data)); };
        if (path === "/api/push/key" && req.method === "GET") return out(200, { publicKey: webPush.publicKey });
        const me = social.authenticate(req);
        if (!me) return out(401, { error: "Vui lòng đăng nhập." });
        if (req.method !== "POST") return out(405, { error: "Không hỗ trợ." });
        if (!(req.headers["content-type"] || "").startsWith("application/json")) return out(415, { error: "Cần Content-Type application/json." });
        if (path === "/api/push/subscribe" || path === "/api/push/test") {
          const now = Date.now(), key = me.id + ":" + path;
          let bucket = pushRateLimits.get(key);
          if (!bucket || now - bucket.time > 60000) { bucket = { time: now, count: 0 }; pushRateLimits.set(key, bucket); }
          if (++bucket.count > (path === "/api/push/test" ? 5 : 20)) return out(429, { error: "Bạn thao tác quá nhanh. Hãy thử lại sau một phút." });
          if (pushRateLimits.size > 5000) for (const [k, v] of pushRateLimits) if (now - v.time > 60000) pushRateLimits.delete(k);
        }
        let b = {};
        try { let raw = ""; for await (const chunk of req) { raw += chunk; if (raw.length > 8192) return out(413, { error: "Quá lớn." }); } b = JSON.parse(raw || "{}"); } catch { return out(400, { error: "Dữ liệu không hợp lệ." }); }
        if (path === "/api/push/subscribe") return webPush.subscribe(me.id, b.subscription) ? out(200, { ok: true }) : out(400, { error: "Đăng ký thông báo không hợp lệ." });
        if (path === "/api/push/unsubscribe") { webPush.unsubscribe(me.id, b.endpoint); return out(200, { ok: true }); }
        if (path === "/api/push/test") { await webPush.notifyTest(me.id); return out(200, { ok: true }); }
        if (path === "/api/push/decline") { calls.declineById(me.id, String(b.callId || "")); return out(200, { ok: true }); }
        return out(404, { error: "Không tìm thấy." });
      }
      if (path.startsWith("/api/") && path !== "/api/music") {
        res.once("finish", () => {
          try {
            const actor = social.authenticate(req);
            social.securityMonitor?.observeHttpExchange(req, res, {
              actorId: actor?.username || actor?.id || "",
              actorRole: actor?.role || "",
              rawPath: req.url || path
            });
          } catch { }
          if ((req.method !== "GET" && req.method !== "HEAD") || path === "/api/me") enforceAccess();
        });
        return social.api(req, res, path);
      }
      // Thư viện nhạc dùng chung cho Studio. Chỉ đặt vào MUSIC_DIR những bản nhạc được phép sử dụng.
      if (path === "/api/music" || path.startsWith("/music/")) {
        const dir = resolve(process.env.MUSIC_DIR || "music");
        const me = social.authenticate(req);
        const creditsFile = resolve(dir, "credits.json");
        const readCredits = async () => {
          try {
            return JSON.parse(await readFile(creditsFile, "utf8"));
          } catch {
            return {};
          }
        };
        const sendJson = (status, data) => {
          res.writeHead(status, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
          res.end(JSON.stringify(data));
        };
        if (path === "/api/music" && req.method === "GET") {
          let names = [];
          try {
            names = (await readdir(dir)).filter((n) => /\.(mp3|m4a|aac)$/i.test(n)).sort().slice(0, 2000);
          } catch { }
          const credits = await readCredits();
          return sendJson(200, {
            tracks: names.map((n) => ({
              file: n,
              title: credits[n]?.title || n.replace(/\.[^.]+$/, "").replace(/[_]+/g, " ").replace(/\s*\[[^\]]*\]\s*$/, "").trim(),
              artist: credits[n]?.artist || "",
              license: credits[n]?.license || "",
              source: credits[n]?.source || "",
              url: "/music/" + encodeURIComponent(n),
            })),
          });
        }
        // Quản trị viên tải nhạc lên / xoá nhạc khỏi thư viện chung
        if (path === "/api/music" && (req.method === "POST" || req.method === "DELETE")) {
          if (!me) return sendJson(401, { error: "Vui lòng đăng nhập." });
          if (me.role !== "admin") return sendJson(403, { error: "Chỉ quản trị viên được quản lý thư viện nhạc." });
          if (req.headers.origin) {
            try {
              if (new URL(req.headers.origin).host !== req.headers.host) return sendJson(403, { error: "Yêu cầu không hợp lệ." });
            } catch {
              return sendJson(403, { error: "Yêu cầu không hợp lệ." });
            }
          } else if (req.headers["sec-fetch-site"] === "cross-site") {
            return sendJson(403, { error: "Yêu cầu không hợp lệ." });
          }
          if (!(req.headers["content-type"] || "").startsWith("application/json"))
            return sendJson(403, { error: "Yêu cầu không hợp lệ." });
          let size = 0;
          const chunks = [];
          for await (const chunk of req) {
            size += chunk.length;
            if (size > 21 * 1024 * 1024) return sendJson(413, { error: "File nhạc tối đa 15 MB." });
            chunks.push(chunk);
          }
          let b;
          try {
            b = JSON.parse(Buffer.concat(chunks).toString() || "{}");
          } catch {
            return sendJson(400, { error: "Dữ liệu không hợp lệ." });
          }
          const credits = await readCredits();
          if (req.method === "DELETE") {
            const name = typeof b.file === "string" ? b.file : "";
            if (!/^[^/\\]+\.(mp3|m4a|aac)$/i.test(name) || name.startsWith(".")) return sendJson(400, { error: "Tên file không hợp lệ." });
            try {
              await unlink(resolve(dir, name));
            } catch { }
            delete credits[name];
            await writeFile(creditsFile, JSON.stringify(credits, null, 2));
            return sendJson(200, { ok: true });
          }
          const clean = (v, n) => (typeof v === "string" ? v.replace(/[\u0000-\u001f]/g, "").trim().slice(0, n) : "");
          const title = clean(b.title, 80), artist = clean(b.artist, 60), license = clean(b.license, 80), source = clean(b.source, 300);
          if (!title || !artist || !license) return sendJson(400, { error: "Nhập tên bài, nghệ sĩ và giấy phép." });
          if (b.rights !== true) return sendJson(400, { error: "Cần xác nhận bạn có quyền dùng và chia sẻ bài này." });
          const m = typeof b.data === "string" && b.data.match(/^data:audio\/(mpeg|mp3|mp4|x-m4a|aac);base64,([A-Za-z0-9+/=]+)$/);
          if (!m) return sendJson(400, { error: "Chọn file MP3 hoặc M4A." });
          const bytes = Buffer.from(m[2], "base64");
          if (bytes.length > 15 * 1024 * 1024) return sendJson(413, { error: "File nhạc tối đa 15 MB." });
          const isMp3 = bytes.slice(0, 3).toString("latin1") === "ID3" || (bytes[0] === 0xff && (bytes[1] & 0xe0) === 0xe0);
          const isMp4 = bytes.slice(4, 8).toString("latin1") === "ftyp";
          if (!isMp3 && !isMp4) return sendJson(400, { error: "File không phải MP3/M4A hợp lệ." });
          const base = (artist + " - " + title).replace(/[\\/:*?"<>|]+/g, " ").replace(/\s+/g, " ").trim().slice(0, 120);
          let name = base + (isMp3 ? ".mp3" : ".m4a");
          for (let i = 2; names_exist(name); i++) name = base + " (" + i + ")" + (isMp3 ? ".mp3" : ".m4a");
          function names_exist(n) {
            return Object.prototype.hasOwnProperty.call(credits, n);
          }
          mkdirSync(dir, { recursive: true });
          await writeFile(resolve(dir, name), bytes);
          credits[name] = { title, artist, license, source, addedBy: me.username, added: new Date().toISOString() };
          await writeFile(creditsFile, JSON.stringify(credits, null, 2));
          return sendJson(201, { ok: true, file: name });
        }
        let name;
        try {
          name = decodeURIComponent(path.slice(7));
        } catch {
          name = "";
        }
        if (!name || name.includes("/") || name.includes("\\") || name.startsWith(".") || !/\.(mp3|m4a|aac)$/i.test(name)) {
          res.writeHead(404);
          return res.end();
        }
        try {
          const file = resolve(dir, name);
          const info = await stat(file);
          if (!info.isFile()) {
            res.writeHead(404);
            return res.end();
          }
          const total = info.size;
          const type = /\.mp3$/i.test(name) ? "audio/mpeg" : "audio/mp4";
          const headers = { "Content-Type": type, "Accept-Ranges": "bytes", "Cache-Control": "private, max-age=86400", "X-Content-Type-Options": "nosniff" };
          // Safari trên iPhone chỉ phát âm thanh khi máy chủ trả từng đoạn theo yêu cầu (HTTP Range).
          const range = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range || "");
          if (range && (range[1] || range[2])) {
            let start = range[1] ? Number(range[1]) : Math.max(0, total - Number(range[2]));
            let end = range[1] && range[2] ? Math.min(Number(range[2]), total - 1) : total - 1;
            if (!Number.isFinite(start) || !Number.isFinite(end) || start > end || start >= total || start < 0) {
              res.writeHead(416, { "Content-Range": "bytes */" + total });
              return res.end();
            }
            res.writeHead(206, { ...headers, "Content-Range": `bytes ${start}-${end}/${total}`, "Content-Length": end - start + 1 });
            return req.method === "HEAD" ? res.end() : pipeFileStream(file, res, { start, end });
          }
          res.writeHead(200, { ...headers, "Content-Length": total });
          return req.method === "HEAD" ? res.end() : pipeFileStream(file, res);
        } catch {
          res.writeHead(404);
          return res.end();
        }
      }
      // Gói nội bộ (IPA / Play AAB / Submission / Test APK): bắt buộc xác thực quản trị viên.
      if (["/download/ios", "/download/ipa", "/download/play-bundle", "/download/aab", "/download/play-submission", "/download/android-test"].includes(path)) {
        const adminActor = social.authenticate(req);
        if (!adminActor || adminActor.role !== "admin") {
          res.writeHead(404);
          return res.end();
        }
        if (req.method !== "GET" && req.method !== "HEAD") {
          res.writeHead(405, { Allow: "GET, HEAD" });
          return res.end();
        }
      }
      // Tải trực tiếp bản phát hành iOS Sideload IPA
      if (path === "/download/ios" || path === "/download/ipa") {
        try {
          const file = resolve("dist/ios/Kinnect-1.2.12-sideload.ipa");
          const info = await stat(file);
          res.writeHead(200, {
            "Content-Type": "application/octet-stream",
            "Content-Length": info.size,
            "Content-Disposition": 'attachment; filename="Kinnect-1.2.12-sideload.ipa"',
            "Cache-Control": "no-store"
          });
          return req.method === "HEAD" ? res.end() : pipeFileStream(file, res);
        } catch {
          res.writeHead(404);
          return res.end();
        }
      }
      // Tải gói Google Play Store AAB
      if (path === "/download/play-bundle" || path === "/download/aab") {
        try {
          const file = resolve("dist/google-play/Kinnect-1.2.12-play.aab");
          const info = await stat(file);
          res.writeHead(200, {
            "Content-Type": "application/octet-stream",
            "Content-Length": info.size,
            "Content-Disposition": 'attachment; filename="Kinnect-1.2.12-play.aab"',
            "Cache-Control": "no-store"
          });
          return req.method === "HEAD" ? res.end() : pipeFileStream(file, res);
        } catch {
          res.writeHead(404);
          return res.end();
        }
      }
      // Tải bộ hồ sơ xuất bản Google Play hoàn chỉnh (AAB, Checks, Store Assets)
      if (path === "/download/play-submission") {
        try {
          const file = resolve("dist/google-play/Kinnect-1.2.12-submission.zip");
          const info = await stat(file);
          res.writeHead(200, {
            "Content-Type": "application/zip",
            "Content-Length": info.size,
            "Content-Disposition": 'attachment; filename="Kinnect-1.2.12-submission.zip"',
            "Cache-Control": "no-store"
          });
          return req.method === "HEAD" ? res.end() : pipeFileStream(file, res);
        } catch {
          res.writeHead(404);
          return res.end();
        }
      }
      // Bản APK thử nghiệm chưa phát hành: chỉ ai có link mới tải được, nút cập nhật trong app không thấy.
      if (path === "/download/android-test") {
        try {
          const dir = new URL("./dist/", import.meta.url);
          const builds = [];
          for (const entry of await readdir(dir)) if (/^Kinnect-[\d.]+-native\.apk$/.test(entry)) builds.push({ entry, at: (await stat(new URL(entry, dir))).mtimeMs });
          if (!builds.length) throw Error("Chưa có APK");
          const name = builds.sort((a, b) => b.at - a.at)[0].entry;
          const file = new URL(name, dir);
          const info = await stat(file);
          res.writeHead(200, { "Content-Type": "application/vnd.android.package-archive", "Content-Length": info.size, "Content-Disposition": 'attachment; filename="' + name + '"', "Cache-Control": "no-store" });
          return req.method === "HEAD" ? res.end() : pipeFileStream(file, res);
        } catch {
          res.writeHead(404);
          return res.end();
        }
      }
      // Nút "Tải app": tự tìm APK của bản phát hành mới nhất trên GitHub và chuyển thẳng tới file để tải.
      if (path === "/download/android") {
        if (!["GET", "HEAD"].includes(req.method)) { res.writeHead(405, { Allow: "GET, HEAD" }); return res.end(); }
        if (await downloadApk(req, res)) return;
        const fallback = "https://github.com/vuanh97nd/Kinnect/releases/latest";
        try {
          if (!latestApk || latestApk.expires < Date.now()) {
            const asset = await publishedApk(fetchImpl || fetch);
            latestApk = { url: asset.url, expires: Date.now() + 60000 };
          }
          res.writeHead(302, { Location: latestApk.url, "Cache-Control": "no-store" });
        } catch {
          res.writeHead(302, { Location: fallback, "Cache-Control": "no-store" });
        }
        return res.end();
      }
      if (path === "/website" || path.startsWith("/website/")) {
        // Website giới thiệu đã chuyển sang kinnect.io.vn.
        const page = path.replace(/^\/website\/?/, "").replace(/\.html$/, "").replace(/^index$/, "");
        res.writeHead(301, { Location: "https://kinnect.io.vn/" + page });
        return res.end();
      }
      if (path === "/health") {
        const isExternal = !!(req.headers['cf-connecting-ip'] || req.headers['x-forwarded-for'] || req.headers['cf-ray']);
        const isLocal = !isExternal && ['127.0.0.1', 'localhost', '::1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress);
        const wsClients = isLocal && wss ? wss.clients.size : 0;
        const wsUsers = isLocal && wss ? new Set([...wss.clients].map(c => c.userId).filter(Boolean)).size : 0;
        const mem = isLocal ? process.memoryUsage() : null;
        const sfuFull = liveSFU.status();
        res.writeHead(200, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
        return res.end(JSON.stringify({
          ok: true,
          version: "0.3.1",
          uiVersion: "2026-10-26-new-ui",
          instanceId: consoleInstanceId,
          liveChatHistory: true,
          storyViewers: true,
          liveGuests: true,
          liveMaxGuests: 3,
          liveSfu: isLocal ? sfuFull : { configured: !!sfuFull.configured, ready: !!sfuFull.ready },
          ...(isLocal ? {
            pid: process.pid,
            telemetry: {
              activeConnections: wsClients,
              activeUsers: wsUsers,
              heapMb: Math.round(mem.heapUsed / 1048576),
              rssMb: Math.round(mem.rss / 1048576),
              uptime: Math.round(process.uptime())
            }
          } : {})
        }));
      }
      const files = {
        "/third-party-notices.txt": ["third-party-notices.txt", "text/plain"],
        "/delete-account": ["delete-account.html", "text/html"],
        "/delete-account/": ["delete-account.html", "text/html"],
        "/account-deletion.js": ["account-deletion.js", "text/javascript"],
        "/account-deletion.css": ["account-deletion.css", "text/css"],
        "/kinnect-logo-v106.svg": ["kinnect-logo-v106.svg", "image/svg+xml"],
        "/kinnect-logo-v106-32.png": ["kinnect-logo-v106-32.png", "image/png"],
        "/kinnect-logo-v106-120.png": ["kinnect-logo-v106-120.png", "image/png"],
        "/kinnect-logo-v106-152.png": ["kinnect-logo-v106-152.png", "image/png"],
        "/kinnect-logo-v106-167.png": ["kinnect-logo-v106-167.png", "image/png"],
        "/kinnect-logo-v106-180.png": ["kinnect-logo-v106-180.png", "image/png"],
        "/kinnect-logo-v106-192.png": ["kinnect-logo-v106-192.png", "image/png"],
        "/kinnect-logo-v106-512.png": ["kinnect-logo-v106-512.png", "image/png"],
        "/kinnect-og-1200x630.png": ["kinnect-og-1200x630.png", "image/png"],
        "/kinnect-mark.svg": ["kinnect-logo-v106.svg", "image/svg+xml"],
        "/favicon.ico": ["favicon.ico", "image/x-icon"],
        "/favicon-32.png": ["kinnect-logo-v106-32.png", "image/png"],
        "/kinnect-ios-120-v7.png": ["kinnect-logo-v106-120.png", "image/png"],
        "/apple-touch-icon-120x120.png": ["kinnect-logo-v106-120.png", "image/png"],
        "/apple-touch-icon-120x120-precomposed.png": ["kinnect-logo-v106-120.png", "image/png"],
        "/kinnect-ios-152-v7.png": ["kinnect-logo-v106-152.png", "image/png"],
        "/apple-touch-icon-152x152.png": ["kinnect-logo-v106-152.png", "image/png"],
        "/apple-touch-icon-152x152-precomposed.png": ["kinnect-logo-v106-152.png", "image/png"],
        "/kinnect-ios-167-v7.png": ["kinnect-logo-v106-167.png", "image/png"],
        "/apple-touch-icon-167x167.png": ["kinnect-logo-v106-167.png", "image/png"],
        "/apple-touch-icon-167x167-precomposed.png": ["kinnect-logo-v106-167.png", "image/png"],
        "/kinnect-ios-180-v7.png": ["kinnect-logo-v106-180.png", "image/png"],
        "/apple-touch-icon-180x180.png": ["kinnect-logo-v106-180.png", "image/png"],
        "/apple-touch-icon-180x180-precomposed.png": ["kinnect-logo-v106-180.png", "image/png"],
        "/kinnect-icon-192.png": ["kinnect-icon-192.png", "image/png"],
        "/apple-touch-icon.png": ["kinnect-logo-v106-180.png", "image/png"],
        "/apple-touch-icon-v5.png": ["kinnect-logo-v106-180.png", "image/png"],
        "/apple-touch-icon-v6.png": ["kinnect-logo-v106-180.png", "image/png"],
        "/apple-touch-icon-precomposed.png": ["kinnect-logo-v106-180.png", "image/png"],
        "/ios.css": ["ios.css", "text/css"],
        "/auth-preview.jpg": ["auth-preview.jpg", "image/jpeg"],
        "/theme.css": ["theme.css", "text/css"],
        "/app-ui.css": ["app-ui.css", "text/css"],
        "/ios.js": ["ios.js", "text/javascript"],
        "/onboarding.js": ["onboarding.js", "text/javascript"],
        "/sw.js": ["sw.js", "text/javascript"],
        "/manifest.webmanifest": ["manifest.webmanifest", "application/manifest+json"],
        "/offline.html": ["offline.html", "text/html"],
        "/social.js": ["social.js", "text/javascript"],
        "/social-feed.js": ["social-feed.js", "text/javascript"],
        "/social-discover.js": ["social-discover.js", "text/javascript"],
        "/social-profile.js": ["social-profile.js", "text/javascript"],
        "/social-messenger.js": ["social-messenger.js", "text/javascript"],
        "/calls.js": ["calls.js", "text/javascript"],
        "/camera.js": ["camera.js", "text/javascript"],
        "/editor-icons.js": ["editor-icons.js", "text/javascript"],
        "/media-editor.js": ["media-editor.js", "text/javascript"],
        "/media-editor.css": ["media-editor.css", "text/css"],
        "/vendor/vision/face_landmarker.task": ["vendor/vision/face_landmarker.task", "application/octet-stream"],
        "/vendor/vision/vision_bundle.mjs": ["vendor/vision/vision_bundle.mjs", "text/javascript"],
        "/vendor/vision/wasm/vision_wasm_internal.js": ["vendor/vision/wasm/vision_wasm_internal.js", "text/javascript"],
        "/vendor/vision/wasm/vision_wasm_internal.wasm": ["vendor/vision/wasm/vision_wasm_internal.wasm", "application/wasm"],
        "/vendor/vision/wasm/vision_wasm_module_internal.js": ["vendor/vision/wasm/vision_wasm_module_internal.js", "text/javascript"],
        "/vendor/vision/wasm/vision_wasm_module_internal.wasm": ["vendor/vision/wasm/vision_wasm_module_internal.wasm", "application/wasm"],
        "/vendor/vision/wasm/vision_wasm_nosimd_internal.js": ["vendor/vision/wasm/vision_wasm_nosimd_internal.js", "text/javascript"],
        "/vendor/vision/wasm/vision_wasm_nosimd_internal.wasm": ["vendor/vision/wasm/vision_wasm_nosimd_internal.wasm", "application/wasm"],
        "/studio.css": ["studio.css", "text/css"],
        "/compact.css": ["compact.css", "text/css"],
        "/desktop.css": ["desktop.css", "text/css"],
        "/live.css": ["live.css", "text/css"],
        "/calls.css": ["calls.css", "text/css"],
        "/messenger.css": ["messenger.css", "text/css"],
        "/live-ui.js": ["live-ui.js", "text/javascript"],
        "/social.css": ["social.css", "text/css"],
        "/kinnect-icon.png": ["kinnect-icon.png", "image/png"],
        "/": ["index.html", "text/html"],
        "/ios": ["index.html", "text/html"],
        "/install-ios": ["install-ios.html", "text/html"],
        "/install-ios-manifest": ["install-ios-manifest.html", "text/html"],
        "/ios.webmanifest": ["ios.webmanifest", "application/manifest+json"],
        "/Kinnect.mobileconfig": ["Kinnect.mobileconfig", "application/x-apple-aspen-config"],
        "/kinnect-ios-install-qr.png": ["kinnect-ios-install-qr.png", "image/png"],
        "/kinnect-maskable-512.png": ["kinnect-maskable-512.png", "image/png"],
        "/install-ios.css": ["install-ios.css", "text/css"],
        "/install-ios.js": ["install-ios.js", "text/javascript"],
        "/app.js": ["app.js", "text/javascript"],
        "/style.css": ["style.css", "text/css"],
        "/tokens.css": ["tokens.css", "text/css"],
        "/polish.css": ["polish.css", "text/css"],
        "/v2": ["v2.html", "text/html"],
        "/v2.css": ["v2.css", "text/css"],
        "/v2.js": ["v2.js", "text/javascript"],
        "/v2-icons.js": ["v2-icons.js", "text/javascript"],
        "/v2-auth-wall.js": ["v2-auth-wall.js", "text/javascript"],
        "/v2-commerce.js": ["v2-commerce.js", "text/javascript"],
        "/v2-admin.js": ["v2-admin.js", "text/javascript"],
        "/v2-plus.js": ["v2-plus.js", "text/javascript"],
        "/fonts/be-vietnam-pro-regular.ttf": ["fonts/be-vietnam-pro-regular.ttf", "font/ttf"],
        "/fonts/be-vietnam-pro-semibold.ttf": ["fonts/be-vietnam-pro-semibold.ttf", "font/ttf"],
      };
      if (!files[path]) {
        const msg = "Not Found";
        res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store", "Content-Length": Buffer.byteLength(msg) });
        return res.end(req.method === "HEAD" ? undefined : msg);
      }
      if (req.method !== "GET" && req.method !== "HEAD") {
        res.writeHead(405, { Allow: "GET, HEAD", "Cache-Control": "no-store" });
        return res.end();
      }
      try {
        const [file, type] = files[path];
        let body = await readFile(new URL("./public/" + file, import.meta.url));
        if ((type === "text/html" || type === "text/javascript") && path !== "/sw.js") {
          // Gắn mã phiên bản theo nội dung vào mọi đường dẫn JS/CSS nội bộ, để trình duyệt và
          // Cloudflare luôn lấy bản mới ngay sau khi cập nhật. Riêng sw.js phải GIỮ NGUYÊN
          // nội dung (không gắn ?v=): danh sách STATIC bên trong so khớp theo url.pathname,
          // nếu bị tiêm query thì cache-hit sẽ trượt và offline-fallback hỏng.
          const version = await buildVersion();
          body = Buffer.from(
            body
              .toString("utf8")
              .replace(/(["'])(\.?\/)([\w.-]+\.(?:js|css))(?:\?v=[\w.-]*)?(["'])/g, (m, q1, pre, name, q2) =>
                name === "sw.js" || !files["/" + name] ? m : q1 + pre + name + "?v=" + version + q2,
              ),
          );
        }
        const textual = /^(text\/|application\/(?:json|manifest\+json)|image\/svg\+xml)/.test(type);
        const requestedVersion = new URL(req.url, "http://localhost").searchParams.get("v");
        const immutable = /\.(?:js|css)$/.test(path) && path !== "/sw.js" && requestedVersion && requestedVersion === (await buildVersion());
        const accepts = String(req.headers["accept-encoding"] || "");
        const encoding = textual && body.length > 1024 ? (/\bbr\b/.test(accepts) ? "br" : /\bgzip\b/.test(accepts) ? "gzip" : "") : "";
        if (encoding) {
          const key = path + "|" + encoding + "|" + createHash("sha1").update(body).digest("hex");
          let packed = compressedStatic.get(key);
          if (!packed) {
            packed = encoding === "br" ? brotliCompressSync(body, { params: { [zlibConstants.BROTLI_PARAM_QUALITY]: 9 } }) : gzipSync(body, { level: 9 });
            if (compressedStatic.size > 200) compressedStatic.clear();
            compressedStatic.set(key, packed);
          }
          body = packed;
        }
        const isDelPage = path === "/delete-account" || path === "/delete-account/";
        res.writeHead(200, {
          "Content-Length": body.length,
          ...(encoding ? { "Content-Encoding": encoding } : {}),
          ...(textual ? { Vary: "Accept-Encoding" } : {}),
          "Content-Type": textual ? type + "; charset=utf-8" : type,
          "Cache-Control": (path === "/Kinnect.mobileconfig" || isDelPage) ? "no-store" : immutable ? "public, max-age=31536000, immutable" : "no-cache",
          ...(path === "/Kinnect.mobileconfig" ? { "Content-Disposition": 'attachment; filename="Kinnect.mobileconfig"' } : {}),
          "X-Content-Type-Options": "nosniff",
          "Referrer-Policy": "no-referrer",
          "Content-Security-Policy": isDelPage
            ? "default-src 'self'; frame-ancestors 'none'; object-src 'none'; base-uri 'self'; form-action 'self'"
            : "default-src 'self'; connect-src 'self' ws: wss:; img-src 'self' data: blob: https://raw.githubusercontent.com/vuanh97nd/Kinnect/ https://*.vnecdn.net https://*.tuoitre.vn; media-src 'self' blob: data:; style-src 'self' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; script-src 'self' 'wasm-unsafe-eval'",
          ...(isDelPage ? { "X-Frame-Options": "DENY" } : {}),
        });
        res.end(req.method === "HEAD" ? undefined : body);
      } catch (err) {
        const code = err?.code === "ENOENT" ? 404 : 500;
        const msg = code === 404 ? "Not Found" : "Internal Server Error";
        res.writeHead(code, { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store", "Content-Length": Buffer.byteLength(msg) });
        res.end(req.method === "HEAD" ? undefined : msg);
      }
    } catch (err) {
      if (!res.headersSent) {
        res.writeHead(500, { "Content-Type": "application/json; charset=utf-8" });
        res.end(JSON.stringify({ error: "Lỗi máy chủ." }));
      } else {
        res.destroy();
      }
    }
  });
  server.keepAliveTimeout = 65000;
  server.headersTimeout = 66000;
  wss = new WebSocketServer({ server, maxPayload: 32768 });
  const wsHeartbeat = setInterval(() => {
    for (const ws of wss.clients) {
      if (ws.isAlive === false) {
        try { ws.terminate(); } catch { }
        continue;
      }
      ws.isAlive = false;
      try { ws.ping(); } catch { }
    }
  }, 25000);
  wsHeartbeat.unref();
  wss.once("close", () => clearInterval(wsHeartbeat));
  const send = (ws, data) => {
    if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(data));
  };
  notifyAIStream = ({ userId, ...event }) => {
    for (const client of wss.clients) if (client.userId === userId && social.authenticate(client.authRequest)) send(client, { type: 'ai-stream', ...event });
  };
  const browserPush = createWebPush({ social, fetchImpl: fetchImpl || fetch });
  const applePush = createApplePush({ social });
  const firebasePush = createFirebasePush({ social, fetchImpl: fetchImpl || fetch });
  const webPush = {
    ...browserPush,
    has: id => browserPush.has(id) || applePush.hasVoip(id) || firebasePush.has(id),
    call: (id, session, from) => { browserPush.call(id, session, from); applePush.call(id, session, from); firebasePush.call(id, session, from); },
    callEnded: (id, session, reason, from) => { browserPush.callEnded(id, session, reason, from); applePush.callEnded(id, session, reason); firebasePush.callEnded(id, session, reason, from); },
    notification: (id, notification) => { browserPush.notification(id, notification); applePush.notification(id, notification); firebasePush.notification(id, notification); },
    notifyTest: async id => { await browserPush.notifyTest(id); await firebasePush.notifyTest(id); }
  };
  pushNotification = (userId, id) => { if (!visible(userId)) webPush.notification(userId, id); };
  // A user "sees" Kinnect when one of their browser tabs reports it is visible.
  const visible = (userId) => [...wss.clients].some((c) => c.userId === userId && c.visible && social.authenticate(c.authRequest));
  let groupCalls;
  const calls = createCalls({ social, wss, send, webPush, visible, isBusy: (userId) => !!groupCalls?.isBusy(userId) });
  groupCalls = createGroupCalls({ social, wss, send, isBusy: (userId) => calls.isBusy(userId) });
  notifyNotifications = (userId) => {
    for (const client of wss.clients)
      if (client.userId === userId && social.authenticate(client.authRequest)) send(client, { type: "notifications-changed" });
  };
  notifyCallMessage = (userIds) => {
    const recipients = new Set(userIds);
    for (const client of wss.clients)
      if (recipients.has(client.userId) && social.authenticate(client.authRequest)) send(client, { type: "conversations-changed" });
  };
  const broadcast = (room, data) =>
    room.members.forEach((ws) => {
      if (
        !ws.authRequest ||
        !social.authenticate(ws.authRequest) ||
        (data.senderId && social.blocked(ws.userId, data.senderId))
      )
        return;
      send(ws, data);
    });
  const sendRooms = (ws) => {
    const u = ws.authRequest && social.authenticate(ws.authRequest);
    if (!u) return;
    const payload = {
      type: "rooms",
      rooms: [...rooms.values()]
        .filter(
          (r) =>
            social.user(r.host.userId)?.suspended === 0 &&
            !social.blocked(ws.userId, r.host.userId),
        )
        .map((r) => ({
          id: r.id,
          title: r.title,
          host: r.host.name,
          hostId: r.host.userId,
          liveMode: r.mode || 'chat', gameTitle: r.gameTitle || '',
          viewers: r.members.size - 1,
        })),
    };
    const serialized = JSON.stringify(payload);
    if (ws._lastRoomsPayload === serialized) return;
    ws._lastRoomsPayload = serialized;
    send(ws, payload);
  };
  const publishListing = () => wss.clients.forEach(sendRooms);
  let listingTimer;
  const listing = () => {
    if (listingTimer) return;
    listingTimer = setTimeout(() => { listingTimer = null; publishListing(); }, 100);
    listingTimer.unref?.();
  };
  function enforceAccess() {
    if (!wss) return;
    let changed = false;
    calls.enforce();
    groupCalls.enforce();
    for (const ws of wss.clients) {
      const u = ws.authRequest && social.authenticate(ws.authRequest);
      if (!u) {
        leave(ws);
        ws.close(4401, "Session unavailable");
        changed = true;
        continue;
      }
      const room = rooms.get(ws.room);
      if (
        room &&
        room.host !== ws &&
        social.blocked(ws.userId, room.host.userId)
      ) {
        leave(ws);
        send(ws, { type: "ended" });
        changed = true;
      }
    }
    for (const room of rooms.values()) liveGuests.access(room);
    if (changed || rooms.size > 0) listing();
  }
  function liveAudience(room, viewerId) {
    return [...new Map([...room.members.values()].filter(peer => peer !== room.host && social.user(peer.userId)?.suspended === 0 && !social.blocked(viewerId, peer.userId)).map(peer => { const u = social.user(peer.userId); return [u.id, { id: u.id, name: u.name, avatar: u.avatar ? '/api/users/' + u.id + '/avatar' : null }]; })).values()];
  }
  function livePresence(room, entrant) {
    if (room.mediaTransport === 'sfu') {
      room.pendingEntrant = entrant || room.pendingEntrant; if (room.presenceTimer) return;
      room.presenceTimer = setTimeout(() => {
        room.presenceTimer = null; if (!rooms.has(room.id)) return; const entrant = room.pendingEntrant; room.pendingEntrant = null; const access = liveRoomBlocks(social, room), users = new Map();
        const profiles = new Map(social.db.prepare('SELECT id,name,avatar IS NOT NULL AS hasAvatar,suspended FROM users WHERE id IN (SELECT value FROM json_each(?))').all(JSON.stringify([...access.ids])).map(u => [u.id, u]));
        for (const p of room.members.values()) if (p !== room.host) { const u = profiles.get(p.userId); if (u?.suspended === 0) users.set(u.id, { id: u.id, name: u.name, avatar: u.hasAvatar ? '/api/users/' + u.id + '/avatar' : null }); }
        for (const peer of room.members.values()) { const hidden = access.blocked.get(peer.userId) || new Set(); let count = users.size; for (const id of hidden) if (users.has(id)) count--; const sample = []; for (const u of users.values()) { if (!hidden.has(u.id)) sample.push(u); if (sample.length === 8) break; } send(peer, { type: 'count', room: room.id, viewers: count, users: sample }); if (entrant && entrant !== peer && !hidden.has(entrant.userId)) send(peer, { type: 'viewer-joined', room: room.id, user: users.get(entrant.userId) }); }
      }, 100); room.presenceTimer.unref(); return;
    }
    for (const peer of room.members.values()) {
      const users = liveAudience(room, peer.userId); send(peer, { type: 'count', room: room.id, viewers: users.length, users });
      if (entrant && entrant !== peer && !social.blocked(peer.userId, entrant.userId)) send(peer, { type: 'viewer-joined', room: room.id, user: users.find(u => u.id === entrant.userId) });
    }
  }
  const liveSFU = createLiveSFU({ env: liveEnv ?? ((dbPath === ":memory:" || process.env.NODE_TEST_CONTEXT) ? {} : process.env), send, social, fetchImpl, onUnavailable: id => { const room = rooms.get(id); if (room?.mediaTransport === 'sfu') leave(room.host); } });
  probes.sockets = () => wss.clients.size; probes.rooms = () => rooms.size; probes.sfu = () => liveSFU.status();
  server.once('close', () => { clearInterval(wsHeartbeat); clearTimeout(listingTimer); for (const room of rooms.values()) clearTimeout(room.presenceTimer); liveSFU.close(); });
  server.on('error', (err) => {
    console.error('[HTTP SERVER ERROR]', new Date().toISOString(), err?.stack || err);
  });
  wss.on('error', (err) => {
    console.error('[WSS ERROR]', new Date().toISOString(), err?.stack || err);
  });
  const liveGuests = createLiveGuests({ send, social, sfu: liveSFU });
  const liveModes = createLiveModes({ send, social, listing });
  const liveGifts = createLiveGifts({ send, social, env: (dbPath === ":memory:" || process.env.NODE_TEST_CONTEXT) ? {} : process.env });
  function leave(ws) {
    const room = rooms.get(ws.room);
    ws.room = null; ws.legacyLiveRoom = null; ws.meshStage = null; ws.sfuStage = null;
    if (!room) return;
    room.members.delete(ws.id);
    if (room.host === ws) {
      broadcast(room, { type: "ended" });
      room.members.forEach((peer) => { peer.room = null; peer.legacyLiveRoom = null; peer.meshStage = null; peer.sfuStage = null; });
      clearTimeout(room.presenceTimer); liveSFU.discard(room.id);
      rooms.delete(room.id);
    } else {
      send(room.host, { type: "peer-left", id: ws.id });
      livePresence(room);
      liveGuests.left(room, ws); liveModes.left(room, ws);
    }
    listing();
  }
  const typing = createTyping({ social, wss, send });
  wss.on("connection", (ws, req) => {
    ws.on("error", () => { });
    ws.isAlive = true;
    ws.on("pong", () => { ws.isAlive = true; });
    const wsGate = social.securityMonitor?.evaluateRequestGate(req, "/ws");
    if (wsGate && !wsGate.allowed) return ws.close(4429, "Temporarily blocked");
    // Browser connections must originate from the same host.
    if (req.headers.origin) {
      try {
        if (new URL(req.headers.origin).host !== req.headers.host)
          return ws.close(1008, "Invalid origin");
      } catch {
        return ws.close(1008);
      }
    }
    let account = social.authenticate(req);
    // Chỉ gia hạn nếu phiên đang hợp lệ và chưa hết hạn (ngăn chặn hồi sinh token đã chết)
    if (account) {
      const cookie = req.headers.cookie || "";
      const token = cookie.split(";").map(x => x.trim()).find(x => x.startsWith("kinnect_session="))?.slice(16);
      if (token) {
        try {
          const tokenHash = createHash("sha256").update(token).digest("hex");
          social.db.prepare("UPDATE sessions SET expires=? WHERE token=? AND expires>?").run(Date.now() + 7 * 86400000, tokenHash, Date.now());
        } catch { }
      }
    }
    if (!account) return ws.close(4401, "Login required");
    const wsUserGate = social.securityMonitor?.evaluateRequestGate(req, "/ws", { userId: account.id, username: account.username, userOnly: true });
    if (wsUserGate && !wsUserGate.allowed) return ws.close(wsUserGate.status === 401 ? 4401 : 4429, "Access restricted");
    ws.authRequest = req;
    ws.userId = account.id;
    ws.id = randomUUID();
    ws.room = null;
    ws.name = account.name;
    ws.window = Date.now();
    ws.messages = 0;
    ws.visible = false;
    send(ws, { type: "welcome", id: ws.id, callResume: true, push: true, liveGifts: liveGifts.catalog(ws.userId) });
    calls.join(ws);
    sendRooms(ws);
    ws.on("message", async (raw) => {
      try {
      const account = social.authenticate(req);
      if (!account) {
        leave(ws);
        return ws.close(4401, "Login required");
      }
      ws.name = account.name;
      if (Date.now() - ws.window > 1000) {
        ws.window = Date.now();
        ws.messages = 0;
      }
      let m;
      try {
        m = JSON.parse(raw);
      } catch {
        return send(ws, { type: "error", message: "Dữ liệu không hợp lệ" });
      }
      if (!m || typeof m !== "object") return;
      const signalling = m.type === 'signal' || m.type === 'call-signal' || m.type === 'group-call-signal';
      if (signalling) { if (Date.now() - (ws.signalWindow || 0) > 10000) { ws.signalWindow = Date.now(); ws.signalMessages = 0; } if (++ws.signalMessages > 600) return ws.close(1008, 'Signalling rate limit'); }
      else if (++ws.messages > 30) return ws.close(1008, 'Rate limit');

      const error = (message) => send(ws, { type: "error", message });
      if (typing.handle(ws, m, account)) return;
      if (m.type === "visibility") { ws.visible = m.visible === true; return; }
      if (calls.handle(ws, m)) return;
      if (groupCalls.handle(ws, m)) return;
      if (["create", "chat"].includes(m.type) && !social.hasPrivacyConsent(account.id)) return error("Vui lòng đồng ý thông báo dữ liệu trước khi phát live hoặc bình luận.");
      if (m.type === "create") {
        if (ws.room) return error("Hãy rời phòng hiện tại trước.");
        if (m.liveMode === 'game' && !social.packageStore.gameAllowed(ws.userId)) return error("Live Game cần gói 30 ngày · 490 xu. Mở Cửa hàng để kích hoạt.");
        if (m.multiGuest === true && liveSFU.enabled && !liveSFU.available) return error("Máy chủ truyền Live đang kết nối lại. Hãy thử lại sau.");
        if (rooms.size >= (liveSFU.enabled ? liveSFU.maxRooms : 100)) return error("Máy chủ đã đầy.");
        ws.name = account.name;
        const room = {
          id: randomUUID(),
          title: String(m.title || "")
            .trim()
            .slice(0, 100),
          host: ws,
          members: new Map([[ws.id, ws]]),
          chatHistory: [],
          created: Date.now(),
          comments: m.comments !== false,
        };
        ws.liveV2 = m.multiGuest === true; ws.liveModes = m.liveModes === true; liveGuests.init(room); liveModes.init(room, m);
        rooms.set(room.id, room);
        ws.room = room.id;
        send(ws, {
          type: "joined", multiGuest: true,
          role: "host",
          history: [],
          aiModeration: !!social.ai.status().moderation,
          room: { id: room.id, title: room.title, liveDecoration: social.packageStore.liveTheme(room.host.userId), hostMembership: social.packageStore.membership(room.host.userId), liveMode: room.mode, gameTitle: room.gameTitle, comments: room.comments !== false, host: room.host.name, hostId: room.host.userId, avatar: social.user(room.host.userId)?.avatar ? "/api/users/" + room.host.userId + "/avatar" : null, viewers: liveAudience(room, ws.userId).length },
        });
        liveGuests.state(room); liveModes.state(room, ws);
        listing();
        return;
      }
      if (m.type === "join") {
        const room = rooms.get(m.room);
        if (
          room &&
          (social.user(room.host.userId)?.suspended !== 0 ||
            social.blocked(ws.userId, room.host.userId))
        )
          return error("Không thể tham gia phòng này.");
        if (!room) return error("Phòng đã kết thúc.");
        if (ws.room) return error("Hãy rời phòng hiện tại trước.");
        if (room.mediaTransport === 'sfu' && m.multiGuest !== true) return error("Hãy cập nhật ứng dụng để xem phòng Live này.");
        const viewerLimit = room.mediaTransport === 'sfu' ? liveSFU.maxViewers : 6;
        if (room.members.size >= viewerLimit + 1) return error("Phòng Live đã đủ " + viewerLimit + " người xem.");
        ws.name = account.name;
        ws.room = room.id;
        const firstVisit = ![...room.members.values()].some(peer => peer.userId === ws.userId);
        ws.liveV2 = m.multiGuest === true; ws.liveModes = m.liveModes === true;
        room.members.set(ws.id, ws);
        send(ws, {
          type: "joined", multiGuest: true,
          role: "viewer",
          room: { id: room.id, title: room.title, liveDecoration: social.packageStore.liveTheme(room.host.userId), hostMembership: social.packageStore.membership(room.host.userId), liveMode: room.mode, gameTitle: room.gameTitle, comments: room.comments !== false, host: room.host.name, hostId: room.host.userId, avatar: social.user(room.host.userId)?.avatar ? "/api/users/" + room.host.userId + "/avatar" : null, viewers: liveAudience(room, ws.userId).length },
          host: room.host.id,
          hostUserId: room.host.userId,
          history: (room.chatHistory || []).filter(message => !social.blocked(ws.userId, message.senderId) && social.user(message.senderId)?.suspended === 0),
        });
        if (!room.host.liveV2) send(room.host, { type: "peer", id: ws.id });
        liveGuests.state(room); liveGuests.announceViewer(room, ws); liveModes.state(room, ws);
        livePresence(room, firstVisit ? ws : null);
        listing();
        return;
      }
      if (m.type === "leave") {
        leave(ws);
        return;
      }
      const room = rooms.get(ws.room);
      if (!room) return error("Bạn chưa tham gia phòng.");
      if (liveModes.handle(room, ws, m)) return;
      if (liveGuests.handle(room, ws, m)) { if (['live-guest-answer', 'live-guest-leave', 'live-guest-remove'].includes(m.type)) liveModes.reconcile(room); return; }
      if (m.type === 'live-frame') {
        if (ws !== room.host || !social.ai.status().moderation || Date.now() - (ws.aiFrameAt || 0) < 15000) return;
        ws.aiFrameAt = Date.now(); const image = m.image; if (!image || image.mime !== 'image/jpeg' || typeof image.data !== 'string' || image.data.length > 200000 || !/^[A-Za-z0-9+/]+={0,2}$/.test(image.data)) return;
        social.ai.enqueue('live', room.id, ws.userId, { text: 'Kiểm tra khung hình livestream lấy mẫu. Phòng ' + room.id, image }); return;
      }
      if (m.type === 'viewers') { const users = [...new Map([...room.members.values()].filter(peer => peer !== room.host && social.user(peer.userId)?.suspended === 0 && !social.blocked(ws.userId, peer.userId)).map(peer => [peer.userId, social.publicUser(social.user(peer.userId), ws.userId)])).values()]; send(ws, { type: 'viewers', room: room.id, users }); return; }
      if (sharedCoreBridge && ['gift', 'live-reaction'].includes(m.type) && m.kind !== 'heart') { try { await sharedCoreBridge.syncCredits(ws.userId); } catch { return error('Chưa đồng bộ được số dư cloud. Vui lòng thử lại.'); } }
      if (rooms.get(ws.room) !== room) return;
      if (liveGifts.handle(room, ws, m, account)) return;
      if (m.type === "gift") {
        if (!liveGifts.enabled()) return error("Quà trải nghiệm đang tạm dừng.");
        try {
          const gift = social.gift(
            ws.userId,
            room.host.userId,
            room.id,
            m.kind,
          );
          broadcast(room, {
            type: "gift",
            name: ws.name,
            senderId: ws.userId,
            ...gift,
          });
        } catch (e) {
          error(e.message);
        }
        return;
      }
      if (m.type === "chat") {
        if (room.comments === false && ws !== room.host) return error("Bình luận đã tắt.");
        const text =
          typeof m.text === "string" ? m.text.trim().slice(0, 500) : "";
        if (text) {
          const message = { type: "chat", id: randomUUID(), roomId: room.id, name: ws.name, senderId: ws.userId, text, created: Date.now() };
          room.chatHistory ||= [];
          room.chatHistory.push(message);
          if (room.chatHistory.length > 200) room.chatHistory.splice(0, room.chatHistory.length - 200);
          broadcast(room, message);
          social.ai.enqueue('live', room.id, ws.userId, { text: 'Bình luận livestream: ' + text });
        }
      }
      if (m.type === "signal") {
        if (room.mediaTransport === 'sfu') { liveSFU.signal(room, ws, m); return; }
        if (m.description && !liveGuests.isPublisher(room, ws) && (m.description.type === 'offer' || /^a=send(?:recv|only)\r?$/m.test(m.description.sdp || ''))) return;
        if (ws.liveV2 && room.host.liveV2 && m.revision !== room.stageRevision) return;
        const target = room.members.get(m.to);
        if (
          !target ||
          !target.authRequest ||
          !social.authenticate(target.authRequest) ||
          target === ws ||
          !liveGuests.canSignal(room, ws, target)
        )
          return;
        if (
          m.description &&
          ["offer", "answer"].includes(m.description.type) &&
          typeof m.description.sdp === "string"
        )
          send(target, {
            type: "signal",
            from: ws.id,
            revision: room.host.liveV2 ? room.stageRevision : 0,
            description: m.description,
          });
        else if (m.candidate && typeof m.candidate === "object")
          send(target, { type: "signal", from: ws.id, revision: room.host.liveV2 ? room.stageRevision : 0, candidate: m.candidate });
      }
      } catch (err) {
        console.error("[WS MESSAGE ERROR]", err?.message || err);
        send(ws, { type: "error", message: "Không xử lý được yêu cầu." });
      }
    });
    ws.on("close", () => { typing.disconnect(ws); calls.disconnect(ws); groupCalls.disconnect(ws); leave(ws); });
  });
  server.once('close', () => { adminConsole.close?.(); adminCloud?.close(); void supabaseSecondarySync?.stop?.(); });
  return { server, wss, rooms, social };
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.on('uncaughtException', (err) => {
    console.error('[UNCAUGHT EXCEPTION]', new Date().toISOString(), err?.stack || err);
  });
  process.on('unhandledRejection', (reason) => {
    console.error('[UNHANDLED REJECTION]', new Date().toISOString(), reason?.stack || reason);
  });
  const dbPath = resolve(process.env.DATA_DIR || "data", "kinnect.sqlite");
  mkdirSync(dirname(dbPath), { recursive: true });
  const { server, wss, social } = createApp({ dbPath, allowEmailDelivery: true });
  const port = Number(process.env.PORT || 3000);
  const host = process.env.HOST || "127.0.0.1";
  let shuttingDown = false;
  const shutdownGracefully = (signal) => {
    if (shuttingDown) return;
    shuttingDown = true;
    console.log(`[SHUTDOWN] Received ${signal}, draining connections...`);
    const forceTimer = setTimeout(() => {
      try { server.closeAllConnections?.(); } catch {}
      try { social.db?.exec("PRAGMA wal_checkpoint(PASSIVE);"); } catch {}
      try { social.close(); } catch {}
      process.exit(0);
    }, 4000);
    forceTimer.unref();
    for (const ws of wss.clients) {
      try { ws.close(1001, "Server shutting down"); } catch {}
    }
    server.close(() => {
      try { social.db?.exec("PRAGMA wal_checkpoint(PASSIVE);"); } catch {}
      try { social.close(); } catch {}
      clearTimeout(forceTimer);
      process.exit(0);
    });
    server.closeIdleConnections?.();
  };
  process.on("SIGINT", () => shutdownGracefully("SIGINT"));
  process.on("SIGTERM", () => shutdownGracefully("SIGTERM"));
  server.listen(port, host, () =>
    console.log("Kinnect Live listening on port " + port + " (" + host + ")"),
  );
}
