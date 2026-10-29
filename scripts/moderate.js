import { resolve, dirname } from "node:path";
import { mkdirSync } from "node:fs";
import { applyModeration } from "../lib/moderation.js";
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
    if (!action || !target)
      throw Error(
        "Usage: npm run moderate -- reports | hide-post ID | show-post ID | hide-short ID | show-short ID | suspend-user ID | restore-user ID | close-report ID",
      );
    applyModeration(social.db, action, target);
    console.log("Applied:", action, target);
  }
} catch (e) {
  console.error(e.message);
  process.exitCode = 1;
} finally {
  social.close();
}
