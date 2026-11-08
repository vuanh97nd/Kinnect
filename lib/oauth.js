// Đăng nhập bằng Google và Facebook (OAuth 2.0, luồng authorization code, chạy phía máy chủ).
// Cấu hình bằng biến môi trường (hoặc file oauth.env ở thư mục chạy):
//   PUBLIC_URL=https://app.kinnect.io.vn
//   GOOGLE_CLIENT_ID=...  GOOGLE_CLIENT_SECRET=...
//   FACEBOOK_APP_ID=...   FACEBOOK_APP_SECRET=...
// Thiếu khóa của nhà cung cấp nào thì nút đăng nhập tương ứng không hiện.
import { createHash, randomBytes, randomUUID, createVerify, createPublicKey } from "node:crypto";

const FB_VERSION = "v21.0";
const PROVIDERS = {
  google: {
    id: () => process.env.GOOGLE_CLIENT_ID,
    secret: () => process.env.GOOGLE_CLIENT_SECRET,
    authorize: "https://accounts.google.com/o/oauth2/v2/auth",
    token: "https://oauth2.googleapis.com/token",
    scope: "openid email profile",
    async profile(accessToken, fetchImpl) {
      const r = await fetchImpl("https://openidconnect.googleapis.com/v1/userinfo", {
        headers: { Authorization: "Bearer " + accessToken },
      });
      if (!r.ok) throw Error("Google không trả thông tin tài khoản.");
      const p = await r.json();
      return { subject: p.sub, email: p.email_verified ? p.email : "", name: p.name || "" };
    },
  },
  facebook: {
    id: () => process.env.FACEBOOK_APP_ID,
    secret: () => process.env.FACEBOOK_APP_SECRET,
    authorize: `https://www.facebook.com/${FB_VERSION}/dialog/oauth`,
    token: `https://graph.facebook.com/${FB_VERSION}/oauth/access_token`,
    scope: "public_profile,email",
    async profile(accessToken, fetchImpl) {
      const r = await fetchImpl(
        `https://graph.facebook.com/${FB_VERSION}/me?fields=id,name,email`,
        { headers: { Authorization: "Bearer " + accessToken } },
      );
      if (!r.ok) throw Error("Facebook không trả thông tin tài khoản.");
      const p = await r.json();
      return { subject: p.id, email: p.email || "", name: p.name || "" };
    },
  },
};

