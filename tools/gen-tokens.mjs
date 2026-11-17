// gen-tokens.mjs — sinh Swift token + trang preview HTML từ design/tokens.json
// Chạy: node tools/gen-tokens.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ratio, auditScheme } from './wcag.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const tokens = JSON.parse(fs.readFileSync(path.join(ROOT, 'design/tokens.json'), 'utf8'));

const weightName = (w) =>
  ({ 400: 'regular', 500: 'medium', 600: 'semibold', 700: 'bold', 800: 'heavy' }[w] || 'regular');

// ---------- 1. Swift ----------
const c = tokens.colors.semantic;
const colorKeys = Object.keys(c.light);

const swiftColors = colorKeys
  .map((k) => `    static let ${k} = dyn(light: "${c.light[k]}", dark: "${c.dark[k]}")`)
  .join('\n');

const swiftType = Object.entries(tokens.typography.roles)
  .map(([name, v]) => `    static let ${name}: Font = scaled(${v.size}, .${weightName(v.weight)}, .${v.relativeTo})`)
  .join('\n');

const swift = `// GENERATED FILE — do not edit by hand.
// Source: design/tokens.json (v${tokens.version}) · regenerate with: node tools/gen-tokens.mjs
import SwiftUI
import UIKit

// MARK: - Color (light/dark tự động theo traitCollection)

enum KTColor {
${swiftColors}

    private static func dyn(light: String, dark: String) -> Color {
        Color(UIColor { trait in
            UIColor(ktHex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

// MARK: - Typography
// Giữ ĐÚNG size thiết kế ở cỡ chữ mặc định, vẫn scale theo Dynamic Type.
// (Trước đây scaled() bóp 16→17, 14→13 nên lệch thiết kế Android.)

enum KTType {
${swiftType}

    private static func scaled(_ size: CGFloat, _ weight: UIFont.Weight, _ style: UIFont.TextStyle) -> Font {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        return Font(UIFontMetrics(forTextStyle: style).scaledFont(for: base))
    }
}

// MARK: - Spacing / Radius

enum KTSpace {
${Object.entries(tokens.grid.spacing).map(([k, v]) => `    static let ${k}: CGFloat = ${v}`).join('\n')}
}

enum KTRadius {
${Object.entries(tokens.grid.radius).map(([k, v]) => `    static let ${k}: CGFloat = ${v}`).join('\n')}
}

// MARK: - Layout

enum KTLayout {
    static let contentMaxWidth: CGFloat = ${tokens.layout.contentMaxWidth}
    static let touchTargetMin: CGFloat = ${tokens.layout.touchTargetMin}
    static let bubbleMaxWidthRatio: CGFloat = ${tokens.layout.bubbleMaxWidthRatio}
}

// MARK: - Motion (tôn trọng Reduce Motion)

enum KTMotion {
    static let fast: Double = ${tokens.motion.fastMs / 1000}
    static let base: Double = ${tokens.motion.baseMs / 1000}
    static let slow: Double = ${tokens.motion.slowMs / 1000}

    static func animation(_ duration: Double, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .timingCurve(${tokens.motion.easing.join(', ')}, duration: duration)
    }
}

// MARK: - Elevation

enum KTElevation {
    struct Spec { let y: CGFloat; let blur: CGFloat; let opacity: Double }
    static let e0 = Spec(y: 0, blur: 0, opacity: 0)
    static let e1 = Spec(y: ${tokens.elevation.e1.y}, blur: ${tokens.elevation.e1.blur}, opacity: ${tokens.elevation.e1.opacity})
    static let e2 = Spec(y: ${tokens.elevation.e2.y}, blur: ${tokens.elevation.e2.blur}, opacity: ${tokens.elevation.e2.opacity})
}

extension View {
    func ktElevation(_ spec: KTElevation.Spec) -> some View {
        shadow(color: .black.opacity(spec.opacity), radius: spec.blur / 2, x: 0, y: spec.y)
    }
}

// MARK: - Hex helper

extension UIColor {
    convenience init(ktHex hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let n = h.count == 3 ? h.map { "\\($0)\\($0)" }.joined() : h
        let v = UInt64(n, radix: 16) ?? 0
        self.init(
            red: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }
}
`;

