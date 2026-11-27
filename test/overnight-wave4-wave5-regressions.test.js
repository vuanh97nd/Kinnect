import http from "node:http";
import { test } from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import {
  createCipheriv,
  createDecipheriv,
  createECDH,
  createHash,
  createHmac,
  createSign,
  generateKeyPairSync,
  randomBytes,
  randomUUID,
  scryptSync,
} from "node:crypto";
import { WebSocket } from "ws";

import { createApp } from "../server.js";
import { openSocial } from "../lib/social.js";
import { createKinnectAI } from "../lib/kinnect-ai.js";
import { createWebPush } from "../lib/webpush.js";
import { createPostgresIdentity } from "../lib/postgres-identity.js";
import { commerceRoute, commerceState } from "../cloud-api/commerce-routes.js";
import { notificationRoute } from "../cloud-api/notification-routes.js";
import { DEFAULT_ECONOMY } from "../lib/economy.js";
import worker from "../cloud-api/worker.js";
import pg from "../cloud-api/node_modules/pg/esm/index.mjs";

const scryptHex = (password, salt) => scryptSync(password, salt, 64).toString("hex");
const jsonFn = (value, status = 200, headers = {}) =>
  Response.json(value, { status, headers: { "Cache-Control": "no-store", ...headers } });

function signAppleToken(privateKey, claims, kid = "apple-test-key-1") {
  const header = Buffer.from(JSON.stringify({ alg: "RS256", kid })).toString("base64url");
  const payload = Buffer.from(JSON.stringify(claims)).toString("base64url");
  const signer = createSign("RSA-SHA256");
  signer.update(`${header}.${payload}`);
  return `${header}.${payload}.${signer.sign(privateKey, "base64url")}`;
}

async function startApp(t, opts = {}) {
  const app = createApp({ dbPath: ":memory:", authLimit: 1000, ...opts });
  await new Promise((resolve) => app.server.listen(0, "127.0.0.1", resolve));
  const origin = "http://127.0.0.1:" + app.server.address().port;
  t.after(async () => {
    for (const ws of app.wss.clients) ws.terminate();
    app.wss.close();
    app.server.closeAllConnections?.();
    await new Promise((resolve) => app.server.close(resolve));
    app.social.close();
  });

  async function api(path, { method = "GET", body, cookie, headers = {} } = {}) {
    const isWrite = ["POST", "PATCH", "PUT"].includes(method);
    const payload = body !== undefined ? JSON.stringify(body) : isWrite ? "{}" : undefined;
    const res = await fetch(origin + "/api" + path, {
      method,
      headers: {
        ...(cookie ? { Cookie: cookie } : {}),
        ...(payload !== undefined ? { "Content-Type": "application/json" } : {}),
        ...headers,
      },
      body: payload,
    });
    const text = await res.text();
    let parsed = text;
    try {
      parsed = JSON.parse(text);
    } catch {}
    return {
      status: res.status,
      body: parsed,
      headers: res.headers,
      cookie: res.headers.get("set-cookie")?.split(";")[0] || "",
    };
  }

  async function register(username, extra = {}) {
    const r = await api("/register", {
      method: "POST",
      body: {
        username,
        name: extra.name || "User " + username,
        password: extra.password || "strong-pass-123",
        agree18: true,
        acceptPrivacyNotice: true,
        acceptTerms: true,
        ...extra,
      },
    });
    assert.equal(r.status, 200, `register ${username} failed: ${JSON.stringify(r.body)}`);
    return { user: r.body.user, cookie: r.cookie };
  }

  async function consoleReq(path, { portal = "admin", method = "GET", data, cookie, originHeader = true } = {}) {
    const port = app.server.address().port;
    const host = portal === "local" ? `localhost:${port}` : `${portal}.kinnect.io.vn`;
    const payload = data !== undefined ? JSON.stringify(data) : null;
    return new Promise((resolve, reject) => {
      const req = http.request(
        origin + path,
        {
          method,
          headers: {
            Host: host,
            ...(cookie ? { Cookie: cookie } : {}),
            ...(payload !== null
              ? { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(payload) }
              : {}),
            ...(method === "POST" && originHeader
              ? { Origin: originHeader === true ? `https://${host}` : originHeader }
              : {}),
          },
        },
        (res) => {
          const chunks = [];
          res.on("data", (c) => chunks.push(c));
          res.on("end", () => {
            const text = Buffer.concat(chunks).toString("utf8");
            let parsed = text;
            if (res.headers["content-type"]?.includes("application/json")) {
              try {
                parsed = JSON.parse(text);
              } catch {}
            }
            resolve({
              status: res.statusCode,
              body: parsed,
              headers: res.headers,
              cookie: res.headers["set-cookie"]?.[0]?.split(";")[0] || "",
            });
          });
        }
      );
      req.on("error", reject);
      if (payload !== null) req.write(payload);
      req.end();
    });
  }

  async function connectWs(cookie) {
    const ws = new WebSocket(origin.replace("http:", "ws:"), { headers: { Cookie: cookie } });
    t.after(() => ws.terminate());
    const queue = [];
    ws.on("message", (raw) => {
      try {
        queue.push(JSON.parse(raw.toString()));
      } catch {}
    });
    await new Promise((resolve, reject) => {
      ws.once("open", resolve);
      ws.once("error", reject);
    });
    const deadline = Date.now() + 2000;
    while (Date.now() < deadline) {
      const idx = queue.findIndex((m) => m.type === "welcome");
      if (idx >= 0) {
        queue.splice(idx, 1);
        return { ws, queue };
      }
      await new Promise((r) => setTimeout(r, 10));
    }
    throw new Error("Timed out waiting for WS welcome");
  }

  return { ...app, origin, api, register, consoleReq, connectWs };
}

function decryptWebPushPayload(encryptedBuf, uaPrivateKey, authSecret) {
  const salt = encryptedBuf.subarray(0, 16);
  const keyLen = encryptedBuf[20];
  const asPublic = encryptedBuf.subarray(21, 21 + keyLen);
  const ciphertextAndTag = encryptedBuf.subarray(21 + keyLen);
  const ecdh = createECDH("prime256v1");
  ecdh.setPrivateKey(uaPrivateKey);
  const shared = ecdh.computeSecret(asPublic);
  const uaPublic = ecdh.getPublicKey();
  const hmac = (k, d) => createHmac("sha256", k).update(d).digest();
  const ikm = hmac(
    hmac(authSecret, shared),
    Buffer.concat([Buffer.from("WebPush: info\0"), uaPublic, asPublic, Buffer.from([1])])
  );
  const prk = hmac(salt, ikm);
  const cek = hmac(prk, Buffer.from("Content-Encoding: aes128gcm\0\x01")).subarray(0, 16);
  const nonce = hmac(prk, Buffer.from("Content-Encoding: nonce\0\x01")).subarray(0, 12);
  const tag = ciphertextAndTag.subarray(-16);
  const ciphertext = ciphertextAndTag.subarray(0, -16);
  const decipher = createDecipheriv("aes-128-gcm", cek, nonce);
  decipher.setAuthTag(tag);
  const plain = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  // Remove trailing RFC 8188 delimiter (0x02 + optional zero padding)
  let end = plain.length - 1;
  while (end >= 0 && plain[end] === 0) end--;
  assert.equal(plain[end], 2);
  return JSON.parse(plain.subarray(0, end).toString("utf8"));
}