export function createOAuth({ db, get, run, user, fail, startSession, sharedSession = null, fetchImpl = fetch, appleKeyResolver = null }) {
  let cachedAppleJwks = null;
  let cachedAppleJwksExpiry = 0;
  db.exec(
    "CREATE TABLE IF NOT EXISTS oauth_accounts(provider TEXT NOT NULL,subject TEXT NOT NULL,user_id TEXT NOT NULL REFERENCES users(id),email TEXT NOT NULL DEFAULT '',created INTEGER NOT NULL,PRIMARY KEY(provider,subject))",
  );
  db.exec(
    "CREATE TABLE IF NOT EXISTS apple_token_replay(replay_id TEXT PRIMARY KEY, expires INTEGER NOT NULL)",
  );
  let jwksRefresh = null;
  // Người đăng nhập lần đầu: giữ tạm thông tin 15 phút để họ xác nhận 18+ và chọn tên đăng nhập.
  const providerFetch = (url, options = {}) => fetchImpl(url, { ...options, signal: AbortSignal.timeout(10000) });
  const pending = new Map();
  // Ứng dụng Android: trình duyệt trả về kinnect://oauth kèm mã dùng một lần (60 giây) để app đổi lấy phiên.
  const appCodes = new Map();
  const appLink = (query) => "kinnect://oauth?" + new URLSearchParams(query);
  const enabled = () =>
    Object.keys(PROVIDERS).filter((p) => PROVIDERS[p].id() && PROVIDERS[p].secret());
  const base = () => (process.env.PUBLIC_URL || "").replace(/\/$/, "");
  const callbackUrl = (provider) => base() + "/api/oauth/" + provider + "/callback";
  const cookie = (req, name) =>
    (req.headers.cookie || "")
      .split(";")
      .map((x) => x.trim())
      .find((x) => x.startsWith(name + "="))
      ?.slice(name.length + 1);
  const secure = () => (process.env.SECURE_COOKIES === "1" ? "; Secure" : "");
  // Trang trung gian: chuyển về app bằng meta refresh để cookie SameSite=Strict được gửi kèm.
  const finish = (res, location, headers = {}) => {
    res.writeHead(200, {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
      "Content-Security-Policy": "default-src 'none'",
      ...headers,
    });
    res.end(
      `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><meta http-equiv="refresh" content="0;url=${location.replace(/&/g, "&amp;")}"><title>Kinnect</title><p>Đang chuyển về Kinnect…</p><p><a href="${location.replace(/&/g, "&amp;")}">Mở lại Kinnect</a></p>`,
    );
  };
  const suggestUsername = (email, name) => {
    const raw = (email.split("@")[0] || name || "ban")
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "")
      .replace(/đ/gi, "d")
      .toLowerCase()
      .replace(/[^a-z0-9_]/g, "")
      .slice(0, 24);
    let candidate = raw.length >= 3 ? raw : "ban_" + raw;
    while (get("SELECT 1 FROM users WHERE username=?", candidate))
      candidate = (raw.slice(0, 20) || "ban") + "_" + randomBytes(2).toString("hex");
    return candidate;
  };

  // Khi cầu PC↔cloud bật, phiên phải do Postgres dùng chung cấp để các API chia sẻ chấp nhận;
  // vẫn gương token sang SQLite cục bộ để các handler nội bộ xác thực được.
  const issueCookie = (req) => async (account) => {
    if (sharedSession) {
      try {
        const token = await sharedSession({
          id: account.id,
          username: account.username,
          name: account.name,
          role: account.role || (user(account.id) || {}).role || "user",
        });
        if (token) {
          const digest = createHash("sha256").update(token).digest("hex");
          run("INSERT INTO sessions(token,user_id,expires) VALUES(?,?,?) ON CONFLICT(token) DO UPDATE SET expires=excluded.expires", digest, account.id, Date.now() + 7 * 86400000);
          run("INSERT OR IGNORE INTO session_info(token,label,created) VALUES(?,?,?)", digest, "OAuth", Date.now());
          return `kinnect_session=${token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=604800${secure()}`;
        }
      } catch (error) {
        console.error("[oauth] shared session", error.message);
      }
    }
    return startSession(account.id, req);
  };
  return async function oauthApi(req, res, path, json, body) {
    const sessionCookie = issueCookie(req);
    if (path === "/api/oauth/providers") return json(200, { providers: enabled() });

    const start = path.match(/^\/api\/oauth\/(google|facebook)\/start$/);
    if (start && req.method === "GET") {
      const provider = start[1];
      const p = PROVIDERS[provider];
      if (!enabled().includes(provider)) fail(404, "Chưa bật đăng nhập bằng " + provider + ".");
      const state = randomBytes(24).toString("hex");
      const client = new URL(req.url, "http://local").searchParams.get("client") === "android" ? "android" : "web";
      const url = new URL(p.authorize);
      url.search = new URLSearchParams({
        client_id: p.id(),
        redirect_uri: callbackUrl(provider),
        response_type: "code",
        scope: p.scope,
        state,
        ...(provider === "google" ? { prompt: "select_account" } : {}),
      });
      res.writeHead(302, {
        Location: url.toString(),
        "Cache-Control": "no-store",
        // Lax để cookie được gửi khi Google/Facebook chuyển hướng về.
        "Set-Cookie": `kinnect_oauth=${provider}.${state}.${client}; HttpOnly; SameSite=Lax; Path=/api/oauth; Max-Age=600${secure()}`,
      });
      return res.end();
    }

    const cb = path.match(/^\/api\/oauth\/(google|facebook)\/callback$/);
    if (cb && req.method === "GET") {
      const provider = cb[1];
      const p = PROVIDERS[provider];
      const q = new URL(req.url, "http://local").searchParams;
      const clear = `kinnect_oauth=; HttpOnly; SameSite=Lax; Path=/api/oauth; Max-Age=0${secure()}`;
      const stored = cookie(req, "kinnect_oauth") || "";
      const android = stored.endsWith(".android");
      const expected = stored.replace(/\.(android|web)$/, "");
      const back = (web, query) => finish(res, android ? appLink(query) : web, { "Set-Cookie": clear });
      if (q.get("error") || !q.get("code")) return back("/?oauth_error=cancelled", { error: "cancelled" });
      if (!expected || expected !== provider + "." + q.get("state")) return back("/?oauth_error=state", { error: "state" });
      let profile;
      try {
        const t = await providerFetch(p.token, {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({
            client_id: p.id(),
            client_secret: p.secret(),
            code: q.get("code"),
            redirect_uri: callbackUrl(provider),
            grant_type: "authorization_code",
          }),
        });
        const token = await t.json();
        if (!t.ok || !token.access_token) throw Error("Không đổi được mã đăng nhập.");
        profile = await p.profile(token.access_token, providerFetch);
        if (!profile.subject) throw Error("Thiếu mã tài khoản.");
      } catch (e) {
        console.error("[oauth]", provider, e.message);
        return back("/?oauth_error=provider", { error: "provider" });
      }
      const link = get(
        "SELECT user_id FROM oauth_accounts WHERE provider=? AND subject=?",
        provider,
        String(profile.subject),
      );
      const linked = link && user(link.user_id);
      if (linked) {
        if (linked.suspended) return back("/?oauth_error=suspended", { error: "suspended" });
        if (android) {
          const code = randomBytes(24).toString("hex");
          for (const [k, v] of appCodes) if (v.expires < Date.now()) appCodes.delete(k);
          appCodes.set(code, { userId: linked.id, expires: Date.now() + 60000 });
          return back("/", { code });
        }
        return finish(res, "/", { "Set-Cookie": [clear, await sessionCookie(linked)] });
      }
      const ticket = randomBytes(24).toString("hex");
      for (const [k, v] of pending) if (v.expires < Date.now()) pending.delete(k);
      pending.set(ticket, {
        provider,
        subject: String(profile.subject),
        email: profile.email,
        name: profile.name.slice(0, 60),
        expires: Date.now() + 15 * 60000,
      });
      return back("/?oauth=complete&ticket=" + ticket, { ticket });
    }

    if (path === "/api/oauth/app-session" && req.method === "POST") {
      const b = await body(req, 2000);
      const v = appCodes.get(typeof b.code === "string" ? b.code : "");
      appCodes.delete(b.code);
      const u = v && v.expires >= Date.now() && user(v.userId);
      if (!u || u.suspended) fail(401, "Phiên đăng nhập đã hết hạn. Hãy thử lại.");
      return json(200, { user: { id: u.id, username: u.username, name: u.name } }, { "Set-Cookie": await sessionCookie({ id: u.id, username: u.username, name: u.name }) });
    }

    if (path === "/api/oauth/pending" && req.method === "GET") {
      const v = pending.get(new URL(req.url, "http://local").searchParams.get("ticket") || "");
      if (!v || v.expires < Date.now()) fail(404, "Phiên đăng nhập đã hết hạn. Hãy thử lại.");
      return json(200, {
        provider: v.provider,
        name: v.name,
        suggestedUsername: suggestUsername(v.email, v.name),
      });
    }

    if (path === "/api/oauth/complete" && req.method === "POST") {
      const b = await body(req, 4000);
      const v = pending.get(typeof b.ticket === "string" ? b.ticket : "");
      if (!v || v.expires < Date.now()) fail(404, "Phiên đăng nhập đã hết hạn. Hãy thử lại.");
      if (b.agree18 !== true) fail(400, "Cần xác nhận bạn đủ 18 tuổi.");
      const username = (typeof b.username === "string" ? b.username : "").trim().toLowerCase();
      if (!/^[a-z0-9_]{3,30}$/.test(username))
        fail(400, "Tên đăng nhập 3–30 chữ không dấu, số hoặc gạch dưới.");
      if (get("SELECT 1 FROM users WHERE username=?", username))
        fail(409, "Tên đăng nhập đã được dùng.");
      const name = (typeof b.name === "string" ? b.name.trim().slice(0, 60) : "") || v.name || username;
      const id = randomUUID();
      // Tài khoản tạo từ Google/Facebook có mật khẩu ngẫu nhiên; có thể đặt mật khẩu qua "Quên mật khẩu".
      run(
        "INSERT INTO users(id,username,password,salt,name,birth_date,created,dm_mode) VALUES(?,?,?,?,?,?,?,'everyone')",
        id,
        username,
        randomBytes(64).toString("hex"),
        randomBytes(16).toString("hex"),
        name,
        "",
        Date.now(),
      );
      run(
        "INSERT INTO oauth_accounts VALUES(?,?,?,?,?)",
        v.provider,
        v.subject,
        id,
        v.email,
        Date.now(),
      );
      pending.delete(b.ticket);
      return json(200, { user: { id, username, name } }, { "Set-Cookie": await sessionCookie({ id, username, name, role: "user" }) });
    }

    
    if ((path === "/api/auth/apple" || path === "/api/oauth/apple") && req.method === "POST") {
      const b = await body(req, 8000);
      const identityToken = typeof b.identityToken === "string" ? b.identityToken.trim() : "";
      if (!identityToken) fail(400, "Thiếu identityToken từ Apple.");

      const parts = identityToken.split(".");
      if (parts.length !== 3) fail(400, "Token Apple không đúng định dạng JWT.");

      let header, claims;
      try {
        header = JSON.parse(Buffer.from(parts[0], "base64url").toString("utf8"));
        claims = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
      } catch {
        fail(400, "Không giải mã được token Apple.");
      }

      if (!header || typeof header !== "object" || !claims || typeof claims !== "object") {
        fail(400, "Cấu trúc header hoặc payload token không hợp lệ.");
      }

      // 1. Strict Header Validation
      if (header.alg !== "RS256") {
        fail(401, "Thuật toán token không hợp lệ (yêu cầu RS256).");
      }
      if (!header.kid || typeof header.kid !== "string") {
        fail(401, "Token thiếu thông tin key ID (kid).");
      }

      // 2. Strict Claims Validation BEFORE Any Account Lookup
      if (claims.iss !== "https://appleid.apple.com") {
        fail(401, "Issuer token không hợp lệ (cần https://appleid.apple.com).");
      }

      const expectedAud = process.env.APPLE_CLIENT_ID || process.env.APPLE_BUNDLE_ID || "app.kinnect.live";
      const audList = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
      if (!audList.includes(expectedAud)) {
        fail(401, `Audience token không khớp (nhận ${claims.aud}, yêu cầu ${expectedAud}).`);
      }

      const nowSec = Math.floor(Date.now() / 1000);
      if (typeof claims.exp !== "number" || !Number.isFinite(claims.exp) || claims.exp < nowSec) {
        fail(401, "Token Apple đã hết hạn hoặc thiếu trường exp hợp lệ.");
      }

      const sub = typeof claims.sub === "string" ? claims.sub.trim() : "";
      if (!sub) {
        fail(400, "Token Apple thiếu trường subject.");
      }

      if (b.appleId && typeof b.appleId === "string" && b.appleId !== sub) {
        fail(400, "appleId không khớp với subject trong token.");
      }

      // 2b. Request-Bound Nonce Verification (Client Request Binding)
      const rawNonce = typeof b.nonce === "string" ? b.nonce.trim() : "";
      if (!rawNonce || typeof claims.nonce !== "string" || !claims.nonce) {
        fail(401, "Thiếu nonce gắn với yêu cầu đăng nhập Apple.");
      }
      const hashedNonce = createHash("sha256").update(rawNonce).digest("hex");
      if (claims.nonce !== hashedNonce) {
        fail(401, "Nonce không khớp với yêu cầu xác thực (request binding failure).");
      }

      // 3. Cryptographic Signature Verification (Fail-Closed)
      let publicKey = null;
      if (appleKeyResolver) {
        const resolved = await appleKeyResolver(header.kid);
        if (resolved) {
          publicKey = resolved.kty ? createPublicKey({ key: resolved, format: "jwk" }) : resolved;
        }
      } else {
        const now = Date.now();
        const cacheFresh = cachedAppleJwks && now <= cachedAppleJwksExpiry;
        let jwk = cacheFresh ? cachedAppleJwks.find(k => k.kid === header.kid) : null;
        if (!jwk) {
          if (!jwksRefresh) {
            jwksRefresh = (async () => {
              try {
                const r = await providerFetch("https://appleid.apple.com/auth/keys");
                if (r.ok) {
                  const jwks = await r.json();
                  if (jwks && Array.isArray(jwks.keys) && jwks.keys.length) {
                    cachedAppleJwks = jwks.keys;
                    cachedAppleJwksExpiry = Date.now() + 3600 * 1000;
                  }
                }
              } catch (err) {
                console.error("[apple-auth] Failed to fetch Apple JWKS:", err.message);
              } finally {
                jwksRefresh = null;
              }
            })();
          }
          await jwksRefresh;
          if (cachedAppleJwks && Date.now() <= cachedAppleJwksExpiry) {
            jwk = cachedAppleJwks.find(k => k.kid === header.kid);
          }
        }
        if (jwk) {
          publicKey = createPublicKey({ key: jwk, format: "jwk" });
        }
      }

      if (!publicKey) {
        fail(401, `Không tìm thấy khóa công khai Apple phù hợp với kid: ${header.kid}`);
      }

      let signatureValid = false;
      try {
        const verifier = createVerify("RSA-SHA256");
        verifier.update(`${parts[0]}.${parts[1]}`);
        signatureValid = verifier.verify(publicKey, Buffer.from(parts[2], "base64url"));
      } catch (err) {
        signatureValid = false;
      }

      if (!signatureValid) {
        fail(401, "Chữ ký mật mã của token Apple không hợp lệ hoặc đã bị giả mạo.");
      }

      // 3b. Replay Attack Prevention (Fail-Closed)
      const replayId = claims.jti || parts[2];
      const expires = Math.floor(claims.exp);
      run("DELETE FROM apple_token_replay WHERE expires <= ?", nowSec);
      const inserted = run(
        "INSERT OR IGNORE INTO apple_token_replay(replay_id, expires) VALUES(?,?)",
        replayId,
        expires
      );
      if (!inserted.changes) {
        fail(401, "Token đã được sử dụng (phát hiện tấn công replay).");
      }

      // 4. Resolve Verified Account
      const link = get(
        "SELECT user_id, email FROM oauth_accounts WHERE provider='apple' AND subject=?",
        sub
      );
      const linked = link && user(link.user_id);
      if (linked) {
        if (linked.suspended) fail(403, "Tài khoản Apple đã bị tạm khóa.");
        const cookie = await sessionCookie(linked);
        return json(200, {
          user: { id: linked.id, username: linked.username, name: linked.name },
          success: true
        }, { "Set-Cookie": cookie });
      }

      // First-time login: create new user without fabricating privaterelay email
      let email = "";
      if (typeof claims.email === "string" && claims.email.includes("@")) {
        email = claims.email.trim();
      } else if (typeof b.email === "string" && b.email.includes("@")) {
        email = b.email.trim();
      }

      let name = "";
      if (typeof b.fullName === "object" && b.fullName) {
        const given = b.fullName.givenName || "";
        const family = b.fullName.familyName || "";
        name = `${family} ${given}`.trim();
      } else if (typeof b.fullName === "string") {
        name = b.fullName.trim();
      }
      if (!name) {
        name = email ? email.split("@")[0] : "Apple User";
      }
      name = name.slice(0, 60);

      const username = suggestUsername(email, name);
      const id = randomUUID();

      run(
        "INSERT INTO users(id,username,password,salt,name,birth_date,created,dm_mode) VALUES(?,?,?,?,?,?,?,'everyone')",
        id,
        username,
        randomBytes(64).toString("hex"),
        randomBytes(16).toString("hex"),
        name,
        "",
        Date.now()
      );

      run(
        "INSERT INTO oauth_accounts(provider,subject,user_id,email,created) VALUES('apple',?,?,?,?)",
        sub,
        id,
        email,
        Date.now()
      );

      const newUser = { id, username, name, role: "user" };
      const cookie = await sessionCookie(newUser);
      return json(200, {
        user: { id, username, name },
        success: true
      }, { "Set-Cookie": cookie });
    }

    fail(404, "Không tìm thấy API đăng nhập.");
  };
}
