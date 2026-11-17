import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

describe('Android NativeApi Fixture Boundary Tests', () => {
  const nativeApiSource = readFileSync('android/app/src/main/java/app/kinnect/live/NativeApi.java', 'utf8');
  const mainActivitySource = readFileSync('android/app/src/main/java/app/kinnect/live/MainActivity.java', 'utf8');
  const nativeSocketSource = readFileSync('android/app/src/main/java/app/kinnect/live/NativeSocket.java', 'utf8');

  it('proves enableFixture self-checks FLAG_DEBUGGABLE and fails-closed in release builds', () => {
    assert.match(nativeApiSource, /FLAG_DEBUGGABLE/);
    assert.match(nativeApiSource, /boolean isDebug = \(context\.getApplicationInfo\(\)\.flags & android\.content\.pm\.ApplicationInfo\.FLAG_DEBUGGABLE\) != 0;/);
    assert.match(nativeApiSource, /if \(!isDebug\) \{\s*fixtureEnabled = false;\s*return false;\s*\}/);
  });

  it('proves zero network fallthrough at transport boundary when fixtureEnabled', () => {
    // In call(), when fixtureEnabled is true, offlineFixture is called and it immediately returns without executing HttpURLConnection
    const callMethodMatch = nativeApiSource.match(/public void call\([^)]+\)\s*\{([\s\S]+?)final String primaryServer/);
    assert.ok(callMethodMatch, 'call() method must contain fixture guard before primaryServer setup');
    const guardBody = callMethodMatch[1];
    assert.match(guardBody, /if \(fixtureEnabled\) \{/);
    assert.match(guardBody, /FixtureResult fr = offlineFixture\(method, path, data\);/);
    assert.match(guardBody, /main\.post\(\(\) -> callback\.done\(fr\.data, fr\.error, fr\.status\)\);/);
    assert.match(guardBody, /return;/);
  });

  it('proves exact METHOD and route matching in offlineFixture (no startsWith false positives)', () => {
    assert.match(nativeApiSource, /"GET"\.equals\(method\) && "\/api\/me"\.equals\(cleanPath\)/);
    assert.match(nativeApiSource, /"POST"\.equals\(method\) && "\/api\/me\/password"\.equals\(cleanPath\)/);
    assert.match(nativeApiSource, /"GET"\.equals\(method\) && "\/api\/posts"\.equals\(cleanPath\)/);
    assert.match(nativeApiSource, /"POST"\.equals\(method\) && cleanPath\.matches\("\/api\/posts\/\[\^\/\]\+\/reaction"\)/);
    assert.match(nativeApiSource, /"POST"\.equals\(method\) && "\/api\/store\/packages\/buy"\.equals\(cleanPath\)/);
    // Unmapped endpoint returns explicit 404 fixture error
    assert.match(nativeApiSource, /Fixture endpoint not mapped: /);
  });

  it('proves background services, probes, and WebSockets are silenced during fixture', () => {
    assert.match(nativeApiSource, /private void maybeProbePrimary\(\)\{\s*if\(fixtureEnabled/);
    assert.match(nativeApiSource, /public void warmVideo\(String path\)\{\s*if\(fixtureEnabled/);
    assert.match(nativeSocketSource, /if\(NativeApi\.isFixtureEnabled\(\)\)\{closed=true;return;\}/);
  });

  it('proves MainActivity enforces FLAG_DEBUGGABLE before activating fixture', () => {
    assert.match(mainActivitySource, /boolean isDebug = \(getApplicationInfo\(\)\.flags & android\.content\.pm\.ApplicationInfo\.FLAG_DEBUGGABLE\) != 0;/);
    assert.match(mainActivitySource, /if\(isDebug && intent\.getBooleanExtra\("ui_review_fixture",false\)\)/);
  });
});
