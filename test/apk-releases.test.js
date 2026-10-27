import { test } from 'node:test';
import assert from 'node:assert/strict';
import { publishedApk, selectPublishedApk } from '../lib/apk-releases.js';
import { createApp } from '../server.js';
const release = (tag, changes = {}) => ({tag_name:tag, draft:false, assets:[{name:`Kinnect-${tag.replace(/^v/,'')}-native.apk`,size:100,state:'uploaded',browser_download_url:`https://github.com/vuanh97nd/Kinnect/releases/download/${tag}/Kinnect-${tag.replace(/^v/,'')}-native.apk`}],...changes});

test('APK choice follows numeric versions rather than collection position or date', () => {
  assert.equal(selectPublishedApk([release('v0.7.1'),release('v0.8.4'),release('v0.8.3'),release('v0.10.0')]).version, 'v0.10.0');
  assert.equal(selectPublishedApk([release('v1.0.0',{draft:true}),release('v0.8.5',{prerelease:true}),release('v0.8.4')]).version, 'v0.8.5');
});

test('APK choice rejects stale filenames, links to another tag, incomplete uploads and foreign URLs', () => {
  const good=release('v0.8.4');
  const bads=[release('v0.9.0',{assets:release('v0.7.1').assets}),release('v0.9.1'),release('v0.9.2'),release('v0.9.3')];
  bads[1].assets[0].browser_download_url=release('v0.8.4').assets[0].browser_download_url;
  bads[2].assets[0].state='starter';
  bads[3].assets[0].browser_download_url='https://example.com/file.apk';
  assert.equal(selectPublishedApk([...bads,good]).version,'v0.8.4');
  assert.equal(selectPublishedApk([release('v0.8.4-beta'),release('v0.9.0',{assets:[]})]),null);
});

test('stable latest remains discoverable when missing from the release collection; an unavailable endpoint is tolerated', async () => {
  const stub=async url=>new Response(JSON.stringify(url.endsWith('/latest')?release('v0.8.4'):[release('v0.7.1')]),{status:200});
  assert.equal((await publishedApk(stub)).version,'v0.8.4');
  const partial=async url=>url.endsWith('/latest')?new Response('',{status:404}):new Response(JSON.stringify([release('v0.8.5',{prerelease:true})]),{status:200});
  assert.equal((await publishedApk(partial)).version,'v0.8.5');
  await assert.rejects(()=>publishedApk(async()=>{throw Error('offline')}));
});

test('download redirects to the selected APK without browser caching; outage opens the releases page', async () => {
  for (const offline of [false,true]) {
    const app=createApp({fetchImpl:async url=>{if(offline)throw Error('offline');return new Response(JSON.stringify(url.endsWith('/latest')?release('v0.8.4'):[release('v0.7.1')]),{status:200});}});
    await new Promise(resolve=>app.server.listen(0,'127.0.0.1',resolve));
    try {
      const response=await fetch('http://127.0.0.1:'+app.server.address().port+'/download/android',{redirect:'manual'});
      assert.equal(response.status,302);
      assert.equal(response.headers.get('cache-control'),'no-store');
      assert.equal(response.headers.get('location'),offline?'https://github.com/vuanh97nd/Kinnect/releases/latest':release('v0.8.4').assets[0].browser_download_url);
    } finally {
      app.wss.close();app.server.closeAllConnections();await new Promise(resolve=>app.server.close(resolve));app.social.close();
    }
  }
});
