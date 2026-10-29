import { publishedApk } from './lib/apk-releases.js';
import {createTyping} from './lib/typing.js';
import {createCalls} from "./lib/calls.js";
import { createWebPush } from "./lib/webpush.js";
import http from "node:http";
import { mkdirSync, createReadStream } from "node:fs";
import { resolve, dirname } from "node:path";
import { openSocial } from "./lib/social.js";
import { loadMailEnv, mailConfigured, smtpConfigured, sendMail } from "./lib/mailer.js";
import { readFile, readdir, stat, writeFile, unlink } from "node:fs/promises";
import { createHash } from "node:crypto";
import { brotliCompressSync, gzipSync, constants as zlibConstants } from "node:zlib";
import { randomUUID } from "node:crypto";
import { WebSocketServer, WebSocket } from "ws";
import { fileURLToPath } from "node:url";

export function createApp({ dbPath = ":memory:", fetchImpl, authLimit, emailSender, emailReady } = {}) {
  loadMailEnv();
  loadMailEnv("oauth.env");
  loadMailEnv("turn.env");
  loadMailEnv("ai.env");
  let notifyAIStream = () => {};
  let notifyNotifications = () => {};
  let pushNotification = () => {};
  let notifyCallMessage = () => {};
  const social = openSocial(dbPath, {
    onNotification: ({ userId, id }) => { notifyNotifications(userId); if (id) pushNotification(userId, id); },
    onAIStream: event => notifyAIStream(event),
    onCallMessage: ({ userIds }) => notifyCallMessage(userIds),
    fetchImpl,authLimit,
    sendEmail:emailSender||sendMail,mailReady:emailReady||smtpConfigured,
    // Báo về email quản trị khi có người gửi yêu cầu quên mật khẩu.
    onResetRequest: (r) => {
      const when = new Date().toLocaleString("vi-VN", { timeZone: "Asia/Ho_Chi_Minh" });
      console.log(`[quen-mat-khau] ${when} @${r.username} (${r.exists ? "có tài khoản" : "không có tài khoản"})`);
      if (!mailConfigured()) return;
      sendMail({
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
  const server = http.createServer(async (req, res) => {
    const path = new URL(req.url, "http://localhost").pathname;
    // Danh sách buổi live đang phát (cho tab "Trực tiếp" ở trang Video, web và app).
    if (path === "/api/live/rooms" && req.method === "GET") {
      const me = social.authenticate(req);
      res.writeHead(me ? 200 : 401, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
      if (!me) return res.end(JSON.stringify({ error: "Vui lòng đăng nhập." }));
      const list = [...rooms.values()]
        .filter((r) => social.user(r.host.userId)?.suspended === 0 && !social.blocked(me.id, r.host.userId))
        .map((r) => {
          const host = social.user(r.host.userId);
          return { id: r.id, title: r.title, host: r.host.name, hostId: r.host.userId, hostUsername: host?.username || "", avatar: host?.avatar ? "/api/users/" + host.id + "/avatar" : null, viewers: r.members.size - 1, started: r.created || Date.now() };
        })
        .sort((a, b) => b.viewers - a.viewers || b.started - a.started);
      return res.end(JSON.stringify({ rooms: list }));
    }
    if (path.startsWith("/api/push/")) {
      const out = (status, data) => { res.writeHead(status, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" }); res.end(JSON.stringify(data)); };
      if (path === "/api/push/key" && req.method === "GET") return out(200, { publicKey: webPush.publicKey });
      const me = social.authenticate(req);
      if (!me) return out(401, { error: "Vui lòng đăng nhập." });
      if (req.method !== "POST") return out(405, { error: "Không hỗ trợ." });
      let b = {};
      try { let raw = ""; for await (const chunk of req) { raw += chunk; if (raw.length > 8192) return out(413, { error: "Quá lớn." }); } b = JSON.parse(raw || "{}"); } catch { return out(400, { error: "Dữ liệu không hợp lệ." }); }
      if (path === "/api/push/subscribe") return webPush.subscribe(me.id, b.subscription) ? out(200, { ok: true }) : out(400, { error: "Đăng ký thông báo không hợp lệ." });
      if (path === "/api/push/unsubscribe") { webPush.unsubscribe(me.id, b.endpoint); return out(200, { ok: true }); }
      if (path === "/api/push/test") { await webPush.notifyTest(me.id); return out(200, { ok: true }); }
      if (path === "/api/push/decline") { calls.declineById(me.id, String(b.callId || "")); return out(200, { ok: true }); }
      return out(404, { error: "Không tìm thấy." });
    }
    if (path.startsWith("/api/") && path !== "/api/music") {
      res.once("finish", () => enforceAccess());
      return social.api(req, res, path);
    }
    // Thư viện nhạc dùng chung cho Studio. Chỉ đặt vào MUSIC_DIR những bản nhạc được phép sử dụng.
    if (path === "/api/music" || path.startsWith("/music/")) {
      if (!social.authenticate(req)) {
        res.writeHead(401, { "Content-Type": "application/json; charset=utf-8" });
        return res.end(JSON.stringify({ error: "Vui lòng đăng nhập." }));
      }
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
        } catch {}
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
        if (me.role !== "admin") return sendJson(403, { error: "Chỉ quản trị viên được quản lý thư viện nhạc." });
        if (req.headers["sec-fetch-site"] === "cross-site" || !(req.headers["content-type"] || "").startsWith("application/json"))
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
          } catch {}
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
        await stat(file);
        const type = /\.mp3$/i.test(name) ? "audio/mpeg" : "audio/mp4";
        const bytes = await readFile(file);
        const headers = { "Content-Type": type, "Accept-Ranges": "bytes", "Cache-Control": "private, max-age=86400", "X-Content-Type-Options": "nosniff" };
        // Safari trên iPhone chỉ phát âm thanh khi máy chủ trả từng đoạn theo yêu cầu (HTTP Range).
        const range = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range || "");
        if (range && (range[1] || range[2])) {
          let start = range[1] ? Number(range[1]) : Math.max(0, bytes.length - Number(range[2]));
          let end = range[1] && range[2] ? Math.min(Number(range[2]), bytes.length - 1) : bytes.length - 1;
          if (start > end || start >= bytes.length) {
            res.writeHead(416, { "Content-Range": "bytes */" + bytes.length });
            return res.end();
          }
          res.writeHead(206, { ...headers, "Content-Range": `bytes ${start}-${end}/${bytes.length}`, "Content-Length": end - start + 1 });
          return res.end(req.method === "HEAD" ? undefined : bytes.subarray(start, end + 1));
        }
        res.writeHead(200, { ...headers, "Content-Length": bytes.length });
        return res.end(req.method === "HEAD" ? undefined : bytes);
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
        return createReadStream(file).pipe(res);
      } catch {
        res.writeHead(404);
        return res.end();
      }
    }
    // Nút "Tải app": tự tìm APK của bản phát hành mới nhất trên GitHub và chuyển thẳng tới file để tải.
    if (path === "/download/android") {
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
      res.writeHead(200, { "Content-Type": "application/json" });
      return res.end(JSON.stringify({ ok: true, version: "0.3.1", uiVersion: "2026-10-26-new-ui", liveChatHistory: true, storyViewers: true }));
    }
    const files = {
      "/website/support.html": ["website/support.html", "text/html"],
      "/website/privacy.html": ["website/privacy.html", "text/html"],
      "/website/community.html": ["website/community.html", "text/html"],
      "/kinnect-mark.svg": ["kinnect-mark.svg", "image/svg+xml"],
      "/favicon.ico": ["favicon.ico", "image/x-icon"],
      "/favicon-32.png": ["favicon-32.png", "image/png"],
      "/kinnect-ios-120-v7.png": ["kinnect-ios-120-v7.png", "image/png"],
      "/apple-touch-icon-120x120.png": ["kinnect-ios-120-v7.png", "image/png"],
      "/apple-touch-icon-120x120-precomposed.png": ["kinnect-ios-120-v7.png", "image/png"],
      "/kinnect-ios-152-v7.png": ["kinnect-ios-152-v7.png", "image/png"],
      "/apple-touch-icon-152x152.png": ["kinnect-ios-152-v7.png", "image/png"],
      "/apple-touch-icon-152x152-precomposed.png": ["kinnect-ios-152-v7.png", "image/png"],
      "/kinnect-ios-167-v7.png": ["kinnect-ios-167-v7.png", "image/png"],
      "/apple-touch-icon-167x167.png": ["kinnect-ios-167-v7.png", "image/png"],
      "/apple-touch-icon-167x167-precomposed.png": ["kinnect-ios-167-v7.png", "image/png"],
      "/kinnect-ios-180-v7.png": ["kinnect-ios-180-v7.png", "image/png"],
      "/apple-touch-icon-180x180.png": ["kinnect-ios-180-v7.png", "image/png"],
      "/apple-touch-icon-180x180-precomposed.png": ["kinnect-ios-180-v7.png", "image/png"],
      "/kinnect-icon-192.png": ["kinnect-icon-192.png", "image/png"],
      "/apple-touch-icon.png": ["apple-touch-icon.png", "image/png"],
      "/apple-touch-icon-v5.png": ["apple-touch-icon-v5.png", "image/png"],
      "/apple-touch-icon-v6.png": ["apple-touch-icon-v6.png", "image/png"],
      "/apple-touch-icon-precomposed.png": ["apple-touch-icon.png", "image/png"],
      "/website/apple-touch-icon.png": ["website/apple-touch-icon.png", "image/png"],
      "/website/": ["website/index.html", "text/html"],
      "/website/index.html": ["website/index.html", "text/html"],
      "/website/style.css": ["website/style.css", "text/css"],
      "/website/app.js": ["website/app.js", "text/javascript"],
      "/website/mark.svg": ["website/mark.svg", "image/svg+xml"],
      "/website/portrait.svg": ["website/portrait.svg", "image/svg+xml"],
      "/website/qr-app.svg": ["website/qr-app.svg", "image/svg+xml"],
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
    };
    if (!files[path]) {
      res.writeHead(404);
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
      res.writeHead(200, {
        "Content-Length": body.length,
        ...(encoding ? { "Content-Encoding": encoding } : {}),
        ...(textual ? { Vary: "Accept-Encoding" } : {}),
        "Content-Type": textual ? type + "; charset=utf-8" : type,
        "Cache-Control": path === "/Kinnect.mobileconfig" ? "no-store" : immutable ? "public, max-age=31536000, immutable" : "no-cache",
        ...(path === "/Kinnect.mobileconfig" ? {"Content-Disposition": 'attachment; filename="Kinnect.mobileconfig"'} : {}),
        "X-Content-Type-Options": "nosniff",
        "Referrer-Policy": "no-referrer",
        "Content-Security-Policy":
          "default-src 'self'; connect-src 'self' ws: wss:; img-src 'self' data: blob: https://raw.githubusercontent.com/vuanh97nd/Kinnect/ https://*.vnecdn.net https://*.tuoitre.vn; media-src 'self' blob: data:; style-src 'self' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; script-src 'self' 'wasm-unsafe-eval'",
      });
      res.end(body);
    } catch {
      res.writeHead(500);
      res.end();
    }
  });
  const wss = new WebSocketServer({ server, maxPayload: 32768 });
  const send = (ws, data) => {
    if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(data));
  };
  notifyAIStream = ({userId,...event}) => {
    for(const client of wss.clients)if(client.userId===userId&&social.authenticate(client.authRequest))send(client,{type:'ai-stream',...event});
  };
  const webPush = createWebPush({ social, fetchImpl: fetchImpl || fetch });
  pushNotification = (userId, id) => { if (!visible(userId)) webPush.notification(userId, id); };
  // A user "sees" Kinnect when one of their browser tabs reports it is visible.
  const visible = (userId) => [...wss.clients].some((c) => c.userId === userId && c.visible && social.authenticate(c.authRequest));
  const calls=createCalls({social,wss,send,webPush,visible});
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
  const listing = () =>
    wss.clients.forEach((ws) => {
      const u = ws.authRequest && social.authenticate(ws.authRequest);
      if (!u) return;
      send(ws, {
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
            viewers: r.members.size - 1,
          })),
      });
    });
  function enforceAccess() {
    calls.enforce();
    for (const ws of wss.clients) {
      const u = ws.authRequest && social.authenticate(ws.authRequest);
      if (!u) {
        leave(ws);
        ws.close(4401, "Session unavailable");
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
      }
    }
    listing();
  }
  function leave(ws) {
    const room = rooms.get(ws.room);
    ws.room = null;
    if (!room) return;
    room.members.delete(ws.id);
    if (room.host === ws) {
      broadcast(room, { type: "ended" });
      room.members.forEach((peer) => (peer.room = null));
      rooms.delete(room.id);
    } else {
      send(room.host, { type: "peer-left", id: ws.id });
      broadcast(room, { type: "count", viewers: room.members.size - 1 });
    }
    listing();
  }
  const typing=createTyping({social,wss,send});
  wss.on("connection", (ws, req) => {
    ws.on("error", () => {});
    // Browser connections must originate from the same host.
    if (req.headers.origin) {
      try {
        if (new URL(req.headers.origin).host !== req.headers.host)
          return ws.close(1008, "Invalid origin");
      } catch {
        return ws.close(1008);
      }
    }
    const account = social.authenticate(req);
    if (!account) return ws.close(4401, "Login required");
    ws.authRequest = req;
    ws.userId = account.id;
    ws.id = randomUUID();
    ws.room = null;
    ws.name = account.name;
    ws.window = Date.now();
    ws.messages = 0;
    ws.visible = false;
    send(ws, { type: "welcome", id: ws.id, callResume: true, push: true });
    calls.join(ws);
    listing();
    ws.on("message", (raw) => {
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
      const signalling=m.type==='signal'||m.type==='call-signal';
      if(signalling){if(Date.now()-(ws.signalWindow||0)>10000){ws.signalWindow=Date.now();ws.signalMessages=0;}if(++ws.signalMessages>600)return ws.close(1008,'Signalling rate limit');}
      else if(++ws.messages>30)return ws.close(1008,'Rate limit');

      const error = (message) => send(ws, { type: "error", message });
      if(typing.handle(ws,m,account))return;
      if(m.type==="visibility"){ws.visible=m.visible===true;return;}
      if(calls.handle(ws,m))return;
      if (m.type === "create") {
        if (ws.room) return error("Hãy rời phòng hiện tại trước.");
        if (rooms.size >= 100) return error("Máy chủ đã đầy.");
        ws.name = account.name;
        const room = {
          id: randomUUID(),
          title: String(m.title || "Cùng trò chuyện")
            .trim()
            .slice(0, 100),
          host: ws,
          members: new Map([[ws.id, ws]]),
          chatHistory: [],
          created: Date.now(),
        };
        rooms.set(room.id, room);
        ws.room = room.id;
        send(ws, {
          type: "joined",
          role: "host",
          history: [],
          aiModeration:!!social.ai.status().moderation,
          room: { id: room.id, title: room.title },
        });
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
        if (room.members.size >= 7)
          return error("Bản thử nghiệm giới hạn 6 người xem mỗi phòng.");
        ws.name = account.name;
        ws.room = room.id;
        room.members.set(ws.id, ws);
        send(ws, {
          type: "joined",
          role: "viewer",
          room: { id: room.id, title: room.title },
          host: room.host.id,
          hostUserId: room.host.userId,
          history: (room.chatHistory || []).filter(message => !social.blocked(ws.userId, message.senderId) && social.user(message.senderId)?.suspended === 0),
        });
        send(room.host, { type: "peer", id: ws.id });
        broadcast(room, { type: "count", viewers: room.members.size - 1 });
        listing();
        return;
      }
      if (m.type === "leave") {
        leave(ws);
        return;
      }
      const room = rooms.get(ws.room);
      if (!room) return error("Bạn chưa tham gia phòng.");
      if(m.type==='live-frame'){
        if(ws!==room.host||!social.ai.status().moderation||Date.now()-(ws.aiFrameAt||0)<15000)return;
        ws.aiFrameAt=Date.now();const image=m.image;if(!image||image.mime!=='image/jpeg'||typeof image.data!=='string'||image.data.length>200000||!/^[A-Za-z0-9+/]+={0,2}$/.test(image.data))return;
        social.ai.enqueue('live',room.id,ws.userId,{text:'Kiểm tra khung hình livestream lấy mẫu. Phòng '+room.id,image});return;
      }
      if(m.type==='viewers'){const users=[...new Map([...room.members.values()].filter(peer=>peer!==room.host&&social.user(peer.userId)?.suspended===0&&!social.blocked(ws.userId,peer.userId)).map(peer=>[peer.userId,social.publicUser(social.user(peer.userId),ws.userId)])).values()];send(ws,{type:'viewers',room:room.id,users});return;}
      if (m.type === "gift") {
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
        const text =
          typeof m.text === "string" ? m.text.trim().slice(0, 500) : "";
        if (text) {
          const message = {type:"chat",id:randomUUID(),roomId:room.id,name:ws.name,senderId:ws.userId,text,created:Date.now()};
          room.chatHistory ||= [];
          room.chatHistory.push(message);
          if(room.chatHistory.length>200)room.chatHistory.splice(0,room.chatHistory.length-200);
          broadcast(room,message);
          social.ai.enqueue('live',room.id,ws.userId,{text:'Bình luận livestream: '+text});
        }
      }
      if (m.type === "signal") {
        const target = room.members.get(m.to);
        if (
          !target ||
          !target.authRequest ||
          !social.authenticate(target.authRequest) ||
          target === ws ||
          (ws !== room.host && target !== room.host)
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
            description: m.description,
          });
        else if (m.candidate && typeof m.candidate === "object")
          send(target, { type: "signal", from: ws.id, candidate: m.candidate });
      }
    });
    ws.on("close", () => {typing.disconnect(ws);calls.disconnect(ws);leave(ws);});
  });
  return { server, wss, rooms, social };
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const dbPath = resolve(process.env.DATA_DIR || "data", "kinnect.sqlite");
  mkdirSync(dirname(dbPath), { recursive: true });
  const { server } = createApp({ dbPath });
  server.listen(Number(process.env.PORT || 3000), "0.0.0.0", () =>
    console.log("Kinnect Live listening on port " + (process.env.PORT || 3000)),
  );
}