// ---------------------------------------------------------------------------
// 1. W3B-01 & W3B-30: cloud-api/worker.js 2FA login block + Preview/Origin guards
// ---------------------------------------------------------------------------
test("Wave 4/5 [W3B-01, W3B-30]: cloud-api worker blocks 2FA login without minting session and rejects invalid preview/origin", async (t) => {
  const OrigClient = pg.Client;
  const users = new Map();
  const userTotp = new Map();
  const sessionInserts = [];

  const salt = "00112233445566778899aabbccddeeff";
  const passwordPlain = "CorrectPassword123!";
  const passwordHash = scryptHex(passwordPlain, salt);

  users.set("alice_profile_2fa", {
    id: "u-2fa-profile",
    username: "alice_profile_2fa",
    password: passwordHash,
    salt,
    role: "user",
    suspended: 0,
    name: "Alice Profile 2FA",
    created: 1000,
    profile: { two_factor_enabled: true },
  });
  users.set("bob_totp_table", {
    id: "u-2fa-table",
    username: "bob_totp_table",
    password: passwordHash,
    salt,
    role: "user",
    suspended: 0,
    name: "Bob TOTP Table",
    created: 2000,
    profile: {},
  });
  userTotp.set("u-2fa-table", { enabled: 1 });

  users.set("carol_no_2fa", {
    id: "u-no-2fa",
    username: "carol_no_2fa",
    password: passwordHash,
    salt,
    role: "user",
    suspended: 0,
    name: "Carol Normal",
    created: 3000,
    profile: {},
  });

  pg.Client = class MockPgClient {
    async connect() {}
    async end() {}
    async query(sql, params = []) {
      const s = sql.replace(/\s+/g, " ").trim();
      if (s.includes("FROM kinnect_core.users WHERE username=$1")) {
        const u = users.get(params[0]);
        return { rows: u ? [u] : [] };
      }
      if (s.includes("information_schema.tables") && s.includes("user_totp")) {
        return { rows: [{ "?column?": 1 }] };
      }
      if (s.includes("FROM kinnect_core.user_totp WHERE user_id=$1")) {
        const row = userTotp.get(params[0]);
        return { rows: row ? [row] : [] };
      }
      if (s.startsWith("INSERT INTO kinnect_core.sessions")) {
        sessionInserts.push({ sql: s, params });
        return { rows: [{ user_id: params[1] }] };
      }
      return { rows: [] };
    }
  };
  t.after(() => {
    pg.Client = OrigClient;
  });

  const env = {
    PREVIEW_KEY: "preview-secret-key-2026",
    HYPERDRIVE: { connectionString: "postgres://mock" },
  };

  // Missing / invalid X-Kinnect-Preview rejected with 404
  const noPreview = await worker.fetch(
    new Request("https://cloud.example/api/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username: "carol_no_2fa", password: passwordPlain }),
    }),
    env
  );
  assert.equal(noPreview.status, 404);

  const badPreview = await worker.fetch(
    new Request("https://cloud.example/api/login", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Kinnect-Preview": "wrong-key" },
      body: JSON.stringify({ username: "carol_no_2fa", password: passwordPlain }),
    }),
    env
  );
  assert.equal(badPreview.status, 404);

  // Malformed Origin header rejected with 403
  const malformedOrigin = await worker.fetch(
    new Request("https://cloud.example/api/login", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Kinnect-Preview": env.PREVIEW_KEY,
        Origin: "://malformed-origin",
      },
      body: JSON.stringify({ username: "carol_no_2fa", password: passwordPlain }),
    }),
    env
  );
  assert.equal(malformedOrigin.status, 403);

  // Cross-origin Origin header rejected with 403
  const crossOrigin = await worker.fetch(
    new Request("https://cloud.example/api/login", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Kinnect-Preview": env.PREVIEW_KEY,
        Origin: "https://evil.example",
      },
      body: JSON.stringify({ username: "carol_no_2fa", password: passwordPlain }),
    }),
    env
  );
  assert.equal(crossOrigin.status, 403);

  // User with profile.two_factor_enabled = true -> 403 { requires2fa: true } and NO session cookie
  const resProfile2fa = await worker.fetch(
    new Request("https://cloud.example/api/login", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Kinnect-Preview": env.PREVIEW_KEY,
        Origin: "https://cloud.example",
      },
      body: JSON.stringify({ username: "alice_profile_2fa", password: passwordPlain }),
    }),
    env
  );
  assert.equal(resProfile2fa.status, 403);
  assert.equal(resProfile2fa.headers.get("set-cookie"), null);
  assert.equal((await resProfile2fa.json()).requires2fa, true);

  // User with user_totp.enabled = 1 -> 403 { requires2fa: true } and NO session cookie
  const resTable2fa = await worker.fetch(
    new Request("https://cloud.example/api/login", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Kinnect-Preview": env.PREVIEW_KEY,
        Origin: "https://cloud.example",
      },
      body: JSON.stringify({ username: "bob_totp_table", password: passwordPlain }),
    }),
    env
  );
  assert.equal(resTable2fa.status, 403);
  assert.equal(resTable2fa.headers.get("set-cookie"), null);
  assert.equal((await resTable2fa.json()).requires2fa, true);
  assert.equal(sessionInserts.length, 0, "2FA-blocked logins must never mint sessions");

  // Normal user without 2FA still logs in cleanly
  const resOk = await worker.fetch(
    new Request("https://cloud.example/api/login", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Kinnect-Preview": env.PREVIEW_KEY,
      },
      body: JSON.stringify({ username: "carol_no_2fa", password: passwordPlain }),
    }),
    env
  );
  assert.equal(resOk.status, 200);
  assert.match(resOk.headers.get("set-cookie") || "", /^kinnect_session=/);
  assert.equal(sessionInserts.length, 1);
});

