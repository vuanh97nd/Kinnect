import { connect } from "node:http2";
import { createPrivateKey, sign } from "node:crypto";
import { readFile } from "node:fs/promises";

function sendHttp2(origin, headers, payload) {
  return new Promise((resolve, reject) => {
    const session = connect(origin);
    let stream, completed = false;
    const timer = setTimeout(() => finish(new Error("APNs timeout")), 10000);
    timer.unref?.();
    function finish(error, result) {
      if (completed) return;
      completed = true;
      clearTimeout(timer);
      stream?.close();
      session.close();
      if (error) reject(error); else resolve(result);
    }
    session.on("error", error => finish(error));
    session.on("connect", () => {
      stream = session.request(headers);
      let status = 0, text = "";
      stream.on("response", response => { status = Number(response[":status"]); });
      stream.on("data", chunk => { if (text.length < 8192) text += chunk; });
      stream.on("error", error => finish(error));
      stream.on("end", () => {
        let body = {};
        try { body = JSON.parse(text || "{}"); } catch {}
        finish(null, { status, body });
      });
      stream.end(JSON.stringify(payload));
    });
  });
}

export function createApplePush({ social, env = process.env, transport = sendHttp2, clock = Date.now } = {}) {
  let auth, authAt = 0;
  const enabled = () => env.APNS_ENABLED === "true" && !!env.APNS_KEY_FILE
    && /^[A-Z0-9]{10}$/.test(env.APNS_KEY_ID || "") && /^[A-Z0-9]{10}$/.test(env.APNS_TEAM_ID || "")
    && ["sandbox", "production"].includes(env.APNS_ENVIRONMENT);
  const hasVoip = userId => enabled() && !!social.db.prepare("SELECT 1 FROM push_devices WHERE user_id=? AND kind='voip'").get(userId);
  async function authorization() {
    if (auth && clock() - authAt < 50 * 60000) return auth;
    const key = createPrivateKey(await readFile(env.APNS_KEY_FILE));
    const encode = data => Buffer.from(JSON.stringify(data)).toString("base64url");
    const header = encode({ alg: "ES256", kid: env.APNS_KEY_ID });
    const claims = encode({ iss: env.APNS_TEAM_ID, iat: Math.floor(clock() / 1000) });
    const message = header + "." + claims;
    auth = message + "." + sign("sha256", Buffer.from(message), { key, dsaEncoding: "ieee-p1363" }).toString("base64url");
    authAt = clock();
    return auth;
  }
  async function deliver(userId, kind, payload, { ttl = 60, silent = false } = {}) {
    if (!enabled()) return [];
    const user = social.user(userId);
    if (!user || user.suspended) return [];
    const origin = env.APNS_ENVIRONMENT === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
    const rows = social.db.prepare("SELECT token FROM push_devices WHERE user_id=? AND kind=?").all(userId, kind);
    const jwt = await authorization();
    return Promise.all(rows.map(async ({ token }) => {
      if (!/^[0-9a-f]{64,400}$/.test(token)) return;
      const response = await transport(origin, {
        ":method": "POST", ":path": "/3/device/" + token,
        authorization: "bearer " + jwt,
        "apns-topic": "app.kinnect.live" + (kind === "voip" ? ".voip" : ""),
        "apns-push-type": kind === "voip" ? "voip" : silent ? "background" : "alert",
        "apns-priority": silent ? "5" : "10",
        "apns-expiration": ttl ? String(Math.floor(clock() / 1000) + ttl) : "0"
      }, payload);
      if (response.status === 410 || response.status === 400 && response.body?.reason === "BadDeviceToken")
        social.db.prepare("DELETE FROM push_devices WHERE user_id=? AND kind=? AND token=?").run(userId, kind, token);
      return { status: response.status, reason: response.body?.reason };
    }));
  }
  // Never throw into websocket/event callbacks or print access-bearing tokens.
  const background = promise => { promise.catch(() => {}); };
  function call(userId, session, from) {
    if (!from || social.blocked(userId, from.id)) return;
    background(deliver(userId, "voip", {
      aps: { "content-available": 1 }, callId: session.id, callerName: from.name,
      callerId: from.id, mode: session.mode
    }, { ttl: 0 }));
  }
  function callEnded(userId, session, reason) {
    background(deliver(userId, "apns", {
      aps: { "content-available": 1 }, type: "call-ended", callId: session.id, reason
    }, { ttl: 0, silent: true }));
  }
  function notification(userId, id) {
    if (!enabled()) return;
    setTimeout(() => {
      try {
      const row = social.db.prepare("SELECT * FROM notifications WHERE id=? AND user_id=?").get(id, userId);
      if (!row || row.seen) return;
      const actor = social.user(row.actor);
      if (!actor || actor.suspended || social.blocked(userId, row.actor)) return;
      background(deliver(userId, "apns", {
        aps: { alert: { title: actor.name || "Kinnect", body: "Bạn có thông báo mới trên Kinnect." }, sound: "default" },
        notificationId: id, type: "notification"
      }));
      } catch { /* The owning server may have shut down before this queued notification. */ }
    }, 50).unref?.();
  }
  return { enabled, hasVoip, deliver, call, callEnded, notification };
}
