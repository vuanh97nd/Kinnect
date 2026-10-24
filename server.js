import http from "node:http";
import { mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { openSocial } from "./lib/social.js";
import { loadMailEnv, mailConfigured, sendMail } from "./lib/mailer.js";
import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { WebSocketServer, WebSocket } from "ws";
import { fileURLToPath } from "node:url";

export function createApp({ dbPath = ":memory:", fetchImpl } = {}) {
  loadMailEnv();
  loadMailEnv("oauth.env");
  let notifyNotifications = () => {};
  const social = openSocial(dbPath, {
    onNotification: ({ userId }) => notifyNotifications(userId),
    fetchImpl,
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
  const server = http.createServer(async (req, res) => {
    const path = new URL(req.url, "http://localhost").pathname;
    if (path.startsWith("/api/")) {
      res.once("finish", () => enforceAccess());
      return social.api(req, res, path);
    }
    if (path === "/website" || path.startsWith("/website/")) {
      // Website giới thiệu đã chuyển sang kinnect.io.vn.
      const page = path.replace(/^\/website\/?/, "").replace(/\.html$/, "").replace(/^index$/, "");
      res.writeHead(301, { Location: "https://kinnect.io.vn/" + page });
      return res.end();
    }
    if (path === "/health") {
      res.writeHead(200, { "Content-Type": "application/json" });
      return res.end(JSON.stringify({ ok: true, version: "0.3.0" }));
    }
    const files = {
      "/website/support.html": ["website/support.html", "text/html"],
      "/website/privacy.html": ["website/privacy.html", "text/html"],
      "/website/community.html": ["website/community.html", "text/html"],
      "/kinnect-mark.svg": ["kinnect-mark.svg", "image/svg+xml"],
      "/kinnect-icon-192.png": ["kinnect-icon-192.png", "image/png"],
      "/apple-touch-icon.png": ["apple-touch-icon.png", "image/png"],
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
      "/social.css": ["social.css", "text/css"],
      "/kinnect-icon.png": ["kinnect-icon.png", "image/png"],
      "/": ["index.html", "text/html"],
      "/app.js": ["app.js", "text/javascript"],
      "/style.css": ["style.css", "text/css"],
    };
    if (!files[path]) {
      res.writeHead(404);
      return res.end();
    }
    try {
      const [file, type] = files[path];
      res.writeHead(200, {
        "Content-Type": type + "; charset=utf-8",
        "Cache-Control": "no-cache",
        "X-Content-Type-Options": "nosniff",
        "Referrer-Policy": "no-referrer",
        "Content-Security-Policy":
          "default-src 'self'; connect-src 'self' ws: wss:; media-src 'self' blob:; style-src 'self' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; script-src 'self'",
      });
      res.end(await readFile(new URL("./public/" + file, import.meta.url)));
    } catch {
      res.writeHead(500);
      res.end();
    }
  });
  const wss = new WebSocketServer({ server, maxPayload: 32768 });
  const send = (ws, data) => {
    if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(data));
  };
  notifyNotifications = (userId) => {
    for (const client of wss.clients)
      if (client.userId === userId && social.authenticate(client.authRequest)) send(client, { type: "notifications-changed" });
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
    send(ws, { type: "welcome", id: ws.id });
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
      if (++ws.messages > 30) return ws.close(1008, "Rate limit");
      let m;
      try {
        m = JSON.parse(raw);
      } catch {
        return send(ws, { type: "error", message: "Dữ liệu không hợp lệ" });
      }
      if (!m || typeof m !== "object") return;
      const error = (message) => send(ws, { type: "error", message });
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
        };
        rooms.set(room.id, room);
        ws.room = room.id;
        send(ws, {
          type: "joined",
          role: "host",
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
        if (text)
          broadcast(room, {
            type: "chat",
            name: ws.name,
            senderId: ws.userId,
            text,
          });
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
    ws.on("close", () => leave(ws));
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
