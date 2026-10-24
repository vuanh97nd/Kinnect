import { test } from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdtemp, rm, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { WebSocket } from "ws";
import { createApp } from "../server.js";
async function start(dbPath) {
  const app = createApp({ dbPath });
  app.server.listen(0, "127.0.0.1");
  await once(app.server, "listening");
  const url = `http://127.0.0.1:${app.server.address().port}`;
  return {
    ...app,
    url,
    async stop() {
      for (const ws of app.wss.clients) ws.terminate();
      await new Promise((r) => app.wss.close(r));
      await new Promise((r) => app.server.close(r));
      app.social.close();
    },
  };
}
async function request(
  app,
  path,
  { cookie, method = "GET", body, headers = {} } = {},
) {
  const r = await fetch(app.url + "/api" + path, {
    method,
    headers: {
      ...(body === undefined ? {} : { "Content-Type": "application/json" }),
      ...(cookie ? { Cookie: cookie } : {}),
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return {
    status: r.status,
    body: await r.json(),
    cookie: r.headers.get("set-cookie")?.split(";")[0],
  };
}
async function register(app, username, extra = {}) {
  const r = await request(app, "/register", {
    method: "POST",
    body: {
      username,
      password: "very-strong-test-password",
      name: username,
      birthDate: "1994-05-10",
      agree18: true,
      ...extra,
    },
  });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return { id: r.body.user.id, cookie: r.cookie, user: r.body.user };
}
const as = (app, u, path, method = "GET", body) =>
  request(app, path, { cookie: u.cookie, method, body });

test("18+ confirmation, six-character passwords, session privacy and logout", async (t) => {
  const app = await start();
  t.after(() => app.stop());
  assert.equal((await request(app, "/posts")).status, 401);
  assert.equal(
    (
      await request(app, "/register", {
        method: "POST",
        body: { username: "unchecked", password: "simple" },
      })
    ).status,
    400,
  );
  assert.equal(
    (
      await request(app, "/register", {
        method: "POST",
        body: { username: "shortpw", password: "abcde", agree18: true },
      })
    ).status,
    400,
  );
  const simple = await register(app, "simplepw", {
    password: "abcdef",
    birthDate: undefined,
  });
  assert.equal(
    (
      await request(app, "/login", {
        method: "POST",
        body: { username: "simplepw", password: "abcdef" },
      })
    ).status,
    200,
  );
  assert.equal(
    app.social.db
      .prepare("SELECT birth_date FROM users WHERE id=?")
      .get(simple.id).birth_date,
    "",
  );
  const alice = await register(app, "alice");
  assert.ok(alice.cookie);
  assert.equal(alice.user.password, undefined);
  assert.equal(alice.user.birth_date, undefined);
  assert.equal(
    (
      await request(app, "/login", {
        method: "POST",
        body: { username: "alice", password: "incorrect-password" },
      })
    ).status,
    401,
  );
  const login = await request(app, "/login", {
    method: "POST",
    body: { username: "alice", password: "very-strong-test-password" },
  });
  assert.equal(login.status, 200);
  const row = app.social.db
    .prepare("SELECT password FROM users WHERE id=?")
    .get(alice.id);
  assert.notEqual(row.password, "very-strong-test-password");
  assert.equal(row.password.length, 128);
  assert.equal(
    (
      await request(app, "/me", {
        method: "PATCH",
        cookie: alice.cookie,
        headers: { Origin: "https://evil.example" },
        body: { name: "changed" },
      })
    ).status,
    403,
  );
  assert.equal((await as(app, alice, "/logout", "POST", {})).status, 200);
  assert.equal((await as(app, alice, "/me")).status, 401);
  const ws = new WebSocket(app.url);
  assert.equal((await once(ws, "close"))[0], 4401);
});

test("profile matching, mutual-only DMs, posts privacy, blocking and reports", async (t) => {
  const app = await start();
  t.after(() => app.stop());
  const a = await register(app, "alice"),
    b = await register(app, "bruno"),
    c = await register(app, "carol");
  assert.equal(
    (
      await as(app, a, "/me", "PATCH", {
        bio: "Coffee friend",
        interests: ["music", "coffee", "music"],
      })
    ).status,
    200,
  );
  await as(app, b, "/me", "PATCH", { interests: ["coffee"] });
  await as(app, c, "/me", "PATCH", { discoverable: false });
  const discover = await as(app, a, "/discover");
  assert.equal(discover.body.users.length, 1);
  assert.equal(discover.body.users[0].score, 1);
  assert.equal(discover.body.users[0].id, b.id);
  assert.equal(
    (
      await as(app, a, "/users/" + b.id + "/messages", "POST", {
        body: "hello",
      })
    ).status,
    403,
  );
  await as(app, a, "/users/" + b.id + "/follow", "POST", {});
  await as(app, b, "/users/" + a.id + "/follow", "POST", {});
  const msg = await as(app, a, "/users/" + b.id + "/messages", "POST", {
    body: "hello friend",
  });
  assert.equal(msg.status, 201);
  assert.equal(
    (await as(app, b, "/users/" + a.id + "/messages")).body.messages[0].body,
    "hello friend",
  );
  assert.equal(
    (
      await as(app, c, "/reports", "POST", {
        targetType: "message",
        targetId: msg.body.message.id,
        reason: "not my message",
      })
    ).status,
    404,
  );
  assert.equal(
    (
      await as(app, b, "/reports", "POST", {
        targetType: "message",
        targetId: msg.body.message.id,
        reason: "Please investigate",
      })
    ).status,
    201,
  );
  const p = await as(app, b, "/posts", "POST", {
    body: "Private update",
    visibility: "followers",
  });
  assert.equal(p.status, 201);
  assert.equal((await as(app, a, "/posts")).body.posts.length, 1);
  assert.equal((await as(app, c, "/posts")).body.posts.length, 0);
  assert.equal(
    (await as(app, a, "/posts/" + p.body.id, "DELETE", {})).status,
    404,
  );
  assert.equal(
    (await as(app, b, "/notifications")).body.notifications.length,
    2,
  );
  await as(app, a, "/users/" + b.id + "/block", "POST", {});
  assert.equal((await as(app, a, "/discover")).body.users.length, 0);
  assert.equal((await as(app, a, "/posts")).body.posts.length, 0);
  assert.equal((await as(app, b, "/users/" + a.id + "/messages")).status, 404);
  assert.equal(
    (await as(app, b, "/users/" + a.id + "/follow", "POST", {})).status,
    404,
  );
  assert.equal((await as(app, a, "/blocks")).body.users.length, 1);
  await as(app, a, "/users/" + b.id + "/block", "DELETE", {});
  assert.equal(
    (await as(app, a, "/users/" + b.id + "/messages", "POST", { body: "new" }))
      .status,
    403,
  );
});

test("SQLite survives restart, avatar format checks, moderation suspends sessions", async (t) => {
  const dir = await mkdtemp(join(tmpdir(), "kinnect-"));
  let app = await start(join(dir, "test.sqlite"));
  t.after(async () => {
    await app.stop();
    await rm(dir, { recursive: true, force: true });
  });
  const a = await register(app, "persistent");
  await as(app, a, "/me", "PATCH", { bio: "Stored profile" });
  await as(app, a, "/posts", "POST", { body: "Stored post" });
  assert.equal(
    (
      await as(app, a, "/me/avatar", "POST", {
        data:
          "data:image/png;base64," +
          Buffer.from("not actually an image").toString("base64"),
      })
    ).status,
    400,
  );
  const png = Buffer.from([
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    ...new Array(20).fill(0),
  ]);
  assert.equal(
    (
      await as(app, a, "/me/avatar", "POST", {
        data: "data:image/png;base64," + png.toString("base64"),
      })
    ).status,
    200,
  );
  const avatar = await fetch(app.url + "/api/users/" + a.id + "/avatar", {
    headers: { Cookie: a.cookie },
  });
  assert.equal(avatar.headers.get("content-type"), "image/png");
  const clip = await readFile(new URL("./fixtures/short.mp4", import.meta.url));
  const posted = await as(app, a, "/shorts", "POST", {
    data: "data:video/mp4;base64," + clip.toString("base64"),
    caption: "Stored video",
  });
  assert.equal(posted.status, 201);
  await app.stop();
  app = await start(join(dir, "test.sqlite"));
  assert.equal(
    (await as(app, a, "/shorts")).body.shorts[0].caption,
    "Stored video",
  );
  assert.equal((await as(app, a, "/me")).body.user.bio, "Stored profile");
  assert.equal((await as(app, a, "/posts")).body.posts[0].body, "Stored post");
  app.social.db.prepare("UPDATE users SET suspended=1 WHERE id=?").run(a.id);
  assert.equal((await as(app, a, "/me")).status, 401);
});

test("blocking evicts a live viewer and logout revokes an open live socket", async (t) => {
  const app = await start();
  const sockets = [];
  t.after(async () => {
    sockets.forEach((ws) => ws.terminate());
    await app.stop();
  });
  const host = await register(app, "live_host"),
    viewer = await register(app, "live_viewer");
  async function connect(account) {
    const ws = new WebSocket(app.url, { headers: { Cookie: account.cookie } });
    sockets.push(ws);
    const queue = [];
    ws.on("message", (r) => queue.push(JSON.parse(r)));
    await once(ws, "open");
    return {
      ws,
      send: (m) => ws.send(JSON.stringify(m)),
      async get(type) {
        for (let i = 0; i < 200; i++) {
          const n = queue.findIndex((m) => m.type === type);
          if (n >= 0) return queue.splice(n, 1)[0];
          await new Promise((r) => setTimeout(r, 5));
        }
        throw Error("Missing " + type);
      },
    };
  }
  const h = await connect(host),
    v = await connect(viewer);
  h.send({ type: "create", name: "Spoofed name", title: "Authenticated live" });
  const room = (await h.get("joined")).room;
  v.send({ type: "join", room: room.id });
  await v.get("joined");
  await h.get("peer");
  await as(app, host, "/users/" + viewer.id + "/block", "POST", {});
  await v.get("ended");
  v.send({ type: "join", room: room.id });
  assert.match((await v.get("error")).message, /Không thể/);
  const close = once(h.ws, "close");
  await as(app, host, "/logout", "POST", {});
  assert.equal((await close)[0], 4401);
});

test("administrator RBAC, role migration and moderation protect user data", async (t) => {
  const app = await start();
  t.after(() => app.stop());
  const admin = await register(app, "owner"),
    member = await register(app, "member");
  assert.equal((await as(app, member, "/admin/reports")).status, 403);
  assert.equal(
    (
      await as(app, member, "/admin/moderate", "POST", {
        action: "suspend-user",
        target: admin.id,
      })
    ).status,
    403,
  );
  await as(app, member, "/me", "PATCH", { role: "admin" });
  assert.equal((await as(app, member, "/me")).body.user.role, "user");
  app.social.db
    .prepare("UPDATE users SET role='admin' WHERE id=?")
    .run(admin.id);
  assert.equal((await as(app, admin, "/me")).body.user.role, "admin");
  const post = await as(app, member, "/posts", "POST", {
    body: "Reported content",
  });
  await as(app, admin, "/reports", "POST", {
    targetType: "post",
    targetId: post.body.id,
    reason: "Please review this content",
  });
  const reports = await as(app, admin, "/admin/reports");
  assert.equal(reports.body.reports[0].subject.body, "Reported content");
  assert.equal(
    (
      await as(app, admin, "/admin/moderate", "POST", {
        action: "hide-post",
        target: post.body.id,
      })
    ).status,
    200,
  );
  assert.equal((await as(app, member, "/posts")).body.posts.length, 0);
  const users = (await as(app, admin, "/admin/users")).body.users;
  assert.equal(users.length, 2);
  assert.equal(users[0].password, undefined);
  assert.equal(users[0].birth_date, undefined);
  assert.equal(
    (
      await as(app, admin, "/admin/moderate", "POST", {
        action: "suspend-user",
        target: admin.id,
      })
    ).status,
    400,
  );
  assert.equal(
    (
      await as(app, admin, "/admin/moderate", "POST", {
        action: "suspend-user",
        target: member.id,
      })
    ).status,
    200,
  );
  assert.equal((await as(app, member, "/me")).status, 401);
});

test("nearby discovery requires consent, hides coordinates and expires locations", async (t) => {
  const app = await start();
  t.after(() => app.stop());
  const a = await register(app, "near_a"),
    b = await register(app, "near_b"),
    far = await register(app, "far_c");
  assert.equal((await as(app, a, "/discover?nearby=1")).status, 400);
  assert.equal(
    (
      await as(app, a, "/me/location", "PATCH", {
        enabled: true,
        latitude: 999,
        longitude: 10,
      })
    ).status,
    400,
  );
  assert.equal(
    (
      await as(app, a, "/me/location", "PATCH", {
        enabled: true,
        latitude: 10.7734,
        longitude: 106.6989,
      })
    ).status,
    200,
  );
  await as(app, b, "/me/location", "PATCH", {
    enabled: true,
    latitude: 10.7741,
    longitude: 106.6991,
  });
  await as(app, far, "/me/location", "PATCH", {
    enabled: true,
    latitude: 21.0285,
    longitude: 105.8542,
  });
  const result = await as(app, a, "/discover?nearby=1");
  assert.equal(result.body.users.length, 1);
  assert.equal(result.body.users[0].id, b.id);
  assert.ok(result.body.users[0].distanceBand);
  assert.equal(result.body.users[0].lat, undefined);
  assert.equal(result.body.users[0].latitude, undefined);
  const stored = app.social.db
    .prepare("SELECT lat,lng FROM users WHERE id=?")
    .get(a.id);
  assert.equal(stored.lat, 10.75);
  assert.equal(stored.lng, 106.7);
  await as(app, b, "/me", "PATCH", { discoverable: false });
  assert.equal((await as(app, a, "/discover?nearby=1")).body.users.length, 0);
  await as(app, b, "/me", "PATCH", { discoverable: true });
  await as(app, a, "/users/" + b.id + "/block", "POST", {});
  assert.equal((await as(app, a, "/discover?nearby=1")).body.users.length, 0);
  await as(app, a, "/me/location", "PATCH", { enabled: false });
  assert.equal((await as(app, a, "/me")).body.user.hasLocation, false);
  assert.equal(
    app.social.db.prepare("SELECT lat FROM users WHERE id=?").get(a.id).lat,
    null,
  );
  app.social.db
    .prepare("UPDATE users SET location_at=? WHERE id=?")
    .run(Date.now() - 2 * 86400000, b.id);
  await as(app, b, "/me");
  assert.equal(
    app.social.db.prepare("SELECT lat FROM users WHERE id=?").get(b.id).lat,
    null,
  );
});

test("short videos upload, durable bytes/ranges, likes, comments, reports and moderation", async (t) => {
  const { readFile } = await import("node:fs/promises");
  const { mp4Duration } = await import("../lib/shorts.js");
  const bytes = await readFile(
    new URL("./fixtures/short.mp4", import.meta.url),
  );
  assert.ok(mp4Duration(bytes) > 0);
  const app = await start();
  t.after(() => app.stop());
  const a = await register(app, "video_author"),
    b = await register(app, "video_viewer");
  assert.equal((await request(app, "/shorts")).status, 401);
  assert.equal(
    (
      await as(app, a, "/shorts", "POST", {
        data:
          "data:video/mp4;base64," + Buffer.from("not mp4").toString("base64"),
      })
    ).status,
    400,
  );
  const tooLong = Buffer.from(bytes);
  const type = tooLong.indexOf(Buffer.from("mvhd")),
    header = type + 4;
  tooLong.writeUInt32BE(61 * tooLong.readUInt32BE(header + 12), header + 16);
  assert.throws(() => mp4Duration(tooLong));
  const result = await as(app, a, "/shorts", "POST", {
    data: "data:video/mp4;base64," + bytes.toString("base64"),
    caption: "A real playable fixture",
  });
  assert.equal(result.status, 201, JSON.stringify(result.body));
  const id = result.body.id;
  const catalog = await as(app, b, "/shorts");
  assert.equal(catalog.body.shorts[0].id, id);
  assert.equal(catalog.body.shorts[0].data, undefined);
  const url = app.url + "/api/shorts/" + id + "/video";
  const range = await fetch(url, {
    headers: { Cookie: b.cookie, Range: "bytes=0-31" },
  });
  assert.equal(range.status, 206);
  assert.equal(
    range.headers.get("content-range"),
    "bytes 0-31/" + bytes.length,
  );
  assert.deepEqual(
    Buffer.from(await range.arrayBuffer()),
    bytes.subarray(0, 32),
  );
  assert.equal(
    (
      await fetch(url, { method: "HEAD", headers: { Cookie: b.cookie } })
    ).headers.get("content-length"),
    String(bytes.length),
  );
  assert.equal(
    (
      await fetch(url, {
        headers: { Cookie: b.cookie, Range: "bytes=99999999-" },
      })
    ).status,
    416,
  );
  await as(app, b, "/shorts/" + id + "/like", "POST", {});
  await as(app, b, "/shorts/" + id + "/like", "POST", {});
  assert.equal((await as(app, a, "/shorts")).body.shorts[0].likes, 1);
  const comment = await as(app, b, "/shorts/" + id + "/comments", "POST", {
    body: "A nice moment",
  });
  assert.equal(comment.status, 201);
  assert.equal(
    (await as(app, a, "/shorts/" + id + "/comments")).body.comments[0].body,
    "A nice moment",
  );
  assert.equal(
    (
      await as(app, b, "/reports", "POST", {
        targetType: "short",
        targetId: id,
        reason: "Please review this video",
      })
    ).status,
    201,
  );
  assert.equal(
    (
      await as(app, a, "/reports", "POST", {
        targetType: "comment",
        targetId: comment.body.id,
        reason: "Please review this comment",
      })
    ).status,
    201,
  );
  assert.equal((await as(app, b, "/shorts/" + id, "DELETE", {})).status, 403);
  await as(app, a, "/users/" + b.id + "/block", "POST", {});
  assert.equal((await as(app, b, "/shorts")).body.shorts.length, 0);
  assert.equal(
    (await fetch(url, { headers: { Cookie: b.cookie } })).status,
    404,
  );
  await as(app, a, "/users/" + b.id + "/block", "DELETE", {});
  app.social.db.prepare("UPDATE users SET role='admin' WHERE id=?").run(b.id);
  const reports = (await as(app, b, "/admin/reports")).body.reports;
  assert.ok(reports.find((r) => r.target_type === "short").subject);
  await as(app, b, "/admin/moderate", "POST", {
    action: "hide-short",
    target: id,
  });
  assert.equal((await as(app, a, "/shorts")).body.shorts.length, 0);
  assert.equal(
    (await fetch(url, { headers: { Cookie: a.cookie } })).status,
    404,
  );
  await as(app, b, "/admin/moderate", "POST", {
    action: "show-short",
    target: id,
  });
  assert.equal((await as(app, a, "/shorts/" + id, "DELETE", {})).status, 200);
  assert.equal(
    app.social.db.prepare("SELECT count(*) AS n FROM short_comments").get().n,
    0,
  );
});

test("legacy 0.2 SQLite user data survives additive role/location/video migrations", async (t) => {
  const { DatabaseSync } = await import("node:sqlite");
  const dir = await mkdtemp(join(tmpdir(), "kinnect-legacy-"));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const path = join(dir, "legacy.sqlite");
  const legacy = new DatabaseSync(path);
  legacy.exec(
    "CREATE TABLE users(id TEXT PRIMARY KEY,username TEXT UNIQUE NOT NULL,password TEXT NOT NULL,salt TEXT NOT NULL,name TEXT NOT NULL,bio TEXT NOT NULL DEFAULT '',interests TEXT NOT NULL DEFAULT '[]',birth_date TEXT NOT NULL,discoverable INTEGER NOT NULL DEFAULT 1,dm_mode TEXT NOT NULL DEFAULT 'mutual',avatar BLOB,avatar_type TEXT,suspended INTEGER NOT NULL DEFAULT 0,created INTEGER NOT NULL); PRAGMA user_version=1;",
  );
  legacy
    .prepare(
      "INSERT INTO users(id,username,password,salt,name,birth_date,created) VALUES(?,?,?,?,?,?,?)",
    )
    .run(
      "legacy-id",
      "legacy_user",
      "original-hash",
      "original-salt",
      "Legacy member",
      "1990-01-01",
      1,
    );
  legacy.close();
  const app = await start(path);
  try {
    const user = app.social.db
      .prepare("SELECT * FROM users WHERE id=?")
      .get("legacy-id");
    assert.equal(user.name, "Legacy member");
    assert.equal(user.password, "original-hash");
    assert.equal(user.birth_date, "1990-01-01");
    assert.equal(user.role, "user");
    assert.equal(user.lat, null);
    assert.equal(
      app.social.db.prepare("PRAGMA user_version").get().user_version,
      6,
    );
    assert.ok(
      app.social.db
        .prepare("SELECT name FROM sqlite_master WHERE name='shorts'")
        .get(),
    );
  } finally {
    await app.stop();
  }
});

test("forgot password: request is stored, admin issues a temporary password, old sessions end", async () => {
  const app = await start(":memory:");
  try {
    const member = await register(app, "quenmk");
    const admin = await register(app, "quantri");
    app.social.db.prepare("UPDATE users SET role='admin' WHERE id=?").run(admin.id);
    const ask = (username, contact = "zalo 0900000000") =>
      request(app, "/password-reset", { method: "POST", body: { username, contact } });
    const ok = await ask("quenmk");
    const missing = await ask("khongton_tai");
    // Cùng một câu trả lời, không lộ tài khoản có tồn tại hay không.
    assert.equal(ok.status, 200);
    assert.deepEqual(ok.body, missing.body);
    assert.equal((await ask("quenmk", "abc")).status, 400);
    const forbidden = await request(app, "/admin/password-resets", { cookie: member.cookie });
    assert.equal(forbidden.status, 403);
    const list = await request(app, "/admin/password-resets", { cookie: admin.cookie });
    const req = list.body.requests.find((r) => r.username === "quenmk");
    assert.ok(req && req.status === "open");
    const reset = await request(app, `/admin/password-resets/${req.id}/reset`, {
      cookie: admin.cookie,
      method: "POST",
      body: {},
    });
    assert.equal(reset.status, 200);
    assert.match(reset.body.temporaryPassword, /^[a-z2-9]{10}$/);
    assert.equal((await request(app, "/me", { cookie: member.cookie })).status, 401);
    const login = await request(app, "/login", {
      method: "POST",
      body: { username: "quenmk", password: reset.body.temporaryPassword },
    });
    assert.equal(login.status, 200);
    const after = await request(app, "/admin/password-resets", { cookie: admin.cookie });
    assert.equal(after.body.requests.find((r) => r.id === req.id).status, "done");
  } finally {
    await app.stop();
  }
});

test("change password keeps current session and rejects wrong current password", async () => {
  const app = await start(":memory:");
  try {
    const u = await register(app, "doimk");
    const other = await request(app, "/login", {
      method: "POST",
      body: { username: "doimk", password: "very-strong-test-password" },
    });
    const wrong = await request(app, "/me/password", {
      cookie: u.cookie,
      method: "POST",
      body: { current: "sai-mat-khau", next: "mat-khau-moi-1" },
    });
    assert.equal(wrong.status, 400);
    const ok = await request(app, "/me/password", {
      cookie: u.cookie,
      method: "POST",
      body: { current: "very-strong-test-password", next: "mat-khau-moi-1" },
    });
    assert.equal(ok.status, 200);
    assert.equal((await request(app, "/me", { cookie: u.cookie })).status, 200);
    assert.equal((await request(app, "/me", { cookie: other.cookie })).status, 401);
    const login = await request(app, "/login", {
      method: "POST",
      body: { username: "doimk", password: "mat-khau-moi-1" },
    });
    assert.equal(login.status, 200);
  } finally {
    await app.stop();
  }
});

test("Google login: state check, first-login 18+ confirmation, then direct login", async () => {
  const env = { ...process.env };
  Object.assign(process.env, {
    GOOGLE_CLIENT_ID: "test-client",
    GOOGLE_CLIENT_SECRET: "test-secret",
    PUBLIC_URL: "https://app.example",
  });
  const fakeFetch = async (url, init = {}) => {
    if (String(url).startsWith("https://oauth2.googleapis.com/token")) {
      assert.equal(new URLSearchParams(init.body).get("code"), "good-code");
      return new Response(JSON.stringify({ access_token: "at-1" }), { status: 200 });
    }
    if (String(url).startsWith("https://openidconnect.googleapis.com/v1/userinfo"))
      return new Response(
        JSON.stringify({ sub: "g-123", email: "minh.anh@gmail.com", email_verified: true, name: "Minh Anh" }),
        { status: 200 },
      );
    throw Error("unexpected " + url);
  };
  const app = createApp({ dbPath: ":memory:", fetchImpl: fakeFetch });
  app.server.listen(0, "127.0.0.1");
  await once(app.server, "listening");
  const url = `http://127.0.0.1:${app.server.address().port}`;
  try {
    const providers = await (await fetch(url + "/api/oauth/providers")).json();
    assert.deepEqual(providers.providers, ["google"]);
    const startRes = await fetch(url + "/api/oauth/google/start", { redirect: "manual" });
    assert.equal(startRes.status, 302);
    const loc = new URL(startRes.headers.get("location"));
    assert.equal(loc.origin, "https://accounts.google.com");
    assert.equal(loc.searchParams.get("redirect_uri"), "https://app.example/api/oauth/google/callback");
    const state = loc.searchParams.get("state");
    const stateCookie = startRes.headers.get("set-cookie").split(";")[0];
    // Sai state → bị từ chối
    const bad = await fetch(url + "/api/oauth/google/callback?code=good-code&state=wrong", {
      headers: { Cookie: stateCookie },
    });
    assert.match(await bad.text(), /oauth_error=state/);
    const cb = await fetch(url + `/api/oauth/google/callback?code=good-code&state=${state}`, {
      headers: { Cookie: stateCookie },
    });
    const ticket = (await cb.text()).match(/ticket=([a-f0-9]+)/)[1];
    const pending = await (await fetch(url + "/api/oauth/pending?ticket=" + ticket)).json();
    assert.equal(pending.suggestedUsername, "minhanh");
    const post = (body) =>
      fetch(url + "/api/oauth/complete", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
    assert.equal((await post({ ticket, username: "minhanh", agree18: false })).status, 400);
    const done = await post({ ticket, username: "minhanh", name: "Minh Anh", agree18: true });
    assert.equal(done.status, 200);
    const session = done.headers.get("set-cookie").split(";")[0];
    const me = await (await fetch(url + "/api/me", { headers: { Cookie: session } })).json();
    assert.equal(me.user.username, "minhanh");
    // Lần sau: vào thẳng, có cookie phiên ngay ở callback
    const start2 = await fetch(url + "/api/oauth/google/start", { redirect: "manual" });
    const state2 = new URL(start2.headers.get("location")).searchParams.get("state");
    const cb2 = await fetch(url + `/api/oauth/google/callback?code=good-code&state=${state2}`, {
      headers: { Cookie: start2.headers.get("set-cookie").split(";")[0] },
    });
    assert.match(cb2.headers.get("set-cookie"), /kinnect_session=/);
    assert.doesNotMatch(await cb2.text(), /ticket=/);
  } finally {
    for (const ws of app.wss.clients) ws.terminate();
    await new Promise((r) => app.wss.close(r));
    await new Promise((r) => app.server.close(r));
    app.social.close();
    process.env = env;
  }
});

test("post likes, comments, profile stats and conversation preview", async () => {
  const app = await start(":memory:");
  try {
    const a = await register(app, "thich_a");
    const b = await register(app, "thich_b");
    const created = await request(app, "/posts", {
      cookie: a.cookie,
      method: "POST",
      body: { body: "Xin chào", visibility: "public" },
    });
    const pid = created.body.id;
    const like = await request(app, `/posts/${pid}/like`, { cookie: b.cookie, method: "POST", body: {} });
    assert.deepEqual(like.body, { likes: 1, liked: true });
    await request(app, `/posts/${pid}/like`, { cookie: b.cookie, method: "POST", body: {} });
    const c = await request(app, `/posts/${pid}/comments`, {
      cookie: b.cookie,
      method: "POST",
      body: { body: "Chào bạn!" },
    });
    assert.equal(c.status, 201);
    const feed = await request(app, "/posts", { cookie: a.cookie });
    const p = feed.body.posts.find((x) => x.id === pid);
    assert.equal(p.likes, 1);
    assert.equal(p.comments, 1);
    assert.equal(p.liked, false);
    const comments = await request(app, `/posts/${pid}/comments`, { cookie: a.cookie });
    assert.equal(comments.body.comments[0].body, "Chào bạn!");
    const notes = await request(app, "/notifications", { cookie: a.cookie });
    assert.deepEqual(notes.body.notifications.map((n) => n.kind).sort(), ["comment", "like"]);
    await request(app, `/users/${a.id}/follow`, { cookie: b.cookie, method: "POST", body: {} });
    const st = await request(app, `/users/${a.id}/stats`, { cookie: b.cookie });
    assert.deepEqual([st.body.followers, st.body.following, st.body.posts], [1, 0, 1]);
    const mine = await request(app, `/posts?user=${b.id}`, { cookie: a.cookie });
    assert.equal(mine.body.posts.length, 0);
    const unlike = await request(app, `/posts/${pid}/like`, { cookie: b.cookie, method: "DELETE", body: {} });
    assert.equal(unlike.body.likes, 0);
    await request(app, `/users/${b.id}/follow`, { cookie: a.cookie, method: "POST", body: {} });
    await request(app, `/users/${a.id}/messages`, { cookie: b.cookie, method: "POST", body: { body: "Hello" } });
    const inbox = await request(app, "/conversations", { cookie: a.cookie });
    assert.equal(inbox.body.users[0].last.body, "Hello");
    assert.equal(inbox.body.users[0].last.mine, false);
  } finally {
    await app.stop();
  }
});

test("community identities remain optional/private, Les is searchable only when shared, presence and newest discovery", async (t) => {
  const app = await start(); t.after(() => app.stop());
  const a = await register(app, "community_a");
  const b = await register(app, "community_b");
  const c = await register(app, "community_c");
  let r = await as(app,b,"/me","PATCH",{age:25,city:"Hà Nội",gender:"Nữ",orientation:"Les",relationshipRole:"Vers Bottom",identityPublic:false,showActivity:false});
  assert.equal(r.body.user.orientation,"Les");
  assert.equal((await as(app,a,"/users/"+b.id)).body.user.orientation,"");
  assert.equal((await as(app,a,"/discover?q=Les")).body.users.length,0);
  await as(app,b,"/me","PATCH",{identityPublic:true});
  assert.equal((await as(app,a,"/discover?q=Les")).body.users[0].orientation,"Les");
  await as(app,b,"/me","PATCH",{bio:"Cà phê"});
  assert.equal((await as(app,b,"/me")).body.user.relationshipRole,"Vers Bottom");
  assert.equal((await as(app,b,"/me","PATCH",{age:17})).status,400);
  const people=(await as(app,a,"/discover")).body.users;
  assert.equal(people[0].id,c.id);
  await as(app,c,"/me/activity","POST",{});
  let active=(await as(app,a,"/discover?sort=active")).body.users;
  assert.ok(active.some(u=>u.id===c.id));assert.ok(!active.some(u=>u.id===b.id));
  await as(app,c,"/logout","POST",{});
  active=(await as(app,a,"/discover?sort=active")).body.users;
  assert.ok(!active.some(u=>u.id===c.id));
});

test("notification delivery is realtime and read receipts affect only the recipient's selected items", async (t) => {
  const app=await start();t.after(()=>app.stop());
  const a=await register(app,"notify_a"), b=await register(app,"notify_b");
  const ws=new WebSocket(app.url,{headers:{Cookie:a.cookie}});await once(ws,"open");
  const changed=new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error("No realtime notification")),3000);ws.on("message",raw=>{if(JSON.parse(raw).type==="notifications-changed"){clearTimeout(timer);resolve();}});});
  await as(app,b,"/users/"+a.id+"/follow","POST",{});await changed;
  const notes=(await as(app,a,"/notifications")).body.notifications;
  assert.equal(notes[0].seen,0);
  await as(app,b,"/notifications","POST",{ids:[notes[0].id]});
  assert.equal((await as(app,a,"/notifications")).body.notifications[0].seen,0);
  await as(app,a,"/notifications","POST",{ids:[notes[0].id]});
  assert.equal((await as(app,a,"/notifications")).body.notifications[0].seen,1);
  await as(app,a,"/users/"+b.id+"/follow","POST",{});
  await as(app,b,"/users/"+a.id+"/messages","POST",{body:"hello"});
  assert.ok((await as(app,a,"/notifications")).body.notifications.some(n=>n.kind==="message"&&!n.seen));
  await as(app,a,"/users/"+b.id+"/messages");
  assert.ok((await as(app,a,"/notifications")).body.notifications.filter(n=>n.kind==="message").every(n=>n.seen));
  ws.terminate();
});

