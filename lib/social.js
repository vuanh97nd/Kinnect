import {createEconomy} from './economy.js';
import {createWallet} from './wallet.js';
import {maintainPrivacy} from './privacy-maintenance.js';
import {createStore} from './store.js';
import {resolve as resolvePrivacyPath} from 'node:path';
import {PRIVACY_VERSION,PRIVACY_NOTICE} from './privacy-notice.js';
import {deleteAccountData} from './account-deletion.js';
import {createKinnectAI} from './kinnect-ai.js';
import {createRecovery} from './recovery.js';
import {createCallConfig} from './call-config.js';
import {createFriendships} from './friendships.js';
import {privatePhotos} from "./private-photos.js";
import {createNews} from "./news.js";
import {messageActions} from "./message-actions.js";
import {chatAttachments} from "./chat-attachments.js";
import {commentThreads} from "./comment-threads.js";
import { createGroups } from "./groups.js";
import { rememberedDevices } from "./remembered-devices.js";
import { decodePostMedia, sendPostMedia } from "./post-media.js";
import { createShorts } from "./shorts.js";
import { applyModeration } from "./moderation.js";
import { createOAuth } from "./oauth.js";
import { DatabaseSync } from "node:sqlite";
import {
  randomBytes,
  randomUUID,
  scrypt as scryptCallback,
  timingSafeEqual,
  createHash,
} from "node:crypto";
import { promisify } from "node:util";
const scrypt = promisify(scryptCallback);
export class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}
const fail = (status, message) => {
  throw new ApiError(status, message);
};
const text = (value, max) =>
  typeof value === "string" ? value.trim().slice(0, max) : "";
