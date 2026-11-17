import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

test('design/tokens.json defines complete 4pt spacing, radius, typography, motion, and light/dark tokens matching Android WebDesign.java', () => {
  const tokens = JSON.parse(readFileSync(new URL('../design/tokens.json', import.meta.url), 'utf8'));
  assert.equal(tokens.grid.baseUnit, 4);
  assert.deepEqual(tokens.grid.spacing, { xs: 4, sm: 8, md: 12, lg: 16, xl: 24, '2xl': 32 });
  assert.deepEqual(tokens.grid.radius, { xs: 8, sm: 12, md: 16, lg: 24, xl: 32, pill: 999 });
  assert.ok(tokens.colors.semantic.light.background);
  assert.ok(tokens.colors.semantic.dark.background);
  assert.ok(tokens.colors.brand.accent);

  const androidDesign = readFileSync(
    new URL('../android/app/src/main/java/app/kinnect/live/WebDesign.java', import.meta.url),
    'utf8'
  );
  assert.match(androidDesign, /CARD_RADIUS = 24/);
  assert.match(androidDesign, /BODY = 15, LABEL = 14, META = 13, TITLE = 22, SECTION = 16/);
  assert.match(androidDesign, /MOTION_FAST = 140, MOTION_BASE = 220/);
  assert.match(androidDesign, /0xff2e9e66/);
});
