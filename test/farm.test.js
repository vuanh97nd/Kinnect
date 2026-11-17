import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createApp } from '../server.js';

// Farm was explicitly removed from the product by the owner on 2026-11-13.
// Keep legacy source/assets/data; active clients must not expose or mutate it.
test('retired Farm API remains unavailable and does not change wallet or retained data', async t => {
  const app = createApp({ dbPath: ':memory:', allowEmailDelivery: false });
  await new Promise(resolve => app.server.listen(0, '127.0.0.1', resolve));
  t.after(async () => {
    for (const ws of app.wss.clients) ws.terminate();
    await new Promise(resolve => app.wss.close(resolve));
    app.server.closeAllConnections();
    await new Promise(resolve => app.server.close(resolve));
    app.social.close();
  });
  const origin = `http://127.0.0.1:${app.server.address().port}`;
  const registered = await fetch(origin + '/api/register', { method: 'POST',
    headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({
      username: 'retired_farm', password: 'local-test-password', agree18: true, acceptPrivacyNotice: true,
    }) });
  assert.equal(registered.status, 200);
  const cookie = registered.headers.get('set-cookie').split(';')[0];
  const user = (await registered.json()).user;
  app.social.db.exec('CREATE TABLE farm_legacy_evidence(user_id TEXT, marker TEXT)');
  app.social.db.prepare('INSERT INTO farm_legacy_evidence VALUES(?,?)').run(user.id, 'preserved');
  const wallet = () => app.social.db.prepare('SELECT count(*) n, sum(coins) coins FROM wallet_entries WHERE user_id=?').get(user.id);
  const before = { ...wallet() };
  for (const [method, path] of [['GET', '/api/farm'], ['POST', '/api/farm/shop/buy'],
    ['POST', '/api/farm/plant'], ['POST', '/api/farm/harvest'], ['POST', '/api/farm/mission/claim']]) {
    const result = await fetch(origin + path, { method, headers: { Cookie: cookie, Origin: origin,
      'Content-Type': 'application/json' }, body: method === 'GET' ? undefined : '{}' });
    assert.equal(result.status, 404, `${method} ${path}`);
    await result.arrayBuffer();
  }
  assert.deepEqual({ ...wallet() }, before);
  assert.equal(app.social.db.prepare('SELECT marker FROM farm_legacy_evidence WHERE user_id=?').get(user.id).marker, 'preserved');
});

test('native apps expose no Farm entry or installer registration', () => {
  const source = readFileSync(new URL('../android/app/src/main/java/app/kinnect/live/MainActivity.java', import.meta.url), 'utf8');
  const manifest = readFileSync(new URL('../android/app/src/main/AndroidManifest.xml', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /FarmGameModule\.(?:open|installed)|Nông trại đã mở/);
  assert.doesNotMatch(manifest, /FarmGameDownloadActivity|FarmGameProvider/);
});
