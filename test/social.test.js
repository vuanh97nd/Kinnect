import { test } from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdtemp, rm } from "node:fs/promises";
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

test("18+ gate, authentication, session privacy, validation and logout", async (t) => {
  const app = await start();
  t.after(() => app.stop());
  assert.equal((await request(app, "/posts")).status, 401);
  assert.equal(
    (
      await request(app, "/register", {
        method: "POST",
        body: {
          username: "minor",
          password: "very-strong-test-password",
          birthDate: "2020-01-01",
          agree18: true,
        },
      })
    ).status,
    400,
  );
  assert.equal(
    (
      await request(app, "/register", {
        method: "POST",
        body: {
          username: "invalid",
          password: "very-strong-test-password",
          birthDate: "2000-02-31",
          agree18: true,
        },
      })
    ).status,
    400,
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
  await app.stop();
  app = await start(join(dir, "test.sqlite"));
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
