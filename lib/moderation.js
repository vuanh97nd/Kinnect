import { randomUUID } from "node:crypto";
export function applyModeration(db, action, target, actor = "local-owner") {
  const commands = {
    "hide-short": [
      "UPDATE shorts SET hidden=1 WHERE id=?",
      "SELECT id FROM shorts WHERE id=?",
    ],
    "show-short": [
      "UPDATE shorts SET hidden=0 WHERE id=?",
      "SELECT id FROM shorts WHERE id=?",
    ],
    "hide-post": [
      "UPDATE posts SET hidden=1 WHERE id=?",
      "SELECT id FROM posts WHERE id=?",
    ],
    "show-post": [
      "UPDATE posts SET hidden=0 WHERE id=?",
      "SELECT id FROM posts WHERE id=?",
    ],
    "suspend-user": [
      "UPDATE users SET suspended=1 WHERE id=?",
      "SELECT id FROM users WHERE id=? AND role!='admin'",
    ],
    "restore-user": [
      "UPDATE users SET suspended=0 WHERE id=?",
      "SELECT id FROM users WHERE id=?",
    ],
    "close-report": [
      "UPDATE reports SET status='closed' WHERE id=?",
      "SELECT id FROM reports WHERE id=?",
    ],
  };
  if (!Object.hasOwn(commands, action) || typeof target !== "string")
    throw new Error("Thao tác không hợp lệ.");
  const [sql, lookup] = commands[action];
  if (!db.prepare(lookup).get(target))
    throw new Error(
      "Không tìm thấy đối tượng hợp lệ; không thể đình chỉ quản trị viên qua API.",
    );
  db.exec("BEGIN IMMEDIATE");
  try {
    db.prepare(sql).run(target);
    if (action === "suspend-user")
      db.prepare("DELETE FROM sessions WHERE user_id=?").run(target);
    db.prepare("INSERT INTO moderation VALUES(?,?,?,?)").run(
      randomUUID(),
      action + ":" + actor,
      target,
      Date.now(),
    );
    db.exec("COMMIT");
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }
}