const swiftDir = path.join(ROOT, 'ios/Kinnect/DesignSystem');
fs.mkdirSync(swiftDir, { recursive: true });
fs.writeFileSync(path.join(swiftDir, 'KinnectTokens.swift'), swift, 'utf8');

// ---------- 2. Preview HTML ----------
const audits = { light: auditScheme(c, 'light'), dark: auditScheme(c, 'dark') };

const swatchRows = colorKeys
  .map((k) => {
    const l = c.light[k];
    const d = c.dark[k];
    const cl = ratio(l, c.light.background);
    const cd = ratio(d, c.dark.background);
    return `<tr>
      <td class="mono">${k}</td>
      <td><span class="chip" style="background:${l}"></span><span class="mono">${l}</span></td>
      <td><span class="chip" style="background:${d}"></span><span class="mono">${d}</span></td>
      <td class="${cl >= 4.5 ? 'ok' : 'warn'}">${cl.toFixed(2)}</td>
      <td class="${cd >= 4.5 ? 'ok' : 'warn'}">${cd.toFixed(2)}</td>
    </tr>`;
  })
  .join('');

const typeRows = Object.entries(tokens.typography.roles)
  .map(
    ([name, v]) =>
      `<div class="typeRow"><span class="mono small">${name} · ${v.size}/${v.weight}</span><span style="font-size:${v.size}px;font-weight:${v.weight}">Kết nối đúng gu. Sống đúng mình.</span></div>`
  )
  .join('');

const spaceBars = Object.entries(tokens.grid.spacing)
  .map(([k, v]) => `<div class="spaceRow"><span class="mono small">${k} = ${v}</span><div style="width:${v * 3}px;height:12px;background:#8B5CF6;border-radius:2px"></div></div>`)
  .join('');

const radiusChips = Object.entries(tokens.grid.radius)
  .map(([k, v]) => `<div class="radiusChip" style="border-radius:${Math.min(v, 40)}px"><span class="mono small">${k}<br>${v}</span></div>`)
  .join('');

const contrastTables = ['light', 'dark']
  .map((scheme) => {
    const rows = audits[scheme]
      .map(
        (r) =>
          `<tr><td class="mono">${r.fg} / ${r.bg}</td><td class="${r.pass ? 'ok' : 'warn'}">${r.value === null ? 'missing' : r.value.toFixed(2)}</td><td class="mono small">≥ ${r.min}</td></tr>`
      )
      .join('');
    return `<div class="card"><h3>${scheme === 'light' ? 'Light' : 'Dark'}</h3><table><thead><tr><th>Cặp</th><th>Tỉ lệ</th><th>Ngưỡng</th></tr></thead><tbody>${rows}</tbody></table></div>`;
  })
  .join('');

