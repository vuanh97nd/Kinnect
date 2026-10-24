import { resolve, dirname } from "node:path";
import { mkdirSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { openSocial } from "../lib/social.js";
const path = resolve(process.env.DATA_DIR || "data", "kinnect.sqlite");
mkdirSync(dirname(path), { recursive: true });
const social = openSocial(path);
const [action, target] = process.argv.slice(2);
try {
  if (action === "reports") {
    console.log(
      JSON.stringify(
        social.db
          .prepare(
            "SELECT id,target_type,target_id,reason,status,created FROM reports WHERE status='open' ORDER BY created",
          )
          .all(),
        null,
        2,
      ),
    );
  } else {
    const commands = {
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
        "SELECT id FROM users WHERE id=?",
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
    if (!commands[action] || !target) {
      console.error(
        "Usage: npm run moderate -- reports | hide-post ID | show-post ID | suspend-user ID | restore-user ID | close-report ID",
      );
      process.exitCode = 1;
    } else {
      const [sql, lookup] = commands[action];
      if (!social.db.prepare(lookup).get(target))
        throw Error("Target not found");
      social.db.exec("BEGIN IMMEDIATE");
      try {
        social.db.prepare(sql).run(target);
        if (action === "suspend-user")
          social.db.prepare("DELETE FROM sessions WHERE user_id=?").run(target);
        social.db
          .prepare("INSERT INTO moderation VALUES(?,?,?,?)")
          .run(randomUUID(), action, target, Date.now());
        social.db.exec("COMMIT");
      } catch (e) {
        social.db.exec("ROLLBACK");
        throw e;
      }
      console.log("Applied:", action, target);
    }
  }
} catch (e) {
  console.error(e.message);
  process.exitCode = 1;
} finally {
  social.close();
}
