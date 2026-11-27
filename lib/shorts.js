import { randomUUID } from "node:crypto";
import { sendCachedMedia } from "./post-media.js";
export function mp4Duration(bytes) {
  if (bytes.length < 24 || bytes.toString("ascii", 4, 8) !== "ftyp")
    throw Error("Chọn video MP4 hợp lệ.");
  function scan(start, end, depth) {
    if (depth > 3) return null;
    for (let at = start; at + 8 <= end; ) {
      let size = bytes.readUInt32BE(at),
        header = 8;
      if (size === 1) {
        if (at + 16 > end) throw Error();
        const extended = bytes.readBigUInt64BE(at + 8);
        if (extended > BigInt(Number.MAX_SAFE_INTEGER)) throw Error();
        size = Number(extended);
        header = 16;
      }
      if (size === 0) size = end - at;
      if (size < header || at + size > end) throw Error();
      const type = bytes.toString("ascii", at + 4, at + 8),
        data = at + header;
      if (type === "mvhd") {
        const v = bytes[data];
        if (v === 0 && data + 20 <= at + size) {
          const scale = bytes.readUInt32BE(data + 12);
          return scale ? bytes.readUInt32BE(data + 16) / scale : null;
        }
        if (v === 1 && data + 32 <= at + size) {
          const scale = bytes.readUInt32BE(data + 20);
          return scale
            ? Number(bytes.readBigUInt64BE(data + 24)) / scale
            : null;
        }
      }
      if (type === "moov") {
        const value = scan(data, at + size, depth + 1);
        if (value !== null) return value;
      }
      at += size;
    }
    return null;
  }
  const duration = scan(0, bytes.length, 0);
  if (!Number.isFinite(duration) || duration <= 0)
    throw Error(
      "Video MP4 phải có thời lượng hợp lệ và metadata thời lượng.",
    );
  return duration;
}
export function createShorts({
  onContent,
  threads,
  mediaCompressor,
  notice,
  db,
  get,
  all,
  run,
  body,
  fail,
  blocked,
  user,
  publicUser,
}) {
  let uploads = 0;
  const activeUserUploads = new Set();
  async function readBodyWithTimeout(req, maxBytes, timeoutMs = 45000) {
    let timer;
    const p = body(req, maxBytes);
    p.catch(() => {});
    try {
      return await Promise.race([
        p,
        new Promise((_, reject) => {
          timer = setTimeout(() => {
            const err = new Error("Quá thời gian tải video lên.");
            err.status = 408;
            req.destroy?.(err);
            reject(err);
          }, timeoutMs);
          timer.unref?.();
        }),
      ]);
    } finally {
      clearTimeout(timer);
    }
  }
  const visible = (id, me) => {
    const s = get(
      "SELECT id,user_id,caption,created,hidden,duration FROM shorts WHERE id=? AND hidden=0",
      id,
    );
    if (
      !s ||
      user(s.user_id)?.suspended !== 0 ||
      (me?.id && blocked(me.id, s.user_id))
    )
      fail(404, "Không tìm thấy video.");
    return s;
  };
  return async function (req, res, path, me, json) {
    if (path === "/api/shorts") {
      const params = new URL(req.url, "http://localhost").searchParams;
      const feed=params.get("feed"), requested=params.get("video") || "", profileUser=params.get("user");
      if (req.method === "GET") {
        const rawBefore = Number(params.get("before"));
        const before = Number.isSafeInteger(rawBefore) && rawBefore > 0 ? rawBefore : null;
        const rawLimit = Number.parseInt(params.get("limit") || "", 10);
        const limit = Number.isFinite(rawLimit) && rawLimit >= 1 ? Math.min(50, rawLimit) : 50;
        const rawOffset = Number.parseInt(params.get("offset") || "", 10);
        const offset = Number.isFinite(rawOffset) && rawOffset >= 0 ? Math.min(5000, rawOffset) : 0;
        let sql = feed === "following"
          ? "SELECT id,user_id,caption,created,duration FROM shorts WHERE hidden=0 AND user_id IN (SELECT id FROM users WHERE suspended=0) AND NOT EXISTS (SELECT 1 FROM blocks WHERE (actor=? AND target=shorts.user_id) OR (target=? AND actor=shorts.user_id)) AND user_id IN (SELECT target FROM follows WHERE actor=?) ORDER BY created DESC LIMIT ?"
          : "SELECT id,user_id,caption,created,duration FROM shorts WHERE hidden=0 AND user_id IN (SELECT id FROM users WHERE suspended=0) AND NOT EXISTS (SELECT 1 FROM blocks WHERE (actor=? AND target=shorts.user_id) OR (target=? AND actor=shorts.user_id)) ORDER BY CASE WHEN id=? THEN 1 ELSE 0 END DESC, (SELECT count(*) FROM short_likes WHERE short_id=shorts.id)*3 + (SELECT count(*) FROM short_comments WHERE short_id=shorts.id)*2 + created/86400000.0 DESC LIMIT ? OFFSET ?";
        if (profileUser) sql = sql.replace(" ORDER BY", " AND user_id=? ORDER BY");
        if (before) sql = sql.replace(" ORDER BY", " AND created<? ORDER BY");
        const queryArgs = [
          me.id,
          me.id,
          ...(feed === "following" ? [me.id] : []),
          ...(profileUser ? [profileUser] : []),
          ...(before ? [before] : []),
          ...(feed === "following" ? [limit + 1] : [requested, limit + 1, offset]),
        ];
        const rows = all(sql, ...queryArgs);
        const hasMore = rows.length > limit;
        const page = rows.slice(0, limit);
        const nextCursor = feed === "following" && hasMore && page.length ? page[page.length - 1].created : null;
        return json(200, {
          shorts: page.map((s) => ({
            ...s,
            author: {...publicUser(user(s.user_id), me.id),followerCount:get('SELECT count(*) AS n FROM follows WHERE target=?',s.user_id).n},
            video: "/api/shorts/" + s.id + "/video",
            thumbnail: get("SELECT 1 FROM media_thumbnails WHERE kind='short' AND target_id=?", s.id)
              ? "/api/shorts/" + s.id + "/thumbnail"
              : null,
            likes: get(
              "SELECT count(*) AS n FROM short_likes WHERE short_id=?",
              s.id,
            ).n,
            comments: get("SELECT count(*) AS n FROM short_comments WHERE short_id=?", s.id).n,
            liked: !!get(
              "SELECT 1 FROM short_likes WHERE short_id=? AND user_id=?",
              s.id,
              me.id,
            ),
          })),
          hasMore,
          nextCursor,
          ...(feed === "following" ? {} : { nextOffset: hasMore ? offset + page.length : null }),
        });
      }
      if (req.method === "POST") {
        if (activeUserUploads.has(me.id))
          fail(429, "Bạn đang có video khác đang tải lên. Vui lòng chờ hoàn tất.");
        if (uploads >= 4)
          fail(429, "Máy chủ đang xử lý video khác. Hãy thử lại.");
        if (
          get(
            "SELECT count(*) AS n FROM shorts WHERE user_id=? AND created>?",
            me.id,
            Date.now() - 86400000,
          ).n >= 10
        )
          fail(429, "Giới hạn 10 video mỗi ngày.");
        activeUserUploads.add(me.id);
        uploads++;
        try {
          const b = await readBodyWithTimeout(req, 60 * 1024 * 1024, 45000);
          if (
            typeof b.data !== "string" ||
            !/^data:video\/mp4;base64,[A-Za-z0-9+/=]+$/.test(b.data)
          )
            fail(400, "Chọn video MP4.");
          const bytes = Buffer.from(b.data.split(",")[1], "base64");
          if (
            get(
              "SELECT count(*) AS n FROM shorts WHERE user_id=? AND created>?",
              me.id,
              Date.now() - 86400000,
            ).n >= 10
          )
            fail(429, "Giới hạn 10 video mỗi ngày.");
          let duration;
          try {
            duration = mp4Duration(bytes);
          } catch (e) {
            fail(400, e.message || "Không đọc được thời lượng MP4.");
          }
          if (duration > 180) {
            fail(400, "Thời lượng video tối đa là 3 phút (180 giây).");
          }
          const id = randomUUID();
          run(
            "INSERT INTO shorts VALUES(?,?,?,?,?,0,?)",
            id,
            me.id,
            typeof b.caption === "string" ? b.caption.trim().slice(0, 500) : "",
            bytes,
            duration,
            Date.now(),
          );
          mediaCompressor?.enqueueVideo({ table: "shorts", id, bytes, type: "video/mp4", profile: "short" });
          onContent?.(id,me.id,typeof b.caption==='string'?b.caption:'');
          return json(201, { id });
        } finally {
          activeUserUploads.delete(me.id);
          uploads--;
        }
      }
    }
    const editComment=path.match(/^\/api\/shorts\/([a-zA-Z0-9-]+)\/comments\/([a-zA-Z0-9-]+)$/);
    if(editComment){const [,id,cid]=editComment;visible(id,me);const c=get('SELECT * FROM short_comments WHERE id=? AND short_id=? AND user_id=?',cid,id,me.id);if(!c)fail(404,'Không tìm thấy bình luận của bạn.');
      if(req.method==='PATCH'){const b=await body(req),content=typeof b.body==='string'?b.body.trim().slice(0,500):'';if(!content)fail(400,'Nhập bình luận.');run('UPDATE short_comments SET body=? WHERE id=?',content,cid);return json(200,{ok:true});}
      if(req.method==='DELETE'){db.exec('BEGIN');try{const parent=get("SELECT parent_id FROM comment_threads WHERE kind='short' AND comment_id=?",cid)?.parent_id;if(parent)run("UPDATE comment_threads SET parent_id=? WHERE kind='short' AND parent_id=?",parent,cid);else run("DELETE FROM comment_threads WHERE kind='short' AND parent_id=?",cid);run("DELETE FROM comment_reactions WHERE kind='short' AND comment_id=?",cid);run("DELETE FROM comment_threads WHERE kind='short' AND comment_id=?",cid);run('DELETE FROM notification_targets WHERE comment_id=?',cid);run('DELETE FROM short_comments WHERE id=?',cid);db.exec('COMMIT');}catch(err){db.exec('ROLLBACK');throw err;}return json(200,{ok:true,comments:get('SELECT count(*) AS n FROM short_comments WHERE short_id=?',id).n});}
      fail(405,'Phương thức không hợp lệ.');
    }
    const route = path.match(
      /^\/api\/shorts\/([a-zA-Z0-9-]+)(?:\/(video|thumbnail|like|comments))?(?:\/([a-zA-Z0-9-]+)\/reaction)?$/,
    );
    if (!route) fail(404, "Không tìm thấy API video.");
    const [, id, action, commentId] = route,
      s = visible(id, me);
    if(commentId){if(action!=='comments'||req.method!=='POST')fail(405,'Phương thức không hợp lệ.');const b=await body(req);return json(200,{comment:threads.react('short',id,commentId,me,b.reaction)});}
    if (!action && req.method === "DELETE") {
      if (s.user_id !== me.id) fail(403, "Chỉ xóa video của mình.");
      db.exec("BEGIN IMMEDIATE");
      try {
        run("DELETE FROM comment_reactions WHERE kind='short' AND comment_id IN (SELECT id FROM short_comments WHERE short_id=?)", id);
        run("DELETE FROM comment_threads WHERE kind='short' AND (comment_id IN (SELECT id FROM short_comments WHERE short_id=?) OR parent_id IN (SELECT id FROM short_comments WHERE short_id=?))", id, id);
        run("DELETE FROM notification_targets WHERE comment_id IN (SELECT id FROM short_comments WHERE short_id=?)", id);
        run("DELETE FROM media_thumbnails WHERE kind='short' AND target_id=?", id);
        run("DELETE FROM shorts WHERE id=?", id);
        db.exec("COMMIT");
      } catch (err) {
        db.exec("ROLLBACK");
        throw err;
      }
      return json(200, { ok: true });
    }
    if (action === "thumbnail" && ["GET", "HEAD"].includes(req.method)) {
      const thumb = get("SELECT type,data FROM media_thumbnails WHERE kind='short' AND target_id=?", id);
      if (!thumb) fail(404, "Chưa có ảnh xem trước.");
      sendCachedMedia(req, res, { bytes: thumb.data, type: thumb.type, maxAge: 600, allowRange: false });
      return;
    }
    if (action === "video" && ["GET", "HEAD"].includes(req.method)) {
      const row = get("SELECT data FROM shorts WHERE id=?", id);
      if (!row) fail(404, "Không tìm thấy video.");
      sendCachedMedia(req, res, { bytes: row.data, type: "video/mp4", maxAge: 600, allowRange: true });
      return;
    }
    if (action === "like") {
      if (req.method === "POST") {
        const r = run("INSERT OR IGNORE INTO short_likes VALUES(?,?)", id, me.id);
        if (r.changes) notice?.(s.user_id, me.id, "short_like", id);
      } else if (req.method === "DELETE")
        run(
          "DELETE FROM short_likes WHERE short_id=? AND user_id=?",
          id,
          me.id,
        );
      else fail(405, "Phương thức không hợp lệ.");
      return json(200, { ok: true });
    }
    if (action === "comments") {
      if (req.method === "GET") {
        const visibleComments = all(
          "SELECT * FROM short_comments WHERE short_id=? ORDER BY created DESC LIMIT 100",
          id,
        ).filter(
          (c) => !blocked(me.id, c.user_id) && user(c.user_id)?.suspended === 0,
        );
        const visibleIds = new Set(visibleComments.map((c) => c.id));
        return json(200, {
          comments: visibleComments.map((c) => ({
            ...threads.decorate("short", c, me, visibleIds),
            author: publicUser(user(c.user_id), me.id),
          })),
        });
      }
      if (req.method === "POST") {
        const b = await body(req),
          text = typeof b.body === "string" ? b.body.trim().slice(0, 500) : "";
        if (!text) fail(400, "Nhập bình luận.");
        const parentId=threads.parent("short",id,b.parentId,me);
        const cid = randomUUID();
        run(
          "INSERT INTO short_comments VALUES(?,?,?,?,?)",
          cid,
          id,
          me.id,
          text,
          Date.now(),
        );
        threads.link("short",cid,parentId);
        notice?.(s.user_id, me.id, "short_comment", id, cid);
        if (parentId) {
          const parent = get("SELECT user_id FROM short_comments WHERE id=?", parentId);
          if (parent && parent.user_id !== s.user_id) {
            notice?.(parent.user_id, me.id, "comment_reply", id, cid);
          }
        }
        return json(201, { id: cid });
      }
    }
    fail(405, "Phương thức không hợp lệ.");
  };
}
