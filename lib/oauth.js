// Đăng nhập bằng Google và Facebook (OAuth 2.0, luồng authorization code, chạy phía máy chủ).
// Cấu hình bằng biến môi trường (hoặc file oauth.env ở thư mục chạy):
//   PUBLIC_URL=https://app.kinnect.io.vn
//   GOOGLE_CLIENT_ID=...  GOOGLE_CLIENT_SECRET=...
//   FACEBOOK_APP_ID=...   FACEBOOK_APP_SECRET=...
// Thiếu khóa của nhà cung cấp nào thì nút đăng nhập tương ứng không hiện.
import { randomBytes, randomUUID } from "node:crypto";

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
        `https://graph.facebook.com/${FB_VERSION}/me?fields=id,name,email&access_token=` +
          encodeURIComponent(accessToken),
      );
      if (!r.ok) throw Error("Facebook không trả thông tin tài khoản.");
      const p = await r.json();
      return { subject: p.id, email: p.email || "", name: p.name || "" };
    },
  },
};

export function createOAuth({ db, get, run, user, fail, startSession, fetchImpl = fetch }) {
  db.exec(
    "CREATE TABLE IF NOT EXISTS oauth_accounts(provider TEXT NOT NULL,subject TEXT NOT NULL,user_id TEXT NOT NULL REFERENCES users(id),email TEXT NOT NULL DEFAULT '',created INTEGER NOT NULL,PRIMARY KEY(provider,subject))",
  );
  // Người đăng nhập lần đầu: giữ tạm thông tin 15 phút để họ xác nhận 18+ và chọn tên đăng nhập.
  const pending = new Map();
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
      `<!doctype html><meta charset="utf-8"><meta http-equiv="refresh" content="0;url=${location}"><title>Kinnect</title><p>Đang chuyển về Kinnect…</p>`,
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

  return async function oauthApi(req, res, path, json, body) {
    if (path === "/api/oauth/providers") return json(200, { providers: enabled() });

    const start = path.match(/^\/api\/oauth\/(google|facebook)\/start$/);
    if (start && req.method === "GET") {
      const provider = start[1];
      const p = PROVIDERS[provider];
      if (!enabled().includes(provider)) fail(404, "Chưa bật đăng nhập bằng " + provider + ".");
      const state = randomBytes(24).toString("hex");
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
        "Set-Cookie": `kinnect_oauth=${provider}.${state}; HttpOnly; SameSite=Lax; Path=/api/oauth; Max-Age=600${secure()}`,
      });
      return res.end();
    }

    const cb = path.match(/^\/api\/oauth\/(google|facebook)\/callback$/);
    if (cb && req.method === "GET") {
      const provider = cb[1];
      const p = PROVIDERS[provider];
      const q = new URL(req.url, "http://local").searchParams;
      const clear = `kinnect_oauth=; HttpOnly; SameSite=Lax; Path=/api/oauth; Max-Age=0${secure()}`;
      const expected = cookie(req, "kinnect_oauth");
      if (q.get("error") || !q.get("code"))
        return finish(res, "/?oauth_error=cancelled", { "Set-Cookie": clear });
      if (!expected || expected !== provider + "." + q.get("state"))
        return finish(res, "/?oauth_error=state", { "Set-Cookie": clear });
      let profile;
      try {
        const t = await fetchImpl(p.token, {
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
        profile = await p.profile(token.access_token, fetchImpl);
        if (!profile.subject) throw Error("Thiếu mã tài khoản.");
      } catch (e) {
        console.error("[oauth]", provider, e.message);
        return finish(res, "/?oauth_error=provider", { "Set-Cookie": clear });
      }
      const link = get(
        "SELECT user_id FROM oauth_accounts WHERE provider=? AND subject=?",
        provider,
        String(profile.subject),
      );
      const linked = link && user(link.user_id);
      if (linked) {
        if (linked.suspended) return finish(res, "/?oauth_error=suspended", { "Set-Cookie": clear });
        return finish(res, "/", { "Set-Cookie": [clear, startSession(linked.id)] });
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
      return finish(res, "/?oauth=complete&ticket=" + ticket, { "Set-Cookie": clear });
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
        "INSERT INTO users(id,username,password,salt,name,birth_date,created) VALUES(?,?,?,?,?,?,?)",
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
      return json(200, { user: { id, username, name } }, { "Set-Cookie": startSession(id) });
    }

    fail(404, "Không tìm thấy API đăng nhập.");
  };
}
