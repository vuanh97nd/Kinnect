import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../server.js';
import { mp4Duration } from '../lib/shorts.js';
// Synthetic container checks admission and storage; it is not a playback fixture.
function video(seconds) {
 const b=Buffer.alloc(13*1024*1024);
 b.writeUInt32BE(24,0);b.write('ftyp',4);b.write('isom',8);
 b.writeUInt32BE(36,24);b.write('moov',28);b.writeUInt32BE(28,32);b.write('mvhd',36);
 b.writeUInt32BE(1000,52);b.writeUInt32BE(seconds*1000,56);
 b.writeUInt32BE(b.length-60,60);b.write('free',64);return b;
}
test('uploads accept media beyond former size and 60-second limits',async t=>{
 const app=createApp();await new Promise(r=>app.server.listen(0,'127.0.0.1',r));
 t.after(async()=>{for(const ws of app.wss.clients)ws.terminate();await new Promise(r=>app.wss.close(r));app.server.closeAllConnections();await new Promise(r=>app.server.close(r));app.social.close();});
 const origin='http://127.0.0.1:'+app.server.address().port;
 const r=await fetch(origin+'/api/register',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:'media_regression',name:'Media',password:'test-password-strong',birthDate:'1994-05-10',agree18:true})});
 assert.equal(r.status,200);const cookie=r.headers.get('set-cookie').split(';')[0];
 const clip=video(125);assert.equal(mp4Duration(clip),125);assert.throws(()=>mp4Duration(Buffer.alloc(100)),/MP4/);
 const png=Buffer.alloc(13*1024*1024);Buffer.from('89504e470d0a1a0a','hex').copy(png);
 for(const [path,type,bytes,field,table] of [['/api/posts','image/png',png,'media','post_media'],['/api/posts','video/mp4',clip,'media','post_media'],['/api/stories','video/mp4',clip,'media','post_media'],['/api/shorts','video/mp4',clip,'data','shorts']]){
  const response=await fetch(origin+path,{method:'POST',headers:{Cookie:cookie,Origin:origin,'Content-Type':'application/json'},body:JSON.stringify({body:'Media regression',[field]:`data:${type};base64,${bytes.toString('base64')}`})});
  const result=await response.json();assert.equal(response.status,201,path+': '+JSON.stringify(result));
  const row=app.social.db.prepare(table==='shorts'?'SELECT data FROM shorts WHERE id=?':'SELECT data FROM post_media WHERE post_id=?').get(result.id);assert.deepEqual(Buffer.from(row.data),bytes);
 }
});
