// Gửi email thông báo qua SMTP (mặc định Gmail, cổng 465 TLS) mà không cần thư viện ngoài.
// Cấu hình bằng biến môi trường (hoặc file mail.env ở thư mục chạy):
//   SMTP_USER=dia_chi@gmail.com   SMTP_PASS=mat_khau_ung_dung_16_ky_tu
//   SMTP_HOST=smtp.gmail.com (tùy chọn)  SMTP_PORT=465 (tùy chọn)
//   RESET_NOTIFY_EMAIL=nguoi_nhan@gmail.com
// Chưa cấu hình thì chỉ ghi log; yêu cầu vẫn được lưu để quản trị viên xử lý trong app.
import tls from "node:tls";
import { readFileSync, existsSync } from "node:fs";

export function loadMailEnv(file = "mail.env") {
  if (!existsSync(file)) return;
  for (const line of readFileSync(file, "utf8").split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.*?)\s*$/);
    if (m && !line.trim().startsWith("#") && process.env[m[1]] === undefined)
      process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
}

export function mailConfigured() {
  return !!(process.env.SMTP_USER && process.env.SMTP_PASS && process.env.RESET_NOTIFY_EMAIL);
}

const b64 = (s) => Buffer.from(s, "utf8").toString("base64");
const header = (s) => "=?UTF-8?B?" + b64(s) + "?=";

export function sendMail({ subject, text }) {
  const user = process.env.SMTP_USER;
  const pass = process.env.SMTP_PASS;
  const to = process.env.RESET_NOTIFY_EMAIL;
  const host = process.env.SMTP_HOST || "smtp.gmail.com";
  const port = Number(process.env.SMTP_PORT || 465);
  if (!user || !pass || !to) return Promise.resolve(false);
  const message = [
    `From: ${header("Kinnect")} <${user}>`,
    `To: <${to}>`,
    `Subject: ${header(subject)}`,
    `Date: ${new Date().toUTCString()}`,
    "MIME-Version: 1.0",
    "Content-Type: text/plain; charset=UTF-8",
    "Content-Transfer-Encoding: base64",
    "",
    b64(text).replace(/.{1,76}/g, "$&\r\n"),
  ].join("\r\n");
  const steps = [
    ["", 220],
    ["EHLO kinnect.local", 250],
    ["AUTH LOGIN", 334],
    [b64(user), 334],
    [b64(pass), 235],
    [`MAIL FROM:<${user}>`, 250],
    [`RCPT TO:<${to}>`, 250],
    ["DATA", 354],
    [message + "\r\n.", 250],
    ["QUIT", 221],
  ];
  return new Promise((resolve, reject) => {
    const socket = tls.connect({ host, port, servername: host, timeout: 20000 });
    let buffer = "";
    let i = 0;
    const done = (err) => {
      socket.destroy();
      err ? reject(err) : resolve(true);
    };
    socket.on("timeout", () => done(Error("SMTP hết thời gian chờ")));
    socket.on("error", done);
    socket.on("data", (chunk) => {
      buffer += chunk.toString();
      // Chờ đủ một phản hồi (dòng cuối có dạng "250 ...", không phải "250-...").
      const lines = buffer.split("\r\n").filter(Boolean);
      const last = lines[lines.length - 1];
      if (!last || !/^\d{3} /.test(last) || !buffer.endsWith("\r\n")) return;
      buffer = "";
      const code = Number(last.slice(0, 3));
      if (code !== steps[i][1]) return done(Error("SMTP lỗi ở bước " + i + ": " + last.slice(0, 120)));
      i++;
      if (i >= steps.length) return done();
      socket.write(steps[i][0] + "\r\n");
    });
  });
}
