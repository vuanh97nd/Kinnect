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
      5,
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