const html = `<!doctype html>
<html lang="vi"><head><meta charset="utf-8">
<title>Kinnect Design System v${tokens.version}</title>
<style>
  :root {
    --bg:${c.dark.background}; --surface:${c.dark.surface}; --up:${c.dark.surfaceElevated};
    --ink:${c.dark.textPrimary}; --sec:${c.dark.textSecondary}; --ter:${c.dark.textTertiary};
    --accent:${c.dark.accent}; --soft:${c.dark.accentSoft}; --border:${c.dark.border};
  }
  * { box-sizing:border-box; }
  body { margin:0; background:var(--bg); color:var(--ink); font:15px/1.55 system-ui,-apple-system,"Segoe UI",sans-serif; }
  .wrap { max-width:1000px; margin:0 auto; padding:28px 24px 60px; }
  h1 { font-size:28px; font-weight:700; margin:0 0 4px; }
  h2 { font-size:20px; font-weight:600; margin:36px 0 12px; padding-bottom:8px; border-bottom:1px solid var(--border); }
  h3 { font-size:15px; font-weight:600; margin:0 0 10px; }
  .sub { color:var(--sec); font-size:13px; }
  .mono { font-family:ui-monospace,Consolas,monospace; font-size:12px; }
  .small { font-size:11px; color:var(--ter); }
  .chip { display:inline-block; width:14px; height:14px; border-radius:4px; margin-right:6px; vertical-align:-2px; border:1px solid var(--border); }
  table { width:100%; border-collapse:collapse; font-size:13px; }
  th { text-align:left; color:var(--ter); font-weight:500; font-size:11px; text-transform:uppercase; letter-spacing:.04em; padding:6px 8px; }
  td { padding:7px 8px; border-top:1px solid var(--border); }
  .ok { color:#34C77B; } .warn { color:#F05252; font-weight:500; }
  .card { background:var(--surface); border:1px solid var(--border); border-radius:16px; padding:16px 18px; margin-bottom:14px; }
  .grid2 { display:grid; grid-template-columns:1fr 1fr; gap:14px; }
  .typeRow { display:flex; align-items:baseline; gap:14px; padding:8px 0; border-bottom:1px solid var(--border); }
  .typeRow span.mono { flex:0 0 150px; }
  .spaceRow { display:flex; align-items:center; gap:12px; padding:5px 0; }
  .spaceRow span { flex:0 0 80px; }
  .radiusRow { display:flex; gap:12px; flex-wrap:wrap; }
  .radiusChip { width:86px; height:60px; background:var(--soft); border:1px solid var(--accent); display:flex; align-items:center; justify-content:center; text-align:center; }
  .btnRow { display:flex; gap:10px; flex-wrap:wrap; align-items:center; }
  .btn { border:0; border-radius:12px; padding:12px 18px; font-size:15px; font-weight:600; min-height:44px; cursor:default; }
  .btn.primary { background:var(--accent); color:#fff; }
  .btn.secondary { background:transparent; color:var(--ink); border:1px solid var(--border); }
  .btn.ghost { background:transparent; color:var(--accent); }
  .row { display:flex; align-items:center; gap:12px; padding:12px 0; border-bottom:1px solid var(--border); }
  .row:last-child { border-bottom:0; }
  .ico { width:36px; height:36px; border-radius:12px; background:var(--soft); display:flex; align-items:center; justify-content:center; color:var(--accent); font-size:15px; font-weight:600; }
  .row .t { font-size:15px; } .row .m { font-size:12px; color:var(--ter); }
  .input { width:100%; background:var(--up); border:1px solid var(--border); border-radius:12px; padding:13px 14px; color:var(--ink); font-size:15px; min-height:44px; }
  .empty { text-align:center; padding:36px 16px; }
  .empty .circle { width:56px; height:56px; border-radius:50%; background:var(--soft); margin:0 auto 12px; display:flex; align-items:center; justify-content:center; color:var(--accent); font-size:22px; }
  .skel { height:14px; border-radius:7px; background:linear-gradient(90deg,var(--up),var(--surface),var(--up)); background-size:200% 100%; animation:sh 1.4s linear infinite; }
  @keyframes sh { 0%{background-position:200% 0} 100%{background-position:-200% 0} }
  .badge { font-size:11px; font-weight:600; padding:3px 8px; border-radius:999px; background:var(--soft); color:var(--accent); }
  .foot { margin-top:36px; color:var(--ter); font-size:12px; }
</style></head>
<body><div class="wrap">
  <h1>Kinnect Design System</h1>
  <div class="sub">v${tokens.version} · sinh tự động từ <span class="mono">design/tokens.json</span> · ${colorKeys.length} màu · ${Object.keys(tokens.typography.roles).length} bậc chữ · lưới ${tokens.grid.baseUnit}pt</div>

  <h2>1 · Màu &amp; tương phản</h2>
  <div class="card">
    <table><thead><tr><th>Token</th><th>Light</th><th>Dark</th><th>Light vs bg</th><th>Dark vs bg</th></tr></thead>
    <tbody>${swatchRows}</tbody></table>
  </div>
  <div class="grid2">${contrastTables}</div>

  <h2>2 · Typography — 9 bậc, giữ đúng size thiết kế</h2>
  <div class="card">${typeRows}</div>

  <h2>3 · Spacing (lưới ${tokens.grid.baseUnit}pt)</h2>
  <div class="card">${spaceBars}</div>

  <h2>4 · Radius</h2>
  <div class="card"><div class="radiusRow">${radiusChips}</div></div>

  <h2>5 · Component</h2>
  <div class="grid2">
    <div class="card">
      <h3>Button</h3>
      <div class="btnRow">
        <button class="btn primary">Mua ngay</button>
        <button class="btn secondary">Huỷ</button>
        <button class="btn ghost">Xem thêm</button>
      </div>
      <div class="small" style="margin-top:10px">Touch target tối thiểu ${tokens.layout.touchTargetMin}pt · radius ${tokens.grid.radius.sm}</div>
    </div>
    <div class="card">
      <h3>Input</h3>
      <input class="input" placeholder="Tên đăng nhập">
      <div class="small" style="margin-top:8px;color:#F05252">Tên đăng nhập hoặc mật khẩu không đúng.</div>
    </div>
    <div class="card">
      <h3>Setting row</h3>
      <div class="row"><div class="ico">V</div><div><div class="t">Ví Kinnect</div><div class="m">Số dư và lịch sử giao dịch</div></div></div>
      <div class="row"><div class="ico">B</div><div><div class="t">Bảo mật</div><div class="m">Mật khẩu, phiên đăng nhập</div></div></div>
    </div>
    <div class="card">
      <h3>Empty state</h3>
      <div class="empty">
        <div class="circle">✉</div>
        <div style="font-size:15px;font-weight:600">Chưa có tin nhắn</div>
        <div class="small" style="margin-top:4px">Kết nối với người bạn quan tâm để bắt đầu.</div>
        <button class="btn primary" style="margin-top:14px">Tìm bạn bè</button>
      </div>
    </div>
    <div class="card">
      <h3>Skeleton</h3>
      <div class="skel" style="width:60%;margin-bottom:8px"></div>
      <div class="skel" style="width:100%;margin-bottom:8px"></div>
      <div class="skel" style="width:85%"></div>
    </div>
    <div class="card">
      <h3>Badge / chip</h3>
      <span class="badge">Mới</span> <span class="badge">Live</span> <span class="badge">1.2.16</span>
      <div class="small" style="margin-top:10px">Elevation: e0 phẳng · e1 (0,1,3,.10) · e2 (0,8,24,.16)</div>
    </div>
  </div>

  <div class="foot">Sinh lúc ${new Date().toISOString().replace('T', ' ').slice(0, 19)} UTC · không sửa file này bằng tay, sửa tokens.json rồi chạy lại generator.</div>
</div></body></html>`;

fs.writeFileSync(path.join(ROOT, 'design/preview.html'), html, 'utf8');

// ---------- 3. Báo cáo ----------
const failLight = audits.light.filter((r) => !r.pass);
const failDark = audits.dark.filter((r) => !r.pass);
console.log(`tokens v${tokens.version}`);
console.log(`  swift : ios/Kinnect/DesignSystem/KinnectTokens.swift`);
console.log(`  html  : design/preview.html`);
console.log(`  contrast light: ${audits.light.length - failLight.length}/${audits.light.length} đạt`);
if (failLight.length) console.log('    trượt:', failLight.map((r) => `${r.fg}/${r.bg}=${r.value?.toFixed(2)}`).join(', '));
console.log(`  contrast dark : ${audits.dark.length - failDark.length}/${audits.dark.length} đạt`);
if (failDark.length) console.log('    trượt:', failDark.map((r) => `${r.fg}/${r.bg}=${r.value?.toFixed(2)}`).join(', '));
process.exit(failLight.length || failDark.length ? 1 : 0);
