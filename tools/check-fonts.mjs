/**
 * Ratchet cho font literal chưa vào type scale.
 *
 * KINNECT-FONT-DEBT.md giải thích vì sao 136 chỗ `.font(.system(size:))` còn lại
 * không thể migrate máy móc: phần lớn là icon/mockup/kích cỡ nằm ngoài thang
 * thiết kế. Script này không ép đổi, chỉ đảm bảo số lượng KHÔNG TĂNG.
 *
 *   node tools/check-fonts.mjs            # kiểm tra
 *   node tools/check-fonts.mjs --update   # ghi baseline mới (chỉ sau khi giảm)
 */
import fs from "node:fs";
import path from "node:path";

const ROOT = "ios/Kinnect";
const BASELINE_FILE = "tools/font-baseline.json";
const NEEDLE = ".font(.system(size:";

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(p, out);
    else if (entry.name.endsWith(".swift")) out.push(p);
  }
  return out;
}

const perFile = {};
let current = 0;
for (const file of walk(ROOT)) {
  const lines = fs.readFileSync(file, "utf8").split("\n");
  let hits = 0;
  for (const line of lines) if (line.includes(NEEDLE)) hits++;
  if (!hits) continue;
  const key = file.replace(/\\/g, "/");
  perFile[key] = hits;
  current += hits;
}

if (process.argv.includes("--update")) {
  const sorted = Object.fromEntries(Object.entries(perFile).sort(([a], [b]) => a.localeCompare(b)));
  fs.writeFileSync(BASELINE_FILE, JSON.stringify({ total: current, perFile: sorted }, null, 2) + "\n");
  console.log(`Đã ghi baseline font: ${current}`);
  process.exit(0);
}

const baselineDoc = JSON.parse(fs.readFileSync(BASELINE_FILE, "utf8"));
console.log(`Font literal: ${current} (baseline ${baselineDoc.total})`);

const grown = Object.entries(perFile).filter(([f, n]) => n > (baselineDoc.perFile[f] || 0));
if (grown.length) {
  console.error("\nCác file tăng font literal — dùng KTType hoặc cập nhật KINNECT-FONT-DEBT.md:");
  for (const [f, n] of grown) console.error(`  ${f}: ${baselineDoc.perFile[f] || 0} -> ${n}`);
  process.exit(1);
}

if (current < baselineDoc.total) {
  console.log(`Đã giảm ${baselineDoc.total - current} — chạy lại với --update để hạ baseline.`);
}
