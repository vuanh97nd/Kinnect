import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,readFileSync,statSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import http from 'node:http';
import {MediaStore} from '../services/windows-server/store.mjs';
import {pull,peerUrl} from '../services/windows-server/sync.mjs';
test('incremental transfer, resume, restart and deletion do not redownload or resurrect',async()=>{
 const root=mkdtempSync(join(tmpdir(),'kinnect-sync-')),a=new MediaStore(join(root,'a'));let b=new MediaStore(join(root,'b')),bytes=0,objectCalls=0;
 const video=Buffer.alloc(200000,43);a.put('video/1',video,'video/mp4');a.put('image/1',Buffer.from('first'),'image/jpeg');
 const server=http.createServer((req,res)=>{if(req.headers.authorization!=='Bearer test-key'){res.writeHead(401);return res.end();}const u=new URL(req.url,'http://local');if(u.pathname==='/sync/changes'){res.setHeader('Content-Type','application/json');return res.end(JSON.stringify({nodeId:a.nodeId,changes:a.changes(Number(u.searchParams.get('after')))}));}const digest=u.pathname.split('/').at(-1),data=readFileSync(a.objectPath(digest)),offset=Number(req.headers.range?.match(/bytes=(\d+)-/)?.[1]||0);objectCalls++;bytes+=data.length-offset;res.writeHead(offset?206:200,offset?{'Content-Range':`bytes ${offset}-${data.length-1}/${data.length}`}:{ });res.end(data.subarray(offset));});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const peer={id:a.nodeId,url:'http://127.0.0.1:'+server.address().port,key:'test-key'};
 try{
  const digest=a.current('video/1').hash;writeFileSync(join(b.root,'partial',digest+'.part'),video.subarray(0,70000));
  assert.equal((await pull(b,peer)).changed,2);assert.equal(bytes,130005);assert.deepEqual(readFileSync(b.objectPath(digest)),video);
  const calls=objectCalls;b.close();b=new MediaStore(join(root,'b'));assert.equal((await pull(b,peer)).changed,0);assert.equal(objectCalls,calls);
  a.put('image/2',Buffer.from('new'),'image/png');assert.equal((await pull(b,peer)).changed,1);assert.equal(objectCalls,calls+1);
  const stale=b.current('image/1');a.remove('image/1');await pull(b,peer);assert.equal(b.current('image/1').deleted,1);assert.equal(b.apply(stale),false);
  assert.equal((await pull(b,peer)).changed,0);assert.equal(b.status().files,2);
  await assert.rejects(pull(b,{...peer,key:'wrong'}),/Mã ghép/);
  assert.throws(()=>b.objectPath('../../secret'),/không hợp lệ/);
 }finally{a.close();b.close();await new Promise(r=>server.close(r));}
});
test('plain HTTP is limited to LAN and loopback, never misleading domain names',()=>{
 assert.equal(peerUrl('http://192.168.1.8:3129'),'http://192.168.1.8:3129');
 for(const url of ['http://localhost.evil.test','http://10.evil.test','http://8.8.8.8','https://user:secret@example.com','https://example.com/path'])assert.throws(()=>peerUrl(url));
});