// ---------------------------------------------------------------------------
// 2. W3B-02 & W5B-06: cloud-api/commerce-routes.js
// ---------------------------------------------------------------------------
test("Wave 4/5 [W3B-02, W5B-06]: cloud commerce enforces gift effectivePrice, empty economy_config, permanent purchases, /api/store/buy, priceCoins=0 rejection, adminAccess=false", async () => {
  const userId = "cloud-buyer-1";
  const now = Date.now();
  const state = {
    economyRows: [], // empty economy_config initially
    walletEntries: [],
    storePackages: [],
    storePurchases: [
      {
        user_id: userId,
        product_id: "kinnect_studio_pro",
        state: "PURCHASED",
        verified: now - 10 * 86400 * 1000, // older than 24h (86400s)
      },
    ],
    giftInventory: [],
  };

  const mockClient = {
    async query(sql, params = []) {
      const s = sql.replace(/\s+/g, " ").trim();
      if (s === "BEGIN" || s === "COMMIT" || s === "ROLLBACK") return { rows: [] };
      if (s.startsWith("SELECT role,suspended FROM kinnect_core.users")) {
        return { rows: [{ role: "user", suspended: 0 }] };
      }
      if (s.includes("FROM kinnect_core.economy_config WHERE id=1")) {
        return { rows: state.economyRows };
      }
      if (s.includes("FROM kinnect_core.wallet_entries WHERE user_id=$1") && s.includes("FILTER")) {
        const gifted = state.walletEntries
          .filter((e) =>
            ["signup_trial", "live_gift_trial", "live_gift_received_trial", "store_trial", "admin_trial", "farm_trial"].includes(e.kind)
          )
          .reduce((a, b) => a + b.coins, 0);
        const purchased = state.walletEntries
          .filter((e) => ["coin_purchase", "live_gift_paid", "store_paid"].includes(e.kind))
          .reduce((a, b) => a + b.coins, 0);
        return { rows: [{ gifted: String(gifted), purchased: String(purchased), earnings: "0" }] };
      }
      if (s.includes("information_schema.columns") && s.includes("wallet_trial_gifts")) {
        return { rows: [{ "?column?": 1 }] };
      }
      if (s.includes("FROM kinnect_core.wallet_trial_gifts")) {
        return { rows: [{ received: "0" }] };
      }
      if (s.includes("FROM kinnect_core.store_packages WHERE user_id=$1 AND expires>$2")) {
        return { rows: state.storePackages.filter((p) => p.user_id === params[0] && p.expires > params[1]) };
      }
      if (s.includes("FROM kinnect_core.store_purchases WHERE user_id=$1 AND state='PURCHASED'")) {
        return { rows: state.storePurchases.filter((p) => p.user_id === params[0] && p.state === "PURCHASED") };
      }
      if (s.includes("information_schema.tables") && s.includes("apple_store_transactions")) {
        return { rows: [] };
      }
      if (s.includes("FROM kinnect_core.gift_inventory")) {
        const agg = new Map();
        for (const item of state.giftInventory) {
          if (item.user_id !== params[0] || item.quantity <= 0) continue;
          const k = `${item.gift_id}\0${item.source}`;
          agg.set(k, (agg.get(k) || 0) + item.quantity);
        }
        return {
          rows: [...agg.entries()].map(([k, q]) => {
            const [giftId, source] = k.split("\0");
            return { giftId, source, quantity: String(q) };
          }),
        };
      }
      if (s.includes("FROM kinnect_core.package_preferences")) return { rows: [] };
      if (s.includes("FROM kinnect_core.store_preferences")) return { rows: [] };
      if (s.includes("FROM kinnect_core.admin_package_events")) return { rows: [] };
      if (s.includes("FROM kinnect_core.store_packages WHERE user_id=$1 AND request_id=$2")) {
        return { rows: state.storePackages.filter((p) => p.user_id === params[0] && p.request_id === params[1]) };
      }
      if (s.startsWith("INSERT INTO kinnect_core.wallet_entries")) {
        state.walletEntries.push({
          id: params[0],
          user_id: params[1],
          reference: params[2],
          kind: params[3],
          coins: params[4],
        });
        return { rows: [] };
      }
      if (s.startsWith("INSERT INTO kinnect_core.store_packages")) {
        state.storePackages.push({
          user_id: params[0],
          request_id: params[1],
          product_id: params[2],
          expires: params[3],
        });
        return { rows: [] };
      }
      if (s.startsWith("INSERT INTO kinnect_core.gift_inventory")) {
        state.giftInventory.push({
          id: params[0],
          user_id: params[1],
          gift_id: params[2],
          quantity: params[3],
          source: params[4],
        });
        return { rows: [] };
      }
      return { rows: [] };
    },
  };

  // 1. Empty economy_config does not crash; permanent store_purchases >24h old remains owned; adminAccess=false
  const emptyState = await commerceState(mockClient, userId);
  assert.equal(emptyState.adminAccess, false);
  assert.equal(emptyState.unlimitedCoins, false);
  assert.equal(emptyState.configVersion, 1);
  assert.equal(emptyState.vndPerCoin, DEFAULT_ECONOMY.vndPerCoin);
  assert.ok(emptyState.owned.includes("kinnect_studio_pro"), "permanent purchase >24h old must stay owned");
  assert.equal(emptyState.studioProPermanent, true);

  const econRes = await commerceRoute({
    request: new Request("https://cloud.example/api/economy"),
    client: mockClient,
    user: { id: userId },
    json: jsonFn,
  });
  assert.equal(econRes.status, 200);
  assert.equal((await econRes.json()).vndPerCoin, DEFAULT_ECONOMY.vndPerCoin);

  // 2. effectivePrice prevents buying gift_love (base 300, 6x rose) for less than sum of giftPrices (6 * 100 = 600)
  state.economyRows = [
    {
      version: 2,
      data: { ...DEFAULT_ECONOMY, giftPrices: { ...DEFAULT_ECONOMY.giftPrices, rose: 100 } },
    },
  ];
  state.walletEntries.push({ id: "w1", user_id: userId, reference: "seed", kind: "admin_trial", coins: 300 });

  const storeRes = await commerceRoute({
    request: new Request("https://cloud.example/api/store"),
    client: mockClient,
    user: { id: userId },
    json: jsonFn,
  });
  assert.equal(storeRes.status, 200);
  const storeBody = await storeRes.json();
  assert.equal(storeBody.adminAccess, false);
  assert.equal(storeBody.packages.find((p) => p.id === "gift_love").priceCoins, 600);

  // priceCoins: 0 rejected with 400
  const zeroPriceRes = await commerceRoute({
    request: new Request("https://cloud.example/api/store/buy", {
      method: "POST",
      body: JSON.stringify({ productId: "gift_love", priceCoins: 0, requestId: "req_zero_price_0001" }),
    }),
    client: mockClient,
    user: { id: userId },
    json: jsonFn,
  });
  assert.equal(zeroPriceRes.status, 400);

  // Trying to buy at old base priceCoins: 300 rejected with 400
  const stalePriceRes = await commerceRoute({
    request: new Request("https://cloud.example/api/store/buy", {
      method: "POST",
      body: JSON.stringify({ productId: "gift_love", priceCoins: 300, requestId: "req_stale_price_0001" }),
    }),
    client: mockClient,
    user: { id: userId },
    json: jsonFn,
  });
  assert.equal(stalePriceRes.status, 400);

  // Trying to buy with only 300 coins fails with 402 (effectivePrice is 600)
  const lowFundsRes = await commerceRoute({
    request: new Request("https://cloud.example/api/store/buy", {
      method: "POST",
      body: JSON.stringify({ productId: "gift_love", priceCoins: 600, requestId: "req_low_funds_0001" }),
    }),
    client: mockClient,
    user: { id: userId },
    json: jsonFn,
  });
  assert.equal(lowFundsRes.status, 402);

  // Top up another 300 -> total 600, then /api/store/buy succeeds at 600
  state.walletEntries.push({ id: "w2", user_id: userId, reference: "seed2", kind: "admin_trial", coins: 300 });
  const buyOkRes = await commerceRoute({
    request: new Request("https://cloud.example/api/store/buy", {
      method: "POST",
      body: JSON.stringify({ productId: "gift_love", priceCoins: 600, requestId: "req_buy_valid_00001" }),
    }),
    client: mockClient,
    user: { id: userId },
    json: jsonFn,
  });
  assert.equal(buyOkRes.status, 200);
  const buyOkBody = await buyOkRes.json();
  assert.equal(buyOkBody.adminAccess, false);
  assert.equal(buyOkBody.adminPurchase, false);
  assert.equal(buyOkBody.giftedCoins, 0);
  assert.ok(buyOkBody.ownedPackages.includes("gift_love"));
});

