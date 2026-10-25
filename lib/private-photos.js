import {randomUUID} from 'node:crypto';
// Ảnh riêng tư: chủ ảnh tải lên, người khác gửi yêu cầu xem, chủ ảnh duyệt / từ chối / thu hồi.
export function privatePhotos({db,fail,blocked,user,publicUser,notice,body}){
 db.exec(`CREATE TABLE IF NOT EXISTS private_photos(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),type TEXT NOT NULL,data BLOB NOT NULL,created INTEGER NOT NULL);
 CREATE INDEX IF NOT EXISTS private_photos_user ON private_photos(user_id,created);
 CREATE TABLE IF NOT EXISTS private_access(owner TEXT NOT NULL REFERENCES users(id),viewer TEXT NOT NULL REFERENCES users(id),status TEXT NOT NULL CHECK(status IN ('pending','granted','denied')),created INTEGER NOT NULL,PRIMARY KEY(owner,viewer));`);
 const get=(s,...p)=>db.prepare(s).get(...p),all=(s,...p)=>db.prepare(s).all(...p),run=(s,...p)=>db.prepare(s).run(...p);
 const MAX=24;
 const visibleUser=id=>{const u=user(id);return u&&!u.suspended?u:null;};
 const clearNotice=(owner,viewer)=>run("UPDATE notifications SET seen=1 WHERE user_id=? AND actor=? AND kind='private_request'",owner,viewer);
 const access=(owner,viewer)=>owner===viewer?'owner':get('SELECT status FROM private_access WHERE owner=? AND viewer=?',owner,viewer)?.status||'none';
 const list=(owner)=>all('SELECT id,created FROM private_photos WHERE user_id=? ORDER BY created DESC',owner).map(p=>({id:p.id,url:'/api/private-photos/'+p.id,created:p.created}));
 function decode(data){
  if(typeof data!=='string'||!/^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$/.test(data))fail(400,'Chọn ảnh PNG, JPEG hoặc WebP.');
  const [prefix,encoded]=data.split(','),bytes=Buffer.from(encoded,'base64'),type=prefix.slice(5,prefix.indexOf(';'));
  if(bytes.length<16||bytes.length>4*1024*1024)fail(400,'Ảnh phải nhỏ hơn 4 MB.');
  const ok=type==='image/png'?bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])):type==='image/jpeg'?bytes[0]===255&&bytes[1]===216&&bytes[2]===255:bytes.toString('ascii',0,4)==='RIFF'&&bytes.toString('ascii',8,12)==='WEBP';
  if(!ok)fail(400,'Định dạng ảnh không hợp lệ.');
  return {type,bytes};
 }
 async function route(req,res,path,me,json){
  let m;
  if(path==='/api/me/private-photos'&&req.method==='POST'){
   const b=await body(req,6*1024*1024);
   if(get('SELECT COUNT(*) n FROM private_photos WHERE user_id=?',me.id).n>=MAX)fail(400,'Tối đa '+MAX+' ảnh riêng tư.');
   const {type,bytes}=decode(b.data),id=randomUUID();
   run('INSERT INTO private_photos VALUES(?,?,?,?,?)',id,me.id,type,bytes,Date.now());
   return json(201,{photos:list(me.id)}),true;
  }
  if((m=path.match(/^\/api\/me\/private-photos\/([a-zA-Z0-9-]+)$/))&&req.method==='DELETE'){
   if(!run('DELETE FROM private_photos WHERE id=? AND user_id=?',m[1],me.id).changes)fail(404,'Không tìm thấy ảnh.');
   return json(200,{photos:list(me.id)}),true;
  }
  if((m=path.match(/^\/api\/private-photos\/([a-zA-Z0-9-]+)$/))&&['GET','HEAD'].includes(req.method)){
   const p=get('SELECT user_id,type,data FROM private_photos WHERE id=?',m[1]);
   const a=p&&access(p.user_id,me.id);
   if(!p||!visibleUser(p.user_id)||(a!=='owner'&&a!=='granted')||blocked(me.id,p.user_id))fail(404,'Không tìm thấy ảnh.');
   res.writeHead(200,{'Content-Type':p.type,'Content-Length':p.data.length,'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'});
   res.end(req.method==='HEAD'?undefined:Buffer.from(p.data));return true;
  }
  if((m=path.match(/^\/api\/users\/([a-zA-Z0-9-]+)\/private$/))&&req.method==='GET'){
   const owner=visibleUser(m[1]);if(!owner||blocked(me.id,owner.id))fail(404,'Không tìm thấy người dùng.');
   const status=access(owner.id,me.id),photos=list(owner.id);
   const out={status,count:photos.length,photos:status==='owner'||status==='granted'?photos:[]};
   if(status==='owner')out.pending=get("SELECT COUNT(*) n FROM private_access WHERE owner=? AND status='pending'",me.id).n;
   return json(200,out),true;
  }
  if((m=path.match(/^\/api\/users\/([a-zA-Z0-9-]+)\/private\/request$/))&&req.method==='POST'){
   const owner=visibleUser(m[1]);if(!owner||owner.id===me.id||blocked(me.id,owner.id))fail(404,'Không tìm thấy người dùng.');
   if(!get('SELECT 1 FROM private_photos WHERE user_id=?',owner.id))fail(400,'Album chưa có ảnh riêng tư.');
   const cur=access(owner.id,me.id);
   if(cur==='granted')return json(200,{status:cur}),true;
   if(cur==='pending')return json(200,{status:cur}),true;
   run("INSERT INTO private_access VALUES(?,?,'pending',?) ON CONFLICT(owner,viewer) DO UPDATE SET status='pending',created=excluded.created",owner.id,me.id,Date.now());
   clearNotice(owner.id,me.id);
   notice(owner.id,me.id,'private_request',me.id);
   return json(200,{status:'pending'}),true;
  }
  if((m=path.match(/^\/api\/users\/([a-zA-Z0-9-]+)\/private\/request$/))&&req.method==='DELETE'){
   const owner=visibleUser(m[1]);if(!owner||owner.id===me.id||blocked(me.id,owner.id))fail(404,'Không tìm thấy người dùng.');
   run("DELETE FROM private_access WHERE owner=? AND viewer=? AND status='pending'",m[1],me.id);
   clearNotice(m[1],me.id);
   return json(200,{status:access(m[1],me.id)}),true;
  }
  if(path==='/api/me/private/requests'&&req.method==='GET'){
   const rows=all("SELECT viewer,status,created FROM private_access WHERE owner=? AND status IN ('pending','granted') ORDER BY status='pending' DESC,created DESC",me.id);
   return json(200,{requests:rows.filter(r=>visibleUser(r.viewer)&&!blocked(me.id,r.viewer)).map(r=>({status:r.status,created:r.created,user:publicUser(user(r.viewer),me.id)}))}),true;
  }
  if((m=path.match(/^\/api\/me\/private\/requests\/([a-zA-Z0-9-]+)$/))&&req.method==='POST'){
   const b=await body(req),viewer=visibleUser(m[1]);
   if(!viewer||viewer.id===me.id||blocked(me.id,viewer.id))fail(404,'Không tìm thấy người dùng.');
   const current=get('SELECT status FROM private_access WHERE owner=? AND viewer=?',me.id,viewer.id);
   if(!current)fail(404,'Yêu cầu không còn tồn tại.');
   if(b.action==='grant'){
    if(!['pending','granted'].includes(current.status))fail(400,'Cần có yêu cầu xem mới để duyệt quyền.');
    run("INSERT INTO private_access VALUES(?,?,'granted',?) ON CONFLICT(owner,viewer) DO UPDATE SET status='granted',created=excluded.created",me.id,viewer.id,Date.now());
    if(current.status!=='granted')notice(viewer.id,me.id,'private_granted',me.id);
   }else if(b.action==='deny')run("UPDATE private_access SET status='denied' WHERE owner=? AND viewer=?",me.id,viewer.id);
   else if(b.action==='revoke'){run('DELETE FROM private_access WHERE owner=? AND viewer=?',me.id,viewer.id);if(current.status==='granted')notice(viewer.id,me.id,'private_revoked',me.id);}
   else fail(400,'Hành động không hợp lệ.');
   clearNotice(me.id,viewer.id);
   return json(200,{status:access(me.id,viewer.id)}),true;
  }
  return false;
 }
 function revokeBetween(a,b){run('DELETE FROM private_access WHERE (owner=? AND viewer=?) OR (owner=? AND viewer=?)',a,b,b,a);clearNotice(a,b);clearNotice(b,a);}
 return {route,revokeBetween};
}
