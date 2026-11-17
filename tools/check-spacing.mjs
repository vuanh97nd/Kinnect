/**
 * Ratchet cho lề ngang ngoài thang.
 *
 * Thanh tiêu đề dùng lề 16 (KTLayout.headerSidePadding). Các giá trị 10/14/18
 * là dấu vết của việc mỗi màn tự đặt lề riêng. Không thể sửa hết một lúc, nên
 * script này giữ một baseline: số lượng không được TĂNG. Sửa được bao nhiêu thì
 * hạ baseline xuống bấy nhiêu.
 *
 *   node tools/check-spacing.mjs            # kiểm tra
 *   node tools/check-spacing.mjs --update   # ghi baseline mới (chỉ sau khi đã giảm)
 */
import fs from "node:fs";
import path from "node:path";

const ROOT = "ios/Kinnect";
const BASELINE_FILE = "tools/spacing-baseline.json";
const SCALE = new Set([0, 2, 4, 8, 12, 16, 20, 24, 32, 40]);

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(p, out);
    else if (entry.name.endsWith(".swift")) out.push(p);
  }
  return out;
}

const offenders = [];
for (const file of walk(ROOT)) {
  const lines = fs.readFileSync(file, "utf8").split("\n");
  lines.forEach((line, i) => {
    const m = line.match(/\.padding\(\.horizontal,\s*(\d+)\)/);
    if (!m) return;
    const value = Number(m[1]);
    if (SCALE.has(value)) return;
    offenders.push({ file, line: i + 1, value });
  });
}

const current = offenders.length;
const update = process.argv.includes("--update");

if (update) {
  fs.writeFileSync(BASELINE_FILE, JSON.stringify({ iosOffScaleHorizontalPadding: current }, null, 2) + "\n");
  console.log(`Đã ghi baseline: ${current}`);
  process.exit(0);
}

const baseline = JSON.parse(fs.readFileSync(BASELINE_FILE, "utf8")).iosOffScaleHorizontalPadding;
console.log(`Lề ngang ngoài thang: ${current} (baseline ${baseline})`);

if (current > baseline) {
  const extra = offenders.slice(baseline);
  console.error(`\nTăng ${current - baseline} chỗ. Dùng bội số của thang 4 (4/8/12/16/24/32).`);
  for (const o of extra) console.error(`  ${o.file}:${o.line}  .padding(.horizontal, ${o.value})`);
  process.exit(1);
}

if (current < baseline) {
  console.log(`Đã giảm ${baseline - current} — chạy lại với --update để hạ baseline.`);
}