// ---------------------------------------------------------------------------
// 3. W3B-03: mirrored_cloud_users skips signup coins + malformed password/salt never throws RangeError
// ---------------------------------------------------------------------------
test("Wave 4/5 [W3B-03]: mirrored_cloud_users suppresses welcome coins and malformed password/salt never crashes with RangeError", async (t) => {
  const { social, api, register } = await startApp(t);
  const db = social.db;

  // 1. User in mirrored_cloud_users gets NO signup_trial welcome coins
  const mirroredId = "cloud-mirrored-u1";
  db.prepare("INSERT OR IGNORE INTO mirrored_cloud_users(user_id) VALUES(?)").run(mirroredId);
  db.prepare(
    "INSERT INTO users(id,username,password,salt,name,birth_date,created,dm_mode) VALUES(?,?,?,?,?,?,?,'everyone')"
  ).run(mirroredId, "mirrored_user", "", "", "Mirrored User", "", Date.now());
  assert.equal(social.wallet.trialBalance(mirroredId), 0);
  assert.equal(
    db.prepare("SELECT COUNT(*) n FROM wallet_entries WHERE user_id=?").get(mirroredId).n,
    0
  );

  // 2. Normal local signup still receives welcome coins
  const local = await register("local_welcome_user");
  const wallet = await api("/wallet", { cookie: local.cookie });
  assert.equal(wallet.status, 200);
  assert.equal(wallet.body.trialCoins, DEFAULT_ECONOMY.signupBonusCoins);

  // 3. Malformed/empty password & salt on login & password-check endpoints return clean 400/401 (no RangeError)
  const malformedId = "malformed-pw-user";
  db.prepare(
    "INSERT INTO users(id,username,password,salt,name,birth_date,created,dm_mode,password_set) VALUES(?,?,?,?,?,?,?,'everyone',1)"
  ).run(malformedId, "malformed_pw", "", "", "Malformed PW", "", Date.now());

  const badLoginEmpty = await api("/login", {
    method: "POST",
    body: { username: "malformed_pw", password: "some-password-123" },
  });
  assert.equal(badLoginEmpty.status, 401);

  db.prepare("UPDATE users SET password='not-128-hex', salt='x' WHERE id=?").run(malformedId);
  const badLoginShortHex = await api("/login", {
    method: "POST",
    body: { username: "malformed_pw", password: "some-password-123" },
  });
  assert.equal(badLoginShortHex.status, 401);

  // Session for user with malformed password/salt -> /api/me/password & /api/me/2fa/setup return clean 400/401
  const tok = randomBytes(32).toString("hex");
  const digest = createHash("sha256").update(tok).digest("hex");
  db.prepare("INSERT INTO sessions VALUES(?,?,?)").run(digest, malformedId, Date.now() + 3600000);
  const cookie = `kinnect_session=${tok}`;

  const pwChange = await api("/me/password", {
    method: "POST",
    cookie,
    body: { current: "anything123", next: "BrandNewPass123!" },
  });
  assert.equal(pwChange.status, 400);

  const setup2fa = await api("/me/2fa/setup", {
    method: "POST",
    cookie,
    body: { password: "anything123" },
  });
  assert.equal(setup2fa.status, 401);

  // Postgres identity verifier also returns null cleanly without RangeError
  const pgIdentity = createPostgresIdentity({
    client: {
      query: async () => ({
        rows: [{ id: "pg-1", username: "pg_bad", password: "", salt: "", role: "user", suspended: 0, name: "Bad", created: 1, profile: {} }],
      }),
    },
  });
  assert.equal(await pgIdentity.verify("pg_bad", "any-password"), null);
});

