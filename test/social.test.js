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

test("profile matching, open DMs, posts privacy, blocking and reports", async (t) => {
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
  assert.equal((await as(app,b,"/me")).body.user.dmMode,"everyone");
  assert.equal((await as(app,a,"/users/"+b.id+"/messages","POST",{body:"Hello without following"})).status,201);
  await as(app,b,"/me","PATCH",{dmMode:"mutual"});
  assert.equal((await as(app,b,"/me")).body.user.dmMode,"everyone");
  // Legacy stored preferences must not prevent messaging without follows.
  app.social.db.prepare("UPDATE users SET dm_mode='mutual' WHERE id=?").run(b.id);
  assert.equal((await as(app,a,"/users/"+b.id+"/messages","POST",{body:"Legacy preference still allows messages"})).status,201);
  await as(app, a, "/users/" + b.id + "/follow", "POST", {});
  await as(app, b, "/users/" + a.id + "/follow", "POST", {});
  const msg = await as(app, a, "/users/" + b.id + "/messages", "POST", {
    body: "hello friend",
  });
  assert.equal(msg.status, 201);
  assert.equal(
    (await as(app, b, "/users/" + a.id + "/messages")).body.messages.at(-1).body,
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
    4,
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
    201,
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
  assert.ok((await as(app, a, "/posts")).body.posts.some(p=>p.body==="Stored post"));
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
  assert.equal(result.body.users[0].distanceMeters,100);
  assert.equal(result.body.users[0].distanceLabel,"100 m");
  assert.ok(result.body.users[0].distanceBand);
  assert.equal(result.body.users[0].lat, undefined);
  assert.equal(result.body.users[0].latitude, undefined);
  const stored = app.social.db
    .prepare("SELECT lat,lng FROM users WHERE id=?")
    .get(a.id);
  assert.equal(stored.lat, 10.7734);
  assert.equal(stored.lng, 106.6989);
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
  assert.equal((await as(app, b, "/shorts?feed=following")).body.shorts.length, 0);
  await as(app, b, "/users/" + a.id + "/follow", "POST", {});
  const followed = (await as(app, b, "/shorts?feed=following")).body.shorts;
  assert.equal(followed[0].id, id);
  assert.equal(followed[0].comments, 1);
  await as(app, b, "/users/" + a.id + "/follow", "DELETE", {});
  assert.equal((await as(app, b, "/shorts?feed=following")).body.shorts.length, 0);
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
      7,
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
    // App Android: quay về kinnect://oauth với mã dùng một lần, app đổi mã lấy phiên
    const start3 = await fetch(url + "/api/oauth/google/start?client=android", { redirect: "manual" });
    const state3 = new URL(start3.headers.get("location")).searchParams.get("state");
    const cb3 = await fetch(url + `/api/oauth/google/callback?code=good-code&state=${state3}`, {
      headers: { Cookie: start3.headers.get("set-cookie").split(";")[0] },
    });
    assert.doesNotMatch(cb3.headers.get("set-cookie"), /kinnect_session=[a-f0-9]/);
    const code = (await cb3.text()).match(/kinnect:\/\/oauth\?code=([a-f0-9]+)/)[1];
    const exchange = (c) =>
      fetch(url + "/api/oauth/app-session", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ code: c }) });
    const appSession = await exchange(code);
    assert.equal(appSession.status, 200);
    assert.equal((await appSession.json()).user.username, "minhanh");
    assert.match(appSession.headers.get("set-cookie"), /kinnect_session=/);
    assert.equal((await exchange(code)).status, 401);
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
    assert.deepEqual(like.body, { likes: 1, liked: true,myReaction:"like",reactions:{like:1} });
    await request(app, `/posts/${pid}/like`, { cookie: b.cookie, method: "POST", body: {} });
    for(const reaction of ['love','haha','wow','sad','angry']){const changed=await request(app,`/posts/${pid}/like`,{cookie:b.cookie,method:'POST',body:{reaction}});assert.equal(changed.body.likes,1);assert.equal(changed.body.myReaction,reaction);assert.deepEqual(changed.body.reactions,{[reaction]:1});}
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
    const musicURL = app.url + list.tracks[0].url;
    const part = await fetch(musicURL, { headers: { Cookie: member.cookie, Range: "bytes=0-2" } });
    assert.equal(part.status, 206);
    assert.equal(part.headers.get("content-range"), "bytes 0-2/67");
    assert.equal(await part.text(), "ID3");
    const suffix = await fetch(musicURL, { headers: { Cookie: member.cookie, Range: "bytes=-4" } });
    assert.equal(suffix.status, 206);
    assert.equal((await suffix.arrayBuffer()).byteLength, 4);
    const invalid = await fetch(musicURL, { headers: { Cookie: member.cookie, Range: "bytes=67-" } });
    assert.equal(invalid.status, 416);
    const head = await fetch(musicURL, { method: "HEAD", headers: { Cookie: member.cookie, Range: "bytes=0-2" } });
    assert.equal(head.status, 206);
    assert.equal(head.headers.get("content-length"), "3");
    assert.equal(await head.text(), "");
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

