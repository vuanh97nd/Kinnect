import { test } from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { WebSocket } from "ws";
import { createApp } from "../server.js";

test("room lifecycle, chat, signaling isolation, host disconnect and HTTP", async (t) => {
  const { server, wss, social } = createApp();
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const url = `http://127.0.0.1:${server.address().port}`;
  const clients = [];
  t.after(async () => {
    clients.forEach((c) => c.ws.terminate());
    await new Promise((r) => wss.close(r));
    await new Promise((r) => server.close(r));
    social.close();
  });
  async function connect() {
    const response = await fetch(url + "/api/register", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        username: "user_" + clients.length,
        password: "test-password-123",
        name: clients.length === 1 ? "Viewer" : "Host",
        birthDate: "1995-01-01",
        agree18: true,
      }),
    });
    assert.equal(response.status, 200);
    const ws = new WebSocket(url, {
      headers: { Cookie: response.headers.get("set-cookie").split(";")[0] },
    });
    const queue = [];
    ws.on("message", (r) => queue.push(JSON.parse(r)));
    await once(ws, "open");
    const c = {
      ws,
      queue,
      send: (m) => ws.send(JSON.stringify(m)),
      async get(type) {
        for (let n = 0; n < 200; n++) {
          const i = queue.findIndex((m) => m.type === type);
          if (i >= 0) return queue.splice(i, 1)[0];
          await new Promise((r) => setTimeout(r, 5));
        }
        throw Error("Timed out waiting for " + type);
      },
    };
    clients.push(c);
    c.id = (await c.get("welcome")).id;
    return c;
  }
  assert.equal((await fetch(url + "/health")).status, 200);
  assert.match(await (await fetch(url)).text(), /Kinnect/);
  assert.equal((await fetch(url + "/missing")).status, 404);
  const host = await connect(),
    viewer = await connect(),
    outsider = await connect();
  host.send({ type: "create", name: "Host", title: "Test live" });
  const joined = await host.get("joined");
  assert.equal(joined.role, "host");
  viewer.send({ type: "join", room: joined.room.id, name: "Viewer" });
  assert.equal((await viewer.get("joined")).role, "viewer");
  assert.equal((await host.get("peer")).id, viewer.id);
  viewer.send({ type: "chat", text: "Hello rainbow" });
  assert.equal((await host.get("chat")).text, "Hello rainbow");
  assert.equal((await viewer.get("chat")).name, "Viewer");
  host.send({
    type: "signal",
    to: viewer.id,
    description: { type: "offer", sdp: "test-sdp" },
  });
  assert.equal((await viewer.get("signal")).from, host.id);
  outsider.send({
    type: "signal",
    to: viewer.id,
    description: { type: "offer", sdp: "unauthorized" },
  });
  assert.match((await outsider.get("error")).message, /chưa tham gia/);
  viewer.send({ type: "leave" });
  assert.equal((await host.get("peer-left")).id, viewer.id);
  viewer.send({ type: "join", room: joined.room.id });
  await viewer.get("joined");
  host.ws.close();
  await viewer.get("ended");
  viewer.send({ type: "join", room: joined.room.id });
  assert.match((await viewer.get("error")).message, /kết thúc/);
});

test("viewer capacity and cross-origin rejection", async (t) => {
  const { server, wss, social } = createApp();
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const url = `ws://127.0.0.1:${server.address().port}`;
  const sockets = [];
  t.after(async () => {
    sockets.forEach((s) => s.terminate());
    await new Promise((r) => wss.close(r));
    await new Promise((r) => server.close(r));
    social.close();
  });
  const bad = new WebSocket(url, { origin: "https://evil.example" });
  sockets.push(bad);
  assert.equal((await once(bad, "close"))[0], 1008);
  async function client() {
    const response = await fetch(
      url.replace("ws:", "http:") + "/api/register",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          username: "member_" + sockets.length,
          password: "test-password-123",
          birthDate: "1995-01-01",
          agree18: true,
        }),
      },
    );
    assert.equal(response.status, 200);
    const ws = new WebSocket(url, {
      headers: { Cookie: response.headers.get("set-cookie").split(";")[0] },
    });
    sockets.push(ws);
    const queue = [];
    ws.on("message", (r) => queue.push(JSON.parse(r)));
    await once(ws, "open");
    return {
      ws,
      async get(type) {
        for (let i = 0; i < 200; i++) {
          const n = queue.findIndex((m) => m.type === type);
          if (n >= 0) return queue.splice(n, 1)[0];
          await new Promise((r) => setTimeout(r, 5));
        }
        throw Error(type);
      },
    };
  }
  const host = await client();
  host.ws.send(JSON.stringify({ type: "create" }));
  const { room } = await host.get("joined");
  for (let i = 0; i < 7; i++) {
    const v = await client();
    v.ws.send(JSON.stringify({ type: "join", room: room.id }));
    if (i < 6) await v.get("joined");
    else assert.match((await v.get("error")).message, /6 người xem/);
  }
});