// ---------------------------------------------------------------------------
// 4 & 5. W3B-06 / W3C-05 & W3C-07: Apple Sign-In agree18 replay protection + password_set=0 recent_auth flows
// ---------------------------------------------------------------------------
test("Wave 4/5 [W3C-07, W3B-06, W3C-05]: Apple missing agree18 preserves replay token, and password_set=0 account uses fresh recent_auth across password, recovery, and 2FA", async (t) => {
  const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const sentEmails = [];
  const { social, api } = await startApp(t, {
    appleKeyResolver: async () => publicKey,
    emailReady: () => true,
    emailSender: async (mail) => {
      sentEmails.push(mail);
      return true;
    },
  });

  const rawNonce = "wave5-apple-nonce-001";
  const hashedNonce = createHash("sha256").update(rawNonce).digest("hex");
  const idToken = signAppleToken(privateKey, {
    iss: "https://appleid.apple.com",
    aud: "app.kinnect.live",
    exp: Math.floor(Date.now() / 1000) + 600,
    sub: "apple-sub-w3c07",
    jti: "jti-w3c07-001",
    nonce: hashedNonce,
    email: "apple.member@example.com",
  });

  // W3C-07: Missing agree18: true returns 400 { requiresAgree18: true } WITHOUT burning apple_token_replay
  const missingAgree = await api("/auth/apple", {
    method: "POST",
    body: { identityToken: idToken, appleId: "apple-sub-w3c07", nonce: rawNonce },
  });
  assert.equal(missingAgree.status, 400);
  assert.equal(missingAgree.body.requiresAgree18, true);
  assert.equal(
    social.db.prepare("SELECT COUNT(*) n FROM apple_token_replay").get().n,
    0,
    "apple_token_replay must not be burned when agree18 is missing"
  );

  // Retry with the EXACT SAME token + agree18: true succeeds
  const appleOk = await api("/auth/apple", {
    method: "POST",
    body: {
      identityToken: idToken,
      appleId: "apple-sub-w3c07",
      nonce: rawNonce,
      agree18: true,
      acceptPrivacyNotice: true,
    },
  });
  assert.equal(appleOk.status, 200);
  assert.equal(appleOk.body.success, true);
  assert.ok(appleOk.cookie.startsWith("kinnect_session="));
  assert.equal(social.db.prepare("SELECT COUNT(*) n FROM apple_token_replay").get().n, 1);

  // Replay attempt with the same token now fails 401
  const replayRes = await api("/auth/apple", {
    method: "POST",
    body: {
      identityToken: idToken,
      appleId: "apple-sub-w3c07",
      nonce: rawNonce,
      agree18: true,
    },
  });
  assert.equal(replayRes.status, 401);

  // W3B-06 / W3C-05: Account has password_set = 0 (hasPassword: false)
  const meBefore = await api("/me", { cookie: appleOk.cookie });
  assert.equal(meBefore.status, 200);
  assert.equal(meBefore.body.user.hasPassword, false);

  // Fresh recent_auth allows POST /api/recovery/email/start without supplying password
  const recStart = await api("/recovery/email/start", {
    method: "POST",
    cookie: appleOk.cookie,
    body: { email: "recovery.oauth@example.com" },
  });
  assert.equal(recStart.status, 200, JSON.stringify(recStart.body));
  assert.ok(recStart.body.challengeId);
  assert.equal(sentEmails.length, 1);

  // Fresh recent_auth allows POST /api/me/2fa/setup without supplying password
  const setup2fa = await api("/me/2fa/setup", {
    method: "POST",
    cookie: appleOk.cookie,
    body: {},
  });
  assert.equal(setup2fa.status, 200, JSON.stringify(setup2fa.body));
  assert.ok(setup2fa.body.secret);

  // Stale recent_auth (>10 min) is rejected with 401 when password_set = 0
  const tok = appleOk.cookie.slice("kinnect_session=".length);
  const digest = createHash("sha256").update(tok).digest("hex");
  social.db.prepare("UPDATE recent_auth SET authenticated_at=? WHERE token=?").run(Date.now() - 11 * 60000, digest);

  const stalePw = await api("/me/password", {
    method: "POST",
    cookie: appleOk.cookie,
    body: { next: "NewStrongPassword123!" },
  });
  assert.equal(stalePw.status, 401);

  // Refresh recent_auth (<10 min) -> POST /api/me/password succeeds without current password, and hasPassword flips to true
  social.db.prepare("UPDATE recent_auth SET authenticated_at=? WHERE token=?").run(Date.now(), digest);
  const setPw = await api("/me/password", {
    method: "POST",
    cookie: appleOk.cookie,
    body: { next: "NewStrongPassword123!" },
  });
  assert.equal(setPw.status, 200);
  assert.equal(setPw.body.ok, true);

  const meAfter = await api("/me", { cookie: appleOk.cookie });
  assert.equal(meAfter.status, 200);
  assert.equal(meAfter.body.user.hasPassword, true);
});

// ---------------------------------------------------------------------------
// 6. W5B-01: cloud-api/notification-routes.js tolerates malformed non-JSON direct_pair
// ---------------------------------------------------------------------------
test("Wave 5 [W5B-01]: GET /api/notifications returns 200 when chat_conversations.direct_pair is malformed non-JSON", async (t) => {
  const chatDb = new DatabaseSync(":memory:");
  t.after(() => chatDb.close());
  chatDb.exec(`
    CREATE TABLE chat_conversations(id TEXT PRIMARY KEY, kind TEXT NOT NULL, direct_pair TEXT, name TEXT, created_by TEXT, created_at INTEGER);
    CREATE TABLE chat_members(conversation_id TEXT, user_id TEXT, role TEXT, joined_at INTEGER, left_at INTEGER);
    CREATE TABLE chat_messages(id TEXT PRIMARY KEY, conversation_id TEXT, sender_id TEXT, body TEXT, created_at INTEGER, recalled_at INTEGER);
    CREATE TABLE chat_hidden_messages(message_id TEXT, user_id TEXT);
    CREATE TABLE chat_receipts(message_id TEXT, user_id TEXT, delivered_at INTEGER, seen_at INTEGER, PRIMARY KEY(message_id, user_id));
    CREATE TABLE chat_preferences(conversation_id TEXT, user_id TEXT, hidden INTEGER DEFAULT 0, muted INTEGER DEFAULT 0, pinned INTEGER DEFAULT 0, unread INTEGER DEFAULT 0, PRIMARY KEY(conversation_id, user_id));
  `);

  const now = Date.now();
  chatDb.prepare("INSERT INTO chat_conversations VALUES('conv-1','direct','dm-abc123','','u-actor',?)").run(now - 5000);
  chatDb.prepare("INSERT INTO chat_members VALUES('conv-1','u-viewer','member',?,NULL)").run(now - 10000);
  chatDb.prepare("INSERT INTO chat_members VALUES('conv-1','u-actor','member',?,NULL)").run(now - 10000);
  chatDb.prepare("INSERT INTO chat_messages VALUES('msg-1','conv-1','u-actor','Xin chao!',?,NULL)").run(now - 1000);
  chatDb.prepare("INSERT INTO chat_preferences VALUES('conv-1','u-viewer',0,1,0,1)").run();

  const d1Shim = {
    prepare(sql) {
      return {
        bind(...args) {
          return {
            run: async () => {
              chatDb.prepare(sql).run(...args);
              return { success: true };
            },
            all: async () => ({ results: chatDb.prepare(sql).all(...args) }),
          };
        },
      };
    },
  };

  const pgClient = {
    async query(sql, params = []) {
      const s = sql.replace(/\s+/g, " ").trim();
      if (s.includes("FROM kinnect_core.notifications")) {
        return {
          rows: [
            {
              id: "n-1",
              user_id: "u-viewer",
              actor: "u-actor",
              kind: "message",
              ref: "msg-1",
              seen: 0,
              created: now - 500,
            },
          ],
        };
      }
      if (s.includes("FROM kinnect_core.users WHERE id=ANY")) {
        return {
          rows: [
            { id: "u-actor", username: "actor1", name: "Actor One", avatar: null, role: "user", suspended: 0, created: 1000 },
          ],
        };
      }
      if (s.includes("FROM kinnect_core.friendships")) {
        return { rows: [{ n: "0" }] };
      }
      return { rows: [] };
    },
  };

  const res = await notificationRoute({
    request: new Request("https://cloud.example/api/notifications", { method: "GET" }),
    env: { CHAT_DB: d1Shim },
    client: pgClient,
    user: { id: "u-viewer" },
    json: jsonFn,
  });

  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.notifications.length, 1);
  assert.equal(body.notifications[0].preview, "Xin chao!");
  assert.equal(body.notifications[0].muted, false);
});

