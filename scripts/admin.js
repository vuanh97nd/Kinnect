import { resolve, dirname } from "node:path";
import { existsSync, mkdirSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { openSocial } from "../lib/social.js";
const [action, username] = process.argv.slice(2);
if (
  !["promote", "demote"].includes(action) ||
  !/^[a-z0-9_]{3,30}$/.test(username || "")
) {
  console.error(
    "Usage: npm run admin -- promote USERNAME | demote USERNAME (tài khoản phải đăng ký trước)",
  );
  process.exit(1);
}
const path = resolve(process.env.DATA_DIR || "data", "kinnect.sqlite");
mkdirSync(dirname(path), { recursive: true });
if (!existsSync(path)) {
  console.error(
    "Không thấy database ở DATA_DIR đã chọn. Hãy chạy backend và đăng ký tài khoản trước.",
  );
  process.exit(1);
}
const store = openSocial(path);
try {
  const user = store.db
    .prepare("SELECT id,role FROM users WHERE username=?")
    .get(username);
  if (!user)
    throw Error(
      "Chưa có tài khoản này. Hãy đăng ký trong app trước; không có tài khoản/mật khẩu quản trị mặc định.",
    );
  store.db.exec("BEGIN IMMEDIATE");
  try {
    if (
      action === "demote" &&
      user.role === "admin" &&
      store.db
        .prepare("SELECT count(*) AS n FROM users WHERE role='admin'")
        .get().n <= 1
    )
      throw Error("Không thể hạ quyền quản trị viên cuối cùng.");
    const role = action === "promote" ? "admin" : "user";
    store.db
      .prepare("UPDATE users SET role=?,suspended=0 WHERE id=?")
      .run(role, user.id);
    store.db
      .prepare("INSERT INTO moderation VALUES(?,?,?,?)")
      .run(randomUUID(), "role-" + role + ":local-owner", user.id, Date.now());
    store.db.exec("COMMIT");
    console.log(
      "Đã cấp quyền " +
        role +
        " cho " +
        username +
        ". Đăng nhập lại hoặc tải lại hồ sơ để cập nhật giao diện.",
    );
  } catch (e) {
    store.db.exec("ROLLBACK");
    throw e;
  }
} catch (e) {
  console.error(e.message);
  process.exitCode = 1;
} finally {
  store.close();
}
