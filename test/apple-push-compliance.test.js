import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, createSign } from "node:crypto";
import { createApp } from "../server.js";

function token(privateKey, claims) {
  const header = Buffer.from(JSON.stringify({ alg: "RS256", kid: "apple-test-key-1" })).toString("base64url");
  const payload = Buffer.from(JSON.stringify(claims)).toString("base64url");
  const signer = createSign("RSA-SHA256");
  signer.update(`${header}.${payload}`);
  return `${header}.${payload}.${signer.sign(privateKey, "base64url")}`;
}

test("Apple nonce is required and push tokens register for the signed-in user", async () => {
  const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const app = createApp({
    appleKeyResolver: async () => publicKey,
  });
  await new Promise((resolve) => app.server.listen(0, "127.0.0.1", resolve));
  const base = `http://127.0.0.1:${app.server.address().port}`;
  const req = async (path, body, cookie) => {
    const response = await fetch(base + path, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(cookie ? { cookie } : {}),
      },
      body: JSON.stringify(body),
    });
    return { status: response.status, cookie: response.headers.get("set-cookie")?.split(";")[0], body: await response.json() };
  };
  try {
    const raw = "required-nonce-value";
    const hash = createHash("sha256").update(raw).digest("hex");
    const exp = Math.floor(Date.now() / 1000) + 600;
    const missing = token(privateKey, {
      iss: "https://appleid.apple.com",
      aud: "app.kinnect.live",
      exp,
      sub: "apple-missing-nonce",
      jti: "missing-nonce-jti",
    });
    assert.equal((await req("/api/auth/apple", { identityToken: missing, appleId: "apple-missing-nonce" })).status, 401);
    const signed = token(privateKey, {
      iss: "https://appleid.apple.com",
      aud: "app.kinnect.live",
      exp,
      sub: "apple-with-nonce",
      jti: "with-nonce-jti",
      nonce: hash,
    });
    const authed = await req("/api/auth/apple", {
      identityToken: signed,
      appleId: "apple-with-nonce",
      nonce: raw,
      agree18: true,
      acceptPrivacyNotice: true,
    });
    assert.equal(authed.status, 200);
    const voip = "ab".repeat(32);
    assert.equal((await req("/api/devices/push", { kind: "voip", token: voip }, authed.cookie)).status, 200);
    const row = app.social.db.prepare("SELECT kind, token FROM push_devices").get();
    assert.equal(row.kind, "voip");
    assert.equal(row.token, voip);
    assert.equal((await req("/api/auth/apple", {
      identityToken: signed,
      appleId: "apple-with-nonce",
      nonce: raw,
    })).status, 401);
  } finally {
    app.wss.close();
    app.server.closeAllConnections?.();
    await new Promise((resolve) => app.server.close(resolve));
    app.social.close();
  }
});
