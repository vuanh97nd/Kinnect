import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = resolve(import.meta.dirname, '..');

test('Phase 4 ADR records the read-only migration gate contract and scaling prerequisites', () => {
  const adrPath = resolve(ROOT, 'docs/PHASE4-ARCHITECTURE-DECISION.md');
  assert.ok(existsSync(adrPath), 'docs/PHASE4-ARCHITECTURE-DECISION.md must exist');
  const adr = readFileSync(adrPath, 'utf8');

  for (const section of [
    '## 1. Recommendation',
    '## 2. Evidence',
    '## 3. Assumptions and Blockers',
    '## 4. Checkpoint',
    '## 5. Baseline and ROI',
    '## 6. Next Decision',
  ]) {
    assert.ok(adr.includes(section), `ADR must include "${section}"`);
  }

  assert.match(adr, /Do not migrate/);
  for (const tag of ['[observed]', '[measured]', '[unknown]']) {
    assert.ok(adr.includes(tag), `ADR must preserve explicit claim tag ${tag}`);
  }

  const scalingArtifacts = [
    'MIGRATION.md',
    'SCREENS.tsv',
    'STATE_AND_STORAGE.tsv',
    'DEPENDENCIES.tsv',
    'EVENTS.tsv',
    'PARITY_CHECKS.md',
  ];
  for (const artifact of scalingArtifacts) {
    assert.ok(adr.includes(artifact), `ADR must identify required scaling artifact ${artifact}`);
    assert.equal(
      existsSync(resolve(ROOT, artifact)),
      false,
      `${artifact} must not be created while Path A (Do not migrate) is active`
    );
  }
});

test('Repository stays free of unapproved Expo / React Native dependencies while Path A is active', () => {
  const pkg = JSON.parse(readFileSync(resolve(ROOT, 'package.json'), 'utf8'));
  const allDeps = { ...(pkg.dependencies || {}), ...(pkg.devDependencies || {}) };
  for (const pkgName of ['react-native', 'expo', 'expo-brownfield', 'expo-router']) {
    assert.equal(allDeps[pkgName], undefined, `Unexpected migration runtime dependency: ${pkgName}`);
  }

  const manifest = readFileSync(resolve(ROOT, 'android/app/src/main/AndroidManifest.xml'), 'utf8');
  assert.doesNotMatch(manifest, /ReactActivity|DevSettingsActivity/);
});

test('Shared Design System, Web bundle split, and Android Phase 3 modules remain present', () => {
  const requiredPaths = [
    'design/tokens.json',
    'public/v2-auth-wall.js',
    'public/v2-commerce.js',
    'public/v2-admin.js',
    'android/app/src/main/java/app/kinnect/live/MediaImageLoader.java',
    'android/app/src/main/java/app/kinnect/live/WindowedListBinder.java',
  ];
  for (const relPath of requiredPaths) {
    assert.ok(existsSync(resolve(ROOT, relPath)), `Missing modular foundation file: ${relPath}`);
  }
});