// ---------------------------------------------------------------------------
// 7. W5B-04: lib/kinnect-ai.js drain() processes moderation when support=0, moderation=1
// ---------------------------------------------------------------------------
test("Wave 5 [W5B-04]: kinnect-ai drain() processes moderation job even when older support job is queued and support=0", async (t) => {
  const social = openSocial(":memory:");
  t.after(() => social.close());

  social.db
    .prepare("INSERT INTO users(id,username,password,salt,name,birth_date,created,role) VALUES(?,?,?,?,?,?,?,?)")
    .run("u-ai-1", "ai_author", "p", "s", "AI Author", "", 1000, "user");

  const calls = [];
  const ai = createKinnectAI({
    db: social.db,
    user: (id) => social.user(id),
    blocked: (a, b) => social.blocked(a, b),
    notice: () => {},
    messageState: { reveal: () => {} },
    env: {
      KINNECT_AI_URL: "https://kinnect-ai.vuanh97nd.workers.dev",
      KINNECT_API_TOKEN: "tok_" + "a".repeat(40),
    },
    send: async (url) => {
      calls.push(String(url));
      return Response.json({ decision: "allow", reason: "ok", evidence: "" });
    },
  });
  t.after(() => ai.close());

  // Enable moderation=1, keep support=0
  social.db.prepare("UPDATE ai_settings SET support=0, moderation=1 WHERE id=1").run();

  // Queue an older support job (created=1000) and a newer moderation ('post') job (created=2000)
  social.db
    .prepare("INSERT INTO ai_jobs(id,kind,target,actor,payload,state,attempts,result,created,updated,dedupe) VALUES(?,?,?,?,?,'queued',0,'',?,?,'dedupe-sup')")
    .run("job-support-old", "support", "msg-1", "u-ai-1", JSON.stringify({ text: "hello" }), 1000, 1000);
  social.db
    .prepare("INSERT INTO ai_jobs(id,kind,target,actor,payload,state,attempts,result,created,updated,dedupe) VALUES(?,?,?,?,?,'queued',0,'',?,?,'dedupe-mod')")
    .run("job-mod-new", "post", "post-1", "u-ai-1", JSON.stringify({ text: "nice photo" }), 2000, 2000);

  await ai.drain();

  assert.equal(calls.length, 1);
  assert.ok(calls[0].endsWith("/v1/moderate"), `expected /v1/moderate call, got ${calls[0]}`);
  assert.equal(social.db.prepare("SELECT state FROM ai_jobs WHERE id='job-mod-new'").get().state, "done");
  assert.equal(social.db.prepare("SELECT state FROM ai_jobs WHERE id='job-support-old'").get().state, "queued");
});

// ---------------------------------------------------------------------------
// 8. W5B-09: lib/webpush.js safety & privacy guarantees
// ---------------------------------------------------------------------------
test("Wave 5 [W5B-09]: webpush sends 0 pushes for suspended recipient, blocked caller, non-member group_message, and leaks 0 previews for recalled/hidden messages", async (t) => {
  const social = openSocial(":memory:");
  t.after(() => social.close());
  const db = social.db;

  const mkUser = (id, suspended = 0) =>
    db
      .prepare("INSERT INTO users(id,username,password,salt,name,birth_date,created,role,suspended) VALUES(?,?,?,?,?,?,?,'user',?)")
      .run(id, id, "p", "s", "Name " + id, "", 1000, suspended);

  mkUser("u-recv", 0);
  mkUser("u-susp", 1);
  mkUser("u-actor", 0);
  mkUser("u-blocked", 0);

  db.prepare("INSERT INTO blocks(actor,target) VALUES('u-recv','u-blocked')").run();
  db.prepare("INSERT INTO chat_groups(id,name,owner,created) VALUES('grp-1','Group 1','u-actor',1000)").run();
  db.prepare("INSERT INTO group_members(group_id,user_id,joined,seen_at) VALUES('grp-1','u-actor',1000,0)").run();

  const pushes = [];
  const webpush = createWebPush({
    social,
    fetchImpl: async (endpoint, init) => {
      pushes.push({ endpoint, body: Buffer.from(init.body) });
      return new Response(null, { status: 201 });
    },
  });

  const subKeys = (userId) => {
    const ecdh = createECDH("prime256v1");
    ecdh.generateKeys();
    const authSecret = randomBytes(16);
    const ok = webpush.subscribe(userId, {
      endpoint: `https://push.test/sub/${userId}`,
      keys: {
        p256dh: ecdh.getPublicKey().toString("base64url"),
        auth: authSecret.toString("base64url"),
      },
    });
    assert.equal(ok, true);
    return { priv: ecdh.getPrivateKey(), auth: authSecret };
  };

  const recvKeys = subKeys("u-recv");
  subKeys("u-susp");

  // 1. Suspended recipient -> 0 pushes on notification & call
  db.prepare("INSERT INTO notifications(id,user_id,actor,kind,ref,seen,created) VALUES('n-susp','u-susp','u-actor','like','p1',0,1000)").run();
  webpush.notification("u-susp", "n-susp");
  await webpush.call("u-susp", { id: "c-susp", mode: "audio" }, { id: "u-actor", name: "Actor" });

  // 2. Blocked caller/actor -> 0 pushes on notification & call
  db.prepare("INSERT INTO notifications(id,user_id,actor,kind,ref,seen,created) VALUES('n-blk','u-recv','u-blocked','message','m-blk',0,1000)").run();
  webpush.notification("u-recv", "n-blk");
  await webpush.call("u-recv", { id: "c-blk", mode: "video" }, { id: "u-blocked", name: "Blocked" });

  // 3. Non-member on group_message -> 0 pushes
  db.prepare("INSERT INTO group_messages(id,group_id,sender,body,created) VALUES('gm-1','grp-1','u-actor','Group secret',1000)").run();
  db.prepare("INSERT INTO notifications(id,user_id,actor,kind,ref,seen,created) VALUES('n-nonmem','u-recv','u-actor','group_message','grp-1',0,1000)").run();
  webpush.notification("u-recv", "n-nonmem");

  await new Promise((r) => setTimeout(r, 120));
  assert.equal(pushes.length, 0, "suspended/blocked/non-member must send 0 pushes");

  // 4. Recalled or hidden direct message -> 0 pushes when seen=1, and 0 preview leaked even if seen=0
  db.prepare("INSERT INTO messages(id,sender,recipient,body,created) VALUES('m-recalled','u-actor','u-recv','TOP_SECRET_RECALLED',2000)").run();
  db.prepare("INSERT INTO recalled_chat_messages(kind,message_id,created) VALUES('direct','m-recalled',2001)").run();
  db.prepare("INSERT INTO notifications(id,user_id,actor,kind,ref,seen,created) VALUES('n-rec-seen','u-recv','u-actor','message','m-recalled',1,2000)").run();
  webpush.notification("u-recv", "n-rec-seen");
  await new Promise((r) => setTimeout(r, 120));
  assert.equal(pushes.length, 0, "recalled notification marked seen sends 0 pushes");

  db.prepare("INSERT INTO messages(id,sender,recipient,body,created) VALUES('m-hidden','u-actor','u-recv','TOP_SECRET_HIDDEN',2100)").run();
  db.prepare("INSERT INTO hidden_chat_messages(kind,message_id,user_id) VALUES('direct','m-hidden','u-recv')").run();
  db.prepare("INSERT INTO notifications(id,user_id,actor,kind,ref,seen,created) VALUES('n-rec-unseen','u-recv','u-actor','message','m-recalled',0,2000)").run();
  db.prepare("INSERT INTO notifications(id,user_id,actor,kind,ref,seen,created) VALUES('n-hid-unseen','u-recv','u-actor','message','m-hidden',0,2100)").run();

  webpush.notification("u-recv", "n-rec-unseen");
  webpush.notification("u-recv", "n-hid-unseen");
  await new Promise((r) => setTimeout(r, 120));

  for (const p of pushes) {
    const decrypted = decryptWebPushPayload(p.body, recvKeys.priv, recvKeys.auth);
    assert.ok(!decrypted.body.includes("TOP_SECRET_RECALLED"), "recalled body preview must never leak");
    assert.ok(!decrypted.body.includes("TOP_SECRET_HIDDEN"), "hidden body preview must never leak");
    assert.equal(decrypted.body, "đã gửi cho bạn một tin nhắn");
  }
});

