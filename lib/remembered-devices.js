import {randomBytes,createHash} from 'node:crypto';
const hash=value=>createHash('sha256').update(value).digest('hex');
export function rememberedDevices({db,user,own,startSession,body,fail,limit}){
 db.exec('CREATE TABLE IF NOT EXISTS remembered_accounts(device TEXT NOT NULL,user_id TEXT NOT NULL REFERENCES users(id),expires INTEGER NOT NULL,PRIMARY KEY(device,user_id))');
 const cookieToken=req=>(req.headers.cookie||'').split(';').map(v=>v.trim()).find(v=>v.startsWith('kinnect_device='))?.slice(15)||'';
 const device=req=>{const token=cookieToken(req);return /^[a-f0-9]{64}$/.test(token)?hash(token):null;};
 const revoke=id=>db.prepare('DELETE FROM remembered_accounts WHERE user_id=?').run(id);
 return {
 revoke,
 remember(req,id,enabled){
  const token=cookieToken(req),valid=/^[a-f0-9]{64}$/.test(token),key=valid?hash(token):null;
  if(enabled!==true){if(key&&enabled===false)db.prepare('DELETE FROM remembered_accounts WHERE device=? AND user_id=?').run(key,id);return [];}
  const next=valid?token:randomBytes(32).toString('hex'),digest=hash(next);
  db.prepare('DELETE FROM remembered_accounts WHERE expires<=?').run(Date.now());
  db.prepare('INSERT OR REPLACE INTO remembered_accounts VALUES(?,?,?)').run(digest,id,Date.now()+30*86400000);
  const rows=db.prepare('SELECT user_id FROM remembered_accounts WHERE device=? ORDER BY expires DESC').all(digest);
  for(const row of rows.slice(5))db.prepare('DELETE FROM remembered_accounts WHERE device=? AND user_id=?').run(digest,row.user_id);
  return [`kinnect_device=${next}; HttpOnly; SameSite=Strict; Path=/; Max-Age=2592000${process.env.SECURE_COOKIES==='1'?'; Secure':''}`];
 },
 async route(req,res,path,json){
  const key=device(req);
  if(path==='/api/remembered'&&req.method==='GET'){
   const accounts=key?db.prepare('SELECT u.id,u.username,u.name FROM remembered_accounts d JOIN users u ON u.id=d.user_id WHERE d.device=? AND d.expires>? AND u.suspended=0 ORDER BY d.expires DESC LIMIT 5').all(key,Date.now()):[];json(200,{accounts});return true;
  }
  if(path==='/api/remembered/login'&&req.method==='POST'){
   limit(req);const data=await body(req,4000);
   const remembered=key&&typeof data.userId==='string'&&db.prepare('SELECT user_id FROM remembered_accounts WHERE device=? AND user_id=? AND expires>?').get(key,data.userId,Date.now());
   const account=remembered&&user(remembered.user_id);
   if(!account||account.suspended)fail(401,'Đăng nhập nhanh đã hết hạn. Vui lòng nhập mật khẩu.');
   json(200,{user:own(account)},{'Set-Cookie':startSession(account.id,req)});return true;
  }
  const remove=path.match(/^\/api\/remembered\/([a-zA-Z0-9-]+)$/);
  if(remove&&req.method==='DELETE'){if(key)db.prepare('DELETE FROM remembered_accounts WHERE device=? AND user_id=?').run(key,remove[1]);json(200,{ok:true});return true;}
  return false;
 }
 };
}
