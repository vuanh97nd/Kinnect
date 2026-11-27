import { createHash, createHmac, randomBytes, timingSafeEqual } from "node:crypto";

const BASE32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

export function base32Encode(buffer) {
  let bits = 0;
  let value = 0;
  let output = "";
  for (const byte of buffer) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      output += BASE32_ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) {
    output += BASE32_ALPHABET[(value << (5 - bits)) & 31];
  }
  return output;
}

export function base32Decode(input) {
  const clean = String(input || "").toUpperCase().replace(/[^A-Z2-7]/g, "");
  let bits = 0;
  let value = 0;
  const out = [];
  for (const ch of clean) {
    const idx = BASE32_ALPHABET.indexOf(ch);
    if (idx < 0) continue;
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return Buffer.from(out);
}

export function generateTotpSecret(numBytes = 20) {
  return base32Encode(randomBytes(numBytes));
}

export function computeTotp(secret, timeMs = Date.now(), stepSeconds = 30, digits = 6) {
  const key = base32Decode(secret);
  const counter = Math.floor(timeMs / 1000 / stepSeconds);
  const msg = Buffer.alloc(8);
  msg.writeBigUInt64BE(BigInt(counter));
  const hmac = createHmac("sha1", key).update(msg).digest();
  const offset = hmac[hmac.length - 1] & 0x0f;
  const binCode =
    ((hmac[offset] & 0x7f) << 24) |
    ((hmac[offset + 1] & 0xff) << 16) |
    ((hmac[offset + 2] & 0xff) << 8) |
    (hmac[offset + 3] & 0xff);
  return String(binCode % 10 ** digits).padStart(digits, "0");
}

export function matchTotpStep(secret, code, { now = Date.now(), stepSeconds = 30, window = 1 } = {}) {
  const clean = String(code || "").replace(/[\s-]/g, "");
  if (!/^\d{6}$/.test(clean)) return null;
  const provided = Buffer.from(clean, "utf8");
  const baseStep = Math.floor(now / 1000 / stepSeconds);
  for (let delta = -window; delta <= window; delta++) {
    const step = baseStep + delta;
    const expected = Buffer.from(computeTotp(secret, step * stepSeconds * 1000, stepSeconds, 6), "utf8");
    if (expected.length === provided.length && timingSafeEqual(expected, provided)) {
      return step;
    }
  }
  return null;
}

export function verifyTotpCode(secret, code, opts = {}) {
  return matchTotpStep(secret, code, opts) !== null;
}

function generateBackupCodes(count = 8) {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const codes = [];
  for (let i = 0; i < count; i++) {
    const raw = [...randomBytes(8)].map((b) => alphabet[b % alphabet.length]).join("");
    codes.push(raw.slice(0, 4) + "-" + raw.slice(4));
  }
  return codes;
}

function hashRecoveryCode(code) {
  const norm = String(code || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  return createHash("sha256").update("kinnect-2fa-recovery:" + norm).digest("hex");
}

export function createTwoFactor({ db, body, fail, verifyPassword, invalidateAuth, clock = () => Date.now() }) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS user_totp(
      user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      secret TEXT NOT NULL,
      enabled INTEGER NOT NULL DEFAULT 0,
      created INTEGER NOT NULL,
      updated INTEGER NOT NULL,
      last_step INTEGER NOT NULL DEFAULT -1
    );
    CREATE TABLE IF NOT EXISTS user_totp_recovery(
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      code_hash TEXT NOT NULL,
      used INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(user_id, code_hash)
    );
  `);
  try {
    db.exec("ALTER TABLE user_totp ADD COLUMN last_step INTEGER NOT NULL DEFAULT -1");
  } catch {}

  const get = (s, ...p) => db.prepare(s).get(...p);
  const run = (s, ...p) => db.prepare(s).run(...p);
  const failedAttempts = new Map();

  function checkRateLimit(userId) {
    const now = clock();
    const rec = failedAttempts.get(userId);
    if (rec && now < rec.until && rec.count >= 8) {
      return false;
    }
    return true;
  }

  function recordFailure(userId) {
    const now = clock();
    let rec = failedAttempts.get(userId);
    if (!rec || now >= rec.until) {
      rec = { count: 0, until: now + 5 * 60 * 1000 };
    }
    rec.count++;
    failedAttempts.set(userId, rec);
    if (failedAttempts.size > 5000) {
      for (const [k, v] of failedAttempts) if (now >= v.until) failedAttempts.delete(k);
    }
  }

  function isEnabled(userId) {
    return !!get("SELECT 1 FROM user_totp WHERE user_id=? AND enabled=1", userId);
  }

  function status(userId) {
    const row = get("SELECT enabled,created,updated FROM user_totp WHERE user_id=?", userId);
    const remaining = row && row.enabled
      ? get("SELECT COUNT(*) AS n FROM user_totp_recovery WHERE user_id=? AND used=0", userId).n
      : 0;
    return {
      enabled: !!row?.enabled,
      pending: !!row && !row.enabled,
      recoveryRemaining: remaining,
      updated: row?.updated || null,
    };
  }

  function verifyForUser(userId, code, { consumeRecovery = true, trackStep = true } = {}) {
    const row = get("SELECT secret,enabled,last_step FROM user_totp WHERE user_id=?", userId);
    if (!row || !row.enabled) return true;
    if (!checkRateLimit(userId)) return false;
    const raw = String(code || "").trim();
    if (!raw) return false;
    const matchedStep = matchTotpStep(row.secret, raw, { now: clock() });
    if (matchedStep !== null) {
      if (trackStep && row.last_step >= matchedStep) {
        recordFailure(userId);
        return false;
      }
      if (trackStep) {
        run("UPDATE user_totp SET last_step=? WHERE user_id=?", matchedStep, userId);
      }
      failedAttempts.delete(userId);
      return true;
    }
    const norm = raw.toUpperCase().replace(/[^A-Z0-9]/g, "");
    if (norm.length === 8) {
      const hash = hashRecoveryCode(norm);
      const hit = get("SELECT 1 FROM user_totp_recovery WHERE user_id=? AND code_hash=? AND used=0", userId, hash);
      if (hit) {
        if (consumeRecovery) {
          run("UPDATE user_totp_recovery SET used=1 WHERE user_id=? AND code_hash=?", userId, hash);
        }
        failedAttempts.delete(userId);
        return true;
      }
    }
    recordFailure(userId);
    return false;
  }

  async function handle(req, path, me, json) {
    if (!path.startsWith("/api/me/2fa")) return false;
    if (path === "/api/me/2fa" && req.method === "GET") {
      json(200, status(me.id));
      return true;
    }
    if (path === "/api/me/2fa/setup" && req.method === "POST") {
      const b = await body(req);
      if (!(await verifyPassword(me, b.password, req))) {
        fail(401, me.password_set === 0 ? "Vui lòng đăng nhập lại bằng Apple/Google/Facebook trong vòng 10 phút trước khi thiết lập 2FA." : "Mật khẩu hiện tại không đúng.");
      }
      if (isEnabled(me.id)) {
        fail(409, "Xác thực 2 lớp đang được bật. Hãy tắt trước khi thiết lập lại.");
      }
      const secret = generateTotpSecret();
      const backupCodes = generateBackupCodes(8);
      const now = clock();
      db.exec("BEGIN IMMEDIATE");
      try {
        run(
          "INSERT INTO user_totp(user_id,secret,enabled,created,updated,last_step) VALUES(?,?,0,?,?,-1) ON CONFLICT(user_id) DO UPDATE SET secret=excluded.secret,enabled=0,updated=excluded.updated,last_step=-1",
          me.id,
          secret,
          now,
          now,
        );
        run("DELETE FROM user_totp_recovery WHERE user_id=?", me.id);
        for (const c of backupCodes) {
          run("INSERT INTO user_totp_recovery(user_id,code_hash,used) VALUES(?,?,0)", me.id, hashRecoveryCode(c));
        }
        db.exec("COMMIT");
      } catch (e) {
        db.exec("ROLLBACK");
        throw e;
      }
      const label = encodeURIComponent("Kinnect:" + me.username);
      const otpauthUri = `otpauth://totp/${label}?secret=${secret}&issuer=Kinnect&algorithm=SHA1&digits=6&period=30`;
      json(200, { secret, otpauthUri, backupCodes, issuer: "Kinnect" });
      return true;
    }
    if (path === "/api/me/2fa/enable" && req.method === "POST") {
      if (!checkRateLimit(me.id)) fail(429, "Quá nhiều lần nhập mã xác thực sai. Hãy thử lại sau 5 phút.");
      const b = await body(req);
      const row = get("SELECT secret,enabled FROM user_totp WHERE user_id=?", me.id);
      if (!row) fail(400, "Chưa khởi tạo xác thực 2 lớp.");
      if (row.enabled) fail(409, "Xác thực 2 lớp đã được bật.");
      const matchedStep = matchTotpStep(row.secret, b.code, { now: clock() });
      if (matchedStep === null) {
        recordFailure(me.id);
        fail(400, "Mã xác thực 6 chữ số không đúng. Vui lòng kiểm tra đồng hồ thiết bị và thử lại.");
      }
      failedAttempts.delete(me.id);
      const token = (req.headers.cookie || "")
        .split(";")
        .map((x) => x.trim())
        .find((x) => x.startsWith("kinnect_session="))
        ?.slice(16);
      const curDigest = token ? createHash("sha256").update(token).digest("hex") : "";
      db.exec("BEGIN IMMEDIATE");
      try {
        run("UPDATE user_totp SET enabled=1,updated=? WHERE user_id=?", clock(), me.id);
        if (get("SELECT name FROM sqlite_master WHERE type='table' AND name='remembered_accounts'")) {
          run("DELETE FROM remembered_accounts WHERE user_id=?", me.id);
        }
        run("DELETE FROM sessions WHERE user_id=? AND token<>?", me.id, curDigest);
        db.exec("COMMIT");
      } catch (e) {
        db.exec("ROLLBACK");
        throw e;
      }
      invalidateAuth?.(me.id, curDigest);
      json(200, { ok: true, ...status(me.id) });
      return true;
    }
    if (path === "/api/me/2fa/disable" && req.method === "POST") {
      const b = await body(req);
      if (!(await verifyPassword(me, b.password, req))) {
        fail(401, me.password_set === 0 ? "Vui lòng đăng nhập lại bằng Apple/Google/Facebook trong vòng 10 phút trước khi tắt 2FA." : "Mật khẩu hiện tại không đúng.");
      }
      if (!isEnabled(me.id)) {
        run("DELETE FROM user_totp WHERE user_id=?", me.id);
        run("DELETE FROM user_totp_recovery WHERE user_id=?", me.id);
        json(200, { ok: true, enabled: false });
        return true;
      }
      if (!verifyForUser(me.id, b.code, { consumeRecovery: false, trackStep: false })) {
        fail(400, "Mã xác thực 2 lớp hoặc mã dự phòng không đúng.");
      }
      db.exec("BEGIN IMMEDIATE");
      try {
        run("DELETE FROM user_totp WHERE user_id=?", me.id);
        run("DELETE FROM user_totp_recovery WHERE user_id=?", me.id);
        db.exec("COMMIT");
      } catch (e) {
        db.exec("ROLLBACK");
        throw e;
      }
      json(200, { ok: true, enabled: false });
      return true;
    }
    if (path === "/api/me/2fa/recovery" && req.method === "POST") {
      const b = await body(req);
      if (!(await verifyPassword(me, b.password, req))) {
        fail(401, me.password_set === 0 ? "Vui lòng đăng nhập lại bằng Apple/Google/Facebook trong vòng 10 phút trước khi tạo lại mã dự phòng." : "Mật khẩu hiện tại không đúng.");
      }
      if (!isEnabled(me.id)) fail(400, "Xác thực 2 lớp chưa được bật.");
      if (!verifyForUser(me.id, b.code, { consumeRecovery: false, trackStep: false })) {
        fail(400, "Mã xác thực 2 lớp không đúng.");
      }
      const backupCodes = generateBackupCodes(8);
      db.exec("BEGIN IMMEDIATE");
      try {
        run("DELETE FROM user_totp_recovery WHERE user_id=?", me.id);
        for (const c of backupCodes) {
          run("INSERT INTO user_totp_recovery(user_id,code_hash,used) VALUES(?,?,0)", me.id, hashRecoveryCode(c));
        }
        run("UPDATE user_totp SET updated=? WHERE user_id=?", clock(), me.id);
        db.exec("COMMIT");
      } catch (e) {
        db.exec("ROLLBACK");
        throw e;
      }
      json(200, { ok: true, backupCodes, recoveryRemaining: backupCodes.length });
      return true;
    }
    fail(405, "Phương thức không hợp lệ.");
  }

  return { isEnabled, status, verifyForUser, handle };
}
