import {createAdminCoinGrants} from './admin-coin-grants.js';
import {createPackageStore} from './store-packages.js';
import {createEconomy} from './economy.js';
import {createWallet} from './wallet.js';
import {maintainPrivacy} from './privacy-maintenance.js';
import {createStore} from './store.js';
import {resolve as resolvePrivacyPath} from 'node:path';
import {PRIVACY_VERSION,PRIVACY_NOTICE} from './privacy-notice.js';
import {deleteAccountData} from './account-deletion.js';
import {createKinnectAI} from './kinnect-ai.js';
import {createAiSecurityMonitor} from './ai-security-monitor.js';
import {createSecurityNotifier} from './security-notifier.js';
import {createRecovery} from './recovery.js';
import {createTwoFactor} from './two-factor.js';
import {createCallConfig} from './call-config.js';
import {createFriendships} from './friendships.js';
import {privatePhotos} from "./private-photos.js";
import {createNews} from "./news.js";
import {messageActions} from "./message-actions.js";
import {chatAttachments} from "./chat-attachments.js";
import {commentThreads} from "./comment-threads.js";
import { createGroups } from "./groups.js";
import { rememberedDevices } from "./remembered-devices.js";
import { decodePostMedia, sendPostMedia, sendCachedMedia, etagMatches } from "./post-media.js";
import { createMediaCompressor } from "./media-compression.js";
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
  db.exec(`PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000; PRAGMA synchronous=NORMAL; PRAGMA cache_size=-131072; PRAGMA mmap_size=1073741824; PRAGMA temp_store=MEMORY; PRAGMA wal_autocheckpoint=2000;
 CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY,username TEXT UNIQUE NOT NULL,password TEXT NOT NULL,salt TEXT NOT NULL,name TEXT NOT NULL,bio TEXT NOT NULL DEFAULT '',interests TEXT NOT NULL DEFAULT '[]',birth_date TEXT NOT NULL,discoverable INTEGER NOT NULL DEFAULT 1,dm_mode TEXT NOT NULL DEFAULT 'everyone',avatar BLOB,avatar_type TEXT,suspended INTEGER NOT NULL DEFAULT 0,created INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),expires INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS push_devices(user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, kind TEXT NOT NULL, token TEXT NOT NULL, updated INTEGER NOT NULL, PRIMARY KEY(user_id, kind, token));
 CREATE TABLE IF NOT EXISTS follows(actor TEXT REFERENCES users(id),target TEXT REFERENCES users(id),PRIMARY KEY(actor,target));
 CREATE TABLE IF NOT EXISTS blocks(actor TEXT REFERENCES users(id),target TEXT REFERENCES users(id),PRIMARY KEY(actor,target));
 CREATE TABLE IF NOT EXISTS posts(id TEXT PRIMARY KEY,user_id TEXT REFERENCES users(id),body TEXT NOT NULL,visibility TEXT NOT NULL,hidden INTEGER NOT NULL DEFAULT 0,created INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS post_categories(post_id TEXT PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,category TEXT NOT NULL);
 CREATE TABLE IF NOT EXISTS post_media(post_id TEXT PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,type TEXT NOT NULL,data BLOB NOT NULL);
 CREATE TABLE IF NOT EXISTS post_media_items(id TEXT PRIMARY KEY,post_id TEXT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,position INTEGER NOT NULL,type TEXT NOT NULL,data BLOB NOT NULL);
 CREATE INDEX IF NOT EXISTS post_media_items_post ON post_media_items(post_id,position);
 CREATE TABLE IF NOT EXISTS post_hashtags(post_id TEXT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,tag TEXT NOT NULL,PRIMARY KEY(post_id,tag));
 CREATE INDEX IF NOT EXISTS post_hashtags_tag ON post_hashtags(tag,post_id);
 CREATE TABLE IF NOT EXISTS post_bookmarks(user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,post_id TEXT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,created INTEGER NOT NULL,PRIMARY KEY(user_id,post_id));
 CREATE INDEX IF NOT EXISTS post_bookmarks_user ON post_bookmarks(user_id,created);
 CREATE TABLE IF NOT EXISTS post_shares(post_id TEXT PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,original_post_id TEXT NOT NULL REFERENCES posts(id) ON DELETE CASCADE);
 CREATE INDEX IF NOT EXISTS post_shares_original ON post_shares(original_post_id);
 CREATE TABLE IF NOT EXISTS media_thumbnails(kind TEXT NOT NULL CHECK(kind IN ('short','post')),target_id TEXT NOT NULL,type TEXT NOT NULL,data BLOB NOT NULL,created INTEGER NOT NULL,PRIMARY KEY(kind,target_id));
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
    ["avatar_updated_at", "INTEGER NOT NULL DEFAULT 0"],
    ["cover_updated_at", "INTEGER NOT NULL DEFAULT 0"],
    ["cloud_chat_sync", "INTEGER NOT NULL DEFAULT 0"],
    ["password_set", "INTEGER NOT NULL DEFAULT 1"],
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
  db.exec("CREATE TABLE IF NOT EXISTS chat_request_ids(user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,kind TEXT NOT NULL CHECK(kind IN ('direct','group')),target_id TEXT NOT NULL,request_id TEXT NOT NULL,message_id TEXT NOT NULL,created INTEGER NOT NULL,PRIMARY KEY(user_id,kind,target_id,request_id)); CREATE INDEX IF NOT EXISTS chat_request_ids_created ON chat_request_ids(created);");
  db.exec(`CREATE INDEX IF NOT EXISTS idx_sessions_user_expires ON sessions(user_id,expires);
   CREATE INDEX IF NOT EXISTS idx_sessions_expires ON sessions(expires);
   CREATE INDEX IF NOT EXISTS idx_posts_hidden_created ON posts(hidden,created DESC);
   CREATE INDEX IF NOT EXISTS idx_posts_user_created ON posts(user_id,created DESC);
   CREATE INDEX IF NOT EXISTS idx_messages_sender_recipient_created ON messages(sender,recipient,created);
   CREATE INDEX IF NOT EXISTS idx_messages_recipient_sender_created ON messages(recipient,sender,created);
   CREATE INDEX IF NOT EXISTS idx_notifications_user_seen_created ON notifications(user_id,seen,created DESC);
   CREATE INDEX IF NOT EXISTS idx_post_comments_post_created ON post_comments(post_id,created);
   CREATE INDEX IF NOT EXISTS idx_short_comments_short_created ON short_comments(short_id,created);
   CREATE INDEX IF NOT EXISTS idx_blocks_target_actor ON blocks(target,actor);
   CREATE INDEX IF NOT EXISTS idx_follows_target_actor ON follows(target,actor);`);
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
  const coinGrants=createAdminCoinGrants({db,body,fail});
  const packageStore=createPackageStore({db,wallet,economy,body,fail});
  const store=createStore({db,body,fail,packages:packageStore,verifier:options.storeVerifier,appleVerifier:options.appleStoreVerifier,env:options.storeEnv||process.env,clock:options.clock});
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
    storeStyle: store.appearance(u.id)?.id||'',storeMembership:packageStore.membership(u.id),
    cover: u.cover ? ("/api/users/"+u.id+"/cover?v="+(u.cover_updated_at||u.created||1)) : null,
    avatar: u.avatar ? ("/api/users/" + u.id + "/avatar?v="+(u.avatar_updated_at||u.created||1)) : null,
    friendship: viewer ? friendConnections?.status(viewer,u.id)||"none" : "none",
    activityShared:!!u.show_activity,
    following: viewer ? follows(viewer, u.id) : false,
    mutual: viewer ? follows(viewer, u.id) && follows(u.id, viewer) : false,
  });
  const notice = (to, actor, kind, ref, targetId = null) => {
    if (to === actor && kind !== "security_alert") return;
    const id = randomUUID(), created = Date.now();
    run("INSERT INTO notifications VALUES(?,?,?,?,?,0,?)", id, to, actor, kind, ref, created);
    if (targetId) run("INSERT INTO notification_targets VALUES(?,?)", id, targetId);
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
  const fastAuthCache = new Map();
  const invalidateAuth = (userId, keepTokenDigest = "") => {
    if (!userId) {
      fastAuthCache.clear();
      return;
    }
    for (const [k, v] of fastAuthCache) {
      if (v?.row?.id === userId && k !== keepTokenDigest) fastAuthCache.delete(k);
    }
  };
  function authenticate(req) {
    const cookie = req.headers.cookie || "";
    const token = cookie
      .split(";")
      .map((x) => x.trim())
      .find((x) => x.startsWith("kinnect_session="))
      ?.slice(16);
    if (!token) return null;
    const tokenDigest = digest(token);
    const now = Date.now();
    const cached = fastAuthCache.get(tokenDigest);
    if (!process.env.NODE_TEST_CONTEXT && cached && now - cached.cachedAt < 5000 && cached.row && cached.row.expires && cached.row.expires > now) {
      return cached.row;
    }
    const row = get(
      "SELECT u.*, s.expires FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token=? AND s.expires>? AND u.suspended=0",
      tokenDigest,
      now,
    );
    if (row) {
      while (fastAuthCache.size >= 5000) {
        fastAuthCache.delete(fastAuthCache.keys().next().value);
      }
      fastAuthCache.set(tokenDigest, { row, cachedAt: now });
    } else {
      fastAuthCache.delete(tokenDigest);
    }
    const device=(cookie.split(';').map(x=>x.trim()).find(x=>x.startsWith('kinnect_device='))||'').slice(15);
    if(row&&/^[a-f0-9]{64}$/.test(device)&&get("SELECT 1 FROM session_info WHERE token=? AND device_hash=''",tokenDigest)&&get('SELECT 1 FROM remembered_accounts WHERE device=? AND user_id=?',digest(device),row.id))run("UPDATE session_info SET device_hash=? WHERE token=? AND device_hash=''",digest(device),tokenDigest);
    return row || null;
  }
  const messageState=messageActions({db,fail,blocked,user,body,onCallMessage:options.onCallMessage});
  const mediaCompressor=createMediaCompressor({db,env:options.mediaEnv||process.env,options:options.mediaCompression||{}});
  const attachments=chatAttachments({db,fail,blocked,user,messageState});
  const groups=createGroups({db,body,fail,text,user,publicUser,blocked,notice,attachments,messageState,mediaCompressor,onCallMessage:options.onCallMessage});
  const privateAlbum=privatePhotos({db,fail,blocked,user,publicUser,notice,body,mediaCompressor});
  const escapeLike=s=>String(s||'').replace(/[\\%_]/g,'\\$&');
  const extractHashtags=content=>{
    if(typeof content!=='string'||!content)return [];
    const found=new Set();
    for(const m of content.matchAll(/(?:^|[\s([{"'.,!?;:])#([\p{L}\p{N}_]{1,40})/gu)){
      found.add(m[1].toLowerCase());
      if(found.size>=15)break;
    }
    return [...found];
  };
  const syncPostHashtags=(postId,content)=>{
    run('DELETE FROM post_hashtags WHERE post_id=?',postId);
    for(const tag of extractHashtags(content))run('INSERT OR IGNORE INTO post_hashtags(post_id,tag) VALUES(?,?)',postId,tag);
  };
  const postMediaPayload=postId=>{
    const items=all('SELECT id,position,type FROM post_media_items WHERE post_id=? ORDER BY position ASC',postId);
    const hasThumb=!!get("SELECT 1 FROM media_thumbnails WHERE kind='post' AND target_id=?",postId);
    if(items.length){
      const mediaItems=items.map(it=>{
        const isVideo=it.type.startsWith('video/');
        return {id:it.id,position:it.position,kind:isVideo?'video':'image',url:'/api/posts/'+postId+'/media/'+it.id,...(isVideo?{thumbnail:hasThumb?'/api/posts/'+postId+'/thumbnail':null}:{})};
      });
      const first=mediaItems[0];
      return {media:{kind:first.kind,url:'/api/posts/'+postId+'/media',...(first.kind==='video'?{thumbnail:first.thumbnail}:{})},mediaItems};
    }
    const pm=get('SELECT type FROM post_media WHERE post_id=?',postId);
    if(!pm)return {media:null,mediaItems:[]};
    const isVideo=pm.type.startsWith('video/');
    const media={kind:isVideo?'video':'image',url:'/api/posts/'+postId+'/media',...(isVideo?{thumbnail:hasThumb?'/api/posts/'+postId+'/thumbnail':null}:{})};
    return {media,mediaItems:[{id:'primary',position:0,...media}]};
  };
  async function decodePostMediaBatch(b,allowAlbum=true){
    if(b.mediaItems!==undefined){
      if(!allowAlbum)fail(400,'Tin 24 giờ chỉ hỗ trợ 1 ảnh hoặc video.');
      if(!Array.isArray(b.mediaItems)||!b.mediaItems.length||b.mediaItems.length>10)fail(400,'Album bài viết hỗ trợ từ 1 đến 10 ảnh.');
      const items=[];let totalBytes=0;
      for(const raw of b.mediaItems){
        const decoded=decodePostMedia(raw,fail);
        if(!decoded)fail(400,'Tệp media không hợp lệ.');
        if(decoded.kind==='video'&&b.mediaItems.length>1)fail(400,'Album nhiều tệp chỉ hỗ trợ ảnh.');
        totalBytes+=decoded.bytes.length;
        if(totalBytes>25*1024*1024)fail(400,'Tổng dung lượng media tối đa là 25 MB.');
        if(decoded.kind==='image'){
          const opt=await mediaCompressor.compressImage(decoded.bytes,decoded.type,'post');
          decoded.bytes=opt.bytes;decoded.type=opt.type;
        }
        items.push({id:randomUUID(),...decoded});
      }
      return {items,primary:items[0]||null};
    }
    const single=decodePostMedia(b.media,fail);
    if(!single)return {items:[],primary:null};
    if(single.kind==='image'){
      const opt=await mediaCompressor.compressImage(single.bytes,single.type,'post');
      single.bytes=opt.bytes;single.type=opt.type;
    }
    const item={id:randomUUID(),...single};
    return {items:[item],primary:item};
  }
  const canViewPost=(p,viewerId)=>!!p&&!p.hidden&&user(p.user_id)?.suspended===0&&!blocked(viewerId,p.user_id)&&(p.visibility==='public'||p.user_id===viewerId||follows(viewerId,p.user_id));
  function decoratePost(p,viewerId,depth=0){
    const {media,mediaItems}=postMediaPayload(p.id);
    const hashtags=all('SELECT tag FROM post_hashtags WHERE post_id=? ORDER BY tag ASC',p.id).map(r=>r.tag);
    let sharedPost=null;
    if(depth===0){
      const share=get('SELECT original_post_id FROM post_shares WHERE post_id=?',p.id);
      if(share){
        const orig=get("SELECT p.*,COALESCE(pc.category,'community') AS category FROM posts p LEFT JOIN post_categories pc ON pc.post_id=p.id WHERE p.id=?",share.original_post_id);
        if(orig&&canViewPost(orig,viewerId)&&!get('SELECT 1 FROM post_stories WHERE post_id=?',orig.id)){
          const origMedia=postMediaPayload(orig.id);
          sharedPost={id:orig.id,body:orig.body,category:orig.category,created:orig.created,author:publicUser(user(orig.user_id),viewerId),media:origMedia.media,mediaItems:origMedia.mediaItems};
        }
      }
    }
    return {
      ...p,
      author: publicUser(user(p.user_id), viewerId),
      media,
      mediaItems,
      hashtags,
      likes: get("SELECT count(*) AS n FROM post_likes WHERE post_id=?", p.id).n,
      myReaction: get('SELECT reaction FROM post_likes WHERE post_id=? AND user_id=?',p.id,viewerId)?.reaction||null,
      reactions: Object.fromEntries(all('SELECT reaction,COUNT(*) AS n FROM post_likes WHERE post_id=? GROUP BY reaction',p.id).map(r=>[r.reaction,r.n])),
      liked: !!get("SELECT 1 FROM post_likes WHERE post_id=? AND user_id=?", p.id, viewerId),
      comments: get("SELECT count(*) AS n FROM post_comments WHERE post_id=?", p.id).n,
      bookmarked: !!get("SELECT 1 FROM post_bookmarks WHERE user_id=? AND post_id=?", viewerId, p.id),
      shares: get("SELECT count(*) AS n FROM post_shares WHERE original_post_id=?", p.id).n,
      sharedPost,
    };
  }
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
  let twoFactor = null;
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
    cloudChatSync: !!u.cloud_chat_sync,
    dmMode: u.dm_mode==='friends'?'friends':'everyone',
    showDistance: !!u.show_distance,
    role: u.role,
    hasPassword: u.password_set !== 0,
    twoFactorEnabled: twoFactor ? twoFactor.isEnabled(u.id) : false,
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
  const webhookLimits = new Map();
  const writes = new Map();
  function limit(req) {
    const key = securityMonitor ? securityMonitor.resolveTrustedClientIp(req) : (req.headers['cf-connecting-ip'] || req.socket.remoteAddress);
    const now = Date.now();
    let b = limits.get(key);
    if (!b || now - b.time > 60000) {
      b = { time: now, count: 0 };
      limits.set(key, b);
    }
    if (++b.count > (options.authLimit || 20)) {
      securityMonitor?.recordEvent({ req, kind: 'rate_limit_anomaly', ip: key, method: req.method, path: req.url, statusCode: 429, metadata: { countInMinute: b.count } });
      fail(429, "Thử lại sau một phút.");
    }
    if (limits.size > 10000)
      for (const [k, v] of limits) if (now - v.time > 60000) limits.delete(k);
  }
  function limitWebhook(req) {
    const key = securityMonitor ? securityMonitor.resolveTrustedClientIp(req) : (req.headers['cf-connecting-ip'] || req.socket.remoteAddress);
    const now = Date.now();
    let b = webhookLimits.get(key);
    if (!b || now - b.time > 60000) {
      b = { time: now, count: 0 };
      webhookLimits.set(key, b);
    }
    if (++b.count > (options.webhookLimit || 300)) {
      securityMonitor?.recordEvent({ req, kind: 'rate_limit_anomaly', ip: key, method: req.method, path: req.url, statusCode: 429, metadata: { countInMinute: b.count, scope: 'webhook' } });
      fail(429, "Thử lại sau một phút.");
    }
    if (webhookLimits.size > 10000)
      for (const [k, v] of webhookLimits) if (now - v.time > 60000) webhookLimits.delete(k);
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
    if(freshCredential)run('INSERT OR REPLACE INTO recent_auth VALUES(?,?)',digest(token),Date.now());
    return `kinnect_session=${token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=604800${process.env.SECURE_COOKIES === "1" ? "; Secure" : ""}`;
  }
  const remembered = rememberedDevices({db,user,own,startSession,twoFactor:()=>twoFactor,sharedSession:options.sharedSession||null,body,fail,limit});
  const isFreshRecentAuth = (req) => {
    const token = (req?.headers?.cookie || "")
      .split(";")
      .map((x) => x.trim())
      .find((x) => x.startsWith("kinnect_session="))
      ?.slice(16);
    if (!token) return false;
    const row = get("SELECT authenticated_at FROM recent_auth WHERE token=?", digest(token));
    return !!row && Date.now() - row.authenticated_at < 10 * 60000;
  };
  const verifyUserPassword = async (u, password) =>
    Boolean(u) &&
    typeof password === "string" &&
    password.length <= 128 &&
    /^[0-9a-f]{128}$/i.test(String(u.password || "")) &&
    typeof u.salt === "string" &&
    u.salt.length > 0 &&
    timingSafeEqual(await scrypt(password, u.salt, 64), Buffer.from(u.password, "hex"));
  const verifyPasswordOrFreshOAuth = async (u, password, req) => {
    if (await verifyUserPassword(u, password)) return true;
    if (u && u.password_set === 0 && req && isFreshRecentAuth(req)) return true;
    return false;
  };
  const recovery=createRecovery({db,body,fail,limit,requireUser,user,
   verifyPassword:verifyPasswordOrFreshOAuth,
   hashPassword:async password=>{const salt=randomBytes(16).toString('hex');return {salt,hash:(await scrypt(password,salt,64)).toString('hex')};},
   revoke:id=>{remembered.revoke(id);invalidateAuth(id);},sendEmail:options.sendEmail||(()=>Promise.resolve(false)),mailReady:options.mailReady||(()=>false)
  });
  twoFactor = createTwoFactor({
    db,
    body,
    fail,
    verifyPassword: verifyPasswordOrFreshOAuth,
    invalidateAuth,
    ...(options.clock ? { clock: options.clock } : {}),
  });
  const oauthApi = createOAuth({
    db,
    get,
    run,
    user,
    fail,
    twoFactor,
    startSession:(id,request)=>startSession(id,request,true),
  sharedSession: options.sharedSession || null,
    ...(options.fetchImpl ? { fetchImpl: options.fetchImpl } : {}),
    ...(options.appleKeyResolver ? { appleKeyResolver: options.appleKeyResolver } : {}),
  });
  const ai=createKinnectAI({db,user,blocked,notice,messageState,onStream:options.onAIStream,send:options.fetchImpl||fetch});
  const securityNotifier = createSecurityNotifier({
    env: options.securityEnv || process.env,
    sendEmail: options.sendEmail || null,
    mailReady: options.mailReady || (() => false),
    fetchImpl: options.fetchImpl || fetch,
    clock: options.clock ? () => options.clock() : () => Date.now(),
  });
  const securityMonitor=createAiSecurityMonitor({
    db,
    env: options.securityEnv || process.env,
    fetchImpl: options.fetchImpl || fetch,
    clock: options.clock ? () => options.clock() : () => Date.now(),
    onAlert: alert => {
      try {
        for (const admin of all("SELECT id FROM users WHERE role='admin' AND suspended=0")) {
          notice(admin.id, admin.id, 'security_alert', alert.id);
        }
      } catch {}
      void securityNotifier.notify(alert).catch(() => {});
    },
    onUserMitigation: ({ action, userId }) => {
      if (action === 'require_reauth' && userId) invalidateAuth(userId);
    }
  });
  const threads=commentThreads({db,fail,blocked,user});
  const shortsApi = createShorts({
    threads,
    mediaCompressor,
    notice,
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
      if(req.method==='GET'&&status===200){const tag='"'+createHash('sha256').update(encoded).digest('hex')+'"';headers={...headers,ETag:tag,Vary:'Cookie'};if(etagMatches(req.headers['if-none-match'],tag)){res.writeHead(304,{'Cache-Control':'no-store',...headers});res.end();return;}}
      res.writeHead(status, {
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
        ...headers,
      });
      res.end(encoded);
    };
    try {
      const gate = securityMonitor.evaluateRequestGate(req, path);
      if (!gate.allowed) {
        res._securityGateBlocked = true;
        return json(gate.status || 429, { error: gate.error, mitigationId: gate.mitigationId, retryAfter: gate.retryAfter }, { "Retry-After": String(gate.retryAfter || 60) });
      }
      if (req.method !== "GET" && req.method !== "HEAD") {
        csrf(req);
        if (!(req.headers["content-type"] || "").startsWith("application/json"))
          fail(415, "Cần Content-Type application/json.");
      }
      if (await recovery.route(req,res,path,json)) return;
      if (await remembered.route(req,res,path,json)) return;
      if (path === "/api/auth/apple" || path.startsWith("/api/oauth/")) {
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
          const validStoredHash =
            Boolean(u) &&
            /^[0-9a-f]{128}$/i.test(String(u.password || "")) &&
            typeof u.salt === "string" &&
            u.salt.length > 0;
          const hash = await scrypt(
            b.password,
            validStoredHash ? u.salt : "kinnect-dummy-salt",
            64,
          );
          const storedBuf = validStoredHash ? Buffer.from(u.password, "hex") : Buffer.alloc(64);
          if (
            !validStoredHash ||
            !timingSafeEqual(hash, storedBuf) ||
            u.suspended
          ) {
            securityMonitor.recordEvent({
              req,
              kind: 'failed_login',
              actorId: username,
              actorRole: u?.role || 'none',
              method: 'POST',
              path: '/api/login',
              statusCode: 401,
              metadata: { userExists: !!u, suspended: !!u?.suspended }
            });
            fail(
              401,
              "Thông tin đăng nhập không đúng hoặc tài khoản không khả dụng.",
            );
          }
          if (twoFactor.isEnabled(u.id)) {
            const totpCode = b.totpCode ?? b.otp ?? b.code;
            if (!totpCode || !String(totpCode).trim()) {
              return json(403, {
                error: "Tài khoản đang bật xác thực 2 lớp. Nhập mã 6 chữ số từ ứng dụng xác thực.",
                requires2fa: true,
              });
            }
            if (!twoFactor.verifyForUser(u.id, totpCode)) {
              securityMonitor.recordEvent({
                req,
                kind: "failed_login",
                actorId: username,
                actorRole: u.role || "user",
                method: "POST",
                path: "/api/login",
                statusCode: 401,
                metadata: { reason: "invalid_2fa" },
              });
              fail(401, "Mã xác thực 2 lớp không đúng hoặc đã hết hạn.");
            }
          }
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
      if(req.method==='POST'&&path==='/api/store/apple-notifications'){
        limitWebhook(req);
        const b=await body(req,65536);
        if(!b.signedPayload)fail(400,'Thiếu signedPayload trong thông báo Apple.');
        return json(200,await store.handleAppleNotification(b.signedPayload));
      }
      if (["GET", "HEAD"].includes(req.method)) {
        const shortVidMatch = path.match(/^\/api\/shorts\/([a-zA-Z0-9-]+)\/(video|thumbnail)$/);
        if (shortVidMatch) {
          const guestMe = authenticate(req) || null;
          return await shortsApi(req, res, path, guestMe, json);
        }
        const postMediaRoute = path.match(/^\/api\/posts\/([a-zA-Z0-9-]+)\/(media|thumbnail)(?:\/([a-zA-Z0-9-]+))?$/);
        if (postMediaRoute) {
          const [, postId, mediaKind, itemId] = postMediaRoute;
          const guestMe = authenticate(req) || null;
          const p = get("SELECT p.*,u.suspended FROM posts p JOIN users u ON u.id=p.user_id WHERE p.id=? AND p.hidden=0", postId);
          const story = get("SELECT expires FROM post_stories WHERE post_id=?", postId);
          const storyBlocked = story && (!guestMe || story.expires <= Date.now() || (p && p.user_id !== guestMe.id && !follows(guestMe.id, p.user_id)));
          if (!p || p.suspended !== 0 || storyBlocked || (guestMe && blocked(guestMe.id, p.user_id)) || (p.visibility !== "public" && (!guestMe || (p.user_id !== guestMe.id && !follows(guestMe.id, p.user_id))))) {
            fail(404, "Không tìm thấy nội dung.");
          }
          if (mediaKind === "thumbnail") {
            const thumb = get("SELECT type,data FROM media_thumbnails WHERE kind='post' AND target_id=?", p.id);
            if (!thumb) fail(404, "Chưa có ảnh xem trước.");
            return sendCachedMedia(req, res, { bytes: thumb.data, type: thumb.type, maxAge: 600, allowRange: false });
          }
          const media = itemId && itemId !== "primary"
            ? get("SELECT type,data FROM post_media_items WHERE id=? AND post_id=?", itemId, p.id)
            : get("SELECT type,data FROM post_media WHERE post_id=?", p.id);
          if (!media) fail(404, "Không có ảnh/video.");
          return sendPostMedia(req, res, media, fail);
        }
      }
      const me = requireUser(req);
      const userGate = securityMonitor.evaluateRequestGate(req, path, { userId: me.id, username: me.username, userOnly: true });
      if (!userGate.allowed) {
        res._securityGateBlocked = true;
        return json(
          userGate.status || 429,
          {
            error: userGate.error,
            mitigationId: userGate.mitigationId,
            ...(userGate.retryAfter ? { retryAfter: userGate.retryAfter } : {}),
            ...(userGate.requiresReauth ? { requiresReauth: true } : {}),
          },
          userGate.retryAfter ? { "Retry-After": String(userGate.retryAfter) } : {},
        );
      }
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
      if(await economy.route(req,res,path,json,me))return;
      if(await coinGrants.route(req,res,path,json,me))return;
      if(await packageStore.route(req,res,path,json,me))return;
      if(path==='/api/live/gifts'&&req.method==='GET')return json(200,{...economy.giftCatalog(),unlimitedCoins:false,balance:wallet.trialBalance(me.id),inventory:packageStore.inventory(me.id).filter(x=>x.source==='gifted')});
      if(await wallet.route(req,res,path,json,me))return;
      if(await store.route(req,res,path,json,me))return;
      if(path==='/api/support'&&req.method==='GET'){const admin=user(ai.status().admin_id)||get("SELECT * FROM users WHERE role='admin' AND suspended=0 ORDER BY created,id LIMIT 1");return json(200,{user:admin?publicUser(admin,me.id):null,contact:'anhvn53@wru.vn',operator:'Mr Ánh'});}
      if(path==='/api/support/request'&&req.method==='POST'){
        const b=await body(req,4096);
        const contactInfo=typeof b.contact==='string'?b.contact.trim():(me.email||'');
        const note=typeof b.note==='string'?b.note.trim():'';
        if(!note)fail(400,'Nội dung hỗ trợ không được để trống.');
        const ticketId=randomUUID(),now=Date.now();
        const admin=user(ai.status()?.admin_id)||get("SELECT * FROM users WHERE role='admin' AND suspended=0 ORDER BY created,id LIMIT 1");
        try{
          db.prepare("INSERT INTO console_tickets (id,subject,description,priority,team,member,created_by,created,updated) VALUES (?,?,?,?,?,?,?,?,?)")
            .run(ticketId,`Yêu cầu hỗ trợ: ${contactInfo||me.name}`,note,'high','support',me.id,me.id,now,now);
          db.prepare("INSERT OR IGNORE INTO console_ticket_teams (ticket_id,team) VALUES (?,?)").run(ticketId,'support');
          db.prepare("INSERT OR IGNORE INTO console_ticket_teams (ticket_id,team) VALUES (?,?)").run(ticketId,'admin');
        }catch{}
        if(admin&&admin.id!==me.id){
          const msgBody=`[Yêu cầu hỗ trợ]\nLiên hệ: ${contactInfo}\nNội dung: ${note}`;
          const msgId=randomUUID();
          try{
            run("INSERT INTO messages VALUES(?,?,?,?,?)",msgId,me.id,admin.id,msgBody,now);
            messageState.reveal("direct",admin.id,me.id);
            messageState.reveal("direct",me.id,admin.id);
            notice(admin.id,me.id,"support_ticket",ticketId);
          }catch{}
        }
        return json(200,{ok:true,ticketId,message:'Đã gửi yêu cầu hỗ trợ thành công. Đội ngũ quản trị sẽ liên hệ sớm.'});
      }
      if(path==='/api/me/privacy-consent'){
        if(req.method==='GET')return json(200,{version:PRIVACY_VERSION,notice:PRIVACY_NOTICE,accepted:!!get('SELECT 1 FROM privacy_consents WHERE user_id=? AND version=?',me.id,PRIVACY_VERSION)});
        if(req.method!=='POST')fail(405,'Chỉ hỗ trợ GET hoặc POST.');const b=await body(req,4096);if(b.accepted!==true||b.version!==PRIVACY_VERSION)fail(400,'Cần đồng ý thông báo dữ liệu hiện hành.');run('INSERT INTO privacy_consents VALUES(?,?,?) ON CONFLICT(user_id) DO UPDATE SET version=excluded.version,created=excluded.created',me.id,PRIVACY_VERSION,Date.now());return json(200,{ok:true});
      }
      const chatStateWrite=(req.method==='POST'||req.method==='DELETE'||req.method==='PATCH')&&(/^\/api\/chat-messages\/(direct|group)\/[^/]+(?:\/(recall|reaction|pin))?$/.test(path)||/^\/api\/chat-preferences\/(direct|group)\/[^/]+$/.test(path));
      const contentWrite=chatStateWrite||(!['GET','HEAD','DELETE'].includes(req.method)&&(/^\/api\/(posts|shorts)(\/|$)/.test(path)||/^\/api\/groups(?:\/[^/]+)?(?:\/messages(?:\/[^/]+)?|\/polls(?:\/[^/]+(?:\/(?:vote|close))?)?|\/avatar)?$/.test(path)||/^\/api\/users\/[^/]+\/messages(?:\/[^/]+)?$/.test(path)||path==='/api/me/avatar'||path==='/api/me/cover'||path==='/api/me/private-photos'||(path==='/api/me'&&req.method==='PATCH')||path==='/api/me/content-consent'));
      if(contentWrite&&!get('SELECT 1 FROM privacy_consents WHERE user_id=? AND version=?',me.id,PRIVACY_VERSION))return json(428,{error:PRIVACY_NOTICE,version:PRIVACY_VERSION});
      if(path==='/api/me/content-consent'&&req.method==='POST')return json(200,{ok:true});
      if(path==='/api/me/ai-consent'&&req.method==='POST'){const b=await body(req,4096);if(typeof b.enabled!=='boolean')fail(400,'Cần xác nhận lựa chọn AI.');return json(200,ai.consent(me.id,b.enabled));}
      if(path==='/api/me/account-deletion'){
        const token=(req.headers.cookie||'').split(';').map(x=>x.trim()).find(x=>x.startsWith('kinnect_session='))?.slice(16);
        const session=token&&get('SELECT authenticated_at FROM recent_auth WHERE token=?',digest(token));
        const fresh=!!session&&Date.now()-session.authenticated_at<10*60000;
        const oauthProviders=all('SELECT provider FROM oauth_accounts WHERE user_id=?',me.id).map(r=>r.provider);
        if(req.method==='GET')return json(200,{requiresPassword:!fresh,username:me.username,permanent:true,oauthProviders,twoFactorEnabled:!!twoFactor.isEnabled(me.id)});
        if(req.method!=='DELETE')fail(405,'Chỉ hỗ trợ GET hoặc DELETE.');
        limit(req);const b=await body(req,4096);
        if(b.confirmUsername!==me.username||b.confirmDelete!==true)fail(400,'Nhập đúng tên đăng nhập và xác nhận xóa vĩnh viễn.');
        const has2fa=twoFactor.isEnabled(me.id);
        const rawTotp=b.totpCode??b.otp??b.code;
        const hasTotpInput=typeof rawTotp==='string'&&rawTotp.trim().length>0;
        const needsPassword=Boolean(b.password)||(!fresh&&!(oauthProviders.length>0&&has2fa&&hasTotpInput));
        if(needsPassword){if(typeof b.password!=='string'||!b.password||!(await verifyUserPassword(me,b.password)))fail(403,'Xác thực chưa đúng. Nhập mật khẩu hoặc đăng nhập lại bằng mật khẩu/Apple/Google/Facebook rồi yêu cầu xóa trong 10 phút.');}
        if(!fresh&&has2fa){if(!hasTotpInput||!twoFactor.verifyForUser(me.id,rawTotp,{trackStep:false}))fail(403,'Tài khoản đang bật xác thực 2 lớp. Nhập mã xác thực 2 lớp (2FA) hợp lệ để xác nhận xóa tài khoản.');}
        deleteAccountData(db,me);
        invalidateAuth(me.id);
        options.onAccountDeleted?.(me.id);
        return json(200,{ok:true,deleted:true},{'Set-Cookie':'kinnect_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0'+(process.env.SECURE_COOKIES==='1'?'; Secure':'')});
      }
      if(path==='/api/me/purge-chat'&&req.method==='POST'){
        const peers=all("SELECT DISTINCT CASE WHEN sender=? THEN recipient ELSE sender END AS peer_id FROM messages WHERE sender=? OR recipient=?",me.id,me.id,me.id);
        for(const p of peers){if(p?.peer_id)messageState.clear('direct',p.peer_id,me.id);}
        run("DELETE FROM chat_attachments WHERE kind='direct' AND message_id IN (SELECT id FROM messages WHERE sender=?)",me.id);
        return json(200,{ok:true,message:'Đã dọn sạch lịch sử trò chuyện khỏi tài khoản và xóa tệp đính kèm bạn đã gửi.'});
      }
      if(path==="/api/news"&&req.method==="GET")return json(200,await getNews());
      if(await privateAlbum.route(req,res,path,me,json))return;
      if(await friendConnections.route(req,res,path,me,json))return;
      if(attachments.serve(req,res,path,me))return;
      if(path==='/api/call-config'&&req.method==='GET'){
       try{return json(200,await callConfig());}catch(e){return json(503,{error:e.message});}
      }
      run("DELETE FROM posts WHERE id IN (SELECT post_id FROM post_stories WHERE expires<=?)", Date.now());
      if(path==='/api/support-account'&&req.method==='GET'){const admin=get("SELECT * FROM users WHERE role='admin' AND suspended=0 ORDER BY created LIMIT 1");if(!admin)fail(404,'Chưa có tài khoản hỗ trợ.');return json(200,{user:publicUser(admin,me.id)});}
      if(await messageState.handle(req,path,me,json))return;
      if(await groups(req,path,me,json))return;
      if (path === "/api/devices/push" && (req.method === "POST" || req.method === "DELETE")) {
        const b = await body(req, 4096);
        const kind = b.kind;
        const rawToken = typeof b.token === "string" ? b.token.trim() : "";
        const token = kind === "fcm" ? rawToken : rawToken.toLowerCase();
        const isAppleKind = ["apns", "voip"].includes(kind);
        const isFcmKind = kind === "fcm";
        if (
          (!isAppleKind && !isFcmKind) ||
          (isAppleKind && !/^[0-9a-f]{64,400}$/.test(token)) ||
          (isFcmKind && !/^[A-Za-z0-9:_\-]{32,4096}$/.test(token))
        ) {
          fail(400, "Token đẩy không hợp lệ.");
        }
        if (req.method === "DELETE") {
          run("DELETE FROM push_devices WHERE user_id=? AND kind=? AND token=?", me.id, kind, token);
          return json(200, { ok: true });
        }
        // A device token belongs to the account currently signed in on that device.
        run("DELETE FROM push_devices WHERE kind=? AND token=? AND user_id<>?", kind, token, me.id);
        run(
          "INSERT INTO push_devices(user_id, kind, token, updated) VALUES(?,?,?,?) ON CONFLICT(user_id, kind, token) DO UPDATE SET updated=excluded.updated",
          me.id,
          kind,
          token,
          Date.now()
        );
        return json(200, { ok: true });
      }
      if (path === "/api/logout" && req.method === "POST") {
        const token = (req.headers.cookie || "")
          .split(";")
          .map((x) => x.trim())
          .find((x) => x.startsWith("kinnect_session="))
          ?.slice(16);
        if (token) {
          const d = digest(token);
          fastAuthCache.delete(d);
          run("DELETE FROM sessions WHERE token=?", d);
        }
        return json(
          200,
          { ok: true },
          {
            "Set-Cookie":
              `kinnect_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0${process.env.SECURE_COOKIES === "1" ? "; Secure" : ""}`,
          },
        );
      }
      if (path.startsWith("/api/shorts"))
        return await shortsApi(req, res, path, me, json);
      if (path.startsWith("/api/admin/")) {
        if (me.role !== "admin") {
          securityMonitor.recordEvent({
            req,
            kind: 'unauthorized_access',
            actorId: me.username || me.id,
            actorRole: me.role || 'user',
            method: req.method,
            path,
            statusCode: 403,
            metadata: { attemptedAdminRoute: path }
          });
          fail(403, "Chỉ quản trị viên có quyền thực hiện.");
        }
        if (path === "/api/admin/security" && req.method === "GET") {
          return json(200, securityMonitor.getOverview());
        }
        if (path === "/api/admin/security/config" && (req.method === "PATCH" || req.method === "POST")) {
          const b = await body(req, 16384);
          return json(200, { ok: true, config: securityMonitor.updateConfig(b, me.username || me.id) });
        }
        if (path === "/api/admin/security/alerts" && req.method === "GET") {
          const params = new URL(req.url, "http://local").searchParams;
          return json(200, {
            alerts: securityMonitor.listAlerts({
              status: params.get("status") || "all",
              severity: params.get("severity") || "all",
              limit: Number(params.get("limit") || 50)
            })
          });
        }
        if (path === "/api/admin/security/alerts" && (req.method === "PATCH" || req.method === "POST")) {
          const b = await body(req, 16384);
          if (!b.id || !b.status) fail(400, "Thiếu mã cảnh báo hoặc trạng thái.");
          return json(200, { ok: true, alert: securityMonitor.updateAlertStatus(String(b.id), String(b.status), me.username || me.id) });
        }
        if (path === "/api/admin/security/mitigations" && req.method === "GET") {
          const params = new URL(req.url, "http://local").searchParams;
          return json(200, {
            mitigations: securityMonitor.listMitigations({
              activeOnly: params.get("active") === "1",
              limit: Number(params.get("limit") || 80)
            })
          });
        }
        if (path === "/api/admin/security/mitigations" && req.method === "POST") {
          const b = await body(req, 16384);
          if (b.action === "revert") {
            if (!b.id) fail(400, "Thiếu mã biện pháp cần hoàn tác.");
            return json(200, {
              ok: true,
              mitigation: securityMonitor.revertMitigation(String(b.id), me.username || me.id, b.reason || "Hoàn tác thủ công bởi Admin")
            });
          }
          const applied = securityMonitor.applyMitigation({
            alertId: String(b.alertId || ""),
            action: String(b.action || ""),
            targetType: String(b.targetType || "ip"),
            targetValue: String(b.targetValue || ""),
            ttlSeconds: Number(b.ttlSeconds || 900),
            reason: String(b.reason || "Áp dụng thủ công bởi Quản trị viên"),
            evidenceSummary: "Manual admin action",
            source: "manual_admin",
            createdBy: me.username || me.id
          });
          return json(201, { ok: true, mitigation: applied });
        }
        if (path === "/api/admin/security/simulate" && req.method === "POST") {
          const b = await body(req, 16384);
          const result = await securityMonitor.simulateScenario(String(b.scenario || "brute_force"), {
            ip: String(b.ip || "203.0.113.77"),
            actorId: String(b.actorId || "")
          });
          return json(200, result);
        }
        if (path === "/api/admin/security/drain" && req.method === "POST") {
          const alerts = await securityMonitor.drainQueue();
          return json(200, { ok: true, processedAlerts: alerts.length, alerts });
        }
        if(path==='/api/admin/ai'&&req.method==='GET')return json(200,{config:ai.status(),credentials:ai.credentialStatus(),jobs:ai.jobs()});
        if(path==='/api/admin/ai'&&req.method==='PATCH'){try{return json(200,{config:ai.configure(await body(req))});}catch{return json(400,{error:'Cấu hình AI không hợp lệ hoặc chưa có khóa kết nối máy chủ.'});}}
        if(path==='/api/admin/ai/credentials'&&req.method==='PATCH'){const b=await body(req);if(!(await verifyUserPassword(me,b.password)))fail(401,'Mật khẩu quản trị không đúng.');try{return json(200,{credentials:await ai.saveCredentials(b)});}catch{return json(400,{error:'Không lưu được cấu hình. Kiểm tra URL Worker, khóa và model NVIDIA.'});}}
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
              const item =
                get("SELECT user_id,body FROM short_comments WHERE id=?", r.target_id) ||
                get("SELECT user_id,body FROM post_comments WHERE id=?", r.target_id) ||
                (get("SELECT 1 FROM sqlite_master WHERE type='table' AND name='comments'") ? get("SELECT user_id,body FROM comments WHERE id=?", r.target_id) : null);
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
          if (r.status !== "open") fail(409, "Yêu cầu không còn chờ xử lý.");
          if (resetRoute[2] === "dismiss") {
            run("INSERT INTO moderation VALUES(?,?,?,?)",randomUUID(),"dismiss-password-request:"+me.id,r.user_id||r.id,Date.now());
            run(
              "UPDATE password_resets SET status='dismissed',handled=? WHERE id=?",
              Date.now(),
              r.id,
            );
            return json(200, { ok: true });
          }
          const target = r.user_id ? user(r.user_id) : null;
          if (!target)
            fail(404, "Tên đăng nhập này không tồn tại.");
          if (target.role !== "user")
            fail(403, "Chỉ được khôi phục tài khoản thành viên thường.");
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
            invalidateAuth(b.target);
            securityMonitor.recordEvent({
              req,
              kind: 'privilege_change',
              actorId: me.username || me.id,
              actorRole: 'admin',
              method: 'POST',
              path,
              statusCode: 200,
              metadata: { moderationAction: b.action, target: b.target }
            });
          } catch (e) {
            fail(400, e.message);
          }
          return json(200, { ok: true });
        }
        fail(404, "Không tìm thấy API quản trị.");
      }
      if (await twoFactor.handle(req, path, me, json)) return;
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
        fastAuthCache.delete(target.token);
        run('DELETE FROM sessions WHERE token=? AND user_id=?',target.token,me.id);return json(200,{ok:true});
      }
      if (path === "/api/me/password" && req.method === "POST") {
        const b = await body(req, 4000);
        if (
          typeof b.next !== "string" ||
          b.next.length < 6 ||
          b.next.length > 128
        )
          fail(400, "Mật khẩu mới cần 6–128 ký tự.");
        if (me.password_set === 0) {
          if (!isFreshRecentAuth(req))
            fail(401, "Vui lòng đăng nhập lại bằng Apple/Google/Facebook trong vòng 10 phút để đặt mật khẩu.");
        } else {
          if (typeof b.current !== "string")
            fail(400, "Mật khẩu mới cần 6–128 ký tự.");
          if (!(await verifyUserPassword(me, b.current)))
            fail(400, "Mật khẩu hiện tại không đúng.");
        }
        const salt = randomBytes(16).toString("hex");
        const hash = (await scrypt(b.next, salt, 64)).toString("hex");
        run("UPDATE users SET password=?,salt=?,password_set=1 WHERE id=?", hash, salt, me.id);
        remembered.revoke(me.id);
        // Đăng xuất các thiết bị khác, giữ phiên hiện tại.
        const token = (req.headers.cookie || "")
          .split(";")
          .map((x) => x.trim())
          .find((x) => x.startsWith("kinnect_session="))
          ?.slice(16);
        const curDigest = token ? digest(token) : "";
        run(
          "DELETE FROM sessions WHERE user_id=? AND token<>?",
          me.id,
          curDigest,
        );
        invalidateAuth(me.id);
        return json(200, { ok: true });
      }
      if (path === "/api/me/activity" && req.method === "POST") {
        run("UPDATE users SET last_active=? WHERE id=?", Date.now(), me.id);
        invalidateAuth(me.id);
        return json(200, { ok: true });
      }
      if (path === "/api/me/location" && req.method === "PATCH") {
        const b = await body(req);
        if (b.enabled === false) {
          run(
            "UPDATE users SET lat=NULL,lng=NULL,location_at=NULL WHERE id=?",
            me.id,
          );
          invalidateAuth(me.id);
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
        invalidateAuth(me.id);
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
        if(b.cloudChatSync!==undefined)run("UPDATE users SET cloud_chat_sync=? WHERE id=?",b.cloudChatSync?1:0,me.id);
        if(typeof b.cloud_chat_sync==='boolean')run("UPDATE users SET cloud_chat_sync=? WHERE id=?",b.cloud_chat_sync?1:0,me.id);
        run("UPDATE users SET profile_dob=?,profile_visibility=?,profile_details=? WHERE id=?",date,JSON.stringify(visibility),JSON.stringify(details),me.id);
        invalidateAuth(me.id);
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
        const coverUpdate=path.endsWith('/cover');
        const optimized=await mediaCompressor.compressImage(bytes,type,coverUpdate?'cover':'avatar');
        const storedBytes=optimized.bytes,storedType=optimized.type;
        const updateTime = Date.now();
        run(
          coverUpdate?"UPDATE users SET cover=?,cover_type=?,cover_updated_at=? WHERE id=?":"UPDATE users SET avatar=?,avatar_type=?,avatar_updated_at=? WHERE id=?",
          storedBytes,
          storedType,
          updateTime,
          me.id,
        );
        if(!coverUpdate)ai.enqueue('avatar',me.id,me.id,{text:'Kiểm tra ảnh đại diện theo quy tắc cộng đồng Kinnect.',image:{mime:storedType,data:storedBytes.toString('base64')}});
        const updateId=randomUUID();
        run('INSERT INTO posts(id,user_id,body,visibility,created) VALUES(?,?,?,?,?)',updateId,me.id,coverUpdate?'đã cập nhật ảnh bìa.':'đã cập nhật ảnh đại diện.','public',Date.now());
        run('INSERT INTO post_media VALUES(?,?,?)',updateId,storedType,storedBytes);
        invalidateAuth(me.id);
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
        const now = Date.now();
        const followingOnly = query.get("following") === "1";
        const recentOnly = query.get("recent") === "1";
        const radiusKm = Math.min(100, Math.max(1, Number(query.get("radius")) || 100));
        const normalize = (v) => adminSearchKey(String(v || ""));
        const canonical = (v) => ["nam", "male", "man"].includes(v) ? "nam" : ["nu", "female", "woman"].includes(v) ? "nu" : v;
        const canonicalOrientation = (raw) => {
          const v = normalize(raw).trim();
          if (!v) return "";
          if (v === "gay" || v.includes("gay") || v.includes("dong tinh nam")) return "gay";
          if (v === "les" || v.startsWith("les ") || v.startsWith("les/") || v.includes("lesbian") || v.includes("dong tinh nu")) return "lesbian";
          if (v === "bi" || v.includes("bisexual") || v.includes("song tinh")) return "bisexual";
          if (v === "pan" || v.includes("pansexual") || v.includes("toan tinh")) return "pansexual";
          if (v === "ace" || v.includes("asexual") || v.includes("vo tinh")) return "asexual";
          if (v.includes("di tinh") || v === "heterosexual" || v === "straight") return "heterosexual";
          if (v === "demi" || v === "a tinh" || v.startsWith("a tinh ") || v.startsWith("a tinh/") || v.includes("demisexual")) return "demisexual";
          if (v.includes("queer")) return "queer";
          if (v.includes("tim hieu") || v === "questioning") return "questioning";
          if (v === "khac" || v === "other") return "other";
          return v;
        };
        const qKey = q ? adminSearchKey(q) : "";
        const wantedGender = normalize(query.get("gender"));
        const wantedOrientation = normalize(query.get("orientation"));
        const wantedCommunityRole = normalize(query.get("communityRole"));
        const minHeight = Number(query.get("minHeight")) || 0;
        const maxHeight = Number(query.get("maxHeight")) || 0;
        const minWeight = Number(query.get("minWeight")) || 0;
        const maxWeight = Number(query.get("maxWeight")) || 0;
        const minAge = Number(query.get("minAge")) || 0;
        const maxAge = Number(query.get("maxAge")) || 0;
        const wantedIntent = normalize(query.get("intent"));
        const where = [
          "u.id<>?",
          "u.discoverable=1",
          "u.suspended=0",
          "NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.actor=? AND b.target=u.id) OR (b.target=? AND b.actor=u.id))",
        ];
        const sqlParams = [me.id, me.id, me.id];
        if (followingOnly) {
          where.push("EXISTS (SELECT 1 FROM follows f WHERE f.actor=? AND f.target=u.id)");
          sqlParams.push(me.id);
        }
        if (nearby) {
          where.push("u.lat IS NOT NULL AND u.lng IS NOT NULL AND u.location_at>?");
          sqlParams.push(now - 86400000);
        }
        if (order === "active") {
          where.push("u.show_activity=1 AND u.last_active>? AND EXISTS (SELECT 1 FROM sessions s WHERE s.user_id=u.id AND s.expires>?)");
          sqlParams.push(now - 90000, now);
        }
        if (wantedGender || wantedOrientation || wantedCommunityRole) {
          where.push("u.identity_public=1");
        }
        if (wantedGender) where.push("u.gender<>''");
        if (wantedOrientation) where.push("u.orientation<>''");
        if (wantedCommunityRole) where.push("u.community_role<>''");
        if (wantedIntent) {
          where.push("u.looking_for<>'' AND admin_search_key(u.looking_for) LIKE ? ESCAPE '\\'");
          sqlParams.push("%" + escapeLike(wantedIntent) + "%");
        }
        if (minAge || maxAge) {
          where.push("(u.profile_dob<>'' OR u.age IS NOT NULL)");
        }
        if (minHeight || maxHeight || minWeight || maxWeight) {
          where.push("u.profile_details<>'{}'");
        }
        if (qKey) {
          where.push(
            "admin_search_key(u.name || ' ' || u.username || ' ' || u.city || ' ' || CASE WHEN u.identity_public=1 THEN u.gender || ' ' || u.orientation || ' ' || u.relationship_role ELSE '' END || ' ' || replace(replace(replace(u.interests,'[\"',''),'\"]',''),'\",\"',' ')) LIKE ? ESCAPE '\\'",
          );
          sqlParams.push("%" + escapeLike(qKey) + "%");
        }
        const candidates = all(
          `SELECT u.* FROM users u WHERE ${where.join(" AND ")} ORDER BY ${recentOnly ? "u.last_active DESC, u.created DESC" : "u.created DESC"} LIMIT 500`,
          ...sqlParams,
        );
        const matched = [];
        for (const u of candidates) {
          if (nearby) {
            const distKm = distance(u);
            if ((u.show_distance ? distKm : Math.ceil(distKm / 2) * 2) > radiusKm) continue;
          }
          const vis = JSON.parse(u.profile_visibility || "{}");
          const isVis = (k) => vis[k] !== false;
          const pubCity = isVis("city") ? u.city : "";
          const pubLookingFor = isVis("lookingFor") ? u.looking_for : "";
          const pubGender = u.identity_public && isVis("gender") ? u.gender : "";
          const pubOrientation = u.identity_public && isVis("orientation") ? u.orientation : "";
          const pubCommunityRole = u.identity_public && isVis("communityRole") ? u.community_role : "";
          const pubRelationshipRole = u.identity_public && isVis("relationshipRole") ? u.relationship_role : "";
          const pubAge = isVis("age") ? (u.profile_dob ? birthAge(u.profile_dob) : u.age) : null;
          const pubInterests = isVis("interests") ? JSON.parse(u.interests || "[]") : [];
          if (qKey) {
            const hay = adminSearchKey([u.name, u.username, pubCity, pubGender, pubOrientation, pubRelationshipRole, ...pubInterests].join(" "));
            if (!hay.includes(qKey)) continue;
          }
          if (wantedGender) {
            const actual = normalize(pubGender);
            if (!actual || canonical(actual) !== canonical(wantedGender)) continue;
          }
          if (wantedOrientation && canonicalOrientation(pubOrientation) !== canonicalOrientation(wantedOrientation)) continue;
          if (wantedCommunityRole && normalize(pubCommunityRole) !== wantedCommunityRole) continue;
          if (minHeight || maxHeight || minWeight || maxWeight) {
            const rawDetails = JSON.parse(u.profile_details || "{}");
            const pubHeight = isVis("height") ? rawDetails.height : undefined;
            const pubWeight = isVis("weight") ? rawDetails.weight : undefined;
            if ((minHeight || maxHeight) && (!Number.isFinite(pubHeight) || (minHeight && pubHeight < minHeight) || (maxHeight && pubHeight > maxHeight))) continue;
            if ((minWeight || maxWeight) && (!Number.isFinite(pubWeight) || (minWeight && pubWeight < minWeight) || (maxWeight && pubWeight > maxWeight))) continue;
          }
          if ((minAge || maxAge) && (!Number.isFinite(pubAge) || (minAge && pubAge < minAge) || (maxAge && pubAge > maxAge))) continue;
          if (wantedIntent && !normalize(pubLookingFor).includes(wantedIntent)) continue;
          const hasLocation = me.lat !== null && me.lng !== null && u.lat !== null && u.lng !== null;
          const roundedMeters = hasLocation ? meters(u) : null;
          const kmVal = roundedMeters !== null ? Number((roundedMeters / 1000).toFixed(1)) : null;
          const labelVal = roundedMeters !== null && u.show_distance ? distanceLabel(roundedMeters) : "";
          matched.push({
            u,
            joinedAt: u.created,
            lastActiveAt: u.show_activity ? u.last_active || null : null,
            score: pubInterests.filter((v) => mine.includes(v)).length,
            roundedMeters,
            kmVal,
            labelVal,
            _sortDistance: roundedMeters !== null && u.show_distance ? roundedMeters : 999999,
          });
        }
        matched.sort((a, b) =>
          nearby ? a._sortDistance - b._sortDistance || b.joinedAt - a.joinedAt :
            order === "interests" ? b.score - a.score || b.joinedAt - a.joinedAt :
            b.joinedAt - a.joinedAt,
        );
        if (recentOnly) {
          matched.sort((a, b) => (b.lastActiveAt || 0) - (a.lastActiveAt || 0) || (nearby ? a._sortDistance - b._sortDistance : b.joinedAt - a.joinedAt));
        }
        const users = matched.slice(0, 50).map((item) => {
          const pub = publicUser(item.u, me.id);
          return {
            ...pub,
            score: item.score,
            distanceBand: item.labelVal,
            distanceLabel: item.labelVal,
            distanceKm: item.roundedMeters !== null && item.u.show_distance ? item.kmVal : null,
            ...(item.roundedMeters !== null && item.u.show_distance ? { distanceMeters: item.roundedMeters } : {}),
          };
        });
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
        const canSeeFollowers = u.id === me.id || follows(me.id, u.id);
        return json(200, {
          user: publicUser(u, me.id),
          followers: get("SELECT count(*) AS n FROM follows WHERE target=?", u.id).n,
          following: get("SELECT count(*) AS n FROM follows WHERE actor=?", u.id).n,
          posts: canSeeFollowers
            ? get("SELECT count(*) AS n FROM posts WHERE user_id=? AND hidden=0 AND id NOT IN (SELECT post_id FROM post_stories)", u.id).n
            : get("SELECT count(*) AS n FROM posts WHERE user_id=? AND hidden=0 AND visibility='public' AND id NOT IN (SELECT post_id FROM post_stories)", u.id).n,
        });
      }
      const directMsgEdit = path.match(/^\/api\/users\/([a-zA-Z0-9-]+)\/messages\/([a-zA-Z0-9-]+)$/);
      if (directMsgEdit && req.method === "PATCH") {
        const [, peerId, msgId] = directMsgEdit;
        if (peerId === me.id) fail(400, "Không thể thao tác với chính mình.");
        targetUser(peerId, me);
        const existing = get("SELECT sender,recipient FROM messages WHERE id=?", msgId);
        if (!existing || !((existing.sender === me.id && existing.recipient === peerId) || (existing.sender === peerId && existing.recipient === me.id))) {
          fail(404, "Không tìm thấy tin nhắn.");
        }
        const b = await body(req, 16000);
        return json(200, { ok: true, message: messageState.editMessage("direct", msgId, me, b.body) });
      }
      const route = path.match(
        /^\/api\/users\/([a-zA-Z0-9-]+)(?:\/(follow|block|messages\/search|messages|avatar|cover))?$/,
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
        if (["avatar","cover"].includes(action) && ["GET","HEAD"].includes(req.method)) {
          const image=action==="cover"?target.cover:target.avatar,imageType=action==="cover"?target.cover_type:target.avatar_type;
          if (!image) fail(404, "Chưa có ảnh.");
          const hasVersion=new URL(req.url,"http://local").searchParams.has("v");
          sendCachedMedia(req, res, { bytes: image, type: imageType, maxAge: hasVersion ? 3600 : 300, allowRange: false });
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
        if (action === "messages/search" && req.method === "GET") {
          const params = new URL(req.url, "http://local").searchParams;
          const q = text(params.get("q"), 100);
          const rawLimit = Number.parseInt(params.get("limit") || "", 10);
          const limit = Number.isFinite(rawLimit) && rawLimit >= 1 ? Math.min(50, rawLimit) : 30;
          if (!q) return json(200, { messages: [], query: "" });
          const needle = "%" + escapeLike(adminSearchKey(q)) + "%";
          const messages = all(
            "SELECT m.id,m.sender,m.recipient,m.body,m.created FROM messages m WHERE ((m.sender=? AND m.recipient=?) OR (m.sender=? AND m.recipient=?)) AND admin_search_key(m.body) LIKE ? ESCAPE '\\' AND NOT EXISTS (SELECT 1 FROM hidden_chat_messages h WHERE h.kind='direct' AND h.message_id=m.id AND h.user_id=?) AND NOT EXISTS (SELECT 1 FROM recalled_chat_messages r WHERE r.kind='direct' AND r.message_id=m.id) ORDER BY m.created DESC,m.rowid DESC LIMIT ?",
            me.id, id, id, me.id, needle, me.id, limit,
          )
            .map((m) => messageState.decorate("direct", { ...m, attachment: attachments.metadata("direct", m.id) }, me.id));
          return json(200, { messages, query: q });
        }
        if (action === "messages") {
          if(req.method==='DELETE'){messageState.clear('direct',id,me.id);return json(200,{ok:true});}
          if (req.method === "GET") {
            const params = new URL(req.url, "http://local").searchParams;
            const rawBefore = Number(params.get("before"));
            const before = Number.isSafeInteger(rawBefore) && rawBefore > 0 ? rawBefore : null;
            const rawLimit = Number.parseInt(params.get("limit") || "", 10);
            const limit = Number.isFinite(rawLimit) && rawLimit >= 1 ? Math.min(100, rawLimit) : 100;
            if (!before) {
              messageState.markRead("direct",id,me.id);
              const readAt=Date.now();
              run("INSERT INTO message_receipts(message_id,delivered_at,seen_at) SELECT id,?,? FROM messages WHERE sender=? AND recipient=? AND NOT EXISTS (SELECT 1 FROM message_receipts r WHERE r.message_id=messages.id AND r.seen_at IS NOT NULL) ON CONFLICT(message_id) DO UPDATE SET delivered_at=COALESCE(delivered_at,excluded.delivered_at),seen_at=COALESCE(seen_at,excluded.seen_at)",readAt,readAt,id,me.id);
              run("UPDATE notifications SET seen=1 WHERE user_id=? AND actor=? AND kind IN ('message','missed_call')", me.id, id);
            }
            const raw = before
              ? all(
                "SELECT m.id,m.sender,m.recipient,m.body,m.created FROM messages m WHERE ((m.sender=? AND m.recipient=?) OR (m.sender=? AND m.recipient=?)) AND m.created<? AND NOT EXISTS (SELECT 1 FROM hidden_chat_messages h WHERE h.kind='direct' AND h.message_id=m.id AND h.user_id=?) ORDER BY m.created DESC,m.rowid DESC LIMIT ?",
                me.id,
                id,
                id,
                me.id,
                before,
                me.id,
                limit + 1,
              )
              : all(
                "SELECT m.id,m.sender,m.recipient,m.body,m.created FROM messages m WHERE ((m.sender=? AND m.recipient=?) OR (m.sender=? AND m.recipient=?)) AND NOT EXISTS (SELECT 1 FROM hidden_chat_messages h WHERE h.kind='direct' AND h.message_id=m.id AND h.user_id=?) ORDER BY m.created DESC,m.rowid DESC LIMIT ?",
                me.id,
                id,
                id,
                me.id,
                me.id,
                limit + 1,
              );
            const hasMore = raw.length > limit;
            const slice = raw.slice(0, limit);
            const nextCursor = hasMore && slice.length ? slice[slice.length - 1].created : null;
            return json(200, {
              user:publicUser(target,me.id),
              aiSupport:ai.supportInfo(me.id,id),
              messages: slice.reverse().map(m=>messageState.decorate("direct",{...m,privateAlbum:privateAlbum.messageMetadata(m.id),receipt:get("SELECT delivered_at AS deliveredAt,seen_at AS seenAt FROM message_receipts WHERE message_id=?",m.id)||{},attachment:attachments.metadata("direct",m.id)},me.id)),
              hasMore,
              nextCursor,
            });
          }
          if (req.method === "POST") {
            if(target.dm_mode==='nobody')fail(403,'Người dùng này đã tắt nhận tin nhắn.');
            if(target.dm_mode==='friends'&&friendConnections.status(me.id,id)!=='friends')fail(403,'Người này chỉ nhận tin nhắn từ bạn bè.');
            const b = await body(req,29000000),
              content = text(b.body, 2000);
            const decorateDirect = (m) => messageState.decorate("direct", {
              ...m,
              privateAlbum: privateAlbum.messageMetadata(m.id),
              receipt: get("SELECT delivered_at AS deliveredAt,seen_at AS seenAt FROM message_receipts WHERE message_id=?", m.id) || {},
              attachment: attachments.metadata("direct", m.id),
            }, me.id);
            let reqId = "";
            if (b.requestId !== undefined && b.requestId !== null && b.requestId !== "") {
              if (typeof b.requestId !== "string" || !b.requestId.trim() || b.requestId.trim().length > 128) {
                fail(400, "Mã yêu cầu không hợp lệ.");
              }
              reqId = b.requestId.trim();
              const prev = get("SELECT message_id FROM chat_request_ids WHERE user_id=? AND kind='direct' AND target_id=? AND request_id=?", me.id, id, reqId);
              if (prev) {
                const existing = get("SELECT id,sender,recipient,body,created FROM messages WHERE id=?", prev.message_id);
                if (existing) return json(200, { duplicate: true, message: decorateDirect(existing) });
              }
            }
            const file=attachments.decode(b.attachment);
            if (!content&&!file) fail(400, "Nhập nội dung hoặc chọn tệp.");
            const replyToId = messageState.resolveReplyTarget("direct", id, b.replyToId, me.id);
            if (file && file.type.startsWith("image/")) {
              const opt = await mediaCompressor.compressImage(file.bytes, file.type, "chat");
              if (opt.compressed) {
                file.bytes = opt.bytes;
                file.type = opt.type;
                file.name = file.name.replace(/\.(png|webp)$/i, ".jpg");
              }
            }
            let message = null, duplicateMessage = null;
            db.exec("BEGIN IMMEDIATE");
            try {
              const freshMe = user(me.id);
              if (!freshMe || freshMe.suspended !== 0) fail(401, "Vui lòng đăng nhập.");
              const freshTarget = user(id);
              if (!freshTarget || freshTarget.suspended !== 0 || blocked(me.id, id)) fail(404, "Không tìm thấy người dùng.");
              if (freshTarget.dm_mode === "nobody") fail(403, "Người dùng này đã tắt nhận tin nhắn.");
              if (freshTarget.dm_mode === "friends" && friendConnections.status(me.id, id) !== "friends") fail(403, "Người này chỉ nhận tin nhắn từ bạn bè.");
              if (reqId) {
                const prev = get("SELECT message_id FROM chat_request_ids WHERE user_id=? AND kind='direct' AND target_id=? AND request_id=?", me.id, id, reqId);
                if (prev) {
                  const existing = get("SELECT id,sender,recipient,body,created FROM messages WHERE id=?", prev.message_id);
                  if (existing) duplicateMessage = existing;
                }
              }
              if (!duplicateMessage) {
                const latestDirect = get("SELECT MAX(created) AS t FROM messages WHERE (sender=? AND recipient=?) OR (sender=? AND recipient=?)", me.id, id, id, me.id)?.t || 0;
                message = {
                  id: randomUUID(),
                  sender: me.id,
                  recipient: id,
                  body: content,
                  created: Math.max(Date.now(), latestDirect + 1),
                };
                run(
                  "INSERT INTO messages VALUES(?,?,?,?,?)",
                  message.id,
                  me.id,
                  id,
                  content,
                  message.created,
                );
                messageState.linkReply("direct", message.id, replyToId);
                attachments.save("direct", message.id, file);
                if (reqId) {
                  run("INSERT OR REPLACE INTO chat_request_ids(user_id,kind,target_id,request_id,message_id,created) VALUES(?, 'direct', ?, ?, ?, ?)", me.id, id, reqId, message.id, message.created);
                }
              }
              db.exec("COMMIT");
            } catch (err) {
              db.exec("ROLLBACK");
              throw err;
            }
            if (duplicateMessage) return json(200, { duplicate: true, message: decorateDirect(duplicateMessage) });
            if (file && (file.type === "video/mp4" || file.type === "video/webm")) {
              mediaCompressor.enqueueVideo({ table: "chat_attachments", id: file.id, bytes: file.bytes, type: file.type, profile: "chat" });
            }
            messageState.reveal("direct",id,me.id);messageState.reveal("direct",me.id,id);
            notice(id, me.id, "message", message.id);
            options.onCallMessage?.({ userIds: [me.id, id] });
            if(me.role==='admin')ai.pause(id,true);else ai.support(message);
            return json(201, { message: decorateDirect(message) });
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
      if (path === "/api/messages/search" && req.method === "GET") {
        const params = new URL(req.url, "http://local").searchParams;
        const q = text(params.get("q"), 100);
        const rawLimit = Number.parseInt(params.get("limit") || "", 10);
        const limit = Number.isFinite(rawLimit) && rawLimit >= 1 ? Math.min(50, rawLimit) : 30;
        if (!q) return json(200, { results: [], query: "" });
        const needle = "%" + escapeLike(adminSearchKey(q)) + "%";
        const directRows = all(
          `SELECT m.id,m.sender,m.recipient,m.body,m.created
           FROM messages m
           JOIN users u ON u.id=(CASE WHEN m.sender=? THEN m.recipient ELSE m.sender END)
           WHERE (m.sender=? OR m.recipient=?)
             AND u.suspended=0
             AND admin_search_key(m.body) LIKE ? ESCAPE '\\'
             AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.actor=? AND b.target=u.id) OR (b.target=? AND b.actor=u.id))
             AND NOT EXISTS (SELECT 1 FROM hidden_chat_messages h WHERE h.kind='direct' AND h.message_id=m.id AND h.user_id=?)
             AND NOT EXISTS (SELECT 1 FROM recalled_chat_messages r WHERE r.kind='direct' AND r.message_id=m.id)
           ORDER BY m.created DESC,m.rowid DESC LIMIT ?`,
          me.id, me.id, me.id, needle, me.id, me.id, me.id, limit,
        )
          .map((m) => {
            const peerId = m.sender === me.id ? m.recipient : m.sender;
            return {
              kind: "direct",
              conversationId: peerId,
              peer: publicUser(user(peerId), me.id),
              message: messageState.decorate("direct", { ...m, attachment: attachments.metadata("direct", m.id) }, me.id),
              created: m.created,
            };
          });
        const groupRows = all(
          `SELECT m.*,g.name AS group_name
           FROM group_messages m
           JOIN group_members gm ON gm.group_id=m.group_id
           JOIN chat_groups g ON g.id=m.group_id
           JOIN users u ON u.id=m.sender
           WHERE gm.user_id=?
             AND u.suspended=0
             AND admin_search_key(m.body) LIKE ? ESCAPE '\\'
             AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.actor=? AND b.target=m.sender) OR (b.target=? AND b.actor=m.sender))
             AND NOT EXISTS (SELECT 1 FROM hidden_chat_messages h WHERE h.kind='group' AND h.message_id=m.id AND h.user_id=?)
             AND NOT EXISTS (SELECT 1 FROM recalled_chat_messages r WHERE r.kind='group' AND r.message_id=m.id)
           ORDER BY m.created DESC,m.rowid DESC LIMIT ?`,
          me.id, needle, me.id, me.id, me.id, limit,
        )
          .map((m) => ({
            kind: "group",
            conversationId: m.group_id,
            groupName: m.group_name,
            message: messageState.decorate("group", { id: m.id, group_id: m.group_id, sender: m.sender, body: m.body, created: m.created, attachment: attachments.metadata("group", m.id), author: publicUser(user(m.sender), me.id) }, me.id),
            created: m.created,
          }));
        const results = [...directRows, ...groupRows].sort((a, b) => b.created - a.created).slice(0, limit);
        return json(200, { results, query: q });
      }
      if (path === "/api/hashtags/trending" && req.method === "GET") {
        const params = new URL(req.url, "http://local").searchParams;
        const rawLimit = Number.parseInt(params.get("limit") || "", 10);
        const limit = Number.isFinite(rawLimit) && rawLimit >= 1 ? Math.min(30, rawLimit) : 15;
        const since = Date.now() - 30 * 86400000;
        const rows = all(
          "SELECT h.tag,p.user_id,p.visibility,p.hidden FROM post_hashtags h JOIN posts p ON p.id=h.post_id WHERE p.hidden=0 AND p.created>? AND p.id NOT IN (SELECT post_id FROM post_stories)",
          since,
        ).filter((r) => canViewPost(r, me.id));
        const counts = new Map();
        for (const r of rows) counts.set(r.tag, (counts.get(r.tag) || 0) + 1);
        const hashtags = [...counts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).slice(0, limit).map(([tag, count]) => ({ tag, count }));
        return json(200, { hashtags });
      }
      if (path === "/api/bookmarks" && req.method === "GET") {
        const params = new URL(req.url, "http://local").searchParams;
        const rawBefore = Number(params.get("before")), before = Number.isSafeInteger(rawBefore) && rawBefore > 0 ? rawBefore : null;
        const rawLimit = Number.parseInt(params.get("limit") || "", 10), limit = Number.isFinite(rawLimit) && rawLimit >= 1 ? Math.min(100, rawLimit) : 50;
        const rows = all(
          "SELECT p.*,COALESCE(pc.category,'community') AS category,b.created AS bookmarked_at FROM post_bookmarks b JOIN posts p ON p.id=b.post_id LEFT JOIN post_categories pc ON pc.post_id=p.id WHERE b.user_id=? AND p.hidden=0 AND p.id NOT IN (SELECT post_id FROM post_stories)" + (before ? " AND b.created<?" : "") + " ORDER BY b.created DESC LIMIT 300",
          me.id, ...(before ? [before] : []),
        ).filter((p) => canViewPost(p, me.id));
        const hasMore = rows.length > limit;
        const page = rows.slice(0, limit);
        const nextCursor = hasMore && page.length ? page[page.length - 1].bookmarked_at : null;
        return json(200, {
          posts: page.map(({ bookmarked_at, ...p }) => ({ ...decoratePost(p, me.id), bookmarkedAt: bookmarked_at })),
          hasMore,
          nextCursor,
        });
      }
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
          .filter(p=>!blocked(me.id,p.user_id)).map(p=>{
            const isVideo = !!p.type && p.type.startsWith("video/");
            const hasThumb = isVideo && !!get("SELECT 1 FROM media_thumbnails WHERE kind='post' AND target_id=?", p.id);
            return {...p,viewCount:p.user_id===me.id?all('SELECT user_id FROM story_views WHERE post_id=?',p.id).filter(v=>user(v.user_id)?.suspended===0&&!blocked(me.id,v.user_id)).length:undefined,author:publicUser(user(p.user_id),me.id),media:p.type?{kind:isVideo?"video":"image",url:"/api/posts/"+p.id+"/media",...(isVideo?{thumbnail:hasThumb?"/api/posts/"+p.id+"/thumbnail":null}:{})}:null};
          });
        return json(200,{stories});
      }
      if (path === "/api/posts" || path === "/api/search/posts" || (path === "/api/stories" && req.method === "POST")) {
        if (req.method === "POST" && path !== "/api/search/posts") {
          const b = await body(req, 35 * 1024 * 1024),
            content = text(b.body, 2000),
            batch = await decodePostMediaBatch(b, path !== "/api/stories"),
            media = batch.primary;
          let shareOriginal = null;
          if (b.sharePostId !== undefined && b.sharePostId !== null && b.sharePostId !== "") {
            if (path === "/api/stories") fail(400, "Không hỗ trợ chia sẻ bài viết vào tin 24 giờ.");
            if (typeof b.sharePostId !== "string") fail(400, "Bài viết chia sẻ không hợp lệ.");
            const orig = get("SELECT p.*,u.suspended FROM posts p JOIN users u ON u.id=p.user_id WHERE p.id=? AND p.hidden=0", b.sharePostId);
            if (!orig || orig.suspended || blocked(me.id, orig.user_id) || orig.visibility !== "public" || get("SELECT 1 FROM post_stories WHERE post_id=?", orig.id)) {
              fail(404, "Không tìm thấy bài viết công khai để chia sẻ.");
            }
            shareOriginal = orig;
          }
          if (
            (!content && !media && !shareOriginal) ||
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
          for(let i=0;i<batch.items.length;i++){
            const it=batch.items[i];
            run("INSERT INTO post_media_items(id,post_id,position,type,data) VALUES(?,?,?,?,?)",it.id,id,i,it.type,it.bytes);
          }
          if(shareOriginal) run("INSERT INTO post_shares(post_id,original_post_id) VALUES(?,?)",id,shareOriginal.id);
          if(path === "/api/stories") run("INSERT INTO post_stories(post_id,expires,background) VALUES(?,?,?)",id,Date.now()+86400000,["purple","sunset","forest","ocean"].includes(b.background)?b.background:"purple");
          syncPostHashtags(id, content);
          db.exec("COMMIT");
          } catch(error) { db.exec("ROLLBACK"); throw error; }
          if(shareOriginal && shareOriginal.user_id !== me.id) notice(shareOriginal.user_id, me.id, "share", id);
          if(media&&media.kind==='video')mediaCompressor.enqueueVideo({table:'post_media',id,bytes:media.bytes,type:media.type,profile:'post'});
          ai.enqueue('post',id,me.id,{text:content||'Kiểm tra nội dung bài viết.',...(media&&['image/png','image/jpeg'].includes(media.type)?{image:{mime:media.type,data:media.bytes.toString('base64')}}:{})});
          return json(201, { id });
        }
        if (req.method === "GET") {
          const params=new URL(req.url,"http://local").searchParams,only=params.get('user'),postId=params.get('post'),category=params.get('category');if(category&&!['community','confessions','questions','events'].includes(category))fail(400,'Mục không hợp lệ.');
          const q = text(params.get('q'), 100);
          const rawTag = text(params.get('tag'), 50).replace(/^#/, '');
          const rawBefore=Number(params.get('before')),before=Number.isSafeInteger(rawBefore)&&rawBefore>0?rawBefore:null;
          const rawLimit=Number.parseInt(params.get('limit')||'',10),limit=Number.isFinite(rawLimit)&&rawLimit>=1?Math.min(100,rawLimit):100;
          const visible = all(
            "SELECT p.*,COALESCE(pc.category,'community') AS category FROM posts p LEFT JOIN post_categories pc ON pc.post_id=p.id JOIN users u ON u.id=p.user_id WHERE p.hidden=0 AND u.suspended=0 AND p.id NOT IN (SELECT post_id FROM post_stories)" +
              (only ? " AND p.user_id=?" : "") + (postId ? " AND p.id=?" : "") +
              (category?" AND COALESCE(pc.category,'community')=?":"") +
              (q?" AND admin_search_key(p.body) LIKE ? ESCAPE '\\'":"") +
              (rawTag?" AND EXISTS (SELECT 1 FROM post_hashtags h WHERE h.post_id=p.id AND admin_search_key(h.tag)=?)":"") +
              (before?" AND p.created<?":"") +
              " ORDER BY p.created DESC,p.rowid DESC LIMIT 500",
            ...(only ? [only] : []),...(postId?[postId]:[]),...(category?[category]:[]),...(q?['%'+escapeLike(adminSearchKey(q))+'%']:[]),...(rawTag?[adminSearchKey(rawTag)]:[]),...(before?[before]:[]),
          )
            .filter((p) => canViewPost(p, me.id));
          const hasMore = visible.length > limit;
          const page = visible.slice(0, limit);
          const nextCursor = hasMore && page.length ? page[page.length - 1].created : null;
          const posts = page.map((p) => decoratePost(p, me.id));
          return json(200, { posts, hasMore, nextCursor, ...(path === "/api/search/posts" ? { query: q, tag: rawTag } : {}) });
        }
      }
      const commentEdit=path.match(/^\/api\/posts\/([a-zA-Z0-9-]+)\/comments\/([a-zA-Z0-9-]+)$/);
      if(commentEdit){
        const [,pid,cid]=commentEdit,p=get('SELECT * FROM posts WHERE id=? AND hidden=0',pid),c=get('SELECT * FROM post_comments WHERE id=? AND post_id=? AND user_id=?',cid,pid,me.id);
        if(!p||!c||get('SELECT 1 FROM post_stories WHERE post_id=?',pid)||blocked(me.id,p.user_id)||user(p.user_id)?.suspended!==0||(p.visibility==='followers'&&p.user_id!==me.id&&!follows(me.id,p.user_id)))fail(404,'Không tìm thấy bình luận của bạn.');
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
        if (!p || get("SELECT 1 FROM post_stories WHERE post_id=?", p.id) || blocked(me.id, p.user_id) || user(p.user_id)?.suspended !== 0 || (p.visibility === "followers" && p.user_id !== me.id && !follows(me.id, p.user_id)))
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
          get("SELECT 1 FROM post_stories WHERE post_id=?", p.id) ||
          blocked(me.id, p.user_id) ||
          user(p.user_id)?.suspended !== 0 ||
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
        if (req.method === "GET") {
          const visibleComments = all(
            "SELECT * FROM post_comments WHERE post_id=? ORDER BY created ASC LIMIT 200",
            pid,
          ).filter((c) => !blocked(me.id, c.user_id) && user(c.user_id)?.suspended === 0);
          const visibleIds = new Set(visibleComments.map((c) => c.id));
          return json(200, {
            comments: visibleComments.map((c) => ({
              ...threads.decorate("post", c, me, visibleIds),
              author: publicUser(user(c.user_id), me.id),
            })),
          });
        }
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
      const postSocialAction = path.match(/^\/api\/posts\/([a-zA-Z0-9-]+)\/(bookmark|share)$/);
      if (postSocialAction) {
        const [, pid, what] = postSocialAction;
        const p = get("SELECT p.*,u.suspended FROM posts p JOIN users u ON u.id=p.user_id WHERE p.id=? AND p.hidden=0", pid);
        if (!p || p.suspended || blocked(me.id, p.user_id) || get("SELECT 1 FROM post_stories WHERE post_id=?", p.id)) {
          fail(404, "Không tìm thấy bài viết.");
        }
        if (what === "bookmark") {
          if (p.visibility !== "public" && p.user_id !== me.id && !follows(me.id, p.user_id)) fail(404, "Không tìm thấy bài viết.");
          if (req.method === "POST") {
            run("INSERT OR REPLACE INTO post_bookmarks(user_id,post_id,created) VALUES(?,?,?)", me.id, pid, Date.now());
            return json(200, { ok: true, bookmarked: true });
          }
          if (req.method === "DELETE") {
            run("DELETE FROM post_bookmarks WHERE user_id=? AND post_id=?", me.id, pid);
            return json(200, { ok: true, bookmarked: false });
          }
          fail(405, "Phương thức không hợp lệ.");
        }
        if (what === "share") {
          if (req.method !== "POST") fail(405, "Phương thức không hợp lệ.");
          if (p.visibility !== "public") fail(403, "Chỉ chia sẻ được bài viết công khai.");
          const b = await body(req, 16000);
          const content = text(b.body, 2000);
          const visibility = b.visibility || "public";
          if (!["public", "followers"].includes(visibility)) fail(400, "Quyền xem không hợp lệ.");
          const category = b.category || "community";
          if (!["community", "confessions", "questions", "events"].includes(category)) fail(400, "Mục đăng bài không hợp lệ.");
          const id = randomUUID();
          db.exec("BEGIN IMMEDIATE");
          try {
            run("INSERT INTO posts VALUES(?,?,?,?,0,?)", id, me.id, content, visibility, Date.now());
            run("INSERT INTO post_categories VALUES(?,?)", id, category);
            run("INSERT INTO post_shares(post_id,original_post_id) VALUES(?,?)", id, p.id);
            syncPostHashtags(id, content);
            db.exec("COMMIT");
          } catch (error) { db.exec("ROLLBACK"); throw error; }
          if (p.user_id !== me.id) notice(p.user_id, me.id, "share", id);
          const createdRow = get("SELECT p.*,COALESCE(pc.category,'community') AS category FROM posts p LEFT JOIN post_categories pc ON pc.post_id=p.id WHERE p.id=?", id);
          return json(201, { id, post: decoratePost(createdRow, me.id) });
        }
      }
      const post = path.match(/^\/api\/posts\/([a-zA-Z0-9-]+)$/);
      if(post && req.method==='PATCH'){
        const current=get('SELECT * FROM posts WHERE id=? AND user_id=? AND hidden=0',post[1],me.id);
        if(!current || get('SELECT 1 FROM post_stories WHERE post_id=?',post[1]))fail(404,'Không tìm thấy bài viết của bạn.');
        const b=await body(req,35 * 1024 * 1024),content=b.body===undefined?current.body:text(b.body,2000),visibility=b.visibility===undefined?current.visibility:b.visibility;
        if(!['public','followers'].includes(visibility))fail(400,'Đối tượng xem không hợp lệ.');
        const replacingMedia=b.media!==undefined||b.mediaItems!==undefined;
        const batch=replacingMedia?await decodePostMediaBatch(b,true):{items:[],primary:null};
        const media=batch.primary;
        const hasMediaAfter=replacingMedia?!!media:!!(get('SELECT post_id FROM post_media WHERE post_id=?',post[1])||get('SELECT 1 FROM post_media_items WHERE post_id=? LIMIT 1',post[1]));
        if(!content&&!hasMediaAfter&&!get('SELECT 1 FROM post_shares WHERE post_id=?',post[1]))fail(400,'Nhập nội dung hoặc chọn ảnh / video.');

        db.exec('BEGIN IMMEDIATE');try{
          run('UPDATE posts SET body=?,visibility=? WHERE id=?',content,visibility,post[1]);
          syncPostHashtags(post[1],content);
          if(replacingMedia){
            run("DELETE FROM media_thumbnails WHERE kind='post' AND target_id=?",post[1]);
            run('DELETE FROM post_media_items WHERE post_id=?',post[1]);
            if(media){
              run('INSERT INTO post_media VALUES(?,?,?) ON CONFLICT(post_id) DO UPDATE SET type=excluded.type,data=excluded.data',post[1],media.type,media.bytes);
              for(let i=0;i<batch.items.length;i++){
                const it=batch.items[i];
                run('INSERT INTO post_media_items(id,post_id,position,type,data) VALUES(?,?,?,?,?)',it.id,post[1],i,it.type,it.bytes);
              }
            }else{
              run('DELETE FROM post_media WHERE post_id=?',post[1]);
            }
          }
          db.exec('COMMIT');
        }catch(error){db.exec('ROLLBACK');throw error;}
        if(media&&media.kind==='video')mediaCompressor.enqueueVideo({table:'post_media',id:post[1],bytes:media.bytes,type:media.type,profile:'post'});
        ai.enqueue('post',post[1],me.id,{text:content||'Kiểm tra nội dung bài viết đã chỉnh sửa.',...(media&&['image/png','image/jpeg'].includes(media.type)?{image:{mime:media.type,data:media.bytes.toString('base64')}}:{})});
        return json(200,{ok:true});
      }
      if (post && req.method === "DELETE") {
        if (!get("SELECT 1 FROM posts WHERE id=? AND user_id=?", post[1], me.id)) {
          fail(404, "Không tìm thấy bài viết của bạn.");
        }
        db.exec("BEGIN IMMEDIATE");
        try {
          run("DELETE FROM comment_reactions WHERE kind='post' AND comment_id IN (SELECT id FROM post_comments WHERE post_id=?)", post[1]);
          run("DELETE FROM comment_threads WHERE kind='post' AND (comment_id IN (SELECT id FROM post_comments WHERE post_id=?) OR parent_id IN (SELECT id FROM post_comments WHERE post_id=?))", post[1], post[1]);
          run("DELETE FROM notification_targets WHERE comment_id IN (SELECT id FROM post_comments WHERE post_id=?)", post[1]);
          run("DELETE FROM media_thumbnails WHERE kind='post' AND target_id=?", post[1]);
          run("DELETE FROM posts WHERE id=? AND user_id=?", post[1], me.id);
          db.exec("COMMIT");
        } catch (err) {
          db.exec("ROLLBACK");
          throw err;
        }
        return json(200, { ok: true });
      }
      if (path === "/api/notifications") {
        if(req.method==='GET')run("INSERT INTO message_receipts(message_id,delivered_at) SELECT id,? FROM messages WHERE recipient=? AND NOT EXISTS (SELECT 1 FROM message_receipts r WHERE r.message_id=messages.id AND r.delivered_at IS NOT NULL) ON CONFLICT(message_id) DO UPDATE SET delivered_at=COALESCE(delivered_at,excluded.delivered_at)",Date.now(),me.id);
        if (req.method === "GET")
          return json(200, {
            friendRequestsPending:friendConnections.pendingCount(me.id),
            ...(me.role==='admin'?{passwordResetsPending:get("SELECT count(*) AS n FROM password_resets WHERE status='open'").n}:{}),
            notifications: all(
              "SELECT * FROM notifications WHERE user_id=? ORDER BY created DESC,rowid DESC LIMIT 100",
              me.id,
            )
              .filter(
                (n) =>
                  !blocked(me.id, n.actor) &&
                  user(n.actor)?.suspended === 0 &&
                  (n.kind !== "group_message" || !!get("SELECT 1 FROM group_members WHERE group_id=? AND user_id=?", n.ref, me.id)),
              )
              .map((n) => {
                const targetId = get("SELECT comment_id FROM notification_targets WHERE notification_id=?", n.id)?.comment_id || null;
                const commentId = (n.kind === "comment" || n.kind === "comment_reply" || n.kind === "short_comment") ? targetId : null;
                // Short content preview for native push popups (guarded against recalled/hidden/unviewable content).
                let row = null;
                let targetKind = null;
                if (n.kind === "message") {
                  if (n.ref && !messageState.recalled("direct", n.ref) && messageState.visible("direct", n.ref, me.id)) {
                    row = get("SELECT body FROM messages WHERE id=? AND (sender=? OR recipient=?)", n.ref, me.id, me.id);
                  }
                } else if (n.kind === "group_message") {
                  const gm = targetId
                    ? get("SELECT id,body FROM group_messages WHERE id=? AND group_id=?", targetId, n.ref)
                    : get("SELECT id,body FROM group_messages WHERE group_id=? AND sender=? AND created<=? ORDER BY created DESC,rowid DESC LIMIT 1", n.ref, n.actor, n.created);
                  if (gm && !messageState.recalled("group", gm.id) && messageState.visible("group", gm.id, me.id)) {
                    row = gm;
                  }
                } else if (n.kind === "comment" || n.kind === "comment_reply") {
                  const postRow = get("SELECT * FROM posts WHERE id=?", n.ref);
                  if (postRow) {
                    targetKind = "post";
                    if (!postRow.hidden && canViewPost(postRow, me.id)) {
                      row = commentId
                        ? get("SELECT body FROM post_comments WHERE id=? AND post_id=?", commentId, n.ref)
                        : get("SELECT body FROM post_comments WHERE post_id=? AND user_id=? ORDER BY created DESC LIMIT 1", n.ref, n.actor);
                    }
                  } else {
                    const shortRow = get("SELECT id,user_id,hidden FROM shorts WHERE id=?", n.ref);
                    if (shortRow) {
                      targetKind = "short";
                      if (!shortRow.hidden && user(shortRow.user_id)?.suspended === 0 && !blocked(me.id, shortRow.user_id)) {
                        row = commentId
                          ? get("SELECT body FROM short_comments WHERE id=? AND short_id=?", commentId, n.ref)
                          : get("SELECT body FROM short_comments WHERE short_id=? AND user_id=? ORDER BY created DESC LIMIT 1", n.ref, n.actor);
                      }
                    }
                  }
                } else if (n.kind === "short_comment") {
                  targetKind = "short";
                  const shortRow = get("SELECT id,user_id,hidden FROM shorts WHERE id=?", n.ref);
                  if (shortRow && !shortRow.hidden && user(shortRow.user_id)?.suspended === 0 && !blocked(me.id, shortRow.user_id)) {
                    row = commentId
                      ? get("SELECT body FROM short_comments WHERE id=? AND short_id=?", commentId, n.ref)
                      : get("SELECT body FROM short_comments WHERE short_id=? AND user_id=? ORDER BY created DESC LIMIT 1", n.ref, n.actor);
                  }
                } else if (n.kind === "like" || n.kind === "share") {
                  targetKind = "post";
                  const postRow = get("SELECT * FROM posts WHERE id=?", n.ref);
                  if (postRow && !postRow.hidden && canViewPost(postRow, me.id)) {
                    row = postRow;
                  }
                } else if (n.kind === "short_like") {
                  targetKind = "short";
                  const shortRow = get("SELECT caption AS body,user_id,hidden FROM shorts WHERE id=?", n.ref);
                  if (shortRow && !shortRow.hidden && user(shortRow.user_id)?.suspended === 0 && !blocked(me.id, shortRow.user_id)) {
                    row = shortRow;
                  }
                }
                const preview = row && typeof row.body === "string" && !row.body.startsWith("{") ? row.body.replace(/\s+/g, " ").trim().slice(0, 160) : "";
                return { ...n, preview, commentId, ...(targetKind ? { targetKind } : {}), muted: n.kind === "message" ? messageState.muted("direct", n.actor, me.id) : n.kind === "group_message" ? messageState.muted("group", n.ref, me.id) : false, actor: publicUser(user(n.actor), me.id) };
              }),
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
                ) ||
                get(
                  "SELECT c.user_id FROM post_comments c JOIN posts p ON p.id=c.post_id WHERE c.id=? AND p.hidden=0",
                  b.targetId,
                ) ||
                (get("SELECT 1 FROM sqlite_master WHERE type='table' AND name='comments'")
                  ? get("SELECT id, user_id FROM comments WHERE id=?", b.targetId)
                  : null);
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
    run("UPDATE users SET password=?,salt=?,password_set=1 WHERE id=?", hash, salt, u.id);
    run("DELETE FROM sessions WHERE user_id=?", u.id);
    remembered.revoke(u.id);
    invalidateAuth(u.id);
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
    db,wallet,economy,packageStore,
    gift,
    notice,
    recordCallEvent,
    resetPassword,
    invalidateAuth,
    api,
    authenticate,
    user,
    blocked,
    publicUser,
    hasPrivacyConsent:id=>!!get('SELECT 1 FROM privacy_consents WHERE user_id=? AND version=?',id,PRIVACY_VERSION),
    ai,
    mediaCompressor,
    twoFactor,
    securityMonitor,
    close: () => {maintenanceClosed=true;clearInterval(maintenanceTimer);mediaCompressor.close();ai.close();securityMonitor.close();db.close();},
  };
}