test('post media and 24-hour stories enforce follower, block and expiry visibility',async t=>{
 const app=await start();t.after(()=>app.stop());
 const a=await register(app,'media_author'),b=await register(app,'media_follower'),c=await register(app,'media_stranger');
 const image='data:image/png;base64,'+(await readFile(new URL('../public/apple-touch-icon.png',import.meta.url))).toString('base64');
 const post=await as(app,a,'/posts','POST',{body:'',visibility:'followers',media:image});assert.equal(post.status,201);
 const path='/api/posts/'+post.body.id+'/media';
 assert.equal((await fetch(app.url+path,{headers:{Cookie:c.cookie}})).status,404);
 await as(app,b,'/users/'+a.id+'/follow','POST',{});
 const feed=(await as(app,b,'/posts')).body.posts;assert.equal(feed[0].media.kind,'image');
 assert.equal((await fetch(app.url+path,{headers:{Cookie:b.cookie}})).status,200);
 assert.equal((await fetch(app.url+path,{headers:{Cookie:b.cookie,Range:'bytes=0-7'}})).status,206);
 assert.equal((await as(app,a,'/posts','POST',{body:'',visibility:'public',media:'data:image/png;base64,YmFk'})).status,400);
 const story=await as(app,a,'/stories','POST',{body:'Tin mới',media:image});assert.equal(story.status,201);
 assert.equal((await as(app,b,'/stories')).body.stories.length,1);
 assert.equal((await as(app,c,'/stories')).body.stories.length,0);
 assert.equal((await as(app,b,'/posts')).body.posts.length,1);
 app.social.db.prepare('UPDATE post_stories SET expires=? WHERE post_id=?').run(Date.now()-1,story.body.id);
 assert.equal((await as(app,b,'/stories')).body.stories.length,0);
 assert.equal((await fetch(app.url+'/api/posts/'+story.body.id+'/media',{headers:{Cookie:b.cookie}})).status,404);
 await as(app,a,'/users/'+b.id+'/block','POST',{});
 assert.equal((await fetch(app.url+path,{headers:{Cookie:b.cookie}})).status,404);
 const video='data:video/mp4;base64,'+(await readFile(new URL('../test/fixtures/short.mp4',import.meta.url))).toString('base64');
 assert.equal((await as(app,a,'/posts','POST',{body:'Video trong bảng tin',visibility:'public',media:video})).status,201);
});

