import { randomUUID } from "node:crypto";

export function createGroupPolls({ db, body, fail, text, user, publicUser, blocked, notice }) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS group_polls(
      id TEXT PRIMARY KEY,
      group_id TEXT NOT NULL REFERENCES chat_groups(id) ON DELETE CASCADE,
      creator_id TEXT NOT NULL REFERENCES users(id),
      question TEXT NOT NULL,
      multiple INTEGER NOT NULL DEFAULT 0,
      closed INTEGER NOT NULL DEFAULT 0,
      created INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS group_polls_group_created ON group_polls(group_id, created DESC);
    CREATE TABLE IF NOT EXISTS group_poll_options(
      id TEXT PRIMARY KEY,
      poll_id TEXT NOT NULL REFERENCES group_polls(id) ON DELETE CASCADE,
      position INTEGER NOT NULL,
      label TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS group_poll_options_poll ON group_poll_options(poll_id, position);
    CREATE TABLE IF NOT EXISTS group_poll_votes(
      poll_id TEXT NOT NULL REFERENCES group_polls(id) ON DELETE CASCADE,
      option_id TEXT NOT NULL REFERENCES group_poll_options(id) ON DELETE CASCADE,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created INTEGER NOT NULL,
      PRIMARY KEY(poll_id, option_id, user_id)
    );
  `);

  const get = (s, ...p) => db.prepare(s).get(...p);
  const all = (s, ...p) => db.prepare(s).all(...p);
  const run = (s, ...p) => db.prepare(s).run(...p);

  function decorate(poll, meId) {
    const options = all("SELECT id,position,label FROM group_poll_options WHERE poll_id=? ORDER BY position ASC", poll.id);
    const votes = all("SELECT option_id,user_id FROM group_poll_votes WHERE poll_id=?", poll.id)
      .filter((v) => !user(v.user_id)?.suspended);
    const counts = new Map();
    const voters = new Set();
    const myOptionIds = [];
    for (const v of votes) {
      counts.set(v.option_id, (counts.get(v.option_id) || 0) + 1);
      voters.add(v.user_id);
      if (v.user_id === meId) myOptionIds.push(v.option_id);
    }
    const creatorRow = user(poll.creator_id);
    return {
      id: poll.id,
      groupId: poll.group_id,
      creatorId: poll.creator_id,
      creator: creatorRow ? publicUser(creatorRow, meId) : null,
      question: poll.question,
      multiple: !!poll.multiple,
      closed: !!poll.closed,
      created: poll.created,
      totalVotes: votes.length,
      totalVoters: voters.size,
      myOptionIds,
      options: options.map((o) => ({
        id: o.id,
        position: o.position,
        label: o.label,
        votes: counts.get(o.id) || 0,
        voted: myOptionIds.includes(o.id),
      })),
    };
  }

  async function handle({ req, group, pollId, subAction, me, manages, members, json }) {
    if (!pollId) {
      if (req.method === "GET") {
        const rows = all("SELECT * FROM group_polls WHERE group_id=? ORDER BY created DESC LIMIT 50", group.id)
          .filter((p) => {
            const c = user(p.creator_id);
            return c && !c.suspended && !blocked(me.id, p.creator_id);
          });
        json(200, { polls: rows.map((p) => decorate(p, me.id)) });
        return true;
      }
      if (req.method === "POST") {
        const b = await body(req, 32000);
        const question = text(b.question, 200);
        if (!question) fail(400, "Nhập câu hỏi bình chọn.");
        if (!Array.isArray(b.options)) fail(400, "Cần danh sách lựa chọn (2–10 mục).");
        const cleanOptions = b.options.map((o) => text(o, 120)).filter(Boolean);
        if (cleanOptions.length < 2 || cleanOptions.length > 10) {
          fail(400, "Bình chọn cần từ 2 đến 10 lựa chọn.");
        }
        const multiple = b.multiple === true ? 1 : 0;
        const id = randomUUID();
        const now = Date.now();
        db.exec("BEGIN IMMEDIATE");
        try {
          run(
            "INSERT INTO group_polls(id,group_id,creator_id,question,multiple,closed,created) VALUES(?,?,?,?,?,0,?)",
            id,
            group.id,
            me.id,
            question,
            multiple,
            now,
          );
          for (let i = 0; i < cleanOptions.length; i++) {
            run(
              "INSERT INTO group_poll_options(id,poll_id,position,label) VALUES(?,?,?,?)",
              randomUUID(),
              id,
              i,
              cleanOptions[i],
            );
          }
          db.exec("COMMIT");
        } catch (e) {
          db.exec("ROLLBACK");
          throw e;
        }
        for (const u of members(group.id)) {
          if (u.id !== me.id && !blocked(me.id, u.id) && !u.suspended) {
            notice(u.id, me.id, "group_message", group.id, id);
          }
        }
        const created = get("SELECT * FROM group_polls WHERE id=?", id);
        json(201, { poll: decorate(created, me.id) });
        return true;
      }
      fail(405, "Phương thức không hợp lệ.");
    }

    const poll = get("SELECT * FROM group_polls WHERE id=? AND group_id=?", pollId, group.id);
    if (!poll || blocked(me.id, poll.creator_id)) fail(404, "Không tìm thấy bình chọn.");

    if (subAction === "vote" && req.method === "POST") {
      if (poll.closed) fail(400, "Bình chọn đã kết thúc.");
      const b = await body(req);
      let chosen = [];
      if (Array.isArray(b.optionIds)) chosen = [...new Set(b.optionIds.filter((x) => typeof x === "string" && x))];
      else if (typeof b.optionId === "string" && b.optionId) chosen = [b.optionId];
      if (!poll.multiple && chosen.length > 1) {
        fail(400, "Bình chọn này chỉ cho phép chọn một phương án.");
      }
      const validIds = new Set(all("SELECT id FROM group_poll_options WHERE poll_id=?", poll.id).map((o) => o.id));
      for (const oid of chosen) {
        if (!validIds.has(oid)) fail(400, "Lựa chọn không hợp lệ.");
      }
      const now = Date.now();
      db.exec("BEGIN IMMEDIATE");
      try {
        run("DELETE FROM group_poll_votes WHERE poll_id=? AND user_id=?", poll.id, me.id);
        for (const oid of chosen) {
          run("INSERT INTO group_poll_votes(poll_id,option_id,user_id,created) VALUES(?,?,?,?)", poll.id, oid, me.id, now);
        }
        db.exec("COMMIT");
      } catch (e) {
        db.exec("ROLLBACK");
        throw e;
      }
      json(200, { poll: decorate(poll, me.id) });
      return true;
    }

    if (subAction === "close" && req.method === "POST") {
      if (poll.creator_id !== me.id && !manages(group, me.id)) {
        fail(403, "Chỉ người tạo hoặc quản trị nhóm được đóng bình chọn.");
      }
      run("UPDATE group_polls SET closed=1 WHERE id=?", poll.id);
      json(200, { poll: decorate(get("SELECT * FROM group_polls WHERE id=?", poll.id), me.id) });
      return true;
    }

    if (!subAction && req.method === "DELETE") {
      if (poll.creator_id !== me.id && !manages(group, me.id)) {
        fail(403, "Chỉ người tạo hoặc quản trị nhóm được xóa bình chọn.");
      }
      run("DELETE FROM group_polls WHERE id=?", poll.id);
      json(200, { ok: true });
      return true;
    }

    fail(405, "Phương thức không hợp lệ.");
  }

  return { handle };
}
