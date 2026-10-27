import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createApp} from '../server.js';

test('short feeds apply bilateral blocks and suspension before limiting candidates',async()=>{
 const app=createApp({authLimit:100});await new Promise(r=>app.server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+app.server.address().port;
 try{
  const members=[];for(const name of ['viewer','blocked','blocksviewer','suspended','eligible']){const r=await fetch(base+'/api/register',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({username:name,name,password:'abcdef',agree18:true})});assert.equal(r.status,200);members.push({...(await r.json()).user,cookie:r.headers.get('set-cookie').split(';')[0]});}
  const [viewer,blocked,blocksviewer,suspended,eligible]=members,db=app.social.db;
  db.prepare('INSERT INTO blocks VALUES(?,?)').run(viewer.id,blocked.id);db.prepare('INSERT INTO blocks VALUES(?,?)').run(blocksviewer.id,viewer.id);db.prepare('UPDATE users SET suspended=1 WHERE id=?').run(suspended.id);
  for(const creator of members.slice(1))db.prepare('INSERT INTO follows VALUES(?,?)').run(viewer.id,creator.id);
  const insert=db.prepare('INSERT INTO shorts VALUES(?,?,?,?,?,0,?)');for(const creator of [blocked,blocksviewer,suspended])for(let i=0;i<201;i++)insert.run(creator.id+'-'+i,creator.id,'Excluded',Buffer.from('unused'),1,Date.now()+i);insert.run('eligible-video',eligible.id,'Visible',Buffer.from('unused'),1,1);
  for(const feed of ['recommended','following']){const r=await fetch(base+'/api/shorts?feed='+feed,{headers:{cookie:viewer.cookie}});assert.equal(r.status,200);assert.deepEqual((await r.json()).shorts.map(s=>s.id),['eligible-video']);}
 }finally{for(const ws of app.wss.clients)ws.terminate();await new Promise(r=>app.wss.close(r));app.server.closeAllConnections();await new Promise(r=>app.server.close(r));app.social.close();}
});
