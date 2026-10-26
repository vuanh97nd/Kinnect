import {randomBytes,randomInt,createHmac,timingSafeEqual} from 'node:crypto';
export function createRecovery({db,body,fail,limit,requireUser,user,verifyPassword,hashPassword,revoke,sendEmail,mailReady,now=Date.now}){
 db.exec(`CREATE TABLE IF NOT EXISTS recovery_emails(user_id TEXT PRIMARY KEY REFERENCES users(id),email TEXT NOT NULL UNIQUE,verified INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS recovery_codes(id TEXT PRIMARY KEY,purpose TEXT NOT NULL,user_id TEXT,email TEXT,proof TEXT NOT NULL,password_version TEXT,created INTEGER NOT NULL,expires INTEGER NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,used INTEGER NOT NULL DEFAULT 0);
 CREATE TABLE IF NOT EXISTS recovery_limits(key TEXT PRIMARY KEY,created INTEGER NOT NULL,count INTEGER NOT NULL,last INTEGER NOT NULL);`);
 const secret=randomBytes(32),generic='Nếu tài khoản có email khôi phục đã xác minh, mã OTP sẽ được gửi tới email đó.';
 const digest=(id,code)=>createHmac('sha256',secret).update(id+':'+code).digest('hex');
 const norm=value=>typeof value==='string'?value.trim().toLowerCase():'';
 const get=(s,...a)=>db.prepare(s).get(...a),run=(s,...a)=>db.prepare(s).run(...a);
 function rate(key){const time=now();const old=get('SELECT * FROM recovery_limits WHERE key=?',key);if(old&&time-old.created<86400000&&(time-old.last<60000||old.count>=10))fail(429,'Vui lòng chờ một phút trước khi gửi lại; tối đa 10 mã mỗi ngày.');run('INSERT OR REPLACE INTO recovery_limits VALUES(?,?,?,?)',key,old&&time-old.created<86400000?old.created:time,old&&time-old.created<86400000?old.count+1:1,time);run('DELETE FROM recovery_limits WHERE last<?',time-86400000);run('DELETE FROM recovery_codes WHERE created<?',time-86400000);}
 function issue(purpose,account,email){const id=randomBytes(24).toString('hex'),code=String(randomInt(0,1000000)).padStart(6,'0'),time=now();if(account)run('UPDATE recovery_codes SET used=1 WHERE purpose=? AND user_id=?',purpose,account.id);run('INSERT INTO recovery_codes(id,purpose,user_id,email,proof,password_version,created,expires) VALUES(?,?,?,?,?,?,?,?)',id,purpose,account?.id||null,email||null,digest(id,code),account?.password||null,time,time+600000);return {id,code};}
 function check(id,code,purpose,owner){const c=get('SELECT * FROM recovery_codes WHERE id=? AND purpose=?',typeof id==='string'?id:'',purpose);const u=c?.user_id&&user(c.user_id);if(!c||c.used||c.attempts>=5||c.expires<=now()||!u||u.suspended||u.password!==c.password_version||(owner&&owner!==u.id))fail(400,'Mã không đúng hoặc đã hết hạn. Hãy yêu cầu mã mới.');run('UPDATE recovery_codes SET attempts=attempts+1 WHERE id=?',c.id);const hash=digest(c.id,typeof code==='string'?code:'');if(!/^\d{6}$/.test(code||'')||!timingSafeEqual(Buffer.from(hash,'hex'),Buffer.from(c.proof,'hex')))fail(400,'Mã không đúng hoặc đã hết hạn. Hãy yêu cầu mã mới.');return {c,u};}
 const deliver=(entry,email,purpose)=>sendEmail({to:email,subject:purpose==='bind'?'Kinnect — Xác minh email khôi phục':'Kinnect — Mã đặt lại mật khẩu',text:`Mã OTP của bạn là: ${entry.code}\n\nMã có hiệu lực 10 phút và chỉ dùng một lần. Không chia sẻ mã này. Nếu không yêu cầu, hãy bỏ qua email.`});
 async function route(req,res,path,json){
  if(!path.startsWith('/api/recovery/'))return false;
  if(path==='/api/recovery/email'&&req.method==='GET'){const me=requireUser(req),record=get('SELECT email FROM recovery_emails WHERE user_id=?',me.id);json(200,{email:record?.email||null,mailReady:mailReady()});return true;}
  if(req.method!=='POST')fail(405,'Chỉ hỗ trợ POST.');limit(req);const b=await body(req,4000);
  const adminEmail=path.match(/^\/api\/recovery\/admin\/users\/([a-f0-9-]{36})\/email$/);
  if(adminEmail){
   const admin=requireUser(req);if(admin.role!=='admin')fail(403,'Chỉ quản trị viên được cấu hình email cho người dùng.');if(!await verifyPassword(admin,b.password))fail(401,'Mật khẩu quản trị viên không đúng.');const fresh=requireUser(req);if(fresh.role!=='admin'||fresh.password!==admin.password)fail(403,'Vui lòng đăng nhập lại.');
   const target=user(adminEmail[1]);if(!target||target.suspended)fail(404,'Không tìm thấy tài khoản.');const email=norm(b.email);if(email.length>254||!/^\S+@[^\s@]+\.[^\s@]+$/.test(email)||/[\r\n<>]/.test(email))fail(400,'Nhập địa chỉ email hợp lệ.');
   const existing=get('SELECT user_id FROM recovery_emails WHERE email=?',email);if(existing&&existing.user_id!==target.id)fail(409,'Email này chưa thể liên kết với tài khoản.');
   db.exec('BEGIN IMMEDIATE');try{run('INSERT OR REPLACE INTO recovery_emails VALUES(?,?,?)',target.id,email,0);run('UPDATE recovery_codes SET used=1 WHERE user_id=?',target.id);run('INSERT INTO moderation VALUES(?,?,?,?)',randomBytes(16).toString('hex'),'set-recovery-email:'+admin.id,target.id,now());db.exec('COMMIT');}catch(e){db.exec('ROLLBACK');throw e;}
   json(200,{ok:true,message:'Đã gán email khôi phục. Người dùng cần nhận OTP để xác nhận khi đặt lại mật khẩu.'});return true;
  }
  if(path==='/api/recovery/email/start'){
   const me=requireUser(req);if(!await verifyPassword(me,b.password))fail(401,'Mật khẩu hiện tại không đúng.');const fresh=requireUser(req);if(fresh.password!==me.password)fail(401,'Vui lòng đăng nhập lại.');
   const email=norm(b.email);if(email.length>254||!/^\S+@[^\s@]+\.[^\s@]+$/.test(email)||/[\r\n<>]/.test(email))fail(400,'Nhập địa chỉ email hợp lệ.');if(!mailReady())fail(503,'Chức năng gửi email hiện chưa sẵn sàng.');rate('bind-user:'+me.id);rate('bind-email:'+email);const entry=issue('bind',me,email);
   try{const sent=await deliver(entry,email,'bind');if(sent!==true)throw Error('not sent');}catch{run('UPDATE recovery_codes SET used=1 WHERE id=?',entry.id);fail(503,'Chưa gửi được email. Vui lòng thử lại sau.');}
   json(200,{challengeId:entry.id,message:'Đã gửi mã xác minh tới email của bạn.'});return true;
  }
  if(path==='/api/recovery/email/verify'){
   const me=requireUser(req);const {c}=check(b.challengeId,b.code,'bind',me.id);const existing=get('SELECT user_id FROM recovery_emails WHERE email=?',c.email);if(existing&&existing.user_id!==me.id)fail(409,'Email này chưa thể liên kết với tài khoản.');
   db.exec('BEGIN IMMEDIATE');try{run('INSERT OR REPLACE INTO recovery_emails VALUES(?,?,?)',me.id,c.email,now());run('UPDATE recovery_codes SET used=1 WHERE user_id=?',me.id);db.exec('COMMIT');}catch(e){db.exec('ROLLBACK');throw e;}json(200,{ok:true,email:c.email});return true;
  }
  if(path==='/api/recovery/reset/start'){
   const identifier=norm(b.identifier??b.email??b.username);const byEmail=identifier.includes('@');if(byEmail?(identifier.length>254||!/^\S+@[^\s@]+\.[^\s@]+$/.test(identifier)||/[\r\n<>]/.test(identifier)):!/^[a-z0-9_]{3,30}$/.test(identifier))fail(400,'Nhập tên đăng nhập hoặc email khôi phục hợp lệ.');if(!mailReady())fail(503,'Chức năng gửi email hiện chưa sẵn sàng. Bạn có thể nhờ quản trị viên hỗ trợ.');const account=get('SELECT u.* FROM users u JOIN recovery_emails r ON r.user_id=u.id WHERE '+(byEmail?'r.email':'u.username')+'=? AND u.suspended=0',identifier);rate('reset:'+(account?.id||identifier));
   const email=account&&get('SELECT email FROM recovery_emails WHERE user_id=?',account.id)?.email;const entry=issue('reset',account,email);
   if(account&&email)Promise.resolve().then(()=>deliver(entry,email,'reset')).then(sent=>{if(sent!==true)run('UPDATE recovery_codes SET used=1 WHERE id=?',entry.id);}).catch(()=>{run('UPDATE recovery_codes SET used=1 WHERE id=?',entry.id);});
   json(200,{challengeId:entry.id,message:generic});return true;
  }
  if(path==='/api/recovery/reset/finish'){
   if(typeof b.password!=='string'||b.password.length<6||b.password.length>128)fail(400,'Mật khẩu mới cần 6–128 ký tự.');
   const prepared=await hashPassword(b.password);
   // No await between checking, consuming the OTP and replacing the password.
   const {c,u}=check(b.challengeId,b.code,'reset');
   db.exec('BEGIN IMMEDIATE');try{run('UPDATE users SET password=?,salt=? WHERE id=?',prepared.hash,prepared.salt,u.id);run('UPDATE recovery_emails SET verified=? WHERE user_id=? AND email=?',now(),u.id,c.email);run('DELETE FROM sessions WHERE user_id=?',u.id);revoke(u.id);run('UPDATE recovery_codes SET used=1 WHERE user_id=?',u.id);run("UPDATE password_resets SET status='done',handled=? WHERE user_id=? AND status='open'",now(),u.id);db.exec('COMMIT');}catch(e){db.exec('ROLLBACK');throw e;}
   json(200,{ok:true,message:'Đã đổi mật khẩu. Hãy đăng nhập bằng mật khẩu mới.'});return true;
  }
  fail(404,'Không tìm thấy chức năng.');
 }
 return {route};
}
