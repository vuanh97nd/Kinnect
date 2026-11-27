import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

describe('Android NativeApi Fixture Boundary Tests', () => {
  const nativeApiSource = readFileSync('android/app/src/main/java/app/kinnect/live/NativeApi.java', 'utf8');
  const mainActivitySource = readFileSync('android/app/src/main/java/app/kinnect/live/MainActivity.java', 'utf8');
  const nativeSocketSource = readFileSync('android/app/src/main/java/app/kinnect/live/NativeSocket.java', 'utf8');
  const studioActivitySource = readFileSync('android/app/src/main/java/app/kinnect/live/StudioActivity.java', 'utf8');
  const incomingCallActivitySource = readFileSync('android/app/src/main/java/app/kinnect/live/IncomingCallActivity.java', 'utf8');
  const storeActivitySource = readFileSync('android/app/src/main/java/app/kinnect/live/StoreActivity.java', 'utf8');

  function extractBraceBlock(source, openBraceIdx) {
    assert.ok(openBraceIdx >= 0 && source[openBraceIdx] === '{', 'Expected opening brace');
    let depth = 0;
    let i = openBraceIdx;
    while (i < source.length) {
      const ch = source[i];
      if (ch === '"' || ch === "'") {
        const quote = ch;
        i++;
        while (i < source.length) {
          if (source[i] === '\\') {
            i += 2;
          } else if (source[i] === quote) {
            i++;
            break;
          } else {
            i++;
          }
        }
        continue;
      }
      if (ch === '/' && source[i + 1] === '/') {
        const nl = source.indexOf('\n', i);
        i = nl === -1 ? source.length : nl + 1;
        continue;
      }
      if (ch === '/' && source[i + 1] === '*') {
        const end = source.indexOf('*/', i + 2);
        i = end === -1 ? source.length : end + 2;
        continue;
      }
      if (ch === '{') depth++;
      else if (ch === '}') {
        depth--;
        if (depth === 0) return source.slice(openBraceIdx, i + 1);
      }
      i++;
    }
    assert.fail('Unclosed brace block');
  }

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
    assert.match(nativeApiSource, /"GET"\.equals\(method\) && "\/api\/me\/account-deletion"\.equals\(cleanPath\)/);
    assert.match(nativeApiSource, /"DELETE"\.equals\(method\) && "\/api\/me\/account-deletion"\.equals\(cleanPath\)/);
    // Unmapped endpoint returns explicit 404 fixture error in JSON diagnostics, never technical "Fixture ..." in UI error string
    assert.match(nativeApiSource, /Fixture endpoint not mapped: /);
    assert.doesNotMatch(nativeApiSource, /new FixtureResult\([^;]*,\s*"Fixture\s+/);
  });

  it('proves background services, probes, and WebSockets are silenced during fixture', () => {
    assert.match(nativeApiSource, /private void maybeProbePrimary\(\)\s*\{\s*if\s*\(fixtureEnabled/);
    assert.match(nativeApiSource, /public void warmVideo\(String path\)\s*\{\s*if\s*\(fixtureEnabled/);
    assert.match(nativeSocketSource, /if\s*\(NativeApi\.isFixtureEnabled\(\)\)\s*\{\s*closed\s*=\s*true;\s*return;\s*\}/);
  });

  it('proves MainActivity enforces FLAG_DEBUGGABLE before activating fixture', () => {
    assert.match(mainActivitySource, /boolean isDebug = \(getApplicationInfo\(\)\.flags & android\.content\.pm\.ApplicationInfo\.FLAG_DEBUGGABLE\) != 0;/);
    assert.match(mainActivitySource, /if\(isDebug && intent\.getBooleanExtra\("ui_review_fixture",false\)\)/);
  });

  it('proves setFixtureEmptyLive is gated by FLAG_DEBUGGABLE and fixtureEnabled', () => {
    const emptyLiveMatch = nativeApiSource.match(/public static synchronized void setFixtureEmptyLive\([^)]+\)\s*\{([\s\S]+?)\n  \}/);
    assert.ok(emptyLiveMatch, 'setFixtureEmptyLive must exist in NativeApi.java');
    const body = emptyLiveMatch[1];
    assert.match(body, /FLAG_DEBUGGABLE/);
    assert.match(body, /fixtureEmptyLive = isDebug && fixtureEnabled;/);
  });

  it('proves MainActivity mock/QA commerce_destination branches are gated by isDebug && NativeApi.isFixtureEnabled()', () => {
    const handleExtrasSig = mainActivitySource.indexOf('private void handleExtras(Intent intent)');
    assert.ok(handleExtrasSig >= 0, 'handleExtras(Intent intent) must exist in MainActivity.java');
    const handleExtrasBrace = mainActivitySource.indexOf('{', handleExtrasSig);
    const handleExtrasBody = extractBraceBlock(mainActivitySource, handleExtrasBrace);

    const guardDecl = 'final boolean allowDebugRoutes = isDebug && NativeApi.isFixtureEnabled();';
    assert.ok(handleExtrasBody.includes(guardDecl), 'handleExtras must define allowDebugRoutes = isDebug && NativeApi.isFixtureEnabled()');

    const allowMarker = 'else if (allowDebugRoutes) {';
    const allowIdx = handleExtrasBody.indexOf(allowMarker);
    assert.ok(allowIdx >= 0, 'handleExtras must gate QA routes inside else if (allowDebugRoutes)');
    const allowOpenBrace = handleExtrasBody.indexOf('{', allowIdx);
    const allowBlock = extractBraceBlock(handleExtrasBody, allowOpenBrace);
    const ungatedHandleExtras = handleExtrasBody.slice(0, allowOpenBrace) + handleExtrasBody.slice(allowOpenBrace + allowBlock.length);

    const qaDestinations = [
      'message_menu', 'report_sheet', 'ugc_report', 'chat_direct', 'chat_group',
      'chat_menu', 'call_incoming', 'feed_story', 'feed_post_detail',
      'feed_comments', 'comments_narrow', 'feed_reactions', 'discover_results',
      'discover_empty', 'shorts_comments', 'live_empty', 'live_setup_sheet',
      'live_room', 'live_gifts_drawer', 'studio_camera', 'studio_photo',
      'studio_video', 'studio_edit', 'studio_effects', 'studio_music_picker'
    ];
    for (const dest of qaDestinations) {
      assert.ok(allowBlock.includes(`"${dest}"`), `QA destination "${dest}" must reside inside allowDebugRoutes`);
      assert.ok(!ungatedHandleExtras.includes(`"${dest}"`), `QA destination "${dest}" must not exist outside allowDebugRoutes`);
    }

    const forbiddenUngatedPayloads = [
      'Lê Hoàng Nam', 'Trần Thanh Trúc', 'Linh Nhi', 'Nhóm Thiết Kế Kinnect',
      'call_qa_01', 'report("user", "u2")', 'navigate(destination)'
    ];
    for (const payload of forbiddenUngatedPayloads) {
      assert.ok(!ungatedHandleExtras.includes(payload), `Mock payload or unsafe fallback "${payload}" must not exist outside allowDebugRoutes`);
    }
  });

  it('proves StudioActivity open_music and auxiliary fixture entry points enforce FLAG_DEBUGGABLE and NativeApi.isFixtureEnabled()', () => {
    const onCreateSig = studioActivitySource.indexOf('public void onCreate(Bundle state)');
    assert.ok(onCreateSig >= 0, 'StudioActivity.onCreate must exist');
    const onCreateBody = extractBraceBlock(studioActivitySource, studioActivitySource.indexOf('{', onCreateSig));
    assert.match(onCreateBody, /FLAG_DEBUGGABLE/);
    assert.match(onCreateBody, /if\s*\(\s*isDebug\s*&&\s*NativeApi\.isFixtureEnabled\(\)\s*&&\s*getIntent\(\)\s*!=\s*null[\s\S]*?getBooleanExtra\("open_music",\s*false\)/);

    const onResumeSig = studioActivitySource.indexOf('protected void onResume()');
    assert.ok(onResumeSig >= 0, 'StudioActivity.onResume must exist');
    const onResumeBody = extractBraceBlock(studioActivitySource, studioActivitySource.indexOf('{', onResumeSig));
    assert.match(onResumeBody, /final boolean isDebugResume\s*=\s*\(getApplicationInfo\(\)\.flags\s*&\s*android\.content\.pm\.ApplicationInfo\.FLAG_DEBUGGABLE\)\s*!=\s*0;/);
    assert.match(onResumeBody, /if\s*\(\s*isDebugResume\s*&&\s*NativeApi\.isFixtureEnabled\(\)\s*&&\s*getIntent\(\)\s*!=\s*null[\s\S]*?getBooleanExtra\("open_music",\s*false\)/);

    assert.match(incomingCallActivitySource, /FLAG_DEBUGGABLE/);
    assert.match(incomingCallActivitySource, /if\s*\(\s*isDebug\s*&&\s*getIntent\(\)\s*!=\s*null\s*&&\s*getIntent\(\)\.getBooleanExtra\("ui_review_fixture",\s*false\)\s*\)/);
    assert.match(incomingCallActivitySource, /if\s*\(\s*m\s*==\s*null\s*&&\s*isDebug\s*&&\s*NativeApi\.isFixtureEnabled\(\)\s*\)/);

    assert.match(storeActivitySource, /FLAG_DEBUGGABLE/);
    assert.match(storeActivitySource, /isDebug\s*&&\s*getIntent\(\)\s*!=\s*null\s*&&\s*getIntent\(\)\.getBooleanExtra\("ui_review_fixture",\s*false\)/);
  });

  it('proves NativeApi.fixtureUser fails closed (returns null) when !fixtureEnabled or !FLAG_DEBUGGABLE', () => {
    const fixtureUserSig = nativeApiSource.indexOf('public synchronized JSONObject fixtureUser(android.content.Context context)');
    assert.ok(fixtureUserSig >= 0, 'NativeApi.fixtureUser must exist');
    const fixtureUserBody = extractBraceBlock(nativeApiSource, nativeApiSource.indexOf('{', fixtureUserSig));

    const notEnabledIdx = fixtureUserBody.indexOf('if (!fixtureEnabled || ctx == null)');
    assert.ok(notEnabledIdx >= 0, 'fixtureUser must check if (!fixtureEnabled || ctx == null)');
    const notEnabledBlock = extractBraceBlock(fixtureUserBody, fixtureUserBody.indexOf('{', notEnabledIdx));
    assert.match(notEnabledBlock, /return\s+null\s*;/);
    assert.ok(!notEnabledBlock.includes('FIXTURE_USER_DEFAULT'), 'fixtureUser must not return FIXTURE_USER_DEFAULT when !fixtureEnabled');

    const notDebugIdx = fixtureUserBody.indexOf('if (!isDebug)');
    assert.ok(notDebugIdx >= 0, 'fixtureUser must check if (!isDebug)');
    const notDebugBlock = extractBraceBlock(fixtureUserBody, fixtureUserBody.indexOf('{', notDebugIdx));
    assert.match(notDebugBlock, /return\s+null\s*;/);
    assert.ok(!notDebugBlock.includes('FIXTURE_USER_DEFAULT'), 'fixtureUser must not return FIXTURE_USER_DEFAULT when !isDebug');
  });
});
