import http from "node:http";
import { mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { openSocial } from "./lib/social.js";
import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { WebSocketServer, WebSocket } from "ws";
import { fileURLToPath } from "node:url";

export function createApp({ dbPath = ":memory:" } = {}) {
  const social = openSocial(dbPath);
  const rooms = new Map();
  const server = http.createServer(async (req, res) => {
    const path = new URL(req.url, "http://localhost").pathname;
    if (path.startsWith("/api/")) {
      res.once("finish", () => enforceAccess());
      return social.api(req, res, path);
    }
    if (path === "/health") {
      res.writeHead(200, { "Content-Type": "application/json" });
      return res.end(JSON.stringify({ ok: true }));
    }
    const files = {
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
        "X-Content-Type-Options": "nosniff",
        "Referrer-Policy": "no-referrer",
        "Content-Security-Policy":
          "default-src 'self'; connect-src 'self' ws: wss:; media-src 'self' blob:; style-src 'self'; script-src 'self'",
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