test("music library: members list tracks, only admins upload or delete, rights confirmation required", async () => {
  const { mkdtemp } = await import("node:fs/promises");
  const dir = await mkdtemp(join(tmpdir(), "kinnect-music-"));
  const prev = process.env.MUSIC_DIR;
  process.env.MUSIC_DIR = dir;
  const app = await start(":memory:");
  try {
    const member = await register(app, "nghe_nhac");
    const admin = await register(app, "quan_ly_nhac");
    app.social.db.prepare("UPDATE users SET role='admin' WHERE id=?").run(admin.id);
    const mp3 = "data:audio/mpeg;base64," + Buffer.concat([Buffer.from("ID3"), Buffer.alloc(64)]).toString("base64");
    const call = (cookie, method, body) =>
      fetch(app.url + "/api/music", {
        method,
        headers: { Cookie: cookie, ...(body ? { "Content-Type": "application/json" } : {}) },
        body: body ? JSON.stringify(body) : undefined,
      });
    assert.equal((await fetch(app.url + "/api/music")).status, 401);
    const track = { data: mp3, title: "Bai thu", artist: "Ban", license: "CC0", rights: true };
    assert.equal((await call(member.cookie, "POST", track)).status, 403);
    assert.equal((await call(admin.cookie, "POST", { ...track, rights: false })).status, 400);
    const up = await call(admin.cookie, "POST", track);
    assert.equal(up.status, 201);
    const { file } = await up.json();
    const list = await (await call(member.cookie, "GET")).json();
    assert.deepEqual(list.tracks.map((t) => [t.file, t.artist, t.license]), [[file, "Ban", "CC0"]]);
    assert.equal((await fetch(app.url + list.tracks[0].url, { headers: { Cookie: member.cookie } })).status, 200);
    assert.equal((await fetch(app.url + "/music/..%2Fserver.js", { headers: { Cookie: member.cookie } })).status, 404);
    assert.equal((await call(member.cookie, "DELETE", { file })).status, 403);
    assert.equal((await call(admin.cookie, "DELETE", { file })).status, 200);
    assert.equal((await (await call(member.cookie, "GET")).json()).tracks.length, 0);
  } finally {
    await app.stop();
    if (prev === undefined) delete process.env.MUSIC_DIR;
    else process.env.MUSIC_DIR = prev;
    await rm(dir, { recursive: true, force: true });
  }
});
