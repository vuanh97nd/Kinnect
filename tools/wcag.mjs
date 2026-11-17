// wcag.mjs — tính tương phản theo WCAG 2.1 (dùng chung cho gen-tokens và check-contrast)

export function parseHex(hex) {
  const h = hex.replace('#', '').trim();
  const n = h.length === 3 ? h.split('').map((c) => c + c).join('') : h;
  return {
    r: parseInt(n.slice(0, 2), 16),
    g: parseInt(n.slice(2, 4), 16),
    b: parseInt(n.slice(4, 6), 16),
  };
}

function channel(v) {
  const s = v / 255;
  return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
}

export function luminance(hex) {
  const { r, g, b } = parseHex(hex);
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
}

export function contrast(fg, bg) {
  const a = luminance(fg);
  const b = luminance(bg);
  const hi = Math.max(a, b);
  const lo = Math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

export function ratio(fg, bg) {
  return Math.round(contrast(fg, bg) * 100) / 100;
}

// Cặp bắt buộc phải đạt. body/large dùng ngưỡng WCAG AA.
export const REQUIRED_PAIRS = [
  ['textPrimary', 'background', 4.5],
  ['textPrimary', 'surface', 4.5],
  ['textPrimary', 'surfaceElevated', 4.5],
  ['textSecondary', 'background', 4.5],
  ['textSecondary', 'surface', 4.5],
  ['textSecondary', 'surfaceElevated', 4.5],
  ['textTertiary', 'background', 4.5],
  ['textTertiary', 'surface', 4.5],
  ['onAccent', 'accent', 4.5],
  ['accent', 'surface', 3.0],
  ['danger', 'surface', 3.0],
  ['success', 'surface', 3.0],
];

export function auditScheme(semantic, scheme) {
  const s = semantic[scheme];
  return REQUIRED_PAIRS.map(([fg, bg, min]) => {
    const fgHex = s[fg];
    const bgHex = s[bg];
    if (!fgHex || !bgHex) return { fg, bg, min, value: null, pass: false, missing: true };
    const value = ratio(fgHex, bgHex);
    return { fg, bg, min, value, pass: value >= min, missing: false };
  });
}