// ---------------------------------------------------------------------------
// 9. W5B-11: lib/chat-attachments.js accepts data:audio/webm;codecs=opus;base64,...
// ---------------------------------------------------------------------------
test("Wave 5 [W5B-11]: chat-attachments accepts data:audio/webm;codecs=opus;base64,... data URLs", async (t) => {
  const { api, register, origin } = await startApp(t);
  const alice = await register("voice_sender");
  const bob = await register("voice_receiver");

  // Valid EBML/WebM header (0x1a 0x45 0xdf 0xa3)
  const webmPayload = Buffer.from([0x1a, 0x45, 0xdf, 0xa3, 0x9f, 0x42, 0x86, 0x81, 0x01]);
  const dataUrl = "data:audio/webm;codecs=opus;base64," + webmPayload.toString("base64");

  const sendRes = await api(`/users/${bob.user.id}/messages`, {
    method: "POST",
    cookie: alice.cookie,
    body: {
      body: "",
      attachment: { name: "voice-note.webm", data: dataUrl },
    },
  });
  assert.equal(sendRes.status, 201, JSON.stringify(sendRes.body));
  assert.equal(sendRes.body.message.attachment.type, "audio/webm");
  assert.equal(sendRes.body.message.attachment.kind, "audio");

  const dlRes = await fetch(origin + sendRes.body.message.attachment.url, {
    headers: { Cookie: bob.cookie },
  });
  assert.equal(dlRes.status, 200);
  assert.equal(dlRes.headers.get("content-type"), "audio/webm");
});

// ---------------------------------------------------------------------------
// 10. W5B-14 / W5B-15 / W5B-17: password-reset guards, operations toggle-maintenance guard, ticket transfer clears assignee
// ---------------------------------------------------------------------------
test("Wave 5 [W5B-14, W5B-15, W5B-17]: closed/admin password resets rejected, operations blocked from toggle-maintenance, ticket transfer clears assignee", async (t) => {
  const { social, api, register, consoleReq } = await startApp(t);
  const db = social.db;
  t.after(() => {
    delete global.__KINNECT_MAINTENANCE_MODE;
  });

  const admin = await register("console_admin_w5");
  const member = await register("console_member_w5");
  db.prepare("UPDATE users SET role='admin' WHERE id=?").run(admin.user.id);

  // Admin login to admin console
  const adminConsoleLogin = await consoleReq("/api/console/login", {
    portal: "admin",
    method: "POST",
    data: { username: admin.user.username, password: "strong-pass-123" },
  });
  assert.equal(adminConsoleLogin.status, 200);
  const adminConsoleCookie = adminConsoleLogin.cookie;

  // W5B-14: Closed password-reset ticket returns 409; admin target reset returns 403
  const closedResetId = randomUUID();
  const adminResetId = randomUUID();
  db.prepare("INSERT INTO password_resets(id,username,user_id,contact,note,status,created,handled) VALUES(?,?,?,?,?,?,?,?)").run(
    closedResetId,
    member.user.username,
    member.user.id,
    "member@example.com",
    "",
    "done",
    Date.now(),
    Date.now()
  );
  db.prepare("INSERT INTO password_resets(id,username,user_id,contact,note,status,created) VALUES(?,?,?,?,?,?,?)").run(
    adminResetId,
    admin.user.username,
    admin.user.id,
    "admin@example.com",
    "",
    "open",
    Date.now()
  );

  // Test via /api/admin/password-resets/:id/reset (lib/social.js)
  assert.equal(
    (await api(`/admin/password-resets/${closedResetId}/reset`, { method: "POST", cookie: admin.cookie })).status,
    409
  );
  assert.equal(
    (await api(`/admin/password-resets/${adminResetId}/reset`, { method: "POST", cookie: admin.cookie })).status,
    403
  );

  // Test via /api/console/resets (lib/admin-console.js)
  assert.equal(
    (await consoleReq("/api/console/resets", { portal: "admin", method: "POST", cookie: adminConsoleCookie, data: { id: closedResetId, action: "reset" } })).status,
    409
  );
  assert.equal(
    (await consoleReq("/api/console/resets", { portal: "admin", method: "POST", cookie: adminConsoleCookie, data: { id: adminResetId, action: "reset" } })).status,
    403
  );

  // W5B-15: operations staff blocked (403) from toggle-maintenance
  const staffSalt = "ops-salt-12345678";
  const staffPass = "OpsStrongPassword123!";
  db.prepare("INSERT INTO console_staff(id,username,name,password,salt,suspended,must_change,created,team) VALUES(?,?,?,?,?,0,0,?,?)").run(
    "ops-staff-1",
    "ops_tech_01",
    "Ops Tech",
    scryptHex(staffPass, staffSalt),
    staffSalt,
    Date.now(),
    "operations"
  );
  const opsLogin = await consoleReq("/api/console/login", {
    portal: "kythuat",
    method: "POST",
    data: { username: "ops_tech_01", password: staffPass },
  });
  assert.equal(opsLogin.status, 200);

  const toggleAttempt = await consoleReq("/api/console/operations/action", {
    portal: "kythuat",
    method: "POST",
    cookie: opsLogin.cookie,
    data: { action: "toggle-maintenance" },
  });
  assert.equal(toggleAttempt.status, 403);
  assert.ok(!global.__KINNECT_MAINTENANCE_MODE);

  // W5B-17: Transferring a ticket between support and finance via action: 'process' clears stale assignee to null
  db.prepare("INSERT INTO console_staff(id,username,name,password,salt,suspended,must_change,created,team) VALUES(?,?,?,?,?,0,0,?,?)").run(
    "sup-staff-1",
    "support_01",
    "Support One",
    scryptHex(staffPass, staffSalt),
    staffSalt,
    Date.now(),
    "support"
  );
  db.prepare("INSERT INTO console_staff(id,username,name,password,salt,suspended,must_change,created,team) VALUES(?,?,?,?,?,0,0,?,?)").run(
    "fin-staff-1",
    "finance_01",
    "Finance One",
    scryptHex(staffPass, staffSalt),
    staffSalt,
    Date.now(),
    "finance"
  );

  const supLogin = await consoleReq("/api/console/login", {
    portal: "hotro",
    method: "POST",
    data: { username: "support_01", password: staffPass },
  });
  assert.equal(supLogin.status, 200);

  const finLogin = await consoleReq("/api/console/login", {
    portal: "taichinh",
    method: "POST",
    data: { username: "finance_01", password: staffPass },
  });
  assert.equal(finLogin.status, 200);

  // Admin creates ticket assigned to support staff
  const createdTicket = await consoleReq("/api/console/tickets", {
    portal: "admin",
    method: "POST",
    cookie: adminConsoleCookie,
    data: {
      subject: "Refund dispute",
      description: "Check wallet ledger",
      team: "support",
      assignee: "sup-staff-1",
    },
  });
  assert.equal(createdTicket.status, 200);
  const ticket = createdTicket.body.ticket;
  assert.equal(ticket.team, "support");
  assert.equal(ticket.assignee, "sup-staff-1");

  // Support transfers ticket to finance via action: 'process' -> assignee cleared to null
  const toFinance = await consoleReq(`/api/console/tickets/${ticket.id}/events`, {
    portal: "hotro",
    method: "POST",
    cookie: supLogin.cookie,
    data: {
      action: "process",
      team: "finance",
      version: ticket.version,
      message: "Chuyển sang tài chính đối soát",
    },
  });
  assert.equal(toFinance.status, 200);
  assert.equal(toFinance.body.ticket.team, "finance");
  assert.equal(toFinance.body.ticket.assignee, null);
  assert.equal(toFinance.body.ticket.assigneeUsername, null);

  // Admin assigns a finance staff member, then finance transfers back to support via action: 'process' -> assignee cleared to null
  const assignFin = await consoleReq(`/api/console/tickets/${ticket.id}/events`, {
    portal: "admin",
    method: "POST",
    cookie: adminConsoleCookie,
    data: {
      action: "assign",
      assignee: "fin-staff-1",
      version: toFinance.body.ticket.version,
    },
  });
  assert.equal(assignFin.status, 200);
  assert.equal(assignFin.body.ticket.assignee, "fin-staff-1");

  const toSupport = await consoleReq(`/api/console/tickets/${ticket.id}/events`, {
    portal: "taichinh",
    method: "POST",
    cookie: finLogin.cookie,
    data: {
      action: "process",
      team: "support",
      version: assignFin.body.ticket.version,
      message: "Chuyển lại bộ phận hỗ trợ",
    },
  });
  assert.equal(toSupport.status, 200);
  assert.equal(toSupport.body.ticket.team, "support");
  assert.equal(toSupport.body.ticket.assignee, null);
});

