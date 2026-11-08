import { test } from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../server.js";

function box(type, payload) {
  const head = Buffer.alloc(8);
  head.writeUInt32BE(8 + payload.length, 0);
  head.write(type, 4, "ascii");
  return Buffer.concat([head, payload]);
}

function sampleMp4() {
  const mvhd = Buffer.alloc(20);
  mvhd.writeUInt32BE(1000, 12);
  mvhd.writeUInt32BE(2000, 16);
  return Buffer.concat([
    box("ftyp", Buffer.from("mp42isom", "ascii")),
    box("mvhd", mvhd),
  ]);
}

const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xd9]);

test("iOS native write payloads match post, story, short, comment and package contracts", async () => {
  const app = createApp();
  await new Promise((resolve) => app.server.listen(0, "127.0.0.1", resolve));
  const base = `http://127.0.0.1:${app.server.address().port}`;
  const req = async (path, body, cookie, method = body ? "POST" : "GET") => {
    const response = await fetch(base + "/api" + path, {
      method,
      headers: {
        ...(cookie ? { cookie } : {}),
        ...(body ? { "content-type": "application/json" } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    return { status: response.status, cookie: response.headers.get("set-cookie")?.split(";")[0], body: await response.json() };
  };
  try {
    const user = await req("/register", {
      username: "ios_payload_user",
      password: "abcdef",
      agree18: true,
      acceptPrivacyNotice: true,
    });
    assert.equal(user.status, 200);
    const cookie = user.cookie;
    const image = `data:image/jpeg;base64,${jpeg.toString("base64")}`;
    const video = `data:video/mp4;base64,${sampleMp4().toString("base64")}`;

    assert.equal((await req("/posts", { text: "xin chao", imageUrl: image }, cookie)).status, 400);
    const post = await req("/posts", { body: "xin chao", visibility: "public", category: "community", media: image }, cookie);
    assert.equal(post.status, 201);
    const posts = await req("/posts", undefined, cookie);
    assert.equal(posts.body.posts.some((item) => item.id === post.body.id), true);

    assert.equal((await req("/stories", { text: "tin", imageUrl: image, backgroundColor: "#7C3AED" }, cookie)).status, 400);
    assert.equal((await req("/stories", { body: "tin", background: "purple", media: image }, cookie)).status, 201);

    assert.equal((await req("/shorts", { videoDataUrl: video, caption: "clip" }, cookie)).status, 400);
    const short = await req("/shorts", { data: video, caption: "clip" }, cookie);
    assert.equal(short.status, 201);
    const shorts = await req("/shorts", undefined, cookie);
    assert.equal(shorts.body.shorts.some((item) => item.id === short.body.id), true);

    assert.equal((await req(`/posts/${post.body.id}/comments`, { text: "hay" }, cookie)).status, 400);
    const comment = await req(`/posts/${post.body.id}/comments`, { body: "hay" }, cookie);
    assert.equal(comment.status, 201);
    const comments = await req(`/posts/${post.body.id}/comments`, undefined, cookie);
    assert.equal(comments.body.comments.some((item) => item.body === "hay"), true);

    const badRequest = "pkg_tooshort";
    assert.equal((await req("/store/packages/buy", { packageId: "style_neon", requestId: "pkg_" + "a".repeat(20) }, cookie)).status, 400);
    const requestId = "pkg_" + "a".repeat(20);
    assert.equal(badRequest.length < 16, true);
    const bought = await req("/store/packages/buy", {
      productId: "style_neon",
      priceCoins: 300,
      requestId,
      coinSource: "gifted",
    }, cookie);
    assert.equal(bought.status, 200);
    assert.equal(bought.body.ownedPackages.includes("style_neon"), true);
    const duplicate = await req("/store/packages/buy", {
      productId: "style_neon",
      priceCoins: 300,
      requestId,
      coinSource: "gifted",
    }, cookie);
    assert.equal(duplicate.status, 200);
    assert.equal(duplicate.body.duplicate, true);
    assert.equal((await req("/store/packages/buy", {
      productId: "style_galaxy",
      priceCoins: 1,
      requestId: "pkg_" + "b".repeat(20),
      coinSource: "gifted",
    }, cookie)).status, 400);
    assert.equal((await req("/store/packages/apply", { packageId: "live_chill", equip: true }, cookie)).status, 403);
    const live = await req("/store/packages/buy", {
      productId: "live_chill",
      priceCoins: 500,
      requestId: "pkg_" + "c".repeat(20),
      coinSource: "gifted",
    }, cookie);
    assert.equal(live.status, 200);
    const applied = await req("/store/packages/apply", { productId: "live_chill" }, cookie);
    assert.equal(applied.status, 200);
    assert.equal(applied.body.liveTheme, "live_chill");
    const poor = await req("/register", {
      username: "ios_payload_poor",
      password: "abcdef",
      agree18: true,
      acceptPrivacyNotice: true,
    });
    assert.equal((await req("/store/packages/buy", {
      productId: "studio_video_365",
      priceCoins: 3990,
      requestId: "pkg_" + "d".repeat(20),
      coinSource: "gifted",
    }, poor.cookie)).status, 402);
  } finally {
    app.wss.close();
    app.server.closeAllConnections?.();
    await new Promise((resolve) => app.server.close(resolve));
    app.social.close();
  }
});