test('remembered device login survives explicit logout, requires its cookie, and is revoked by password change',async t=>{
 const app=await start();t.after(()=>app.stop());const a=await register(app,'trusted_device');
 const login=await fetch(app.url+'/api/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:'trusted_device',password:'very-strong-test-password',remember:true})});
 assert.equal(login.status,200);const cookies=login.headers.getSetCookie();const session=cookies.find(c=>c.startsWith('kinnect_session=')).split(';')[0],device=cookies.find(c=>c.startsWith('kinnect_device=')).split(';')[0];
 assert.ok(cookies.find(c=>c.startsWith('kinnect_device=')).includes('HttpOnly'));
 await request(app,'/logout',{cookie:session,method:'POST',body:{}});
 assert.equal((await request(app,'/me',{cookie:session})).status,401);
 const remembered=await request(app,'/remembered',{cookie:device});assert.equal(remembered.body.accounts[0].id,a.id);
 assert.equal((await request(app,'/remembered/login',{method:'POST',body:{userId:a.id}})).status,401);
 const quick=await request(app,'/remembered/login',{cookie:device,method:'POST',body:{userId:a.id}});assert.equal(quick.status,200);
 assert.equal((await request(app,'/me',{cookie:quick.cookie})).status,200);
 await request(app,'/me/password',{cookie:quick.cookie,method:'POST',body:{current:'very-strong-test-password',next:'new-password'}});
 assert.equal((await request(app,'/remembered',{cookie:device})).body.accounts.length,0);
 assert.equal((await request(app,'/remembered/login',{cookie:device,method:'POST',body:{userId:a.id}})).status,401);
 const again=await fetch(app.url+'/api/login',{method:'POST',headers:{'Content-Type':'application/json',Cookie:device},body:JSON.stringify({username:'trusted_device',password:'new-password',remember:true})});assert.equal(again.status,200);
 assert.equal((await request(app,'/remembered/'+a.id,{cookie:device,method:'DELETE',body:{}})).status,200);
 assert.equal((await request(app,'/remembered',{cookie:device})).body.accounts.length,0);
});


test('group membership protects messages, unread counts and ownership transfer',async t=>{
 const app=await start();t.after(()=>app.stop());const a=await register(app,'group_a'),b=await register(app,'group_b'),c=await register(app,'group_c'),outsider=await register(app,'group_out');
 assert.equal((await as(app,a,'/groups','POST',{name:'Bạn bè',members:[]})).status,400);
 const created=await as(app,a,'/groups','POST',{name:'Bạn bè',members:[b.id,b.id]});assert.equal(created.status,201);const id=created.body.group.id;assert.equal(created.body.group.members.length,2);
 assert.equal((await as(app,outsider,'/groups/'+id+'/messages')).status,404);
 assert.equal((await as(app,outsider,'/groups/'+id+'/messages','POST',{body:'intruder'})).status,404);
 assert.equal((await as(app,b,'/groups/'+id+'/members','POST',{members:[c.id]})).status,403);
 assert.equal((await as(app,a,'/groups/'+id+'/members','POST',{members:[c.id]})).status,200);
 assert.equal((await as(app,b,'/groups/'+id+'/members','DELETE',{userId:c.id})).status,403);
 assert.equal((await as(app,a,'/groups/'+id+'/members','DELETE',{userId:a.id})).status,400);
 assert.equal((await as(app,a,'/groups/'+id+'/members','DELETE',{userId:c.id})).status,200);
 assert.equal((await as(app,c,'/groups/'+id+'/messages')).status,404);
 assert.equal((await as(app,a,'/groups/'+id+'/members','POST',{members:[c.id]})).status,200);
 assert.equal((await as(app,b,'/groups/'+id,'PATCH',{name:'wrong'})).status,403);
 assert.equal((await as(app,a,'/groups/'+id,'PATCH',{name:'Nhóm mới'})).body.group.name,'Nhóm mới');
 assert.equal((await as(app,a,'/groups/'+id+'/messages','POST',{body:'Xin chào nhóm'})).status,201);
 assert.equal((await as(app,b,'/groups')).body.groups[0].unread,1);
 assert.equal((await as(app,b,'/groups/'+id+'/messages')).body.messages[0].body,'Xin chào nhóm');
 assert.equal((await as(app,b,'/groups')).body.groups[0].unread,0);
 assert.ok((await as(app,b,'/notifications')).body.notifications.filter(n=>n.kind==='group_message').every(n=>n.seen));
 await as(app,a,'/groups/'+id+'/leave','POST',{});assert.equal((await as(app,a,'/groups/'+id)).status,404);
 const remaining=(await as(app,b,'/groups/'+id)).body.group;assert.notEqual(remaining.owner,a.id);assert.equal(remaining.members.length,2);
 const nextOwner=remaining.owner===b.id?b:c;assert.equal((await as(app,nextOwner,'/groups/'+id,'PATCH',{name:'Sau chuyển quyền'})).status,200);
 await as(app,b,'/groups/'+id+'/leave','POST',{});await as(app,c,'/groups/'+id+'/leave','POST',{});assert.equal(app.social.db.prepare('SELECT COUNT(*) AS n FROM chat_groups WHERE id=?').get(id).n,0);
});

test('private call signaling requires acceptance and blocks outsiders, revoked sessions and blocked users',async t=>{
 const app=await start();t.after(()=>app.stop());const a=await register(app,'call_a'),b=await register(app,'call_b'),c=await register(app,'call_out'),offline=await register(app,'call_offline');
 async function client(u){const ws=new WebSocket(app.url,{headers:{Cookie:u.cookie}}),queue=[];ws.on('message',raw=>queue.push(JSON.parse(raw)));await once(ws,'open');return {ws,queue,send:m=>ws.send(JSON.stringify(m)),wait:async type=>{const until=Date.now()+2000;while(Date.now()<until){const i=queue.findIndex(m=>m.type===type);if(i>=0)return queue.splice(i,1)[0];await new Promise(r=>setTimeout(r,10));}throw Error('Missing '+type);}};}
 const aa=await client(a),bb=await client(b),cc=await client(c);
 aa.send({type:'call-start',to:b.id,requestId:'one'});const ring=await aa.wait('call-ringing'),incoming=await bb.wait('call-incoming');assert.equal(incoming.from.id,a.id);assert.equal(incoming.callId,ring.callId);
 aa.send({type:'call-signal',callId:ring.callId,description:{type:'offer',sdp:'before accept'}});await new Promise(r=>setTimeout(r,30));assert.ok(!bb.queue.some(m=>m.type==='call-signal'));
 cc.send({type:'call-end',callId:ring.callId});bb.send({type:'call-accept',callId:ring.callId});await aa.wait('call-accepted');await bb.wait('call-accepted');
 cc.send({type:'call-signal',callId:ring.callId,description:{type:'offer',sdp:'intruder'}});aa.send({type:'call-signal',callId:ring.callId,description:{type:'offer',sdp:'legitimate'}});assert.equal((await bb.wait('call-signal')).description.sdp,'legitimate');
 cc.send({type:'call-start',to:b.id,requestId:'busy'});assert.equal((await cc.wait('call-ended')).reason,'busy');
 await as(app,b,'/users/'+a.id+'/block','POST',{});assert.equal((await aa.wait('call-ended')).reason,'unavailable');await bb.wait('call-ended');
 aa.send({type:'call-start',to:b.id,requestId:'blocked'});assert.equal((await aa.wait('call-ended')).reason,'unavailable');
 await as(app,b,'/users/'+a.id+'/block','DELETE',{});aa.send({type:'call-start',to:b.id,mode:'audio',requestId:'decline'});const declined=await aa.wait('call-ringing');await bb.wait('call-incoming');bb.send({type:'call-decline',callId:declined.callId});assert.equal((await aa.wait('call-ended')).reason,'declined');await bb.wait('call-ended');const declinedChat=(await as(app,a,'/users/'+b.id+'/messages')).body.messages;assert.ok(declinedChat.some(m=>m.body==='Cuộc gọi thoại bị từ chối.'));await aa.wait('conversations-changed');await bb.wait('conversations-changed');assert.ok((await as(app,a,'/conversations')).body.users.some(u=>u.id===b.id));assert.ok(!(await as(app,b,'/notifications')).body.notifications.some(n=>n.kind==='missed_call'));
 aa.send({type:'call-start',to:offline.id,mode:'video',requestId:'offline'});assert.equal((await aa.wait('call-ended')).reason,'unavailable');const missedChat=(await as(app,a,'/users/'+offline.id+'/messages')).body.messages;assert.ok(missedChat.some(m=>m.body==='Cuộc gọi video nhỡ.'));assert.ok(!(await as(app,offline,'/notifications')).body.notifications.some(n=>n.kind==='missed_call'));
  aa.send({type:'call-start',to:b.id,requestId:'logout'});await aa.wait('call-ringing');await bb.wait('call-incoming');await as(app,a,'/logout','POST',{});assert.equal((await bb.wait('call-ended')).reason,'unavailable');
  assert.equal((await request(app,'/call-config')).status,401);assert.equal((await as(app,b,'/call-config')).status,200);
});

 test('comment replies and reactions persist with resource and block checks',async t=>{
 const app=await start();t.after(()=>app.stop());const a=await register(app,'thread_a'),b=await register(app,'thread_b');const image='data:image/png;base64,'+(await readFile(new URL('../public/apple-touch-icon.png',import.meta.url))).toString('base64');
 for(const resource of ['posts','shorts']){const data=resource==='posts'?{body:'Thread test'}:{caption:'Thread test',data:'data:video/mp4;base64,'+(await readFile(new URL('./fixtures/short.mp4',import.meta.url))).toString('base64')};const made=await as(app,a,'/'+resource,'POST',data);assert.equal(made.status,201);const base='/'+resource+'/'+made.body.id+'/comments',root=(await as(app,a,base,'POST',{body:'Root'})).body.id;const reply=await as(app,b,base,'POST',{body:'Reply',parentId:root});assert.equal(reply.status,201);assert.equal((await as(app,b,base,'POST',{body:'Bad',parentId:'missing'})).status,404);assert.equal((await as(app,b,base+'/'+root+'/reaction','POST',{reaction:'love'})).body.comment.reactions.love,1);assert.equal((await as(app,b,base+'/'+root+'/reaction','POST',{reaction:'haha'})).body.comment.reactions.haha,1);const comments=(await as(app,a,base)).body.comments;assert.equal(comments.find(c=>c.id===reply.body.id).parentId,root);assert.equal(comments.find(c=>c.id===root).reactions.love,undefined);await as(app,b,base+'/'+root+'/reaction','POST',{reaction:null});assert.deepEqual((await as(app,b,base)).body.comments.find(c=>c.id===root).reactions,{});}
 const update=await as(app,a,'/me/cover','POST',{data:image});assert.equal(update.status,200);assert.ok(update.body.user.cover);const cover=await fetch(app.url+update.body.user.cover,{headers:{Cookie:b.cookie}});assert.equal(cover.status,200);assert.ok((await as(app,b,'/posts')).body.posts.some(p=>p.body==='đã cập nhật ảnh bìa.'&&p.media));
 await as(app,b,'/users/'+a.id+'/block','POST',{});assert.equal((await fetch(app.url+update.body.user.cover,{headers:{Cookie:b.cookie}})).status,404);
 });

test('chat files support images, video ranges, downloads and conversation membership',async t=>{
 const app=await start();t.after(()=>app.stop());const a=await register(app,'file_a'),b=await register(app,'file_b'),c=await register(app,'file_out');
 const fixtures=[['photo.png',await readFile(new URL('../public/apple-touch-icon.png',import.meta.url)),'image'],['clip.mp4',await readFile(new URL('./fixtures/short.mp4',import.meta.url)),'video'],['notes.txt',Buffer.from('private attachment'),'file']];
 const group=(await as(app,a,'/groups','POST',{name:'Tệp nhóm',members:[b.id]})).body.group;
 for(const [kind,base] of [['direct','/users/'+b.id+'/messages'],['group','/groups/'+group.id+'/messages']])for(const [name,bytes,type] of fixtures){const sent=await as(app,a,base,'POST',{body:'',attachment:{name,data:'data:application/octet-stream;base64,'+bytes.toString('base64')}});assert.equal(sent.status,201,JSON.stringify(sent.body));const list=await as(app,b,kind==='direct'?'/users/'+a.id+'/messages':base);const file=list.body.messages.find(m=>m.id===sent.body.message.id).attachment;assert.equal(file.kind,type);assert.equal(file.name,name);const response=await fetch(app.url+file.url,{headers:{Cookie:b.cookie}});assert.equal(response.status,200);assert.deepEqual(Buffer.from(await response.arrayBuffer()),bytes);if(type==='file')assert.match(response.headers.get('content-disposition'),/^attachment/);assert.equal((await fetch(app.url+file.url,{headers:{Cookie:c.cookie}})).status,404);assert.equal((await fetch(app.url+file.url)).status,401);const range=await fetch(app.url+file.url,{headers:{Cookie:b.cookie,Range:'bytes=0-7'}});assert.equal(range.status,206);assert.deepEqual(Buffer.from(await range.arrayBuffer()),bytes.subarray(0,8));}
 const grouped=(await as(app,b,'/groups/'+group.id+'/messages')).body.messages[0].attachment;await as(app,b,'/groups/'+group.id+'/leave','POST',{});assert.equal((await fetch(app.url+grouped.url,{headers:{Cookie:b.cookie}})).status,404);
 const direct=(await as(app,b,'/users/'+a.id+'/messages')).body.messages[0].attachment;await as(app,b,'/users/'+a.id+'/block','POST',{});assert.equal((await fetch(app.url+direct.url,{headers:{Cookie:b.cookie}})).status,404);
 assert.equal((await as(app,a,'/users/'+c.id+'/messages','POST',{attachment:{name:'empty',data:'data:;base64,'}})).status,400);
});

test('message delete recall reactions and conversation clearing stay scoped to each user',async t=>{
 const app=await start();t.after(()=>app.stop());const a=await register(app,'actions_a'),b=await register(app,'actions_b'),c=await register(app,'actions_out');const g=(await as(app,a,'/groups','POST',{name:'Actions',members:[b.id]})).body.group;
 for(const kind of ['direct','group']){const from=kind==='direct'?'/users/'+b.id+'/messages':'/groups/'+g.id+'/messages',to=kind==='direct'?'/users/'+a.id+'/messages':from;const sent=await as(app,a,from,'POST',{body:'Message one'});assert.equal(sent.status,201);const id=sent.body.message.id,action='/chat-messages/'+kind+'/'+id;
 assert.equal((await as(app,c,action,'DELETE',{})).status,404);assert.equal((await as(app,b,action+'/recall','POST',{})).status,403);
 assert.equal((await as(app,b,action+'/reaction','POST',{reaction:'love'})).body.message.reactions.love,1);assert.equal((await as(app,a,from)).body.messages[0].reactions.love,1);
 await as(app,b,action,'DELETE',{});assert.equal((await as(app,b,to)).body.messages.length,0);assert.equal((await as(app,a,from)).body.messages.length,1);
 const second=(await as(app,a,from,'POST',{body:'Recall me'})).body.message;await as(app,a,'/chat-messages/'+kind+'/'+second.id+'/recall','POST',{});const recalled=(await as(app,b,to)).body.messages.find(m=>m.id===second.id);assert.equal(recalled.recalled,true);assert.equal(recalled.body,'Tin nhắn đã được thu hồi');assert.equal((await as(app,b,'/chat-messages/'+kind+'/'+second.id+'/reaction','POST',{reaction:'like'})).status,404);
 await as(app,b,to,'DELETE',{});assert.equal((await as(app,b,to)).body.messages.length,0);assert.ok((await as(app,a,from)).body.messages.length>0);assert.equal(kind==='direct'?(await as(app,b,'/conversations')).body.users.length:(await as(app,b,'/groups')).body.groups.length,0);
 await as(app,a,from,'POST',{body:'New conversation'});assert.equal((await as(app,b,to)).body.messages.length,1);assert.equal(kind==='direct'?(await as(app,b,'/conversations')).body.users.length:(await as(app,b,'/groups')).body.groups.length,1);
 }
});

test('delivery and seen receipts are independent from notification read state and presence privacy',async t=>{
 const app=await start();t.after(()=>app.stop());const a=await register(app,'receipt_a'),b=await register(app,'receipt_b');const sent=(await as(app,a,'/users/'+b.id+'/messages','POST',{body:'Read state'})).body.message;
 let m=(await as(app,a,'/users/'+b.id+'/messages')).body.messages.find(m=>m.id===sent.id);assert.equal(m.receipt.deliveredAt,undefined);await as(app,b,'/notifications');m=(await as(app,a,'/users/'+b.id+'/messages')).body.messages[0];assert.ok(m.receipt.deliveredAt);assert.equal(m.receipt.seenAt,null);await as(app,b,'/notifications','POST',{});assert.equal((await as(app,a,'/users/'+b.id+'/messages')).body.messages[0].receipt.seenAt,null);await as(app,b,'/users/'+a.id+'/messages');assert.ok((await as(app,a,'/users/'+b.id+'/messages')).body.messages[0].receipt.seenAt);
 app.social.db.prepare('UPDATE users SET last_active=? WHERE id=?').run(Date.now()-5*60000,b.id);assert.ok((await as(app,a,'/users/'+b.id)).body.user.lastActiveAt);await as(app,b,'/me','PATCH',{showActivity:false});const hidden=(await as(app,a,'/users/'+b.id)).body.user;assert.equal(hidden.lastActiveAt,null);assert.equal(hidden.isActive,false);
});

test('pins are shared and mute is per member without losing unread messages',async t=>{
 const app=await start();t.after(()=>app.stop());const a=await register(app,'pin_a'),b=await register(app,'pin_b'),out=await register(app,'pin_out');const g=(await as(app,a,'/groups','POST',{name:'Pinned',members:[b.id]})).body.group;
 for(const kind of ['direct','group']){const from=kind==='direct'?'/users/'+b.id+'/messages':'/groups/'+g.id+'/messages',to=kind==='direct'?'/users/'+a.id+'/messages':from,id=(await as(app,a,from,'POST',{body:'Pin this'})).body.message.id;
 assert.equal((await as(app,a,'/chat-messages/'+kind+'/'+id+'/pin','POST',{})).status,200);assert.equal((await as(app,b,to)).body.messages[0].pinned,true);assert.equal((await as(app,out,'/chat-messages/'+kind+'/'+id+'/pin','POST',{})).status,404);
 const preference='/chat-preferences/'+kind+'/'+(kind==='direct'?a.id:g.id);assert.equal((await as(app,b,preference,'POST',{muted:true})).body.muted,true);assert.equal((await as(app,b,preference)).body.muted,true);const fresh=(await as(app,a,from,'POST',{body:'Muted but unread'})).body.message;const note=(await as(app,b,'/notifications')).body.notifications.find(n=>kind==='direct'?n.ref===fresh.id:n.kind==='group_message'&&!n.seen);assert.equal(note.muted,true);assert.equal(note.seen,0);assert.equal((await as(app,b,preference,'POST',{muted:false})).body.muted,false);
 await as(app,a,'/chat-messages/'+kind+'/'+id+'/recall','POST',{});assert.ok(!(await as(app,b,to)).body.messages[0].pinned);
 }
});

test('private albums require approval and revoke access immediately',async t=>{
 const app=await start();t.after(()=>app.stop());const a=await register(app,'private_owner'),b=await register(app,'private_viewer'),c=await register(app,'private_other');
 const bytes=await readFile(new URL('../public/apple-touch-icon.png',import.meta.url)),data='data:image/png;base64,'+bytes.toString('base64');
 assert.equal((await as(app,a,'/me/private-photos','POST',{data:'data:image/png;base64,'+Buffer.alloc(32).toString('base64')})).status,400);
 const made=await as(app,a,'/me/private-photos','POST',{data});assert.equal(made.status,201);const photo=made.body.photos[0],album='/users/'+a.id+'/private',decision='/me/private/requests/'+b.id;
 const image=(u,method='GET')=>fetch(app.url+photo.url,{method,headers:u?{Cookie:u.cookie}:{}});
 assert.equal((await image()).status,401);assert.equal((await image(b)).status,404);const own=await image(a);assert.equal(own.status,200);assert.equal(own.headers.get('cache-control'),'private, no-store');assert.deepEqual(Buffer.from(await own.arrayBuffer()),bytes);
 assert.deepEqual((await as(app,b,album)).body.photos,[]);assert.equal((await as(app,b,'/me/private-photos/'+photo.id,'DELETE',{})).status,404);
 for(let i=0;i<2;i++)assert.equal((await as(app,b,album+'/request','POST',{})).body.status,'pending');
 assert.equal((await as(app,a,'/notifications')).body.notifications.filter(n=>n.kind==='private_request').length,1);
  app.social.db.prepare('INSERT INTO notifications(id,user_id,actor,kind,ref,seen,created) VALUES(?,?,?,?,?,?,?)').run('legacy-duplicate',a.id,b.id,'private_request',b.id,0,Date.now());
  await as(app,b,album+'/request','POST',{});assert.equal((await as(app,a,'/notifications')).body.notifications.filter(n=>n.kind==='private_request'&&!n.seen).length,1);
 assert.equal((await as(app,c,decision,'POST',{action:'grant'})).status,404);
 await as(app,a,decision,'POST',{action:'deny'});assert.equal((await image(b)).status,404);
 await as(app,b,album+'/request','POST',{});await as(app,b,album+'/request','DELETE',{});assert.equal((await as(app,a,'/me/private/requests')).body.requests.length,0);
 await as(app,b,album+'/request','POST',{});await as(app,a,decision,'POST',{action:'grant'});assert.equal((await image(b)).status,200);assert.equal((await image(c)).status,404);const head=await image(b,'HEAD');assert.equal(head.status,200);assert.equal((await head.arrayBuffer()).byteLength,0);
 await as(app,a,decision,'POST',{action:'revoke'});assert.equal((await image(b)).status,404);
 await as(app,b,album+'/request','POST',{});await as(app,a,decision,'POST',{action:'grant'});await as(app,b,'/users/'+a.id+'/block','POST',{});assert.equal((await image(b)).status,404);await as(app,b,'/users/'+a.id+'/block','DELETE',{});assert.equal((await image(b)).status,404);
 await as(app,b,album+'/request','POST',{});await as(app,a,decision,'POST',{action:'grant'});app.social.db.prepare('UPDATE users SET suspended=1 WHERE id=?').run(a.id);assert.equal((await image(b)).status,404);app.social.db.prepare('UPDATE users SET suspended=0 WHERE id=?').run(a.id);
 assert.equal((await as(app,a,'/me/private-photos/'+photo.id,'DELETE',{})).status,200);assert.equal((await image(a)).status,404);
});

test('friend requests suggestions acceptance and blocking stay scoped',async t=>{
 const app=await start();t.after(()=>app.stop());const a=await register(app,'friend_a'),b=await register(app,'friend_b'),c=await register(app,'friend_c');
 assert.equal((await request(app,'/friends')).status,401);assert.equal((await as(app,a,'/users/'+a.id+'/friend-request','POST',{})).status,404);
 await as(app,a,'/me','PATCH',{city:'Đà Nẵng',interests:['âm nhạc']});await as(app,b,'/me','PATCH',{city:'Đà Nẵng',interests:['âm nhạc']});assert.equal((await as(app,a,'/friend-suggestions')).body.users[0].id,b.id);
 for(let i=0;i<2;i++)assert.equal((await as(app,a,'/users/'+b.id+'/friend-request','POST',{})).body.status,'outgoing');assert.equal((await as(app,b,'/friend-requests')).body.incoming.length,1);assert.equal((await as(app,b,'/notifications')).body.friendRequestsPending,1);
 assert.equal((await as(app,c,'/users/'+a.id+'/friend-request/respond','POST',{action:'accept'})).status,404);assert.equal((await as(app,a,'/users/'+b.id+'/friend-request/respond','POST',{action:'accept'})).status,404);
 assert.equal((await as(app,a,'/friend-suggestions')).body.users.some(u=>u.id===b.id),false);await as(app,b,'/users/'+a.id+'/friend-request/respond','POST',{action:'accept'});assert.equal((await as(app,a,'/friends')).body.users[0].friendship,'friends');assert.equal((await as(app,b,'/friends')).body.users[0].id,a.id);assert.equal((await as(app,a,'/users/'+b.id)).body.user.following,true);
 await as(app,b,'/me','PATCH',{showActivity:false});const hidden=(await as(app,a,'/friends')).body.users[0];assert.equal(hidden.activityShared,false);assert.equal(hidden.isActive,false);assert.equal(hidden.lastActiveAt,null);
 await as(app,a,'/users/'+b.id+'/friendship','DELETE',{});assert.equal((await as(app,b,'/friends')).body.users.length,0);await as(app,a,'/users/'+b.id+'/friend-request','POST',{});await as(app,b,'/users/'+a.id+'/friend-request/respond','POST',{action:'decline'});assert.equal((await as(app,b,'/friend-requests')).body.incoming.length,0);
 await as(app,a,'/users/'+b.id+'/friend-request','POST',{});await as(app,b,'/users/'+a.id+'/block','POST',{});assert.equal((await as(app,a,'/users/'+b.id+'/friend-request','POST',{})).status,404);await as(app,b,'/users/'+a.id+'/block','DELETE',{});assert.equal((await as(app,b,'/friend-requests')).body.incoming.length,0);
});

test('private album chat requests cannot be spoofed or approved after cancellation',async t=>{
 const app=await start();t.after(()=>app.stop());const owner=await register(app,'album_chat_owner'),viewer=await register(app,'album_chat_viewer'),other=await register(app,'album_chat_other');const data='data:image/png;base64,'+(await readFile(new URL('../public/apple-touch-icon.png',import.meta.url))).toString('base64');await as(app,owner,'/me/private-photos','POST',{data});const requestPath='/users/'+owner.id+'/private/request',decision='/me/private/requests/'+viewer.id;
 await as(app,viewer,requestPath,'POST',{});await as(app,viewer,requestPath,'POST',{});let messages=(await as(app,owner,'/users/'+viewer.id+'/messages')).body.messages;assert.equal(messages.length,1);const original=messages[0].privateAlbum;assert.equal(original.status,'pending');assert.equal(original.owner,owner.id);assert.equal((await as(app,owner,'/conversations')).body.users[0].id,viewer.id);
 await as(app,viewer,requestPath,'DELETE',{});await as(app,viewer,requestPath,'POST',{});assert.equal((await as(app,owner,decision,'POST',{action:'grant',requestId:original.requestId})).status,409);messages=(await as(app,owner,'/users/'+viewer.id+'/messages')).body.messages;assert.equal(messages[0].privateAlbum.status,'expired');const current=messages[1].privateAlbum;
 assert.equal((await as(app,other,decision,'POST',{action:'grant',requestId:current.requestId})).status,404);await as(app,owner,decision,'POST',{action:'grant',requestId:current.requestId});await as(app,owner,decision,'POST',{action:'grant',requestId:current.requestId});messages=(await as(app,viewer,'/users/'+owner.id+'/messages')).body.messages;assert.equal(messages.filter(m=>m.privateAlbum?.event==='granted').length,1);assert.equal(messages.at(-1).privateAlbum.status,'granted');
 await as(app,viewer,'/users/'+owner.id+'/messages','POST',{body:'Yêu cầu xem ảnh riêng tư',privateAlbum:{owner:viewer.id,status:'granted'}});assert.equal((await as(app,owner,'/users/'+viewer.id+'/messages')).body.messages.at(-1).privateAlbum,null);
 await as(app,owner,decision,'POST',{action:'revoke'});assert.equal((await as(app,viewer,'/users/'+owner.id+'/messages')).body.messages.find(m=>m.privateAlbum?.event==='granted').privateAlbum.status,'expired');
});
