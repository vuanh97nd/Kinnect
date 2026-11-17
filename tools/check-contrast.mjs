// check-contrast.mjs — gate CI: mọi cặp màu/chữ trong design/tokens.json phải đạt WCAG AA.
// Chạy: node tools/check-contrast.mjs   (exit 1 nếu có cặp trượt)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { auditScheme } from './wcag.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const tokens = JSON.parse(fs.readFileSync(path.join(ROOT, 'design/tokens.json'), 'utf8'));
const semantic = tokens.colors.semantic;

let failed = 0;
for (const scheme of ['light', 'dark']) {
  const rows = auditScheme(semantic, scheme);
  const bad = rows.filter((r) => !r.pass);
  const ok = rows.length - bad.length;
  console.log(`${scheme.padEnd(5)} ${ok}/${rows.length} đạt`);
  for (const r of bad) {
    failed++;
    const value = r.missing ? 'thiếu token' : `${r.value.toFixed(2)} < ${r.min}`;
    console.log(`  FAIL ${r.fg} trên ${r.bg}: ${value}`);
  }
}

if (failed > 0) {
  console.error(`\n${failed} cặp màu không đạt WCAG AA. Sửa design/tokens.json.`);
  process.exit(1);
}
console.log('\nTất cả cặp màu đạt WCAG AA.');
