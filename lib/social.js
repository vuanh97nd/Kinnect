import { DatabaseSync } from "node:sqlite";
import {
  randomBytes,
  randomUUID,
  scrypt as scryptCallback,
  timingSafeEqual,
  createHash,
} from "node:crypto";
import { promisify } from "node:util";
const scrypt = promisify(scryptCallback);
export class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}
const fail = (status, message) => {
  throw new ApiError(status, message);
};
const text = (value, max) =>
  typeof value === "string" ? value.trim().slice(0, max) : "";
const digest = (value) => createHash("sha256").update(value).digest("hex");
export function openSocial(dbPath) {
  const db = new DatabaseSync(dbPath);
  db.exec(`PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL;
 CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY,username TEXT UNIQUE NOT NULL,password TEXT NOT NULL,salt TEXT NOT NULL,name TEXT NOT NULL,bio TEXT NOT NULL DEFAULT '',interests TEXT NOT NULL DEFAULT '[]',birth_date TEXT NOT NULL,discoverable INTEGER NOT NULL DEFAULT 1,dm_mode TEXT NOT NULL DEFAULT 'mutual',avatar BLOB,avatar_type TEXT,suspended INTEGER NOT NULL DEFAULT 0,created INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),expires INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS follows(actor TEXT REFERENCES users(id),target TEXT REFERENCES users(id),PRIMARY KEY(actor,target));
 CREATE TABLE IF NOT EXISTS blocks(actor TEXT REFERENCES users(id),target TEXT REFERENCES users(id),PRIMARY KEY(actor,target));
 CREATE TABLE IF NOT EXISTS posts(id TEXT PRIMARY KEY,user_id TEXT REFERENCES users(id),body TEXT NOT NULL,visibility TEXT NOT NULL,hidden INTEGER NOT NULL DEFAULT 0,created INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY,sender TEXT REFERENCES users(id),recipient TEXT REFERENCES users(id),body TEXT NOT NULL,created INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS notifications(id TEXT PRIMARY KEY,user_id TEXT REFERENCES users(id),actor TEXT REFERENCES users(id),kind TEXT NOT NULL,ref TEXT,seen INTEGER NOT NULL DEFAULT 0,created INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS reports(id TEXT PRIMARY KEY,reporter TEXT REFERENCES users(id),target_type TEXT NOT NULL,target_id TEXT NOT NULL,reason TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'open',created INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS moderation(id TEXT PRIMARY KEY,action TEXT NOT NULL,target TEXT NOT NULL,created INTEGER NOT NULL);
 PRAGMA user_version=1;`);
  const run = (sql, ...args) => db.prepare(sql).run(...args);
  const get = (sql, ...args) => db.prepare(sql).get(...args);
  const all = (sql, ...args) => db.prepare(sql).all(...args);
  const user = (id) => get("SELECT * FROM users WHERE id=?", id);
  const blocked = (a, b) =>
    !!get(
      "SELECT 1 FROM blocks WHERE (actor=? AND target=?) OR (actor=? AND target=?)",
      a,
      b,
      b,
      a,
    );
  const follows = (a, b) =>
    !!get("SELECT 1 FROM follows WHERE actor=? AND target=?", a, b);
  const publicUser = (u, viewer) => ({
    id: u.id,
    username: u.username,
    name: u.name,
    bio: u.bio,
    interests: JSON.parse(u.interests),
    avatar: u.avatar ? "/api/users/" + u.id + "/avatar" : null,
    following: viewer ? follows(viewer, u.id) : false,
    mutual: viewer ? follows(viewer, u.id) && follows(u.id, viewer) : false,
  });
  const notice = (to, actor, kind, ref) => {
    if (to !== actor)
      run(
        "INSERT INTO notifications VALUES(?,?,?,?,?,0,?)",
        randomUUID(),
        to,
        actor,
        kind,
        ref,
        Date.now(),
      );
  };
  function authenticate(req) {
    const cookie = req.headers.cookie || "";
    const token = cookie
      .split(";")
      .map((x) => x.trim())
      .find((x) => x.startsWith("kinnect_session="))
      ?.slice(16);
    if (!token) return null;
    const row = get(
      "SELECT u.* FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token=? AND s.expires>? AND u.suspended=0",
      digest(token),
      Date.now(),
    );
    return row || null;
  }
  function requireUser(req) {
    return authenticate(req) || fail(401, "Vui lòng đăng nhập.");
  }
  function targetUser(id, me) {
    const u = user(id);
    if (!u || u.suspended || blocked(me.id, id))
      fail(404, "Không tìm thấy người dùng.");
    return u;
  }
  const own = (u) => ({
    ...publicUser(u, u.id),
    discoverable: !!u.discoverable,
    dmMode: u.dm_mode,
  });
  const limits = new Map();
  const writes = new Map();
  function limit(req) {
    const key = req.socket.remoteAddress;
    const now = Date.now();
    let b = limits.get(key);
    if (!b || now - b.time > 60000) {
      b = { time: now, count: 0 };
      limits.set(key, b);
    }
    if (++b.count > 20) fail(429, "Thử lại sau một phút.");
    if (limits.size > 10000)
      for (const [k, v] of limits) if (now - v.time > 60000) limits.delete(k);
  }
  async function body(req) {
    let size = 0;
    const chunks = [];
    for await (const chunk of req) {
      size += chunk.length;
      if (size > 1500000) fail(413, "Dữ liệu quá lớn.");
      chunks.push(chunk);
    }
    try {
      const value = JSON.parse(Buffer.concat(chunks).toString() || "{}");
      if (!value || typeof value !== "object" || Array.isArray(value))
        throw Error();
      return value;
    } catch {
      fail(400, "JSON không hợp lệ.");
    }
  }
  function csrf(req) {
    if (req.headers.origin) {
      let o;
      try {
        o = new URL(req.headers.origin);
      } catch {
        fail(403, "Origin không hợp lệ.");
      }
      if (o.host !== req.headers.host) fail(403, "Origin không hợp lệ.");
    } else if (req.headers["sec-fetch-site"] === "cross-site")
      fail(403, "Yêu cầu khác nguồn bị từ chối.");
  }
  async function api(req, res, path) {
    const json = (status, data, headers = {}) => {
      res.writeHead(status, {
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
        ...headers,
      });
      res.end(JSON.stringify(data));
    };
    try {
      if (req.method !== "GET") {
        csrf(req);
        if (!(req.headers["content-type"] || "").startsWith("application/json"))
          fail(415, "Cần Content-Type application/json.");
      }
      if (path === "/api/register" || path === "/api/login") {
        if (req.method !== "POST") fail(405, "Chỉ hỗ trợ POST.");
        limit(req);
        const b = await body(req);
        const username = text(b.username, 40).toLowerCase();
        if (
          !/^[a-z0-9_]{3,30}$/.test(username) ||
          typeof b.password !== "string" ||
          b.password.length < 10 ||
          b.password.length > 128
        )
          fail(
            400,
            "Tên đăng nhập 3–30 chữ/số/gạch dưới; mật khẩu 10–128 ký tự.",
          );
        let u;
        if (path === "/api/register") {
          const date = text(b.birthDate, 10);
          const birth = new Date(date + "T00:00:00Z");
          const cutoff = new Date();
          cutoff.setUTCFullYear(cutoff.getUTCFullYear() - 18);
          if (
            !/^\d{4}-\d{2}-\d{2}$/.test(date) ||
            !Number.isFinite(birth.getTime()) ||
            birth.toISOString().slice(0, 10) !== date ||
            birth > cutoff ||
            birth.getUTCFullYear() < 1900 ||
            b.agree18 !== true
          )
            fail(
              400,
              "Kinnect chỉ dành cho người từ 18 tuổi; cần ngày sinh hợp lệ và đồng ý quy tắc.",
            );
          if (get("SELECT id FROM users WHERE username=?", username))
            fail(409, "Tên đăng nhập đã được dùng.");
          const name = text(b.name, 60) || username,
            salt = randomBytes(16).toString("hex"),
            hash = (await scrypt(b.password, salt, 64)).toString("hex"),
            id = randomUUID();
          try {
            run(
              "INSERT INTO users(id,username,password,salt,name,birth_date,created) VALUES(?,?,?,?,?,?,?)",
              id,
              username,
              hash,
              salt,
              name,
              date,
              Date.now(),
            );
          } catch (e) {
            if (e.code?.includes("SQLITE"))
              fail(409, "Tên đăng nhập đã được dùng.");
            throw e;
          }
          u = user(id);
        } else {
          u = get("SELECT * FROM users WHERE username=?", username);
          const hash = await scrypt(
            b.password,
            u?.salt || "kinnect-dummy-salt",
            64,
          );
          if (
            !u ||
            !timingSafeEqual(hash, Buffer.from(u.password, "hex")) ||
            u.suspended
          )
            fail(
              401,
              "Thông tin đăng nhập không đúng hoặc tài khoản không khả dụng.",
            );
        }
        const token = randomBytes(32).toString("hex");
        run("DELETE FROM sessions WHERE expires<?", Date.now());
        run(
          "INSERT INTO sessions VALUES(?,?,?)",
          digest(token),
          u.id,
          Date.now() + 7 * 86400000,
        );
        return json(
          200,
          { user: own(u) },
          {
            "Set-Cookie": `kinnect_session=${token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=604800${process.env.SECURE_COOKIES === "1" ? "; Secure" : ""}`,
          },
        );
      }
      const me = requireUser(req);
      if (req.method !== "GET") {
        const now = Date.now();
        let bucket = writes.get(me.id);
        if (!bucket || now - bucket.time > 60000) {
          bucket = { time: now, count: 0 };
          writes.set(me.id, bucket);
        }
        if (++bucket.count > 120)
          fail(429, "Bạn thao tác quá nhanh. Hãy thử lại sau một phút.");
        if (writes.size > 10000)
          for (const [id, v] of writes)
            if (now - v.time > 60000) writes.delete(id);
      }
      if (path === "/api/logout" && req.method === "POST") {
        const token = (req.headers.cookie || "")
          .split(";")
          .map((x) => x.trim())
          .find((x) => x.startsWith("kinnect_session="))
          ?.slice(16);
        if (token) run("DELETE FROM sessions WHERE token=?", digest(token));
        return json(
          200,
          { ok: true },
          {
            "Set-Cookie":
              "kinnect_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0",
          },
        );
      }
      if (path === "/api/me" && req.method === "GET")
        return json(200, { user: own(me) });
      if (path === "/api/me" && req.method === "PATCH") {
        const b = await body(req);
        const interests = Array.isArray(b.interests)
          ? [
              ...new Set(
                b.interests
                  .map((v) => text(v, 30).toLowerCase())
                  .filter(Boolean),
              ),
            ].slice(0, 10)
          : JSON.parse(me.interests);
        if (
          b.dmMode !== undefined &&
          !["mutual", "everyone"].includes(b.dmMode)
        )
          fail(400, "Cài đặt tin nhắn không hợp lệ.");
        run(
          "UPDATE users SET name=?,bio=?,interests=?,discoverable=?,dm_mode=? WHERE id=?",
          text(b.name, 60) || me.name,
          b.bio === undefined ? me.bio : text(b.bio, 500),
          JSON.stringify(interests),
          typeof b.discoverable === "boolean"
            ? Number(b.discoverable)
            : me.discoverable,
          b.dmMode || me.dm_mode,
          me.id,
        );
        return json(200, { user: own(user(me.id)) });
      }
      if (path === "/api/me/avatar" && req.method === "POST") {
        const b = await body(req);
        if (
          typeof b.data !== "string" ||
          !/^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$/.test(b.data)
        )
          fail(400, "Chọn ảnh PNG, JPEG hoặc WebP.");
        const [prefix, encoded] = b.data.split(",");
        const bytes = Buffer.from(encoded, "base64");
        if (bytes.length > 1024 * 1024 || bytes.length < 16)
          fail(400, "Ảnh phải nhỏ hơn 1 MB.");
        const type = prefix.slice(5, prefix.indexOf(";"));
        const valid =
          type === "image/png"
            ? bytes
                .subarray(0, 8)
                .equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
            : type === "image/jpeg"
              ? bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255
              : bytes.toString("ascii", 0, 4) === "RIFF" &&
                bytes.toString("ascii", 8, 12) === "WEBP";
        if (!valid) fail(400, "Định dạng ảnh không hợp lệ.");
        run(
          "UPDATE users SET avatar=?,avatar_type=? WHERE id=?",
          bytes,
          type,
          me.id,
        );
        return json(200, { user: own(user(me.id)) });
      }
      if (path === "/api/discover" && req.method === "GET") {
        const q = text(
          new URL(req.url, "http://local").searchParams.get("q"),
          60,
        ).toLowerCase();
        const mine = JSON.parse(me.interests);
        const users = all(
          "SELECT * FROM users WHERE id<>? AND discoverable=1 AND suspended=0 ORDER BY created DESC LIMIT 500",
          me.id,
        )
          .filter((u) => !blocked(me.id, u.id))
          .map((u) => ({
            ...publicUser(u, me.id),
            score: JSON.parse(u.interests).filter((v) => mine.includes(v))
              .length,
          }))
          .filter(
            (u) =>
              !q ||
              [u.name, u.username, ...u.interests]
                .join(" ")
                .toLowerCase()
                .includes(q),
          )
          .sort((a, b) => b.score - a.score)
          .slice(0, 50);
        return json(200, { users });
      }
      const route = path.match(
        /^\/api\/users\/([a-zA-Z0-9-]+)(?:\/(follow|block|messages|avatar))?$/,
      );
      if (route) {
        const [, id, action] = route;
        if (id === me.id && action && action !== "avatar")
          fail(400, "Không thể thao tác với chính mình.");
        if (action === "block") {
          if (!user(id)) fail(404, "Không tìm thấy người dùng.");
          if (req.method === "POST") {
            run("INSERT OR IGNORE INTO blocks VALUES(?,?)", me.id, id);
            run(
              "DELETE FROM follows WHERE (actor=? AND target=?) OR (actor=? AND target=?)",
              me.id,
              id,
              id,
              me.id,
            );
            return json(200, { ok: true, blocked: id });
          }
          if (req.method === "DELETE") {
            run("DELETE FROM blocks WHERE actor=? AND target=?", me.id, id);
            return json(200, { ok: true });
          }
        }
        const target = targetUser(id, me);
        if (!action && req.method === "GET")
          return json(200, { user: publicUser(target, me.id) });
        if (action === "avatar" && req.method === "GET") {
          if (!target.avatar) fail(404, "Chưa có ảnh.");
          res.writeHead(200, {
            "Content-Type": target.avatar_type,
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
          });
          res.end(Buffer.from(target.avatar));
          return;
        }
        if (action === "follow") {
          if (req.method === "POST") {
            const result = run(
              "INSERT OR IGNORE INTO follows VALUES(?,?)",
              me.id,
              id,
            );
            if (result.changes) notice(id, me.id, "follow", me.id);
            return json(200, { user: publicUser(target, me.id) });
          }
          if (req.method === "DELETE") {
            run("DELETE FROM follows WHERE actor=? AND target=?", me.id, id);
            return json(200, { user: publicUser(target, me.id) });
          }
        }
        if (action === "messages") {
          if (req.method === "GET")
            return json(200, {
              messages: all(
                "SELECT id,sender,recipient,body,created FROM messages WHERE (sender=? AND recipient=?) OR (sender=? AND recipient=?) ORDER BY created DESC,rowid DESC LIMIT 100",
                me.id,
                id,
                id,
                me.id,
              ).reverse(),
            });
          if (req.method === "POST") {
            if (
              target.dm_mode === "mutual" &&
              !(follows(me.id, id) && follows(id, me.id))
            )
              fail(
                403,
                "Người này chỉ nhận tin nhắn khi hai bên cùng theo dõi nhau.",
              );
            const b = await body(req),
              content = text(b.body, 2000);
            if (!content) fail(400, "Nhập nội dung tin nhắn.");
            const message = {
              id: randomUUID(),
              sender: me.id,
              recipient: id,
              body: content,
              created: Date.now(),
            };
            run(
              "INSERT INTO messages VALUES(?,?,?,?,?)",
              message.id,
              me.id,
              id,
              content,
              message.created,
            );
            notice(id, me.id, "message", message.id);
            return json(201, { message });
          }
        }
      }
      if (path === "/api/blocks" && req.method === "GET")
        return json(200, {
          users: all(
            "SELECT u.* FROM users u JOIN blocks b ON b.target=u.id WHERE b.actor=?",
            me.id,
          ).map((u) => publicUser(u, me.id)),
        });
      if (path === "/api/conversations" && req.method === "GET") {
        const people = all(
          "SELECT * FROM users WHERE id IN (SELECT recipient FROM messages WHERE sender=? UNION SELECT sender FROM messages WHERE recipient=?)",
          me.id,
          me.id,
        )
          .filter((u) => !u.suspended && !blocked(me.id, u.id))
          .map((u) => publicUser(u, me.id));
        return json(200, { users: people });
      }
      if (path === "/api/posts") {
        if (req.method === "POST") {
          const b = await body(req),
            content = text(b.body, 2000);
          if (
            !content ||
            !["public", "followers"].includes(b.visibility || "public")
          )
            fail(400, "Nội dung hoặc quyền xem không hợp lệ.");
          const id = randomUUID();
          run(
            "INSERT INTO posts VALUES(?,?,?,?,0,?)",
            id,
            me.id,
            content,
            b.visibility || "public",
            Date.now(),
          );
          return json(201, { id });
        }
        if (req.method === "GET") {
          const posts = all(
            "SELECT p.* FROM posts p JOIN users u ON u.id=p.user_id WHERE p.hidden=0 AND u.suspended=0 ORDER BY p.created DESC,p.rowid DESC LIMIT 500",
          )
            .filter(
              (p) =>
                !blocked(me.id, p.user_id) &&
                (p.visibility === "public" ||
                  p.user_id === me.id ||
                  follows(me.id, p.user_id)),
            )
            .slice(0, 100)
            .map((p) => ({ ...p, author: publicUser(user(p.user_id), me.id) }));
          return json(200, { posts });
        }
      }
      const post = path.match(/^\/api\/posts\/([a-zA-Z0-9-]+)$/);
      if (post && req.method === "DELETE") {
        const result = run(
          "DELETE FROM posts WHERE id=? AND user_id=?",
          post[1],
          me.id,
        );
        if (!result.changes) fail(404, "Không tìm thấy bài viết của bạn.");
        return json(200, { ok: true });
      }
      if (path === "/api/notifications") {
        if (req.method === "GET")
          return json(200, {
            notifications: all(
              "SELECT * FROM notifications WHERE user_id=? ORDER BY created DESC,rowid DESC LIMIT 100",
              me.id,
            )
              .filter(
                (n) => !blocked(me.id, n.actor) && !user(n.actor)?.suspended,
              )
              .map((n) => ({ ...n, actor: publicUser(user(n.actor), me.id) })),
          });
        if (req.method === "POST") {
          run("UPDATE notifications SET seen=1 WHERE user_id=?", me.id);
          return json(200, { ok: true });
        }
      }
      if (path === "/api/reports" && req.method === "POST") {
        const b = await body(req),
          reason = text(b.reason, 1000);
        if (reason.length < 5) fail(400, "Mô tả lý do ít nhất 5 ký tự.");
        if (b.targetType === "user") {
          if (b.targetId === me.id || !user(b.targetId))
            fail(404, "Không tìm thấy đối tượng.");
        } else if (b.targetType === "post") {
          const p = get(
            "SELECT * FROM posts WHERE id=? AND hidden=0",
            b.targetId,
          );
          if (
            !p ||
            blocked(me.id, p.user_id) ||
            (p.visibility === "followers" &&
              p.user_id !== me.id &&
              !follows(me.id, p.user_id))
          )
            fail(404, "Không tìm thấy bài viết.");
        } else if (b.targetType === "message") {
          if (
            !get(
              "SELECT id FROM messages WHERE id=? AND (sender=? OR recipient=?)",
              b.targetId,
              me.id,
              me.id,
            )
          )
            fail(404, "Không tìm thấy tin nhắn.");
        } else fail(400, "Loại báo cáo không hợp lệ.");
        const id = randomUUID();
        run(
          "INSERT INTO reports(id,reporter,target_type,target_id,reason,created) VALUES(?,?,?,?,?,?)",
          id,
          me.id,
          b.targetType,
          b.targetId,
          reason,
          Date.now(),
        );
        return json(201, { id });
      }
      fail(404, "Không tìm thấy API.");
    } catch (e) {
      if (!res.headersSent)
        json(e.status || 500, { error: e.status ? e.message : "Lỗi máy chủ." });
      else res.end();
      if (!e.status) console.error("API failure:", e.code || e.name);
    }
  }
  return {
    db,
    api,
    authenticate,
    user,
    blocked,
    publicUser,
    close: () => db.close(),
  };
}