// ---------------------------------------------------------------------------
// 11. W5W-13 (W3B-26): POST /internal/admin/invalidate-auth
// ---------------------------------------------------------------------------
test("Wave 5 [W5W-13, W3B-26]: /internal/admin/invalidate-auth rejects forwarded/wrong-secret requests, flushes fastAuthCache, and closes WS with 4401", async (t) => {
  const internalSecret = "wave5-internal-secret-2026-key";
  const { social, origin, api, register, connectWs } = await startApp(t, { internalSecret });

  const target = await register("invalidate_target");
  const { ws } = await connectWs(target.cookie);

  const wsClosed = new Promise((resolve) => {
    ws.once("close", (code, reason) => resolve({ code, reason: reason.toString() }));
  });

  // Populate fastAuthCache with an authenticated request
  assert.equal((await api("/me", { cookie: target.cookie })).status, 200);

  // 1. Reject X-Forwarded-For / CF-Connecting-IP (403) and wrong/missing secret (401)
  const forwardedRes = await fetch(origin + "/internal/admin/invalidate-auth", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Kinnect-Internal": internalSecret,
      "X-Forwarded-For": "203.0.113.5",
    },
    body: JSON.stringify({ userId: target.user.id }),
  });
  assert.equal(forwardedRes.status, 403);

  const cfRes = await fetch(origin + "/internal/admin/invalidate-auth", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Kinnect-Internal": internalSecret,
      "CF-Connecting-IP": "203.0.113.6",
    },
    body: JSON.stringify({ userId: target.user.id }),
  });
  assert.equal(cfRes.status, 403);

  const wrongSecretRes = await fetch(origin + "/internal/admin/invalidate-auth", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Kinnect-Internal": "wrong-secret-value-123456",
    },
    body: JSON.stringify({ userId: target.user.id }),
  });
  assert.equal(wrongSecretRes.status, 401);

  const missingSecretRes = await fetch(origin + "/internal/admin/invalidate-auth", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ userId: target.user.id }),
  });
  assert.equal(missingSecretRes.status, 401);

  // 2. Temporarily exercise real fastAuthCache hit path (bypassing NODE_TEST_CONTEXT guard)
  const savedTestContext = process.env.NODE_TEST_CONTEXT;
  t.after(() => {
    if (savedTestContext !== undefined) process.env.NODE_TEST_CONTEXT = savedTestContext;
  });

  // Suspend user directly in SQLite; while fastAuthCache is still warm (<5s), /api/me serves cached row
  social.db.prepare("UPDATE users SET suspended=1 WHERE id=?").run(target.user.id);
  delete process.env.NODE_TEST_CONTEXT;
  const cachedHit = await api("/me", { cookie: target.cookie });
  assert.equal(cachedHit.status, 200, "sanity check: fastAuthCache serves cached auth before invalidation");

  // 3. Valid loopback call with internalSecret invalidates fastAuthCache & closes WS with 4401
  const okRes = await fetch(origin + "/internal/admin/invalidate-auth", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Kinnect-Internal": internalSecret,
    },
    body: JSON.stringify({ userId: target.user.id }),
  });
  assert.equal(okRes.status, 200);
  assert.equal((await okRes.json()).ok, true);

  const closeInfo = await wsClosed;
  assert.equal(closeInfo.code, 4401);

  const afterInvalidation = await api("/me", { cookie: target.cookie });
  assert.equal(afterInvalidation.status, 401, "fastAuthCache must be evicted immediately after invalidate-auth");
});
