export function createFriendships({db,user,publicUser,blocked,notice,body,fail}){
 db.exec("CREATE TABLE IF NOT EXISTS friendships(low_id TEXT NOT NULL REFERENCES users(id),high_id TEXT NOT NULL REFERENCES users(id),requester TEXT NOT NULL REFERENCES users(id),status TEXT NOT NULL CHECK(status IN ('pending','accepted')),created INTEGER NOT NULL,PRIMARY KEY(low_id,high_id)); CREATE INDEX IF NOT EXISTS friendships_requester ON friendships(requester,status)");
 const get=(q,...p)=>db.prepare(q).get(...p),all=(q,...p)=>db.prepare(q).all(...p),run=(q,...p)=>db.prepare(q).run(...p),pair=(a,b)=>[a,b].sort();
 function status(a,b){if(!a||a===b)return 'none';const row=get('SELECT requester,status FROM friendships WHERE low_id=? AND high_id=?',...pair(a,b));return !row?'none':row.status==='accepted'?'friends':row.requester===a?'outgoing':'incoming';}
 const active=id=>{const u=user(id);return u&&!u.suspended?u:null;};
 function rows(me,state){return all('SELECT * FROM friendships WHERE (low_id=? OR high_id=?) AND status=? ORDER BY created DESC',me,me,state).map(r=>({...r,other:r.low_id===me?r.high_id:r.low_id})).filter(r=>active(r.other)&&!blocked(me,r.other));}
 const pendingCount=me=>rows(me,'pending').filter(r=>r.requester!==me).length;
 const clearNotice=(recipient,actor)=>run("UPDATE notifications SET seen=1 WHERE user_id=? AND actor=? AND kind='friend_request'",recipient,actor);
 function removeBetween(a,b){run('DELETE FROM friendships WHERE low_id=? AND high_id=?',...pair(a,b));clearNotice(a,b);clearNotice(b,a);}
 async function route(req,res,path,me,json){
 if(path==='/api/friends'&&req.method==='GET'){json(200,{users:rows(me.id,'accepted').map(r=>publicUser(user(r.other),me.id))});return true;}
 if(path==='/api/friend-requests'&&req.method==='GET'){const pending=rows(me.id,'pending');json(200,{incoming:pending.filter(r=>r.requester!==me.id).map(r=>publicUser(user(r.other),me.id)),outgoing:pending.filter(r=>r.requester===me.id).map(r=>publicUser(user(r.other),me.id))});return true;}
 if(path==='/api/friend-suggestions'&&req.method==='GET'){
  const interests=JSON.parse(me.interests||'[]'),city=me.city?.trim().toLocaleLowerCase('vi');
  const candidates=all('SELECT * FROM users WHERE id<>? AND suspended=0 AND discoverable=1 ORDER BY created DESC LIMIT 500',me.id).filter(u=>!blocked(me.id,u.id)&&status(me.id,u.id)==='none').map(u=>{const sharedInterests=JSON.parse(u.interests||'[]').filter(x=>interests.includes(x)).length,sameCity=!!city&&city===publicUser(u,me.id).city?.trim().toLocaleLowerCase('vi');return {...publicUser(u,me.id),sharedInterests,sameCity,recommendationScore:sharedInterests*2+(sameCity?3:0)};}).sort((a,b)=>b.recommendationScore-a.recommendationScore||b.joinedAt-a.joinedAt).slice(0,24);
  json(200,{users:candidates});return true;
 }
 const match=path.match(/^\/api\/users\/([a-zA-Z0-9-]+)\/(friend-request|friendship)(?:\/(respond))?$/);if(!match)return false;
 const [,id,action,respond]=match,target=active(id);if(!target||id===me.id||blocked(me.id,id))fail(404,'Không tìm thấy người dùng.');
 const current=status(me.id,id),keys=pair(me.id,id);
 if(action==='friend-request'&&!respond&&req.method==='POST'){
  if(current==='none'||current==='outgoing')run('INSERT OR IGNORE INTO follows VALUES(?,?)',me.id,id);
  if(current==='none'){run("INSERT INTO friendships VALUES(?,?,?,'pending',?)",...keys,me.id,Date.now());notice(id,me.id,'friend_request',me.id);}
  json(200,{status:status(me.id,id),user:publicUser(target,me.id)});return true;
 }
 if(action==='friend-request'&&!respond&&req.method==='DELETE'){if(current!=='outgoing')fail(400,'Không có lời mời đã gửi.');removeBetween(me.id,id);json(200,{status:'none'});return true;}
 if(action==='friend-request'&&respond&&req.method==='POST'){
  const b=await body(req);if(!['accept','decline'].includes(b.action))fail(400,'Thao tác không hợp lệ.');
  if(current==='friends'&&b.action==='accept'){json(200,{status:'friends'});return true;}
  if(current!=='incoming')fail(404,'Lời mời không còn tồn tại.');
  if(b.action==='accept'){run("UPDATE friendships SET status='accepted' WHERE low_id=? AND high_id=?",...keys);run('INSERT OR IGNORE INTO follows VALUES(?,?)',me.id,id);run('INSERT OR IGNORE INTO follows VALUES(?,?)',id,me.id);notice(id,me.id,'friend_accepted',me.id);clearNotice(me.id,id);}else removeBetween(me.id,id);
  json(200,{status:status(me.id,id)});return true;
 }
 if(action==='friendship'&&!respond&&req.method==='DELETE'){if(current!=='friends')fail(404,'Hai bạn chưa kết bạn.');removeBetween(me.id,id);json(200,{status:'none'});return true;}
 fail(405,'Phương thức không hợp lệ.');
 }
 return {route,status,pendingCount,removeBetween};
}
