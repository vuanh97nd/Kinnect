import { resolve, dirname } from "node:path";
import { existsSync, mkdirSync } from "node:fs";
import { randomUUID, randomBytes, scrypt as scryptCallback } from "node:crypto";
import { promisify } from "node:util";
import { openSocial } from "../lib/social.js";
const [action, username] = process.argv.slice(2);
if (
  !["promote", "demote", "create", "reset-password"].includes(action) ||
  !/^[a-z0-9_]{3,30}$/.test(username || "")
) {
  console.error(
    "Usage: npm run admin -- promote USERNAME | demote USERNAME | reset-password USERNAME\n" +
      "       npm run admin -- create USERNAME  (mật khẩu đọc từ biến môi trường KINNECT_PASSWORD)",
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
  if (action === "create") {
    // Tạo tài khoản quản trị mới. Mật khẩu lấy từ biến môi trường để không lưu vào lịch sử lệnh.
    const password = process.env.KINNECT_PASSWORD || "";
    if (password.length < 6 || password.length > 128)
      throw Error("Đặt KINNECT_PASSWORD (6–128 ký tự) trước khi chạy lệnh create.");
    if (store.db.prepare("SELECT 1 FROM users WHERE username=?").get(username))
      throw Error("Tên đăng nhập đã tồn tại. Dùng promote để cấp quyền quản trị.");
    const salt = randomBytes(16).toString("hex");
    const hash = (await promisify(scryptCallback)(password, salt, 64)).toString("hex");
    const id = randomUUID();
    store.db
      .prepare(
        "INSERT INTO users(id,username,password,salt,name,birth_date,created,role,discoverable) VALUES(?,?,?,?,?,?,?,'admin',0)",
      )
      .run(id, username, hash, salt, "Quản trị Kinnect", "", Date.now());
    store.db
      .prepare("INSERT INTO moderation VALUES(?,?,?,?)")
      .run(randomUUID(), "create-admin:local-owner", id, Date.now());
    console.log("Đã tạo tài khoản quản trị @" + username + " (ẩn khỏi Khám phá).");
    process.exit(0);
  }
  if (action === "reset-password") {
    const u = store.db.prepare("SELECT id FROM users WHERE username=?").get(username);
    if (!u) throw Error("Không có tài khoản @" + username + ".");
    const temp = await store.resetPassword(u.id);
    store.db
      .prepare("INSERT INTO moderation VALUES(?,?,?,?)")
      .run(randomUUID(), "reset-password:local-owner", u.id, Date.now());
    console.log("Mật khẩu tạm của @" + username + ": " + temp);
    console.log("Mọi phiên đăng nhập cũ đã bị đăng xuất. Gửi mật khẩu này cho đúng chủ tài khoản và nhắc họ đổi sau khi đăng nhập.");
    process.exit(0);
  }
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