const digest = (value) => createHash("sha256").update(value).digest("hex");
export function openSocial(dbPath, options = {}) {
  const callConfig=createCallConfig();
  const db = new DatabaseSync(dbPath);
  db.exec('CREATE TABLE IF NOT EXISTS privacy_consents(user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,version TEXT NOT NULL,created INTEGER NOT NULL)');
  db.exec('CREATE TABLE IF NOT EXISTS recent_auth(token TEXT PRIMARY KEY REFERENCES sessions(token) ON DELETE CASCADE,authenticated_at INTEGER NOT NULL)');
  const adminSearchKey=value=>String(value||'').normalize('NFD').replace(/\p{M}/gu,'').replace(/[đĐ]/g,'d').toLowerCase();
  db.function('admin_search_key',{deterministic:true},adminSearchKey);
  db.exec(`PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;
 CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY,username TEXT UNIQUE NOT NULL,password TEXT NOT NULL,salt TEXT NOT NULL,name TEXT NOT NULL,bio TEXT NOT NULL DEFAULT '',interests TEXT NOT NULL DEFAULT '[]',birth_date TEXT NOT NULL,discoverable INTEGER NOT NULL DEFAULT 1,dm_mode TEXT NOT NULL DEFAULT 'everyone',avatar BLOB,avatar_type TEXT,suspended INTEGER NOT NULL DEFAULT 0,created INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),expires INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS follows(actor TEXT REFERENCES users(id),target TEXT REFERENCES users(id),PRIMARY KEY(actor,target));
 CREATE TABLE IF NOT EXISTS blocks(actor TEXT REFERENCES users(id),target TEXT REFERENCES users(id),PRIMARY KEY(actor,target));
 CREATE TABLE IF NOT EXISTS posts(id TEXT PRIMARY KEY,user_id TEXT REFERENCES users(id),body TEXT NOT NULL,visibility TEXT NOT NULL,hidden INTEGER NOT NULL DEFAULT 0,created INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS post_categories(post_id TEXT PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,category TEXT NOT NULL);
 CREATE TABLE IF NOT EXISTS post_media(post_id TEXT PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,type TEXT NOT NULL,data BLOB NOT NULL);
 CREATE TABLE IF NOT EXISTS story_views(post_id TEXT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,viewed_at INTEGER NOT NULL,PRIMARY KEY(post_id,user_id));
 CREATE TABLE IF NOT EXISTS post_stories(post_id TEXT PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,expires INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY,sender TEXT REFERENCES users(id),recipient TEXT REFERENCES users(id),body TEXT NOT NULL,created INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS notifications(id TEXT PRIMARY KEY,user_id TEXT REFERENCES users(id),actor TEXT REFERENCES users(id),kind TEXT NOT NULL,ref TEXT,seen INTEGER NOT NULL DEFAULT 0,created INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS reports(id TEXT PRIMARY KEY,reporter TEXT REFERENCES users(id),target_type TEXT NOT NULL,target_id TEXT NOT NULL,reason TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'open',created INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS shorts(id TEXT PRIMARY KEY,user_id TEXT REFERENCES users(id),caption TEXT NOT NULL,data BLOB NOT NULL,duration REAL NOT NULL,hidden INTEGER NOT NULL DEFAULT 0,created INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS short_likes(short_id TEXT REFERENCES shorts(id) ON DELETE CASCADE,user_id TEXT REFERENCES users(id),PRIMARY KEY(short_id,user_id));
 CREATE TABLE IF NOT EXISTS short_comments(id TEXT PRIMARY KEY,short_id TEXT REFERENCES shorts(id) ON DELETE CASCADE,user_id TEXT REFERENCES users(id),body TEXT NOT NULL,created INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS gifts(id TEXT PRIMARY KEY,sender TEXT REFERENCES users(id),recipient TEXT REFERENCES users(id),room TEXT NOT NULL,kind TEXT NOT NULL,created INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS post_likes(post_id TEXT REFERENCES posts(id) ON DELETE CASCADE,user_id TEXT REFERENCES users(id),created INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(post_id,user_id));
 CREATE TABLE IF NOT EXISTS post_comments(id TEXT PRIMARY KEY,post_id TEXT REFERENCES posts(id) ON DELETE CASCADE,user_id TEXT REFERENCES users(id),body TEXT NOT NULL,created INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS password_resets(id TEXT PRIMARY KEY,username TEXT NOT NULL,user_id TEXT,contact TEXT NOT NULL,note TEXT NOT NULL DEFAULT '',status TEXT NOT NULL DEFAULT 'open',created INTEGER NOT NULL,handled INTEGER);
 CREATE TABLE IF NOT EXISTS moderation(id TEXT PRIMARY KEY,action TEXT NOT NULL,target TEXT NOT NULL,created INTEGER NOT NULL);
`);
  if (
    !db
      .prepare("PRAGMA table_info(users)")
      .all()
      .some((column) => column.name === "role")
  ) {
    db.exec(
      "ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'user' CHECK(role IN ('user','admin'))",
    );
  }
  for (const [name, type] of [
    ["lat", "REAL"],
    ["lng", "REAL"],
    ["cover", "BLOB"],
    ["cover_type", "TEXT"],
    ["location_at", "INTEGER"],
    ["location_precision", "INTEGER NOT NULL DEFAULT 0"],
    ["gender", "TEXT NOT NULL DEFAULT ''"],
    ["orientation", "TEXT NOT NULL DEFAULT ''"],
    ["community_role", "TEXT NOT NULL DEFAULT ''"],
    ["relationship_role", "TEXT NOT NULL DEFAULT ''"],
    ["pronouns", "TEXT NOT NULL DEFAULT ''"],
    ["age", "INTEGER"],
    ["city", "TEXT NOT NULL DEFAULT ''"],
    ["looking_for", "TEXT NOT NULL DEFAULT ''"],
    ["identity_public", "INTEGER NOT NULL DEFAULT 0"],
    ["show_activity", "INTEGER NOT NULL DEFAULT 1"],
    ["show_distance", "INTEGER NOT NULL DEFAULT 1"],
    ["last_active", "INTEGER NOT NULL DEFAULT 0"],
    ["profile_dob", "TEXT NOT NULL DEFAULT ''"],
    ["profile_visibility", "TEXT NOT NULL DEFAULT '{}'"],
    ["profile_details", "TEXT NOT NULL DEFAULT '{}'"],
  ])
    if (
      !db
        .prepare("PRAGMA table_info(users)")
        .all()
        .some((c) => c.name === name)
    )
      db.exec("ALTER TABLE users ADD COLUMN " + name + " " + type);
  if(!db.prepare('PRAGMA table_info(post_stories)').all().some(c=>c.name==='background'))db.exec("ALTER TABLE post_stories ADD COLUMN background TEXT NOT NULL DEFAULT 'purple'");
  if(db.prepare("PRAGMA user_version").get().user_version<7)db.exec("UPDATE users SET dm_mode='everyone' WHERE dm_mode='mutual'");
  db.exec("UPDATE users SET lat=NULL,lng=NULL,location_at=NULL WHERE location_at IS NOT NULL AND location_precision<>100");
  db.exec("PRAGMA user_version=7");
  if(!db.prepare('PRAGMA table_info(post_likes)').all().some(c=>c.name==='reaction'))db.exec("ALTER TABLE post_likes ADD COLUMN reaction TEXT NOT NULL DEFAULT 'like'");
  db.exec("CREATE TABLE IF NOT EXISTS message_receipts(message_id TEXT PRIMARY KEY,delivered_at INTEGER,seen_at INTEGER)");
  db.exec("CREATE TABLE IF NOT EXISTS session_info(token TEXT PRIMARY KEY REFERENCES sessions(token) ON DELETE CASCADE,label TEXT NOT NULL,created INTEGER NOT NULL,device_hash TEXT NOT NULL DEFAULT '')");
  db.exec("CREATE TABLE IF NOT EXISTS notification_targets(notification_id TEXT PRIMARY KEY REFERENCES notifications(id) ON DELETE CASCADE,comment_id TEXT NOT NULL)");
  const run = (sql, ...args) => db.prepare(sql).run(...args);
  const get = (sql, ...args) => db.prepare(sql).get(...args);
  const all = (sql, ...args) => db.prepare(sql).all(...args);
  const user = (id) => get("SELECT * FROM users WHERE id=?", id);
  const blocked = (a, b) =>
    !!get(
      "SELECT 1 FROM blocks WHERE (actor=? AND target=?) OR (actor=? AND target=?)",
      a,
      b,
      b,
      a,
    );
  const follows = (a, b) =>
    !!get("SELECT 1 FROM follows WHERE actor=? AND target=?", a, b);
  let friendConnections=null;
  const birthAge = value => {if(!/^\d{4}-\d{2}-\d{2}$/.test(value||''))return null;const d=new Date(value+'T00:00:00Z'),now=new Date();if(Number.isNaN(d.getTime())||d.toISOString().slice(0,10)!==value)return null;return now.getUTCFullYear()-d.getUTCFullYear()-(now.getUTCMonth()<d.getUTCMonth()||(now.getUTCMonth()===d.getUTCMonth()&&now.getUTCDate()<d.getUTCDate())?1:0);};
  const profileVisible=(u,key)=>JSON.parse(u.profile_visibility||'{}')[key]!==false;
  const publicDetails=u=>Object.fromEntries(Object.entries(JSON.parse(u.profile_details||'{}')).filter(([key])=>profileVisible(u,key)));
  const economy=createEconomy({db,body,fail});
  const wallet=createWallet({db,body,fail,economy});
  const store=createStore({db,body,fail,verifier:options.storeVerifier,env:options.storeEnv||process.env});
  const publicUser = (u, viewer) => ({
    id: u.id,
    username: u.username,
    name: u.name,
    bio: profileVisible(u,"bio") ? u.bio : "",
    age: profileVisible(u,"age") ? (u.profile_dob ? birthAge(u.profile_dob) : u.age) : null,
    city: profileVisible(u,"city") ? u.city : "",
    lookingFor: profileVisible(u,"lookingFor") ? u.looking_for : "",
    gender: u.identity_public && profileVisible(u,"gender") ? u.gender : "",
    communityRole: u.identity_public && profileVisible(u,"communityRole") ? u.community_role : "",
    orientation: u.identity_public && profileVisible(u,"orientation") ? u.orientation : "",
    relationshipRole: u.identity_public && profileVisible(u,"relationshipRole") ? u.relationship_role : "",
    pronouns: u.identity_public && profileVisible(u,"pronouns") ? u.pronouns : "",
    joinedAt: u.created,
    isNew: Date.now() - u.created < 7 * 86400000,
    lastActiveAt:u.show_activity?u.last_active||null:null,
    isActive: !!u.show_activity && Date.now() - u.last_active < 90000 && !!get("SELECT 1 FROM sessions WHERE user_id=? AND expires>? LIMIT 1", u.id, Date.now()),
    interests: profileVisible(u,"interests") ? JSON.parse(u.interests) : [],
    ...publicDetails(u),
    storeStyle: store.appearance(u.id)?.id||'',
    cover: u.cover ? "/api/users/"+u.id+"/cover" : null,
    avatar: u.avatar ? "/api/users/" + u.id + "/avatar" : null,
    friendship: viewer ? friendConnections?.status(viewer,u.id)||"none" : "none",
    activityShared:!!u.show_activity,
    following: viewer ? follows(viewer, u.id) : false,
    mutual: viewer ? follows(viewer, u.id) && follows(u.id, viewer) : false,
  });
  const notice = (to, actor, kind, ref) => {
    if (to === actor) return;
    const id = randomUUID(), created = Date.now();
    run("INSERT INTO notifications VALUES(?,?,?,?,?,0,?)", id, to, actor, kind, ref, created);
    options.onNotification?.({ userId: to, id, kind });
    return id;
  };
  const recordCallEvent = (callerId, recipientId, mode, result, duration=0) => {
    const caller = user(callerId), recipient = user(recipientId);
    if (!caller || !recipient || callerId === recipientId || blocked(callerId, recipientId) || caller.suspended || recipient.suspended) return;
    const callName = mode === "audio" ? "thoại" : "video";
    const outcome = result === "ended" ? "· "+String(Math.floor(duration/60)).padStart(2,"0")+":"+String(duration%60).padStart(2,"0") : result === "declined" ? "bị từ chối" : "nhỡ";
    const message = { id: randomUUID(), sender: callerId, recipient: recipientId, body: `Cuộc gọi ${callName} ${outcome}.`, created: Date.now() };
    run("INSERT INTO messages VALUES(?,?,?,?,?)", message.id, message.sender, message.recipient, message.body, message.created);
    messageState.reveal("direct", recipientId, callerId);
    messageState.reveal("direct", callerId, recipientId);
    if(result==="missed")notice(recipientId,callerId,"missed_call",message.id);
    options.onCallMessage?.({ userIds: [callerId, recipientId] });
  };
  function authenticate(req) {
    const cookie = req.headers.cookie || "";
    const token = cookie
      .split(";")
      .map((x) => x.trim())
      .find((x) => x.startsWith("kinnect_session="))
      ?.slice(16);
    if (!token) return null;
    const row = get(
      "SELECT u.* FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token=? AND s.expires>? AND u.suspended=0",
      digest(token),
      Date.now(),
    );
    const device=(cookie.split(';').map(x=>x.trim()).find(x=>x.startsWith('kinnect_device='))||'').slice(15);
    if(row&&/^[a-f0-9]{64}$/.test(device)&&get("SELECT 1 FROM session_info WHERE token=? AND device_hash=''",digest(token))&&get('SELECT 1 FROM remembered_accounts WHERE device=? AND user_id=?',digest(device),row.id))run("UPDATE session_info SET device_hash=? WHERE token=? AND device_hash=''",digest(device),digest(token));
    return row || null;
  }
  const messageState=messageActions({db,fail,blocked,user,body});
  const attachments=chatAttachments({db,fail,blocked,user,messageState});
  const groups=createGroups({db,body,fail,text,user,publicUser,blocked,notice,attachments,messageState});
  const privateAlbum=privatePhotos({db,fail,blocked,user,publicUser,notice,body});
  friendConnections=createFriendships({db,user,publicUser,blocked,notice,body,fail});
  function requireUser(req) {
    return authenticate(req) || fail(401, "Vui lòng đăng nhập.");
  }
  function targetUser(id, me) {
    const u = user(id);
    if (!u || u.suspended || blocked(me.id, id))
      fail(404, "Không tìm thấy người dùng.");
    return u;
  }
  const own = (u) => ({
    ...publicUser(u, u.id),
    bio:u.bio,city:u.city,lookingFor:u.looking_for,interests:JSON.parse(u.interests),
    age:u.profile_dob?birthAge(u.profile_dob):u.age,birthDate:u.profile_dob,profileVisibility:JSON.parse(u.profile_visibility||"{}"),...JSON.parse(u.profile_details||"{}"),
    gender: u.gender,
    communityRole:u.community_role,
    orientation: u.orientation,
    relationshipRole: u.relationship_role,
    pronouns: u.pronouns,
    identityPublic: !!u.identity_public,
    showActivity: !!u.show_activity,
    discoverable: !!u.discoverable,
    dmMode: u.dm_mode==='friends'?'friends':'everyone',
    showDistance: !!u.show_distance,
    role: u.role,
    receivedGifts: get(
      "SELECT count(*) AS n FROM gifts WHERE recipient=?",
      u.id,
    ).n,
    hasLocation:
      u.lat !== null &&
      u.lng !== null &&
      Date.now() - (u.location_at || 0) < 86400000,
  });
  const getNews=createNews();
  const limits = new Map();
  const writes = new Map();
  function limit(req) {
    const key = req.socket.remoteAddress;
    const now = Date.now();
    let b = limits.get(key);
    if (!b || now - b.time > 60000) {
      b = { time: now, count: 0 };
      limits.set(key, b);
    }
    if (++b.count > (options.authLimit || 20)) fail(429, "Thử lại sau một phút.");
    if (limits.size > 10000)
      for (const [k, v] of limits) if (now - v.time > 60000) limits.delete(k);
  }
  async function body(req, maximum = 1500000) {
    let size = 0;
    const chunks = [];
    for await (const chunk of req) {
      size += chunk.length;
      if (size > maximum) fail(413, "Dữ liệu quá lớn.");
      chunks.push(chunk);
    }
    try {
      const value = JSON.parse(Buffer.concat(chunks).toString() || "{}");
      if (!value || typeof value !== "object" || Array.isArray(value))
        throw Error();
      return value;
    } catch {
      fail(400, "JSON không hợp lệ.");
    }
  }
  function csrf(req) {
    if (req.headers.origin) {
      let o;
      try {
        o = new URL(req.headers.origin);
      } catch {
        fail(403, "Origin không hợp lệ.");
      }
      if (o.host !== req.headers.host) fail(403, "Origin không hợp lệ.");
    } else if (req.headers["sec-fetch-site"] === "cross-site")
      fail(403, "Yêu cầu khác nguồn bị từ chối.");
  }
  function startSession(userId, req, freshCredential=false) {
    ai.welcome(userId);
    run("UPDATE users SET last_active=? WHERE id=?", Date.now(), userId);
    const token = randomBytes(32).toString("hex");
    run("DELETE FROM sessions WHERE expires<?", Date.now());
    run(
      "INSERT INTO sessions VALUES(?,?,?)",
      digest(token),
      userId,
      Date.now() + 7 * 86400000,
    );
    const agent=req?.headers?.['user-agent']||'',browser=/Edg\//.test(agent)?'Edge':/Firefox\//.test(agent)?'Firefox':/Chrome\//.test(agent)?'Chrome':/Safari\//.test(agent)?'Safari':'Trình duyệt web',system=/Android/.test(agent)?'Android':/iPhone|iPad/.test(agent)?'iOS':/Windows/.test(agent)?'Windows':/Macintosh/.test(agent)?'macOS':/Linux/.test(agent)?'Linux':'';
    run('INSERT INTO session_info(token,label,created) VALUES(?,?,?)',digest(token),browser+(system?' · '+system:''),Date.now());
    if(freshCredential)run('INSERT INTO recent_auth VALUES(?,?)',digest(token),Date.now());
    return `kinnect_session=${token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=604800${process.env.SECURE_COOKIES === "1" ? "; Secure" : ""}`;
  }
  const remembered = rememberedDevices({db,user,own,startSession,body,fail,limit});
  const recovery=createRecovery({db,body,fail,limit,requireUser,user,
   verifyPassword:async(u,password)=>typeof password==='string'&&password.length<=128&&timingSafeEqual(await scrypt(password,u.salt,64),Buffer.from(u.password,'hex')),
   hashPassword:async password=>{const salt=randomBytes(16).toString('hex');return {salt,hash:(await scrypt(password,salt,64)).toString('hex')};},
   revoke:id=>remembered.revoke(id),sendEmail:options.sendEmail||(()=>Promise.resolve(false)),mailReady:options.mailReady||(()=>false)
  });
  const oauthApi = createOAuth({
    db,
    get,
    run,
    user,
    fail,
    startSession:(id,request)=>startSession(id,request,true),
    ...(options.fetchImpl ? { fetchImpl: options.fetchImpl } : {}),
  });
  const ai=createKinnectAI({db,user,blocked,notice,messageState,onStream:options.onAIStream,send:options.fetchImpl||fetch});
  const threads=commentThreads({db,fail,blocked,user});
  const shortsApi = createShorts({
    threads,
    onContent:(id,actor,caption)=>ai.enqueue("short",id,actor,{text:caption||"Video mới cần duyệt khung hình."}),
    db,
    get,
    all,
    run,
    body,
    fail,
    blocked,
    user,
    publicUser,
  });
  async function api(req, res, path) {
    const json = (status, data, headers = {}) => {
      const encoded=JSON.stringify(data);
      if(req.method==='GET'&&status===200){const tag='"'+createHash('sha256').update(encoded).digest('hex')+'"';headers={...headers,ETag:tag,Vary:'Cookie'};if(req.headers['if-none-match']===tag){res.writeHead(304,{'Cache-Control':'no-store',...headers});res.end();return;}}
      res.writeHead(status, {
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
        ...headers,
      });
      res.end(encoded);
    };
    try {
      if (req.method !== "GET" && req.method !== "HEAD") {
        csrf(req);
        if (!(req.headers["content-type"] || "").startsWith("application/json"))
          fail(415, "Cần Content-Type application/json.");
      }
      if (await recovery.route(req,res,path,json)) return;
      if (await remembered.route(req,res,path,json)) return;
      if (path.startsWith("/api/oauth/")) {
        if(path !== "/api/oauth/providers" || req.method !== "GET") limit(req);
        return await oauthApi(req, res, path, json, body);
      }
      if (path === "/api/register" || path === "/api/login") {
        if (req.method !== "POST") fail(405, "Chỉ hỗ trợ POST.");
        limit(req);
        const b = await body(req);
        const username = text(b.username, 40).toLowerCase();
        if (
          !/^[a-z0-9_]{3,30}$/.test(username) ||
          typeof b.password !== "string" ||
          b.password.length < 6 ||
          b.password.length > 128
        )
          fail(
            400,
            "Tên đăng nhập 3–30 chữ/số/gạch dưới; mật khẩu 6–128 ký tự.",
          );
        let u;
        if (path === "/api/register") {
          // Registration no longer collects birth dates; retain legacy column
          // for backwards-compatible SQLite migration without inventing a date.
          if (b.agree18 !== true) fail(400, "Cần xác nhận bạn đủ 18 tuổi.");
          const date = "";
          if (get("SELECT id FROM users WHERE username=?", username))
            fail(409, "Tên đăng nhập đã được dùng.");
          const name = text(b.name, 60) || username,
            salt = randomBytes(16).toString("hex"),
            hash = (await scrypt(b.password, salt, 64)).toString("hex"),
            id = randomUUID();
          try {
            run(
              "INSERT INTO users(id,username,password,salt,name,birth_date,created,dm_mode) VALUES(?,?,?,?,?,?,?,'everyone')",
              id,
              username,
              hash,
              salt,
              name,
              date,
              Date.now(),
            );
          } catch (e) {
            if (e.code?.includes("SQLITE"))
              fail(409, "Tên đăng nhập đã được dùng.");
            throw e;
          }
          u = user(id);
        } else {
          u = get("SELECT * FROM users WHERE username=?", username);
          const hash = await scrypt(
            b.password,
            u?.salt || "kinnect-dummy-salt",
            64,
          );
          if (
            !u ||
            !timingSafeEqual(hash, Buffer.from(u.password, "hex")) ||
            u.suspended
          )
            fail(
              401,
              "Thông tin đăng nhập không đúng hoặc tài khoản không khả dụng.",
            );
        }
        if(b.acceptPrivacyNotice===true)run('INSERT OR REPLACE INTO privacy_consents VALUES(?,?,?)',u.id,PRIVACY_VERSION,Date.now());
        return json(200, { user: own(u) }, { "Set-Cookie": [startSession(u.id,req,true), ...remembered.remember(req,u.id,b.remember)] });
      }
      if (path === "/api/password-reset") {
        if (req.method !== "POST") fail(405, "Chỉ hỗ trợ POST.");
        limit(req);
        const b = await body(req, 4000);
        const username = text(b.username, 40).toLowerCase();
        const contact = text(b.contact, 120);
        const note = text(b.note, 500);
        if (!/^[a-z0-9_]{3,30}$/.test(username))
          fail(400, "Nhập đúng tên đăng nhập của bạn.");
        if (contact.length < 5)
          fail(400, "Để lại email, số điện thoại hoặc Zalo để quản trị viên liên hệ.");
        const u = get("SELECT id FROM users WHERE username=?", username);
        // Giới hạn 3 yêu cầu/ngày cho mỗi tên đăng nhập để tránh spam.
        const recent = get(
          "SELECT count(*) AS n FROM password_resets WHERE username=? AND created>?",
          username,
          Date.now() - 86400000,
        ).n;
        if (recent >= 3) fail(429, "Bạn đã gửi tối đa 3 yêu cầu trong 24 giờ. Vui lòng chờ quản trị viên xử lý hoặc thử lại sau.");
        if (recent < 3) {
          const id = randomUUID();
          run(
            "INSERT INTO password_resets(id,username,user_id,contact,note,created) VALUES(?,?,?,?,?,?)",
            id,
            username,
            u?.id || null,
            contact,
            note,
            Date.now(),
          );
          for(const admin of all("SELECT id FROM users WHERE role='admin' AND suspended=0"))options.onNotification?.({userId:admin.id,kind:'password_reset_request',id});
          options.onResetRequest?.({ id, username, exists: !!u, contact, note });
        }
        // Luôn trả cùng một câu, không tiết lộ tài khoản có tồn tại hay không.
        return json(200, {
          ok: true,
          message:
            "Đã gửi yêu cầu. Quản trị viên sẽ liên hệ với bạn qua thông tin đã để lại để cấp mật khẩu tạm.",
        });
      }
      run(
        "UPDATE users SET lat=NULL,lng=NULL,location_at=NULL WHERE location_at IS NOT NULL AND location_at<?",
        Date.now() - 86400000,
      );
      const me = requireUser(req);
      if(await economy.route(req,res,path,json,me))return;
      if(path==='/api/live/gifts'&&req.method==='GET')return json(200,{...economy.giftCatalog(),balance:wallet.trialBalance(me.id)});
      if(await wallet.route(req,res,path,json,me))return;
      if(await store.route(req,res,path,json,me))return;
      if(path==='/api/support'&&req.method==='GET'){const admin=user(ai.status().admin_id)||get("SELECT * FROM users WHERE role='admin' AND suspended=0 ORDER BY created,id LIMIT 1");return json(200,{user:admin?publicUser(admin,me.id):null,contact:'anhvn53@wru.vn',operator:'Mr Ánh'});}
      if(path==='/api/me/privacy-consent'){
        if(req.method==='GET')return json(200,{version:PRIVACY_VERSION,notice:PRIVACY_NOTICE,accepted:!!get('SELECT 1 FROM privacy_consents WHERE user_id=? AND version=?',me.id,PRIVACY_VERSION)});
        if(req.method!=='POST')fail(405,'Chỉ hỗ trợ GET hoặc POST.');const b=await body(req,4096);if(b.accepted!==true||b.version!==PRIVACY_VERSION)fail(400,'Cần đồng ý thông báo dữ liệu hiện hành.');run('INSERT INTO privacy_consents VALUES(?,?,?) ON CONFLICT(user_id) DO UPDATE SET version=excluded.version,created=excluded.created',me.id,PRIVACY_VERSION,Date.now());return json(200,{ok:true});
      }
      const contentWrite=!['GET','HEAD','DELETE'].includes(req.method)&&(/^\/api\/(posts|shorts)(\/|$)/.test(path)||/^\/api\/groups(?:\/[^/]+)?(?:\/messages|\/avatar)?$/.test(path)||/^\/api\/users\/[^/]+\/messages$/.test(path)||path==='/api/me/avatar'||path==='/api/me/cover'||(path==='/api/me'&&req.method==='PATCH')||path==='/api/me/content-consent');
      if(contentWrite&&!get('SELECT 1 FROM privacy_consents WHERE user_id=? AND version=?',me.id,PRIVACY_VERSION))return json(428,{error:PRIVACY_NOTICE,version:PRIVACY_VERSION});
      if(path==='/api/me/content-consent'&&req.method==='POST')return json(200,{ok:true});
      if(path==='/api/me/ai-consent'&&req.method==='POST'){const b=await body(req,4096);if(typeof b.enabled!=='boolean')fail(400,'Cần xác nhận lựa chọn AI.');return json(200,ai.consent(me.id,b.enabled));}
      if(path==='/api/me/account-deletion'){
        const token=(req.headers.cookie||'').split(';').map(x=>x.trim()).find(x=>x.startsWith('kinnect_session='))?.slice(16);
        const session=token&&get('SELECT authenticated_at FROM recent_auth WHERE token=?',digest(token));
        const fresh=!!session&&Date.now()-session.authenticated_at<10*60000;
        if(req.method==='GET')return json(200,{requiresPassword:!fresh,username:me.username,permanent:true});
        if(req.method!=='DELETE')fail(405,'Chỉ hỗ trợ GET hoặc DELETE.');
        limit(req);const b=await body(req,4096);
        if(b.confirmUsername!==me.username||b.confirmDelete!==true)fail(400,'Nhập đúng tên đăng nhập và xác nhận xóa vĩnh viễn.');
        if(!fresh||b.password){if(typeof b.password!=='string'||!b.password||b.password.length>128||!timingSafeEqual(await scrypt(b.password,me.salt,64),Buffer.from(me.password,'hex')))fail(403,'Xác thực chưa đúng. Nhập mật khẩu hoặc đăng nhập lại bằng mật khẩu/Google/Facebook rồi yêu cầu xóa trong 10 phút.');}
        deleteAccountData(db,me);
        return json(200,{ok:true,deleted:true},{'Set-Cookie':'kinnect_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0'+(process.env.SECURE_COOKIES==='1'?'; Secure':'')});
      }
      if(path==="/api/news"&&req.method==="GET")return json(200,await getNews());
      if(await privateAlbum.route(req,res,path,me,json))return;
      if(await friendConnections.route(req,res,path,me,json))return;
      if(attachments.serve(req,res,path,me))return;
      if(path==='/api/call-config'&&req.method==='GET'){
       try{return json(200,await callConfig());}catch(e){return json(503,{error:e.message});}
      }
      run("DELETE FROM posts WHERE id IN (SELECT post_id FROM post_stories WHERE expires<=?)", Date.now());
      if (req.method !== "GET" && req.method !== "HEAD") {
        const now = Date.now();
        let bucket = writes.get(me.id);
        if (!bucket || now - bucket.time > 60000) {
          bucket = { time: now, count: 0 };
          writes.set(me.id, bucket);
        }
        if (++bucket.count > 120)
          fail(429, "Bạn thao tác quá nhanh. Hãy thử lại sau một phút.");
        if (writes.size > 10000)
          for (const [id, v] of writes)
            if (now - v.time > 60000) writes.delete(id);
      }
      if(path==='/api/support-account'&&req.method==='GET'){const admin=get("SELECT * FROM users WHERE role='admin' AND suspended=0 ORDER BY created LIMIT 1");if(!admin)fail(404,'Chưa có tài khoản hỗ trợ.');return json(200,{user:publicUser(admin,me.id)});}
      if(await messageState.handle(req,path,me,json))return;
      if(await groups(req,path,me,json))return;
      if (path === "/api/logout" && req.method === "POST") {
        const token = (req.headers.cookie || "")
          .split(";")
          .map((x) => x.trim())
          .find((x) => x.startsWith("kinnect_session="))
          ?.slice(16);
        if (token) run("DELETE FROM sessions WHERE token=?", digest(token));
        return json(
          200,
          { ok: true },
          {
            "Set-Cookie":
              "kinnect_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0",
          },
        );
      }
      if (path.startsWith("/api/shorts"))
        return await shortsApi(req, res, path, me, json);
      if (path.startsWith("/api/admin/")) {
        if (me.role !== "admin")
          fail(403, "Chỉ quản trị viên có quyền thực hiện.");
        if(path==='/api/admin/ai'&&req.method==='GET')return json(200,{config:ai.status(),credentials:ai.credentialStatus(),jobs:ai.jobs()});
        if(path==='/api/admin/ai'&&req.method==='PATCH'){try{return json(200,{config:ai.configure(await body(req))});}catch{return json(400,{error:'Cấu hình AI không hợp lệ hoặc chưa có khóa kết nối máy chủ.'});}}
        if(path==='/api/admin/ai/credentials'&&req.method==='PATCH'){const b=await body(req);if(typeof b.password!=='string'||b.password.length>128||!timingSafeEqual(await scrypt(b.password,me.salt,64),Buffer.from(me.password,'hex')))fail(401,'Mật khẩu quản trị không đúng.');try{return json(200,{credentials:await ai.saveCredentials(b)});}catch{return json(400,{error:'Không lưu được cấu hình. Kiểm tra URL Worker, khóa và model NVIDIA.'});}}
        if(path==='/api/admin/ai/test'&&req.method==='POST'){const b=await body(req);if(!['cloudflare','nvidia','fallback'].includes(b.provider))fail(400,'Dịch vụ không hợp lệ.');try{return json(200,await ai.testConnection(b.provider));}catch{return json(503,{error:'Không kết nối được AI đã chọn. Kiểm tra khóa, model, hạn mức và trạng thái dịch vụ.'});}}
        const aiPause=path.match(/^\/api\/admin\/ai\/conversations\/([a-zA-Z0-9-]+)$/);if(aiPause&&req.method==='PATCH'){const b=await body(req);if(typeof b.paused!=='boolean')fail(400,'Trạng thái không hợp lệ.');ai.pause(aiPause[1],b.paused);return json(200,{ok:true});}
        if (path === "/api/admin/reports" && req.method === "GET") {
          const reports = all(
            "SELECT * FROM reports ORDER BY CASE WHEN status='open' AND (reason LIKE '%CSAM%' OR reason LIKE '%CSAE%' OR reason LIKE 'An toàn trẻ em%') THEN 0 ELSE 1 END,created DESC LIMIT 200",
          ).map((r) => {
            let subject = null;
            if (r.target_type === "user") {
              const u = user(r.target_id);
              if (u)
                subject = {
                  userId: u.id,
                  username: u.username,
                  suspended: !!u.suspended,
                };
            }
            if (r.target_type === "post") {
              const p = get("SELECT * FROM posts WHERE id=?", r.target_id);
              if (p)
                subject = {
                  userId: p.user_id,
                  body: p.body,
                  hidden: !!p.hidden,
                };
            }
            if (r.target_type === "message") {
              const m = get("SELECT * FROM messages WHERE id=?", r.target_id);
              if (m) subject = { userId: m.sender, body: m.body };
            }
            if(r.target_type==='group_message'){const message=get('SELECT sender,body FROM group_messages WHERE id=?',r.target_id);if(message)subject={userId:message.sender,body:message.body};}
            if (r.target_type === "short") {
              const item = get(
                "SELECT user_id,caption,hidden FROM shorts WHERE id=?",
                r.target_id,
              );
              if (item)
                subject = {
                  userId: item.user_id,
                  body: item.caption,
                  hidden: !!item.hidden,
                };
            }
            if (r.target_type === "comment") {
              const item = get(
                "SELECT user_id,body FROM short_comments WHERE id=?",
                r.target_id,
              );
              if (item) subject = { userId: item.user_id, body: item.body };
            }
            return { ...r, subject };
          });
          return json(200, { reports });
        }
        if(path==='/api/admin/overview'&&req.method==='GET')return json(200,{
          users:get('SELECT count(*) n FROM users').n,
          suspended:get('SELECT count(*) n FROM users WHERE suspended=1').n,
          pendingResets:get("SELECT count(*) n FROM password_resets WHERE status='open'").n,
          openReports:get("SELECT count(*) n FROM reports WHERE status='open'").n,
        });
        if(path==='/api/admin/activity'&&req.method==='GET')return json(200,{entries:all('SELECT m.id,m.action,m.target,m.created,u.username,u.name,a.username AS actorUsername FROM moderation m LEFT JOIN users u ON u.id=m.target LEFT JOIN users a ON a.id=substr(m.action,instr(m.action,char(58))+1) ORDER BY m.created DESC,m.rowid DESC LIMIT 100')});
        if (path === '/api/admin/users' && req.method === 'GET') {
          const params=new URL(req.url,'http://local').searchParams;
          const q=adminSearchKey(text(params.get('q'),60)),state=params.get('state')||'all';
          if(!['all','active','suspended','admin','no-email'].includes(state))fail(400,'Bộ lọc tài khoản không hợp lệ.');
          const condition="(admin_search_key(u.username) LIKE ? OR admin_search_key(u.name) LIKE ?)"+(state==='active'?' AND u.suspended=0':state==='suspended'?' AND u.suspended=1':state==='admin'?" AND u.role='admin'":state==='no-email'?' AND r.user_id IS NULL':'');
          const from=' FROM users u LEFT JOIN recovery_emails r ON r.user_id=u.id WHERE '+condition;
          return json(200,{
            total:get('SELECT count(*) n'+from,'%'+q+'%','%'+q+'%').n,
            users:all('SELECT u.id,u.username,u.name,u.role,u.suspended,u.created,r.email AS recoveryEmail,r.verified AS emailVerified'+from+' ORDER BY u.created DESC,u.id LIMIT 100','%'+q+'%','%'+q+'%'),
          });
        }
        if (path === "/api/admin/password-resets" && req.method === "GET")
          return json(200, {
            requests: all(
              "SELECT p.id,p.username,p.user_id,p.contact,p.note,p.status,p.created,u.name FROM password_resets p LEFT JOIN users u ON u.id=p.user_id ORDER BY p.status='open' DESC,p.created DESC,p.rowid DESC LIMIT 100",
            ),
          });
        const resetRoute = path.match(
          /^\/api\/admin\/password-resets\/([a-f0-9-]{36})\/(reset|dismiss)$/,
        );
        if (resetRoute && req.method === "POST") {
          const r = get("SELECT * FROM password_resets WHERE id=?", resetRoute[1]);
          if (!r) fail(404, "Không tìm thấy yêu cầu.");
          if (resetRoute[2] === "dismiss") {
            run("INSERT INTO moderation VALUES(?,?,?,?)",randomUUID(),"dismiss-password-request:"+me.id,r.user_id||r.id,Date.now());
            run(
              "UPDATE password_resets SET status='dismissed',handled=? WHERE id=?",
              Date.now(),
              r.id,
            );
            return json(200, { ok: true });
          }
          if (!r.user_id || !user(r.user_id))
            fail(404, "Tên đăng nhập này không tồn tại.");
          const temp = await resetPassword(r.user_id);
          run(
            "INSERT INTO moderation VALUES(?,?,?,?)",
            randomUUID(),
            "reset-password:" + me.id,
            r.user_id,
            Date.now(),
          );
          return json(200, { ok: true, username: r.username, temporaryPassword: temp });
        }
        if (path === "/api/admin/moderate" && req.method === "POST") {
          const b = await body(req);
          try {
            applyModeration(db, b.action, b.target, me.id);
          } catch (e) {
            fail(400, e.message);
          }
          return json(200, { ok: true });
        }
        fail(404, "Không tìm thấy API quản trị.");
      }
      if(path==='/api/me/sessions'&&req.method==='GET'){
        const current=(req.headers.cookie||'').split(';').map(x=>x.trim()).find(x=>x.startsWith('kinnect_session='))?.slice(16);
        return json(200,{sessions:all('SELECT s.token,s.expires,i.label,i.created FROM sessions s LEFT JOIN session_info i ON i.token=s.token WHERE s.user_id=? AND s.expires>? ORDER BY i.created DESC',me.id,Date.now()).map(r=>({id:digest(r.token+me.id).slice(0,32),label:r.label||'Trình duyệt web',created:r.created||null,expires:r.expires,current:!!current&&r.token===digest(current)}))});
      }
      const sessionRoute=path.match(/^\/api\/me\/sessions\/([a-f0-9]{32})$/);
      if(sessionRoute&&req.method==='DELETE'){
        const current=(req.headers.cookie||'').split(';').map(x=>x.trim()).find(x=>x.startsWith('kinnect_session='))?.slice(16);
        const target=all('SELECT s.token,i.device_hash FROM sessions s LEFT JOIN session_info i ON i.token=s.token WHERE s.user_id=?',me.id).find(r=>digest(r.token+me.id).slice(0,32)===sessionRoute[1]);
        if(!target)fail(404,'Phiên đăng nhập không còn tồn tại.');if(current&&target.token===digest(current))fail(400,'Dùng Đăng xuất để kết thúc phiên hiện tại.');
        if(target.device_hash)run('DELETE FROM remembered_accounts WHERE device=? AND user_id=?',target.device_hash,me.id);
        run('DELETE FROM sessions WHERE token=? AND user_id=?',target.token,me.id);return json(200,{ok:true});
      }
      if (path === "/api/me/password" && req.method === "POST") {
        const b = await body(req, 4000);
        if (
          typeof b.current !== "string" ||
          typeof b.next !== "string" ||
          b.next.length < 6 ||
          b.next.length > 128
        )
          fail(400, "Mật khẩu mới cần 6–128 ký tự.");
        const old = await scrypt(b.current, me.salt, 64);
        if (!timingSafeEqual(old, Buffer.from(me.password, "hex")))
          fail(400, "Mật khẩu hiện tại không đúng.");
        const salt = randomBytes(16).toString("hex");
        const hash = (await scrypt(b.next, salt, 64)).toString("hex");
        run("UPDATE users SET password=?,salt=? WHERE id=?", hash, salt, me.id);
        remembered.revoke(me.id);
        // Đăng xuất các thiết bị khác, giữ phiên hiện tại.
        const token = (req.headers.cookie || "")
          .split(";")
          .map((x) => x.trim())
          .find((x) => x.startsWith("kinnect_session="))
          ?.slice(16);
        run(
          "DELETE FROM sessions WHERE user_id=? AND token<>?",
          me.id,
          token ? digest(token) : "",
        );
        return json(200, { ok: true });
      }
      if (path === "/api/me/activity" && req.method === "POST") {
        run("UPDATE users SET last_active=? WHERE id=?", Date.now(), me.id);
        return json(200, { ok: true });
      }
      if (path === "/api/me/location" && req.method === "PATCH") {
        const b = await body(req);
        if (b.enabled === false) {
          run(
            "UPDATE users SET lat=NULL,lng=NULL,location_at=NULL WHERE id=?",
            me.id,
          );
          return json(200, { user: own(user(me.id)) });
        }
        if (
          b.enabled !== true ||
          typeof b.latitude !== "number" ||
          typeof b.longitude !== "number" ||
          !Number.isFinite(b.latitude) ||
          !Number.isFinite(b.longitude) ||
          Math.abs(b.latitude) > 90 ||
          Math.abs(b.longitude) > 180
        )
          fail(400, "Cần vị trí hợp lệ và đồng ý bật tìm quanh đây.");
        run(
          "UPDATE users SET lat=?,lng=?,location_at=?,location_precision=100 WHERE id=?",
          Math.round(b.latitude * 10000) / 10000,
          Math.round(b.longitude * 10000) / 10000,
          Date.now(),
          me.id,
        );
        return json(200, { user: own(user(me.id)) });
      }
      if (path === "/api/me" && req.method === "GET") {ai.welcome(me.id);return json(200, { user: own(me) });}
      if (path === "/api/me" && req.method === "PATCH") {
        const b = await body(req);
        const interests = Array.isArray(b.interests)
          ? [
              ...new Set(
                b.interests
                  .map((v) => text(v, 30).toLowerCase())
                  .filter(Boolean),
              ),
            ].slice(0, 10)
          : JSON.parse(me.interests);
        if (
          b.dmMode !== undefined &&
          !["mutual", "everyone", "friends"].includes(b.dmMode)
        )
          fail(400, "Cài đặt tin nhắn không hợp lệ.");
        if(b.showDistance!==undefined&&typeof b.showDistance!=='boolean')fail(400,'Cài đặt khoảng cách không hợp lệ.');
        const optionalText = (key, column, maximum) => {
          if (b[key] !== undefined && typeof b[key] !== "string") fail(400, "Thông tin hồ sơ không hợp lệ.");
          return b[key] === undefined ? me[column] : text(b[key], maximum);
        };
        const date = b.birthDate === undefined ? me.profile_dob : b.birthDate;
        if(typeof date!=='string'||(date&&(birthAge(date)===null||birthAge(date)<18||birthAge(date)>99)))fail(400,'Ngày sinh phải hợp lệ và đủ 18 đến 99 tuổi.');
        const age = date ? birthAge(date) : b.age === undefined ? me.age : b.age;
        const visibility=JSON.parse(me.profile_visibility||'{}');
        if(b.profileVisibility!==undefined){if(!b.profileVisibility||Array.isArray(b.profileVisibility)||typeof b.profileVisibility!=='object')fail(400,'Cài đặt hiển thị không hợp lệ.');for(const key of ['bio','age','gender','orientation','communityRole','pronouns','relationshipRole','lookingFor','city','interests','height','weight','occupation','school']){if(b.profileVisibility[key]!==undefined){if(typeof b.profileVisibility[key]!=='boolean')fail(400,'Cài đặt hiển thị không hợp lệ.');visibility[key]=b.profileVisibility[key];}}}
        const details=JSON.parse(me.profile_details||'{}');for(const key of ['occupation','school'])if(b[key]!==undefined){if(typeof b[key]!=='string')fail(400,'Thông tin hồ sơ không hợp lệ.');details[key]=text(b[key],100);}
        for(const [key,min,max] of [['height',80,250],['weight',20,400]])if(b[key]!==undefined){const value=b[key]===''||b[key]===null?null:Number(b[key]);if(value!==null&&(!Number.isInteger(value)||value<min||value>max))fail(400,'Chiều cao hoặc cân nặng không hợp lệ.');details[key]=value;}
        if (age !== null && (!Number.isInteger(age) || age < 18 || age > 99)) fail(400, "Tuổi cần từ 18 đến 99, hoặc để trống.");
        const profile = {
          gender: optionalText("gender", "gender", 60),
          orientation: optionalText("orientation", "orientation", 60),
          relationshipRole: optionalText("relationshipRole", "relationship_role", 40),
          pronouns: optionalText("pronouns", "pronouns", 30),
          city: optionalText("city", "city", 80),
          lookingFor: optionalText("lookingFor", "looking_for", 300),
        };
        run(
          "UPDATE users SET name=?,bio=?,interests=?,discoverable=?,dm_mode=? WHERE id=?",
          text(b.name, 60) || me.name,
          b.bio === undefined ? me.bio : text(b.bio, 500),
          JSON.stringify(interests),
          typeof b.discoverable === "boolean"
            ? Number(b.discoverable)
            : me.discoverable,
          b.dmMode === undefined ? me.dm_mode : b.dmMode==='friends'?'friends':'everyone',
          me.id,
        );
        run("UPDATE users SET age=?,gender=?,orientation=?,relationship_role=?,pronouns=?,city=?,looking_for=?,identity_public=?,show_activity=? WHERE id=?",
          age, profile.gender, profile.orientation, profile.relationshipRole, profile.pronouns, profile.city, profile.lookingFor,
          typeof b.identityPublic === "boolean" ? Number(b.identityPublic) : me.identity_public,
          typeof b.showActivity === "boolean" ? Number(b.showActivity) : me.show_activity, me.id);
        if(b.communityRole!==undefined){if(typeof b.communityRole!=='string')fail(400,'Vai trò không hợp lệ.');const role=text(b.communityRole,60);if(!["","Top","Bottom","Vers","Vers Top","Vers Bottom","Side","Femme","Masc / Butch","Androgynous","Stem","Đang tìm hiểu","Khác"].includes(role))fail(400,"Vai trò không hợp lệ.");run("UPDATE users SET community_role=? WHERE id=?",role,me.id);}
        if(b.showDistance!==undefined)run("UPDATE users SET show_distance=? WHERE id=?",Number(b.showDistance),me.id);
        run("UPDATE users SET profile_dob=?,profile_visibility=?,profile_details=? WHERE id=?",date,JSON.stringify(visibility),JSON.stringify(details),me.id);
        return json(200, { user: own(user(me.id)) });
      }
      if (["/api/me/avatar","/api/me/cover"].includes(path) && req.method === "POST") {
        const b = await body(req);
        if (
          typeof b.data !== "string" ||
          !/^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$/.test(b.data)
        )
          fail(400, "Chọn ảnh PNG, JPEG hoặc WebP.");
        const [prefix, encoded] = b.data.split(",");
        const bytes = Buffer.from(encoded, "base64");
        if (bytes.length > 1024 * 1024 || bytes.length < 16)
          fail(400, "Ảnh phải nhỏ hơn 1 MB.");
        const type = prefix.slice(5, prefix.indexOf(";"));
        const valid =
          type === "image/png"
            ? bytes
                .subarray(0, 8)
                .equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
            : type === "image/jpeg"
              ? bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255
              : bytes.toString("ascii", 0, 4) === "RIFF" &&
                bytes.toString("ascii", 8, 12) === "WEBP";
        if (!valid) fail(400, "Định dạng ảnh không hợp lệ.");
        run(
          path.endsWith("/cover")?"UPDATE users SET cover=?,cover_type=? WHERE id=?":"UPDATE users SET avatar=?,avatar_type=? WHERE id=?",
          bytes,
          type,
          me.id,
        );
        if(!path.endsWith('/cover'))ai.enqueue('avatar',me.id,me.id,{text:'Kiểm tra ảnh đại diện theo quy tắc cộng đồng Kinnect.',image:{mime:type,data:bytes.toString('base64')}});
        const updateId=randomUUID(),coverUpdate=path.endsWith('/cover');
        run('INSERT INTO posts(id,user_id,body,visibility,created) VALUES(?,?,?,?,?)',updateId,me.id,coverUpdate?'đã cập nhật ảnh bìa.':'đã cập nhật ảnh đại diện.','public',Date.now());
        run('INSERT INTO post_media VALUES(?,?,?)',updateId,type,bytes);
        return json(200, { user: own(user(me.id)) });
      }
      if (path === "/api/discover" && req.method === "GET") {
        const query = new URL(req.url, "http://local").searchParams,
          nearby = query.get("nearby") === "1";
        if (
          nearby &&
          (me.lat === null ||
            me.lng === null ||
            Date.now() - (me.location_at || 0) > 86400000)
        )
          fail(
            400,
            "Bật tìm quanh đây và cập nhật vị trí để xem thành viên gần bạn.",
          );
        const q = text(query.get("q"), 60).replace(/^@/, "").toLowerCase(),
          mine = JSON.parse(me.interests),
          order = query.get("sort") || "new";
        if (!["new", "active", "interests"].includes(order)) fail(400, "Cách sắp xếp không hợp lệ.");
        const distance = (u) => {
          const radians = (d) => (d * Math.PI) / 180;
          const dlat = radians(u.lat - me.lat),
            dlng = radians(u.lng - me.lng);
          return (
            6371 *
            2 *
            Math.asin(
              Math.min(
                1,
                Math.sqrt(
                  Math.sin(dlat / 2) ** 2 +
                    Math.cos(radians(me.lat)) *
                      Math.cos(radians(u.lat)) *
                      Math.sin(dlng / 2) ** 2,
                ),
              ),
            )
          );
        };
        const meters=u=>Math.max(0,Math.round(distance(u)*10)*100);
        const distanceLabel=m=>m<100?'< 100 m':m<1000?m+' m':(m/1000).toLocaleString('vi-VN',{minimumFractionDigits:1,maximumFractionDigits:1})+' km';
        const users = all(
          "SELECT * FROM users WHERE id<>? AND discoverable=1 AND suspended=0 ORDER BY created DESC LIMIT 500",
          me.id,
        )
          .filter(
            (u) =>
              !blocked(me.id, u.id) &&
              (query.get("following")!=="1"||follows(me.id,u.id)) &&
              (!nearby ||
                (u.lat !== null &&
                  u.lng !== null &&
                  Date.now() - (u.location_at || 0) < 86400000 &&
                  distance(u) <= Math.min(100,Math.max(1,Number(query.get("radius"))||100)))),
          )
          .map((u) => {
            const roundedMeters = nearby ? meters(u) : null;
            return {
              ...publicUser(u, me.id),
              score: publicUser(u, me.id).interests.filter((v) => mine.includes(v))
                .length,
              ...(nearby
                ? {
                    distanceBand: u.show_distance ? distanceLabel(roundedMeters) : "",
                    distanceLabel: u.show_distance ? distanceLabel(roundedMeters) : "",
                    _sortDistance: roundedMeters,
                    ...(u.show_distance ? {distanceMeters:roundedMeters}:{}),
                  }
                : {}),
            };
          })
          .filter(
            (u) =>
              !q ||
              adminSearchKey([u.name, u.username, u.city, u.gender, u.orientation, u.relationshipRole, ...u.interests].join(" ")).includes(adminSearchKey(q)),
          )
          .sort((a, b) =>
            nearby ? a._sortDistance - b._sortDistance || b.joinedAt - a.joinedAt :
              order === "interests" ? b.score - a.score || b.joinedAt - a.joinedAt :
              b.joinedAt - a.joinedAt,
          )
          .filter((u) => order !== "active" || u.isActive)
          .filter(u=>{
            const normalize=v=>adminSearchKey(String(v||''));
            const wanted=normalize(query.get('gender')),actual=normalize(u.gender);
            const canonical=v=>['nam','male','man'].includes(v)?'nam':['nu','female','woman'].includes(v)?'nu':v;
            if(wanted&&(!actual||canonical(actual)!==canonical(wanted)))return false;
            for(const key of ['orientation','communityRole']){const wanted=normalize(query.get(key));if(wanted&&normalize(u[key])!==wanted)return false;}
            for(const key of ['height','weight']){const suffix=key[0].toUpperCase()+key.slice(1),low=Number(query.get('min'+suffix))||0,high=Number(query.get('max'+suffix))||0,value=u[key];if((low||high)&&(!Number.isFinite(value)||low&&value<low||high&&value>high))return false;}
            const min=Number(query.get('minAge'))||0,max=Number(query.get('maxAge'))||0;
            if((min||max)&&(!Number.isFinite(u.age)||min&&u.age<min||max&&u.age>max))return false;
            const intent=normalize(query.get('intent'));if(intent&&!normalize(u.lookingFor).includes(intent))return false;
            return true;
          })
          .sort((a,b)=>query.get('recent')==='1'?(b.lastActiveAt||0)-(a.lastActiveAt||0)||(nearby?a._sortDistance-b._sortDistance:b.joinedAt-a.joinedAt):0)
          .slice(0, 50)
          .map(({ band, _sortDistance, ...u }) => u);
        return json(200, { users, filtersApplied:true, filterVersion:2 });
      }
      const connections=path.match(/^\/api\/users\/([a-zA-Z0-9-]+)\/(followers|following)$/);
      if(connections&&req.method==='GET'){
       const [,id,kind]=connections;const owner=user(id);if(!owner||owner.suspended||blocked(me.id,id))fail(404,'Không tìm thấy hồ sơ.');
       const people=all(kind==='followers'?'SELECT u.* FROM users u JOIN follows f ON f.actor=u.id WHERE f.target=? ORDER BY u.name,u.id':'SELECT u.* FROM users u JOIN follows f ON f.target=u.id WHERE f.actor=? ORDER BY u.name,u.id',id).filter(u=>!u.suspended&&!blocked(me.id,u.id)).map(u=>publicUser(u,me.id));
       return json(200,{users:people});
      }
      const stats = path.match(/^\/api\/users\/([a-zA-Z0-9-]+)\/stats$/);
      if (stats && req.method === "GET") {
        const u = user(stats[1]);
        if (!u || u.suspended || blocked(me.id, u.id)) fail(404, "Không tìm thấy người dùng.");
        return json(200, {
          user: publicUser(u, me.id),
          followers: get("SELECT count(*) AS n FROM follows WHERE target=?", u.id).n,
          following: get("SELECT count(*) AS n FROM follows WHERE actor=?", u.id).n,
          posts: get("SELECT count(*) AS n FROM posts WHERE user_id=? AND hidden=0", u.id).n,
        });
      }
      const route = path.match(
        /^\/api\/users\/([a-zA-Z0-9-]+)(?:\/(follow|block|messages|avatar|cover))?$/,
      );
      if (route) {
        const [, id, action] = route;
        if (id === me.id && action && !["avatar","cover"].includes(action))
          fail(400, "Không thể thao tác với chính mình.");
        if (action === "block") {
          if (!user(id)) fail(404, "Không tìm thấy người dùng.");
          if (req.method === "POST") {
            run("INSERT OR IGNORE INTO blocks VALUES(?,?)", me.id, id);
            privateAlbum.revokeBetween(me.id,id);
            friendConnections.removeBetween(me.id,id);
            run(
              "DELETE FROM follows WHERE (actor=? AND target=?) OR (actor=? AND target=?)",
              me.id,
              id,
              id,
              me.id,
            );
            return json(200, { ok: true, blocked: id });
          }
          if (req.method === "DELETE") {
            run("DELETE FROM blocks WHERE actor=? AND target=?", me.id, id);
            return json(200, { ok: true });
          }
        }
        const target = targetUser(id, me);
        if (!action && req.method === "GET")
          return json(200, { user: publicUser(target, me.id) });
        if (["avatar","cover"].includes(action) && req.method === "GET") {
          const image=action==="cover"?target.cover:target.avatar,imageType=action==="cover"?target.cover_type:target.avatar_type;
          if (!image) fail(404, "Chưa có ảnh.");
          res.writeHead(200, {
            "Content-Type": imageType,
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
          });
          res.end(Buffer.from(image));
          return;
        }
        if (action === "follow") {
          if (req.method === "POST") {
            const result = run(
              "INSERT OR IGNORE INTO follows VALUES(?,?)",
              me.id,
              id,
            );
            if (result.changes) notice(id, me.id, "follow", me.id);
            return json(200, { user: publicUser(target, me.id) });
          }
          if (req.method === "DELETE") {
            run("DELETE FROM follows WHERE actor=? AND target=?", me.id, id);
            return json(200, { user: publicUser(target, me.id) });
          }
        }
        if (action === "messages") {
          if(req.method==='DELETE'){messageState.clear('direct',id,me.id);return json(200,{ok:true});}
          if (req.method === "GET") {
            messageState.markRead("direct",id,me.id);
            const readAt=Date.now();
            run("INSERT INTO message_receipts(message_id,delivered_at,seen_at) SELECT id,?,? FROM messages WHERE sender=? AND recipient=? ON CONFLICT(message_id) DO UPDATE SET delivered_at=COALESCE(delivered_at,excluded.delivered_at),seen_at=COALESCE(seen_at,excluded.seen_at)",readAt,readAt,id,me.id);
            run("UPDATE notifications SET seen=1 WHERE user_id=? AND actor=? AND kind IN ('message','missed_call')", me.id, id);
            return json(200, {
              user:publicUser(target,me.id),
              aiSupport:ai.supportInfo(me.id,id),
              messages: all(
                "SELECT id,sender,recipient,body,created FROM messages WHERE (sender=? AND recipient=?) OR (sender=? AND recipient=?) ORDER BY created DESC,rowid DESC LIMIT 100",
                me.id,
                id,
                id,
                me.id,
              ).reverse().filter(m=>messageState.visible("direct",m.id,me.id)).map(m=>messageState.decorate("direct",{...m,privateAlbum:privateAlbum.messageMetadata(m.id),receipt:get("SELECT delivered_at AS deliveredAt,seen_at AS seenAt FROM message_receipts WHERE message_id=?",m.id)||{},attachment:attachments.metadata("direct",m.id)},me.id)),
            });
          }
          if (req.method === "POST") {
            if(target.dm_mode==='friends'&&friendConnections.status(me.id,id)!=='friends')fail(403,'Người này chỉ nhận tin nhắn từ bạn bè.');
            const b = await body(req,29000000),
              content = text(b.body, 2000);
            const file=attachments.decode(b.attachment);
            if (!content&&!file) fail(400, "Nhập nội dung hoặc chọn tệp.");
            const message = {
              id: randomUUID(),
              sender: me.id,
              recipient: id,
              body: content,
              created: Date.now(),
            };
            run(
              "INSERT INTO messages VALUES(?,?,?,?,?)",
              message.id,
              me.id,
              id,
              content,
              message.created,
            );
            attachments.save("direct",message.id,file);
            messageState.reveal("direct",id,me.id);messageState.reveal("direct",me.id,id);
            notice(id, me.id, "message", message.id);
            if(me.role==='admin')ai.pause(id,true);else ai.support(message);
            return json(201, { message });
          }
        }
      }
      if (path === "/api/blocks" && req.method === "GET")
        return json(200, {
          users: all(
            "SELECT u.* FROM users u JOIN blocks b ON b.target=u.id WHERE b.actor=?",
            me.id,
          ).map((u) => publicUser(u, me.id)),
        });
      if (path === "/api/conversations" && req.method === "GET") {
        const people = all(
          "SELECT * FROM users WHERE id IN (SELECT recipient FROM messages WHERE sender=? UNION SELECT sender FROM messages WHERE recipient=?)",
          me.id,
          me.id,
        )
          .filter((u) => !u.suspended && !blocked(me.id, u.id)&&!messageState.hidden("direct",u.id,me.id))
          .map((u) => {
            const last = get(
              "SELECT id,sender,body,created FROM messages WHERE ((sender=? AND recipient=?) OR (sender=? AND recipient=?)) AND id NOT IN (SELECT message_id FROM hidden_chat_messages WHERE kind='direct' AND user_id=?) ORDER BY created DESC,rowid DESC LIMIT 1",
              me.id,
              u.id,
              u.id,
              me.id,
              me.id,
            );
            return {
              ...publicUser(u, me.id),
              pinned:messageState.pinnedConversation("direct",u.id,me.id),muted:messageState.muted("direct",u.id,me.id),
              unread: Math.max(messageState.manualUnread("direct",u.id,me.id)?1:0,get("SELECT COUNT(*) AS count FROM notifications WHERE user_id=? AND actor=? AND kind IN ('message','missed_call') AND seen=0",me.id,u.id).count),
              last: last ? { body: messageState.recalled("direct",last.id)?"Tin nhắn đã được thu hồi":last.body.slice(0, 120)||attachments.metadata("direct",last.id)?.name||"Tệp đính kèm", created: last.created, mine: last.sender === me.id } : null,
            };
          })
          .sort((a, b) => (b.last?.created || 0) - (a.last?.created || 0));
        return json(200, { users: people });
      }
      const storyAction=path.match(/^\/api\/stories\/([a-zA-Z0-9-]+)\/(view|viewers)$/);
      if(storyAction){const [,id,action]=storyAction,p=get('SELECT p.*,s.expires FROM posts p JOIN post_stories s ON s.post_id=p.id WHERE p.id=? AND p.hidden=0',id);if(!p||p.expires<=Date.now()||user(p.user_id)?.suspended||blocked(me.id,p.user_id)||(p.user_id!==me.id&&!follows(me.id,p.user_id)))fail(404,'Tin không còn khả dụng.');
        if(action==='view'&&req.method==='POST'){if(p.user_id!==me.id)run('INSERT OR IGNORE INTO story_views(post_id,user_id,viewed_at) VALUES(?,?,?)',id,me.id,Date.now());return json(200,{ok:true});}
        if(action==='viewers'&&req.method==='GET'){if(p.user_id!==me.id)fail(403,'Chỉ chủ tin được xem danh sách người xem.');const viewers=all('SELECT v.user_id,v.viewed_at FROM story_views v WHERE post_id=? ORDER BY viewed_at DESC',id).filter(v=>user(v.user_id)?.suspended===0&&!blocked(me.id,v.user_id)).map(v=>({...publicUser(user(v.user_id),me.id),viewedAt:v.viewed_at}));return json(200,{viewers,count:viewers.length});}
        fail(405,'Phương thức không hợp lệ.');
      }
      if (path === "/api/stories" && req.method === "GET") {
        const stories = all("SELECT p.id,p.user_id,p.body,p.created,s.expires,s.background,m.type FROM posts p JOIN post_stories s ON s.post_id=p.id LEFT JOIN post_media m ON m.post_id=p.id JOIN users u ON u.id=p.user_id WHERE p.hidden=0 AND u.suspended=0 AND s.expires>? AND (p.user_id=? OR p.user_id IN (SELECT target FROM follows WHERE actor=?)) ORDER BY p.created DESC LIMIT 100", Date.now(),me.id,me.id)
          .filter(p=>!blocked(me.id,p.user_id)).map(p=>({...p,viewCount:p.user_id===me.id?all('SELECT user_id FROM story_views WHERE post_id=?',p.id).filter(v=>user(v.user_id)?.suspended===0&&!blocked(me.id,v.user_id)).length:undefined,author:publicUser(user(p.user_id),me.id),media:p.type?{kind:p.type.startsWith("video/")?"video":"image",url:"/api/posts/"+p.id+"/media"}:null}));
        return json(200,{stories});
      }
      const mediaRoute=path.match(/^\/api\/posts\/([a-zA-Z0-9-]+)\/media$/);
      if(mediaRoute && ["GET","HEAD"].includes(req.method)){
        const p=get("SELECT p.*,u.suspended FROM posts p JOIN users u ON u.id=p.user_id WHERE p.id=? AND p.hidden=0",mediaRoute[1]);
        const story=get("SELECT expires FROM post_stories WHERE post_id=?",mediaRoute[1]);
        if(!p||p.suspended||blocked(me.id,p.user_id)||(p.visibility!=="public"&&p.user_id!==me.id&&!follows(me.id,p.user_id))||(story&&story.expires<=Date.now()))fail(404,"Không tìm thấy nội dung.");
        const media=get("SELECT type,data FROM post_media WHERE post_id=?",p.id);if(!media)fail(404,"Không có ảnh/video.");
        return sendPostMedia(req,res,media,fail);
      }
      if (path === "/api/posts" || (path === "/api/stories" && req.method === "POST")) {
        if (req.method === "POST") {
          const b = await body(req, Number.MAX_SAFE_INTEGER),
            content = text(b.body, 2000), media = decodePostMedia(b.media, fail);
          if (
            (!content && !media) ||
            !["public", "followers"].includes(b.visibility || "public")
          )
            fail(400, "Nội dung hoặc quyền xem không hợp lệ.");
          const category=b.category||'community';if(!['community','confessions','questions','events'].includes(category))fail(400,'Mục đăng bài không hợp lệ.');
          const id = randomUUID();

          db.exec("BEGIN IMMEDIATE");
          try {
          run(
            "INSERT INTO posts VALUES(?,?,?,?,0,?)",
            id,
            me.id,
            content,
            path === "/api/stories" ? "followers" : b.visibility || "public",
            Date.now(),
          );
          if(path!=="/api/stories")run('INSERT INTO post_categories VALUES(?,?)',id,category);
          if(media) run("INSERT INTO post_media VALUES(?,?,?)",id,media.type,media.bytes);
          if(path === "/api/stories") run("INSERT INTO post_stories(post_id,expires,background) VALUES(?,?,?)",id,Date.now()+86400000,["purple","sunset","forest","ocean"].includes(b.background)?b.background:"purple");
          db.exec("COMMIT");
          } catch(error) { db.exec("ROLLBACK"); throw error; }
          ai.enqueue('post',id,me.id,{text:content||'Kiểm tra nội dung bài viết.',...(media&&['image/png','image/jpeg'].includes(media.type)?{image:{mime:media.type,data:media.bytes.toString('base64')}}:{})});
          return json(201, { id });
        }
        if (req.method === "GET") {
          const params=new URL(req.url,"http://local").searchParams,only=params.get('user'),postId=params.get('post'),category=params.get('category');if(category&&!['community','confessions','questions','events'].includes(category))fail(400,'Mục không hợp lệ.');
          const posts = all(
            "SELECT p.*,COALESCE(pc.category,'community') AS category FROM posts p LEFT JOIN post_categories pc ON pc.post_id=p.id JOIN users u ON u.id=p.user_id WHERE p.hidden=0 AND u.suspended=0 AND p.id NOT IN (SELECT post_id FROM post_stories)" +
              (only ? " AND p.user_id=?" : "") + (postId ? " AND p.id=?" : "") +
              (category?" AND COALESCE(pc.category,'community')=?":"") +
              " ORDER BY p.created DESC,p.rowid DESC LIMIT 500",
            ...(only ? [only] : []),...(postId?[postId]:[]),...(category?[category]:[]),
          )
            .filter(
              (p) =>
                !blocked(me.id, p.user_id) &&
                (p.visibility === "public" ||
                  p.user_id === me.id ||
                  follows(me.id, p.user_id)),
            )
            .slice(0, 100)
            .map((p) => ({
              ...p,
              author: publicUser(user(p.user_id), me.id),
              media: get("SELECT type FROM post_media WHERE post_id=?",p.id) ? {kind:get("SELECT type FROM post_media WHERE post_id=?",p.id).type.startsWith("video/")?"video":"image",url:"/api/posts/"+p.id+"/media"}:null,
              likes: get("SELECT count(*) AS n FROM post_likes WHERE post_id=?", p.id).n,
              myReaction: get('SELECT reaction FROM post_likes WHERE post_id=? AND user_id=?',p.id,me.id)?.reaction||null,
              reactions: Object.fromEntries(all('SELECT reaction,COUNT(*) AS n FROM post_likes WHERE post_id=? GROUP BY reaction',p.id).map(r=>[r.reaction,r.n])),
              liked: !!get("SELECT 1 FROM post_likes WHERE post_id=? AND user_id=?", p.id, me.id),
              comments: get("SELECT count(*) AS n FROM post_comments WHERE post_id=?", p.id).n,
            }));
          return json(200, { posts });
        }
      }
      const commentEdit=path.match(/^\/api\/posts\/([a-zA-Z0-9-]+)\/comments\/([a-zA-Z0-9-]+)$/);
      if(commentEdit){
        const [,pid,cid]=commentEdit,p=get('SELECT * FROM posts WHERE id=? AND hidden=0',pid),c=get('SELECT * FROM post_comments WHERE id=? AND post_id=? AND user_id=?',cid,pid,me.id);
        if(!p||!c||blocked(me.id,p.user_id)||user(p.user_id)?.suspended||(p.visibility==='followers'&&p.user_id!==me.id&&!follows(me.id,p.user_id)))fail(404,'Không tìm thấy bình luận của bạn.');
        if(req.method==='PATCH'){const b=await body(req,4000),content=text(b.body,1000);if(!content)fail(400,'Nhập bình luận.');run('UPDATE post_comments SET body=? WHERE id=?',content,cid);return json(200,{ok:true});}
        if(req.method==='DELETE'){
          db.exec('BEGIN');try{
            const parent=get("SELECT parent_id FROM comment_threads WHERE kind='post' AND comment_id=?",cid)?.parent_id;
            if(parent)run("UPDATE comment_threads SET parent_id=? WHERE kind='post' AND parent_id=?",parent,cid);else run("DELETE FROM comment_threads WHERE kind='post' AND parent_id=?",cid);
            run("DELETE FROM comment_reactions WHERE kind='post' AND comment_id=?",cid);run("DELETE FROM comment_threads WHERE kind='post' AND comment_id=?",cid);run('DELETE FROM notification_targets WHERE comment_id=?',cid);run('DELETE FROM post_comments WHERE id=?',cid);db.exec('COMMIT');
          }catch(err){db.exec('ROLLBACK');throw err;}
          return json(200,{ok:true,comments:get('SELECT count(*) AS n FROM post_comments WHERE post_id=?',pid).n});
        }
        fail(405,'Phương thức không hợp lệ.');
      }
      const postReactors = path.match(/^\/api\/posts\/([a-zA-Z0-9-]+)\/reactions$/);
      if (postReactors) {
        if (req.method !== "GET") fail(405, "Phương thức không hợp lệ.");
        const p = get("SELECT * FROM posts WHERE id=? AND hidden=0", postReactors[1]);
        if (!p || blocked(me.id, p.user_id) || user(p.user_id)?.suspended || (p.visibility === "followers" && p.user_id !== me.id && !follows(me.id, p.user_id)))
          fail(404, "Không tìm thấy bài viết.");
        const users = all("SELECT user_id,reaction FROM post_likes WHERE post_id=? ORDER BY created DESC LIMIT 500", p.id)
          .map((r) => ({ r, u: user(r.user_id) }))
          .filter(({ r, u }) => u && !u.suspended && !blocked(me.id, r.user_id))
          .map(({ r, u }) => ({ ...publicUser(u, me.id), reaction: r.reaction }));
        return json(200, { users });
      }
      const postAction = path.match(/^\/api\/posts\/([a-zA-Z0-9-]+)\/(like|comments)(?:\/([a-zA-Z0-9-]+)\/reaction)?$/);
      if (postAction) {
        const [, pid, what, commentId] = postAction;
        const p = get("SELECT * FROM posts WHERE id=? AND hidden=0", pid);
        if (
          !p ||
          blocked(me.id, p.user_id) ||
          user(p.user_id)?.suspended ||
          (p.visibility === "followers" && p.user_id !== me.id && !follows(me.id, p.user_id))
        )
          fail(404, "Không tìm thấy bài viết.");
        if(commentId){if(req.method!=='POST')fail(405,'Phương thức không hợp lệ.');const b=await body(req);return json(200,{comment:threads.react('post',pid,commentId,me,b.reaction)});}
        if (what === "like") {
          if (req.method === "POST") {
            const b=await body(req),reaction=b.reaction||'like';if(!['like','love','haha','wow','sad','angry'].includes(reaction))fail(400,'Biểu cảm không hợp lệ.');
            const hadReaction=!!get("SELECT 1 FROM post_likes WHERE post_id=? AND user_id=?",pid,me.id);
            const r = run("INSERT INTO post_likes(post_id,user_id,created,reaction) VALUES(?,?,?,?) ON CONFLICT(post_id,user_id) DO UPDATE SET reaction=excluded.reaction", pid, me.id, Date.now(),reaction);
            if (r.changes&&!hadReaction) notice(p.user_id, me.id, "like", pid);
          } else if (req.method === "DELETE")
            run("DELETE FROM post_likes WHERE post_id=? AND user_id=?", pid, me.id);
          else fail(405, "Phương thức không hợp lệ.");
          return json(200, {
            likes: get("SELECT count(*) AS n FROM post_likes WHERE post_id=?", pid).n,
            liked: req.method === "POST",
            myReaction:get('SELECT reaction FROM post_likes WHERE post_id=? AND user_id=?',pid,me.id)?.reaction||null,
            reactions:Object.fromEntries(all('SELECT reaction,COUNT(*) AS n FROM post_likes WHERE post_id=? GROUP BY reaction',pid).map(r=>[r.reaction,r.n])),
          });
        }
        if (req.method === "GET")
          return json(200, {
            comments: all(
              "SELECT * FROM post_comments WHERE post_id=? ORDER BY created ASC LIMIT 200",
              pid,
            )
              .filter((c) => !blocked(me.id, c.user_id) && !user(c.user_id)?.suspended)
              .map((c) => ({ ...threads.decorate("post",c,me),author: publicUser(user(c.user_id), me.id) })),
          });
        if (req.method === "POST") {
          const b = await body(req, 4000);
          const content = text(b.body, 1000);
          if (!content) fail(400, "Nhập bình luận.");
          const parentId=threads.parent("post",pid,b.parentId,me);
          const id = randomUUID();
          run("INSERT INTO post_comments VALUES(?,?,?,?,?)", id, pid, me.id, content, Date.now());
          threads.link("post",id,parentId);
          const notificationId=notice(p.user_id, me.id, "comment", pid);
          if(notificationId)run('INSERT INTO notification_targets VALUES(?,?)',notificationId,id);
          if(parentId){const parent=get('SELECT user_id FROM post_comments WHERE id=?',parentId);if(parent&&parent.user_id!==p.user_id){const replyNotice=notice(parent.user_id,me.id,'comment_reply',pid);if(replyNotice)run('INSERT INTO notification_targets VALUES(?,?)',replyNotice,id);}}
          return json(201, { id });
        }
        fail(405, "Phương thức không hợp lệ.");
      }
      const post = path.match(/^\/api\/posts\/([a-zA-Z0-9-]+)$/);
      if(post && req.method==='PATCH'){
        const current=get('SELECT * FROM posts WHERE id=? AND user_id=? AND hidden=0',post[1],me.id);
        if(!current)fail(404,'Không tìm thấy bài viết của bạn.');
        const b=await body(req,Number.MAX_SAFE_INTEGER),content=b.body===undefined?current.body:text(b.body,2000),visibility=b.visibility===undefined?current.visibility:b.visibility;
        if(!['public','followers'].includes(visibility))fail(400,'Đối tượng xem không hợp lệ.');
        const media=b.media===undefined?null:decodePostMedia(b.media,fail);
        if(!content&&!media&&!get('SELECT post_id FROM post_media WHERE post_id=?',post[1]))fail(400,'Nhập nội dung hoặc chọn ảnh / video.');

        db.exec('BEGIN IMMEDIATE');try{run('UPDATE posts SET body=?,visibility=? WHERE id=?',content,visibility,post[1]);if(media)run('INSERT INTO post_media VALUES(?,?,?) ON CONFLICT(post_id) DO UPDATE SET type=excluded.type,data=excluded.data',post[1],media.type,media.bytes);db.exec('COMMIT');}catch(error){db.exec('ROLLBACK');throw error;}
        ai.enqueue('post',post[1],me.id,{text:content||'Kiểm tra nội dung bài viết đã chỉnh sửa.',...(media&&['image/png','image/jpeg'].includes(media.type)?{image:{mime:media.type,data:media.bytes.toString('base64')}}:{})});
        return json(200,{ok:true});
      }
      if (post && req.method === "DELETE") {
        const result = run(
          "DELETE FROM posts WHERE id=? AND user_id=?",
          post[1],
          me.id,
        );
        if (!result.changes) fail(404, "Không tìm thấy bài viết của bạn.");
        return json(200, { ok: true });
      }
      if (path === "/api/notifications") {
        if(req.method==='GET')run("INSERT INTO message_receipts(message_id,delivered_at) SELECT id,? FROM messages WHERE recipient=? ON CONFLICT(message_id) DO UPDATE SET delivered_at=COALESCE(delivered_at,excluded.delivered_at)",Date.now(),me.id);
        if (req.method === "GET")
          return json(200, {
            friendRequestsPending:friendConnections.pendingCount(me.id),
            ...(me.role==='admin'?{passwordResetsPending:get("SELECT count(*) AS n FROM password_resets WHERE status='open'").n}:{}),
            notifications: all(
              "SELECT * FROM notifications WHERE user_id=? ORDER BY created DESC,rowid DESC LIMIT 100",
              me.id,
            )
              .filter(
                (n) => !blocked(me.id, n.actor) && !user(n.actor)?.suspended,
              )
              .map((n) => { const commentId=get("SELECT comment_id FROM notification_targets WHERE notification_id=?",n.id)?.comment_id||null;
                // Short content preview for native push popups (message/comment text, post excerpt).
                const row=n.kind==="message"?get("SELECT body FROM messages WHERE id=?",n.ref)
                  :n.kind==="group_message"?get("SELECT body FROM group_messages WHERE group_id=? AND sender=? AND created<=? ORDER BY created DESC LIMIT 1",n.ref,n.actor,n.created+5000)
                  :n.kind==="comment"||n.kind==="comment_reply"?(commentId?get("SELECT body FROM post_comments WHERE id=?",commentId):get("SELECT body FROM post_comments WHERE post_id=? AND user_id=? ORDER BY created DESC LIMIT 1",n.ref,n.actor))
                  :n.kind==="like"?get("SELECT body FROM posts WHERE id=?",n.ref):null;
                const preview=row&&typeof row.body==="string"&&!row.body.startsWith("{")?row.body.replace(/\s+/g," ").trim().slice(0,160):"";
                return { ...n,preview,commentId,muted:n.kind==="message"?messageState.muted("direct",n.actor,me.id):n.kind==="group_message"?messageState.muted("group",n.ref,me.id):false, actor: publicUser(user(n.actor), me.id) }; }),
          });
        if (req.method === "POST") {
          const b = await body(req);
          if (b.ids !== undefined) {
            if (!Array.isArray(b.ids) || b.ids.length > 100 || b.ids.some(id => typeof id !== "string")) fail(400, "Danh sách thông báo không hợp lệ.");
            for (const id of b.ids) run("UPDATE notifications SET seen=1 WHERE id=? AND user_id=?", id, me.id);
          } else if(b.scope==="social")run("UPDATE notifications SET seen=1 WHERE user_id=? AND kind NOT IN ('message','group_message')",me.id);else run("UPDATE notifications SET seen=1 WHERE user_id=?", me.id);
          return json(200, { ok: true });
        }
      }
      if (path === "/api/reports" && req.method === "POST") {
        const b = await body(req),
          reason = text(b.reason, 1000);
        if (reason.length < 5) fail(400, "Mô tả lý do ít nhất 5 ký tự.");
        if (b.targetType === "user") {
          if (b.targetId === me.id || !user(b.targetId))
            fail(404, "Không tìm thấy đối tượng.");
        } else if (b.targetType === "post") {
          const p = get(
            "SELECT * FROM posts WHERE id=? AND hidden=0",
            b.targetId,
          );
          if (
            !p ||
            blocked(me.id, p.user_id) ||
            (p.visibility === "followers" &&
              p.user_id !== me.id &&
              !follows(me.id, p.user_id))
          )
            fail(404, "Không tìm thấy bài viết.");
        } else if (b.targetType === "message") {
          if (
            !get(
              "SELECT id FROM messages WHERE id=? AND (sender=? OR recipient=?)",
              b.targetId,
              me.id,
              me.id,
            )
          )
            fail(404, "Không tìm thấy tin nhắn.");
        } else if(b.targetType==='group_message'){
          if(!get('SELECT m.id FROM group_messages m JOIN group_members g ON g.group_id=m.group_id WHERE m.id=? AND g.user_id=?',b.targetId,me.id))fail(404,'Không tìm thấy tin nhắn nhóm trong nhóm bạn tham gia.');
        } else if (b.targetType === "short" || b.targetType === "comment") {
          const item =
            b.targetType === "short"
              ? get(
                  "SELECT user_id FROM shorts WHERE id=? AND hidden=0",
                  b.targetId,
                )
              : get(
                  "SELECT c.user_id FROM short_comments c JOIN shorts s ON s.id=c.short_id WHERE c.id=? AND s.hidden=0",
                  b.targetId,
                );
          if (
            !item ||
            blocked(me.id, item.user_id) ||
            user(item.user_id)?.suspended
          )
            fail(404, "Không tìm thấy nội dung.");
        } else if(b.targetType === "app") { b.targetId=me.id; } else fail(400, "Loại báo cáo không hợp lệ.");
        const id = randomUUID();
        run(
          "INSERT INTO reports(id,reporter,target_type,target_id,reason,created) VALUES(?,?,?,?,?,?)",
          id,
          me.id,
          b.targetType,
          b.targetId,
          reason,
          Date.now(),
        );
        return json(201, { id });
      }
      fail(404, "Không tìm thấy API.");
    } catch (e) {
      if (!res.headersSent)
        json(e.status || 500, { error: e.status ? e.message : "Lỗi máy chủ." });
      else res.end();
      if (!e.status) console.error("API failure:", e.code || e.name);
    }
  }
  function gift(sender, recipient, room, kind) {
    if (!["heart", "rainbow", "star"].includes(kind))
      throw new Error("Quà thử nghiệm không hợp lệ.");
    if (
      sender === recipient ||
      blocked(sender, recipient) ||
      user(recipient)?.suspended
    )
      throw new Error("Không thể gửi quà cho người này.");
    if (
      get(
        "SELECT count(*) AS n FROM gifts WHERE sender=? AND created>?",
        sender,
        Date.now() - 60000,
      ).n >= 5
    )
      throw new Error("Quà miễn phí giới hạn 5 lần mỗi phút.");
    run(
      "INSERT INTO gifts VALUES(?,?,?,?,?,?)",
      randomUUID(),
      sender,
      recipient,
      room,
      kind,
      Date.now(),
    );
    notice(recipient, sender, "gift", kind);
    return { kind };
  }
  async function resetPassword(userId) {
    const u = user(userId);
    if (!u) fail(404, "Không tìm thấy tài khoản.");
    // Mật khẩu tạm 10 ký tự, bỏ các ký tự dễ nhầm (0/O, 1/l/I).
    const alphabet = "abcdefghijkmnpqrstuvwxyz23456789";
    const temp = [...randomBytes(10)].map((x) => alphabet[x % alphabet.length]).join("");
    const salt = randomBytes(16).toString("hex");
    const hash = (await scrypt(temp, salt, 64)).toString("hex");
    run("UPDATE users SET password=?,salt=? WHERE id=?", hash, salt, u.id);
    run("DELETE FROM sessions WHERE user_id=?", u.id);
    remembered.revoke(u.id);
    run(
      "UPDATE password_resets SET status='done',handled=? WHERE user_id=? AND status='open'",
      Date.now(),
      u.id,
    );
    return temp;
  }
  let maintenanceClosed=false;
  const maintenance=()=>{if(!maintenanceClosed)void maintainPrivacy(db,dbPath===':memory:'?null:resolvePrivacyPath(dbPath,'..','backups')).catch(()=>console.error('Privacy maintenance failed; operator action required.'));};
  maintenance();const maintenanceTimer=setInterval(maintenance,3600000);maintenanceTimer.unref();
  return {
    db,wallet,economy,
    gift,
    notice,
    recordCallEvent,
    resetPassword,
    api,
    authenticate,
    user,
    blocked,
    publicUser,
    hasPrivacyConsent:id=>!!get('SELECT 1 FROM privacy_consents WHERE user_id=? AND version=?',id,PRIVACY_VERSION),
    ai,
    close: () => {maintenanceClosed=true;clearInterval(maintenanceTimer);ai.close();db.close();},
  };
}
