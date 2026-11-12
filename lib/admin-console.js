import {createAdminInfrastructure} from './admin-infrastructure.js';
import {createConsoleTickets} from './console-tickets.js';
import {createConsoleWalletTools} from './console-wallet-tools.js';
import {createOpsMonitorService} from './ops-monitor-service.js';
import {analyzeTicketWithAI, generateSmartReply, generateBriefSummary} from './ai-copilot.js';
import {
  ensureViolationAndReputationTables,
  getReputationInfo,
  getAccountViolationDossier,
  restoreReputation,
  deductReputation,
  VIOLATION_TYPES,
  PENALTY_POINTS
} from './ai-violation-reporter.js';
import {randomBytes,randomUUID,createHash,scryptSync,timingSafeEqual} from 'node:crypto';
import {readFile,stat} from 'node:fs/promises';
import {applyModeration} from './moderation.js';
export function createAdminConsole(social,{loginAdmin,authority,restartServer,databasePath,instanceId=randomUUID(),cloudRuntime,persistentState=false,trustedPrincipal,getPcTelemetry}={}) {
 const db=social.db;
 if(persistentState){db.exec('CREATE TABLE IF NOT EXISTS console_persistent_state(namespace TEXT,key TEXT,value TEXT,PRIMARY KEY(namespace,key))');db.exec("DELETE FROM console_persistent_state WHERE namespace='attempts'");}
 const persistentMap=namespace=>({get:key=>{const row=db.prepare('SELECT value FROM console_persistent_state WHERE namespace=? AND key=?').get(namespace,key);return row?JSON.parse(row.value):undefined;},set:(key,value)=>db.prepare('INSERT OR REPLACE INTO console_persistent_state VALUES(?,?,?)').run(namespace,key,JSON.stringify(value)),delete:key=>db.prepare('DELETE FROM console_persistent_state WHERE namespace=? AND key=?').run(namespace,key),*[Symbol.iterator](){for(const row of db.prepare('SELECT key,value FROM console_persistent_state WHERE namespace=?').all(namespace))yield[row.key,JSON.parse(row.value)];}});
 const sessions=persistentState?persistentMap('sessions'):new Map(), attempts=persistentState?persistentMap('attempts'):new Map();
 ensureViolationAndReputationTables(db);
 db.exec(`CREATE TABLE IF NOT EXISTS console_staff(id TEXT PRIMARY KEY,username TEXT UNIQUE NOT NULL,name TEXT NOT NULL,password TEXT NOT NULL,salt TEXT NOT NULL,suspended INTEGER NOT NULL DEFAULT 0,must_change INTEGER NOT NULL DEFAULT 1,created INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS console_audit(id TEXT PRIMARY KEY,actor TEXT NOT NULL,action TEXT NOT NULL,target TEXT,created INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS console_messages(id TEXT PRIMARY KEY,channel TEXT NOT NULL DEFAULT 'all',sender_id TEXT NOT NULL,sender_username TEXT NOT NULL,sender_name TEXT NOT NULL,sender_role TEXT NOT NULL,sender_team TEXT NOT NULL,content TEXT NOT NULL,ticket_id TEXT,created INTEGER NOT NULL);
 CREATE INDEX IF NOT EXISTS idx_console_messages_channel_created ON console_messages(channel, created);
 CREATE INDEX IF NOT EXISTS idx_console_messages_created ON console_messages(created);`);
 if(!db.prepare('PRAGMA table_info(console_staff)').all().some(c=>c.name==='team'))db.exec("ALTER TABLE console_staff ADD COLUMN team TEXT NOT NULL DEFAULT 'support'");
 const infrastructure=createAdminInfrastructure({cloudEnabled:!!authority&&!!databasePath&&databasePath!==':memory:'});
 const tickets=createConsoleTickets(db);
 const walletTools=createConsoleWalletTools({db,authority,replicateCredits:!cloudRuntime});
 const one=(sql,...v)=>db.prepare(sql).get(...v),all=(sql,...v)=>db.prepare(sql).all(...v);
 const audit=(actor,action,target='')=>{db.prepare('INSERT INTO console_audit VALUES(?,?,?,?,?)').run(randomUUID(),actor,action,target,Date.now());cloudRuntime?.queueAction?.({actor,action,target});};
 const opsMonitor=createOpsMonitorService({db,audit,sessions,getPcTelemetry:getPcTelemetry||cloudRuntime?.getPcTelemetry});
 const digest=s=>createHash('sha256').update(s).digest('hex');
 const validPassword=p=>typeof p==='string'&&p.length>=12&&p.length<=128;
 const verify=(p,u)=>u&&typeof p==='string'&&p.length<=128&&/^[0-9a-f]{128}$/i.test(u.password)&&typeof u.salt==='string'&&u.salt.length>0&&timingSafeEqual(scryptSync(p,u.salt,64),Buffer.from(u.password,'hex'));
 const temporary=()=>randomBytes(18).toString('base64url');
 const setPassword=(id,password)=>{const salt=randomBytes(16).toString('hex');db.prepare('UPDATE console_staff SET password=?,salt=? WHERE id=?').run(scryptSync(password,salt,64).toString('hex'),salt,id);};
 const revoke=id=>{for(const[k,v]of sessions)if(v.id===id)sessions.delete(k);};
 const hostMode=req=>{const rawHost=req.headers['x-forwarded-host']||req.headers['x-console-portal']||req.headers.host||'';const host=String(rawHost).split(':')[0].toLowerCase();return host==='admin.kinnect.io.vn'?'admin':host==='hotro.kinnect.io.vn'?'support':host==='taichinh.kinnect.io.vn'?'finance':host==='kythuat.kinnect.io.vn'?'operations':(['127.0.0.1','localhost'].includes(host)?'local':'none');};
 const safeUser=u=>({id:u.id,username:u.username,name:u.name,role:u.role,team:u.role==='admin'?'admin':u.team||'support',mustChange:!!u.must_change});
 const fail=(status,message)=>{const e=new Error(message);e.status=status;throw e;};
 const principal=async(req,mode)=>{const token=String(req.headers.cookie||'').split(';').map(x=>x.trim()).find(x=>x.startsWith('kinnect_console='))?.slice(16);const key=token&&digest(token),s=key&&sessions.get(key);if(!s)return null;if(Date.now()>s.until||Date.now()-s.last>30*60*1000){sessions.delete(key);return null;}let u;if(s.role==='admin'){if(authority){try{u=await authority.user(s.id);}catch{}}if(!u||!u.password)u=one("SELECT id,username,name,role,suspended,password,0 AS must_change FROM users WHERE id=? AND role='admin'",s.id);}else{u=one("SELECT *, 'support' AS role FROM console_staff WHERE id=?",s.id);}if(!u||u.suspended||digest(u.password)!==s.credential||s.role==='admin'&&u.role!=='admin'||mode!=='local'&&(mode==='admin'?u.role!=='admin':u.role!=='support'||(u.team||'support')!==mode)){sessions.delete(key);return null;}s.last=Date.now();sessions.set(key,s);return {...safeUser(u),key};};
 async function body(req){let bytes=0,parts=[];for await(const c of req){bytes+=c.length;if(bytes>32768)fail(413,'Dữ liệu quá lớn.');parts.push(c);}try{return JSON.parse(Buffer.concat(parts).toString()||'{}');}catch{fail(400,'Dữ liệu không hợp lệ.');}}
 const consoleRoute=async function consoleRoute(req,res){
  const url=new URL(req.url,'http://localhost'),path=url.pathname,mode=hostMode(req),isConsoleHost=['admin','support','operations','finance'].includes(mode);
  if(!path.startsWith('/api/console/')&&!path.startsWith('/admin')&&!isConsoleHost)return false;
  const headers={'Cache-Control':'no-store, no-cache, must-revalidate','CDN-Cache-Control':'no-store','Cloudflare-CDN-Cache-Control':'no-store','X-Content-Type-Options':'nosniff','X-Frame-Options':'DENY','Referrer-Policy':'no-referrer','Permissions-Policy':'geolocation=(), microphone=(), camera=(), payment=(), usb=()','Cross-Origin-Opener-Policy':'same-origin','Strict-Transport-Security':'max-age=31536000; includeSubDomains; preload','Content-Security-Policy':"default-src 'self'; script-src 'self'; style-src 'self'; style-src-attr 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"};
  const send=(status,data,extra={})=>{res.writeHead(status,{...headers,'Content-Type':'application/json; charset=utf-8',...extra});res.end(JSON.stringify(data));return true;};
  try{
   if(mode==='none')return send(404,{error:'Không tìm thấy trang.'});
   if(!path.startsWith('/api/console/')){
    if(path==='/index.html'){res.writeHead(301,{...headers,Location:'/'+url.search});res.end();return true;}
    if(path==='/robots.txt'){res.writeHead(200,{...headers,'Content-Type':'text/plain; charset=utf-8','Cache-Control':'public, max-age=86400'});res.end(req.method==='HEAD'?undefined:'User-agent: *\nDisallow: /\n');return true;}
    const asset=path==='/admin/mark.svg'?'../kinnect-logo-v106.svg':path==='/admin/regular.ttf'?'../fonts/be-vietnam-pro-regular.ttf':path==='/admin/semibold.ttf'?'../fonts/be-vietnam-pro-semibold.ttf':path==='/admin/theme-boot.js'?'theme-boot.js':path==='/admin/admin.js'?'admin.js':path==='/admin/admin.css'?'admin.css':path==='/admin/wallet-tools.js'?'wallet-tools.js':path==='/admin/wallet-tools.css'?'wallet-tools.css':path==='/admin/admin-v2.css'?'admin-v2.css':path==='/admin/admin-v2.js'?'admin-v2.js':path==='/admin/ops-monitor.css'?'ops-monitor.css':path==='/admin/ops-monitor.js'?'ops-monitor.js':(['/','/admin','/admin/','/admin/index.html'].includes(path)?'index.html':null);
    if(!asset)return send(404,{error:'Không tìm thấy trang.'});
    if(!['GET','HEAD'].includes(req.method))return send(405,{error:'Phương thức không hợp lệ.'});
    const bytes=await readFile(new URL('../public/admin/'+asset,import.meta.url));
    const assetHeaders=asset==='index.html'?{...headers,'CF-Cache-Status':'DYNAMIC'}:{...headers,'Cache-Control':'public, max-age=31536000, immutable'};
    if(asset!=='index.html'){delete assetHeaders['CDN-Cache-Control'];delete assetHeaders['Cloudflare-CDN-Cache-Control'];}
    res.writeHead(200,{...assetHeaders,'Content-Type':asset.endsWith('.ttf')?'font/ttf':asset.endsWith('.svg')?'image/svg+xml':asset.endsWith('.js')?'text/javascript; charset=utf-8':asset.endsWith('.css')?'text/css; charset=utf-8':'text/html; charset=utf-8'});res.end(req.method==='HEAD'?undefined:bytes);return true;
   }
   if(!['GET','POST'].includes(req.method))return send(405,{error:'Phương thức không hợp lệ.'});
   if(req.method==='POST'){
    let origin;try{origin=new URL(req.headers.origin);}catch{fail(403,'Yêu cầu phải xuất phát từ cổng quản trị.');}
    const targetHost=req.headers['x-forwarded-host']||req.headers['x-console-portal']||req.headers.host;
    if(origin.host!==targetHost||!['http:','https:'].includes(origin.protocol))fail(403,'Nguồn yêu cầu không hợp lệ.');
   }
   if(path==='/api/console/health'&&req.method==='GET')return send(200,{ok:true,instanceId});
   const b=req.method==='POST'?await body(req):{};
   const cookie=(token,max=28800)=>`kinnect_console=${token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${max}${mode!=='local'||process.env.SECURE_COOKIES==='1'?'; Secure':''}`;
   if(path==='/api/console/login'&&req.method==='POST'){
    const now=Date.now(),ip=req.headers['cf-connecting-ip']||req.socket.remoteAddress;
    for(const[k,v]of attempts)if(v.until<now)attempts.delete(k);
    const key=ip+':'+mode,rate=attempts.get(key)||{n:0,until:now+15*60*1000};
    if(rate.n>=12)fail(429,'Đăng nhập quá nhiều lần. Thử lại sau 15 phút.');rate.n++;attempts.set(key,rate);
    const username=String(b.username||'').trim().toLowerCase();if(!/^[a-z0-9_]{3,30}$/.test(username)||typeof b.password!=='string'||b.password.length>128)fail(401,'Tên đăng nhập hoặc mật khẩu không đúng.');
    let u;
    if(mode!=='admin'){const staff=one("SELECT *, 'support' AS role FROM console_staff WHERE username=?",username);if(staff&&(mode==='local'||(staff.team||'support')===mode)&&verify(b.password,staff))u=staff;}
    if(!u&&['admin','local'].includes(mode)){
     const local=one("SELECT *,0 AS must_change FROM users WHERE username=? AND role='admin'",username);
     if(authority){try{u=await authority.verify(username,b.password);}catch{}}
     if(!u&&local&&verify(b.password,local))u=local;
     if(!u&&loginAdmin){try{const remote=await loginAdmin(username,b.password);if(remote?.role==='admin')u=local||one("SELECT *,0 AS must_change FROM users WHERE id=? AND role='admin'",remote.id);}catch{}}
    }
    if(!u||u.suspended)fail(401,'Tên đăng nhập hoặc mật khẩu không đúng, hoặc không có quyền vào cổng này.');
    const token=temporary();for(const[k,v]of sessions)if(v.until<now||now-v.last>1800000)sessions.delete(k);sessions.set(digest(token),{id:u.id,role:u.role,credential:digest(u.password),until:now+28800000,last:now});attempts.delete(key);audit(u.username,'login',mode);return send(200,{user:safeUser(u)},{'Set-Cookie':cookie(token)});
   }
   const me=trustedPrincipal?.(req)||await principal(req,mode);if(!me)fail(401,'Phiên đã hết hạn. Vui lòng đăng nhập lại.');
   if(path==='/api/console/me'&&req.method==='GET')return send(200,{user:{id:me.id,username:me.username,name:me.name,role:me.role,team:me.team,mustChange:me.mustChange}});
   if(path==='/api/console/logout'&&req.method==='POST'){sessions.delete(me.key);return send(200,{ok:true},{'Set-Cookie':cookie('',0)});}
   if(path==='/api/console/password'&&req.method==='POST'){
    if(me.role!=='support')fail(400,'Admin đổi mật khẩu trong ứng dụng Kinnect.');const u=one('SELECT * FROM console_staff WHERE id=?',me.id);
    if(!verify(b.current,u))fail(401,'Mật khẩu hiện tại không đúng.');if(!validPassword(b.password)||b.password===b.current)fail(400,'Mật khẩu mới cần 12–128 ký tự và khác mật khẩu hiện tại.');setPassword(me.id,b.password);db.prepare('UPDATE console_staff SET must_change=0 WHERE id=?').run(me.id);revoke(me.id);audit(me.username,'change-password');return send(200,{ok:true},{'Set-Cookie':cookie('',0)});
   }
   if(me.mustChange)fail(403,'Bạn cần đổi mật khẩu tạm trước khi làm việc.');
   if(path.startsWith('/api/console/team')){
    if(me.role!=='admin')fail(403,'Chỉ admin cấp cao nhất quản lý nhân sự.');
    if(path==='/api/console/team'&&req.method==='GET')return send(200,{staff:all('SELECT id,username,name,suspended,must_change,created,team FROM console_staff ORDER BY created')});
    if(path==='/api/console/team'&&req.method==='POST'){
     if(b.action==='create'){
      const username=String(b.username||'').trim().toLowerCase(),name=String(b.name||'').trim().slice(0,80);if(!/^[a-z0-9_]{3,30}$/.test(username)||!name)fail(400,'Nhập tên đăng nhập 3–30 chữ/số/gạch dưới và tên hiển thị.');
      if(one('SELECT id FROM console_staff WHERE username=?',username)||one('SELECT id FROM users WHERE username=?',username))fail(409,'Tên tài khoản đã tồn tại.');
      const team=b.team||'support';if(!['support','operations','finance'].includes(team))fail(400,'Nhóm không hợp lệ.');
      const id=randomUUID(),salt=randomBytes(16).toString('hex'),password=temporary();db.prepare('INSERT INTO console_staff(id,username,name,password,salt,suspended,must_change,created,team) VALUES(?,?,?,?,?,0,1,?,?)').run(id,username,name,scryptSync(password,salt,64).toString('hex'),salt,Date.now(),team);audit(me.username,'create-support',username);return send(200,{username,temporaryPassword:password});
     }
     const staff=one('SELECT * FROM console_staff WHERE id=?',b.id);if(!staff)fail(404,'Không tìm thấy nhân sự.');
     if(b.action==='move'){if(!['support','operations','finance'].includes(b.team))fail(400,'Nhóm không hợp lệ.');db.prepare('UPDATE console_staff SET team=? WHERE id=?').run(b.team,staff.id);revoke(staff.id);audit(me.username,'move-team:'+b.team,staff.username);return send(200,{ok:true});}
     if(b.action==='reset'){const password=temporary();setPassword(staff.id,password);db.prepare('UPDATE console_staff SET must_change=1 WHERE id=?').run(staff.id);revoke(staff.id);audit(me.username,'reset-support-password',staff.username);return send(200,{username:staff.username,temporaryPassword:password});}
     if(!['suspend','restore'].includes(b.action))fail(400,'Thao tác không hợp lệ.');db.prepare('UPDATE console_staff SET suspended=? WHERE id=?').run(b.action==='suspend'?1:0,staff.id);revoke(staff.id);audit(me.username,b.action+'-support',staff.username);return send(200,{ok:true});
    }
   }
   if(path.startsWith('/api/console/ops/'))return await opsMonitor({path,method:req.method,body:b,me,send});
   const endpoint=path.split('/')[3];
   const allowed={
     support:['overview','users','resets','reports','moderate','content','post-media','activity','tickets','teams','reputation','member-360','ai','messages'],
     operations:['overview','operations','ops','activity','tickets','teams','ai','messages'],
     finance:['overview','finance','activity','tickets','teams','wallet-tools','member-360','ai','messages']
   };
   if(me.role!=='admin'&&!(allowed[me.team]||[]).includes(endpoint))fail(403,'Nhóm của bạn không được cấp chức năng này.');
   if(path==='/api/console/ai/analyze'&&req.method==='POST'){
     const result=analyzeTicketWithAI({
       subject:b.subject||'',
       description:b.description||'',
       member:b.member||'',
       team:b.team||'support',
       priority:b.priority||'normal'
     });
     return send(200,{ok:true,analysis:result});
   }
   if(path==='/api/console/ai/smart-reply'&&req.method==='POST'){
     const text=generateSmartReply({
       type:b.type||'resolved',
       customNote:b.customNote||'',
       member:b.member||''
     });
     return send(200,{ok:true,reply:text});
   }
   if(path==='/api/console/ai/brief'&&req.method==='POST'){
     const brief=generateBriefSummary({
       tickets:b.tickets||{},
       reports:b.reports||0,
       resets:b.resets||0,
       pendingWallet:b.pendingWallet||0
     });
     return send(200,{ok:true,brief});
   }
   if(path==='/api/console/messages'&&req.method==='GET'){
     const channel=String(url.searchParams.get('channel')||'all');
     const since=Number(url.searchParams.get('since')||0);
     const ticketId=url.searchParams.get('ticket_id');

     const userTeam=me.role==='admin'?'admin':(me.team||'support');
     const allowedChannels=new Set(['all']);
     if(userTeam==='admin'){
       allowedChannels.add('support-finance').add('support-operations').add('finance-operations').add('support').add('finance').add('operations').add('admin');
     }else if(userTeam==='support'){
       allowedChannels.add('support-finance').add('support-operations').add('support');
     }else if(userTeam==='finance'){
       allowedChannels.add('support-finance').add('finance-operations').add('finance');
     }else if(userTeam==='operations'){
       allowedChannels.add('support-operations').add('finance-operations').add('operations');
     }

     if(channel!=='any'&&!allowedChannels.has(channel)){
       fail(403,'Bạn không có quyền truy cập kênh trao đổi này.');
     }

     let rows;
     if(ticketId){
       rows=all('SELECT * FROM console_messages WHERE ticket_id=? AND created>? ORDER BY created ASC LIMIT 100',ticketId,since);
     }else if(channel==='any'){
       const placeholders=Array.from(allowedChannels).map(()=>'?').join(',');
       rows=all(`SELECT * FROM console_messages WHERE channel IN (${placeholders}) AND created>? ORDER BY created ASC LIMIT 100`,...Array.from(allowedChannels),since);
     }else{
       rows=all('SELECT * FROM console_messages WHERE channel=? AND created>? ORDER BY created ASC LIMIT 100',channel,since);
     }

     return send(200,{messages:rows});
   }
   if(path==='/api/console/messages'&&req.method==='POST'){
     const channel=String(b.channel||'all').trim();
     const content=String(b.content||'').trim();
     const ticketId=b.ticket_id?String(b.ticket_id).trim():null;

     if(!content)fail(400,'Nội dung tin nhắn không được để trống.');
     if(content.length>2000)fail(400,'Nội dung tin nhắn không vượt quá 2000 ký tự.');

     const userTeam=me.role==='admin'?'admin':(me.team||'support');
     const allowedChannels=new Set(['all']);
     if(userTeam==='admin'){
       allowedChannels.add('support-finance').add('support-operations').add('finance-operations').add('support').add('finance').add('operations').add('admin');
     }else if(userTeam==='support'){
       allowedChannels.add('support-finance').add('support-operations').add('support');
     }else if(userTeam==='finance'){
       allowedChannels.add('support-finance').add('finance-operations').add('finance');
     }else if(userTeam==='operations'){
       allowedChannels.add('support-operations').add('finance-operations').add('operations');
     }

     if(!allowedChannels.has(channel))fail(403,'Bạn không thể gửi tin nhắn vào kênh này.');

     const msgId=randomUUID();
     const now=Date.now();
     db.prepare('INSERT INTO console_messages(id,channel,sender_id,sender_username,sender_name,sender_role,sender_team,content,ticket_id,created) VALUES(?,?,?,?,?,?,?,?,?,?)').run(
       msgId,channel,me.id,me.username,me.name||me.username,me.role,userTeam,content,ticketId,now
     );

     return send(201,{
       ok:true,
       message:{
         id:msgId,channel,sender_id:me.id,sender_username:me.username,sender_name:me.name||me.username,
         sender_role:me.role,sender_team:userTeam,content,ticket_id:ticketId,created:now
       }
     });
   }
   if(path==='/api/console/tickets/ai-classify'&&req.method==='POST'){
    const {classifyTicket}=await import('./ai-dispatcher.js');
    return send(200,classifyTicket({subject:b.subject||'',description:b.description||'',member:b.member||'',category:b.category||''}));
   }
   if(path==='/api/console/tickets/ai-dispatch'&&req.method==='POST'){
    const {dispatchTicketWithAI}=await import('./ai-dispatcher.js');
    const res=dispatchTicketWithAI(db,{
      subject:b.subject||'',
      description:b.description||'',
      member:b.member||'',
      category:b.category||'',
      reporter:me.username,
      actorName:me.name||me.username,
      preferredTeam:b.team,
      preferredPriority:b.priority
    });
    audit(me.username,'ai-dispatch-ticket',res.ticket.id);
    return send(201,res);
   }
   const ticketResult=await tickets({me,method:req.method,path:path.slice('/api/console'.length),url,body:b});
   if(ticketResult!==null)return send(200,ticketResult);
   const walletResult=await walletTools({me,method:req.method,path:path.slice('/api/console'.length),url,body:b});
   if(walletResult!==null)return send(200,walletResult);
   if(path==='/api/console/teams'&&req.method==='GET')return send(200,{teams:[{id:'admin',name:'Admin cấp cao nhất'},{id:'support',name:'Hỗ trợ & Kiểm duyệt'},{id:'operations',name:'Bộ phận kỹ thuật'},{id:'finance',name:'Bộ phận tài chính'}]});
   if(path==='/api/console/finance'&&req.method==='GET'){
    const q=String(url.searchParams.get('q')||'').slice(0,60);
    const kindFilter=String(url.searchParams.get('kind')||'all').trim();
    let ledger=null;
    if(authority)ledger=await authority.finance(q);
    if(!ledger){
     const kindSql=kindFilter&&kindFilter!=='all'?' AND w.kind=?':'';
     const args=['%'+q+'%','%'+q+'%',...(kindSql?[kindFilter]:[])];
     ledger={
      entries:all('SELECT w.id,w.reference,w.kind,w.coins,w.net_vnd,w.creator_vnd,w.platform_vnd,w.created,u.username,u.name FROM wallet_entries w JOIN users u ON u.id=w.user_id WHERE (u.username LIKE ? OR w.reference LIKE ?)'+kindSql+' ORDER BY w.created DESC LIMIT 120',...args),
      totals:one('SELECT count(*) AS entries,COALESCE(sum(net_vnd),0) AS net_vnd,COALESCE(sum(creator_vnd),0) AS creator_vnd,COALESCE(sum(platform_vnd),0) AS platform_vnd,COALESCE(sum(coins),0) AS total_coins FROM wallet_entries')
     };
    } else if(kindFilter&&kindFilter!=='all'&&Array.isArray(ledger.entries)){
     ledger.entries=ledger.entries.filter(e=>e.kind===kindFilter);
    }
    let pendingWalletOps=0;
    try{pendingWalletOps=one("SELECT count(*) n FROM console_wallet_operations WHERE state='pending'")?.n||0;}catch{}
    return send(200,{...ledger,pendingWalletOps,economy:social.economy.read(),topUpEnabled:false,payoutEnabled:false});
   }
   if(cloudRuntime&&path.startsWith('/api/console/operations'))return await cloudRuntime.operations({path,method:req.method,body:b,me,send,url});
   if(path==='/api/console/operations'&&req.method==='GET'){
    const status=social.ai.status();
    let dbSize=0;
    try{
      const sFile=databasePath&&databasePath!==':memory:'?databasePath:null;if(!sFile)throw Error('No disk database');
      const info=await stat(sFile);
      dbSize=Math.round(info.size/1048576*10)/10;
    }catch{}
    const mem=process.memoryUsage();
    return send(200,{
      infrastructure:await infrastructure(),
      uptime:Math.floor(process.uptime()),
      memoryMb:Math.round(mem.rss/1048576),
      memoryDetail:{
        rss:Math.round(mem.rss/1048576),
        heapTotal:Math.round(mem.heapTotal/1048576),
        heapUsed:Math.round(mem.heapUsed/1048576),
        external:Math.round(mem.external/1048576)
      },
      platform:process.platform+' ('+process.arch+') - Node '+process.version,
      maintenanceMode:Boolean(global.__KINNECT_MAINTENANCE_MODE),
      ai:{
        ready:!!status.ready,
        support:!!status.support,
        moderation:!!status.moderation,
        queue:status.queue,
        failed:status.failed
      },
      database:{
        sizeMb:databasePath===':memory:'?null:dbSize,
        tables:one("SELECT count(*) n FROM sqlite_master WHERE type='table'").n,
        indexes:one("SELECT count(*) n FROM sqlite_master WHERE type='index'").n,
        users:one("SELECT count(*) n FROM users").n,
        violations:one("SELECT count(*) n FROM account_violations").n,
        status:'not_checked'
      },
      services:{
        server:{name:'Core Web & WebSocket API',status:'operational',port:3000,pid:process.pid},
        tunnel:{name:'Cloudflare Edge Ingress Tunnel',status:'not_checked',hosts:['admin.kinnect.io.vn','hotro.kinnect.io.vn','kythuat.kinnect.io.vn','taichinh.kinnect.io.vn']},
        sfu:{name:'WebRTC High-Capacity SFU',status:'not_checked',port:7885}
      },
      jobs:all('SELECT id,kind,state,attempts,created FROM ai_jobs ORDER BY created DESC LIMIT 50')
    });
   }
   if(path==='/api/console/operations/action'&&req.method==='POST'){
    if(me.role!=='admin'&&me.team!=='operations')fail(403,'Chỉ Bộ phận Kỹ thuật và Admin được thực hiện thao tác này.');
    const action=String(b.action||'').trim();
    if(['toggle-ai-moderation','toggle-ai-support'].includes(action)&&me.role!=='admin')fail(403,'Chỉ Admin thay đổi chính sách AI hỗ trợ hoặc kiểm duyệt.');
    if(action==='toggle-maintenance'){
      global.__KINNECT_MAINTENANCE_MODE=!global.__KINNECT_MAINTENANCE_MODE;
      audit(me.username,'toggle-maintenance',global.__KINNECT_MAINTENANCE_MODE?'ON':'OFF');
      return send(200,{ok:true,maintenanceMode:global.__KINNECT_MAINTENANCE_MODE,message:global.__KINNECT_MAINTENANCE_MODE?'Đã BẬT Chế độ bảo trì hệ thống. Người dùng ngoài ứng dụng sẽ nhận thông báo bảo trì.':'Đã TẮT Chế độ bảo trì hệ thống. Ứng dụng đã mở lại bình thường cho toàn bộ người dùng.'});
    }
    if(action==='purge-cache'){
      if(!global.gc)fail(503,'Tiến trình không bật chức năng thu gom bộ nhớ thủ công; không có cache nào bị xóa.');
      global.gc();audit(me.username,'request-garbage-collection');
      return send(200,{ok:true,message:'Đã yêu cầu thu gom bộ nhớ. Không xóa dữ liệu hoặc cache ứng dụng.'});
    }
    if(action==='optimize-db'){
      db.exec('PRAGMA wal_checkpoint(TRUNCATE)');
      db.exec('PRAGMA optimize');
      audit(me.username,'optimize-db');
      return send(200,{ok:true,message:'Đã tối ưu hóa chỉ mục CSDL SQLite và giải phóng tệp nhật ký WAL thành công.'});
    }
    if(action==='check-integrity'){
      const res=one('PRAGMA quick_check');
      audit(me.username,'check-integrity');
      return send(200,{ok:true,status:res?.quick_check||'ok',message:'Cơ sở dữ liệu toàn vẹn: '+JSON.stringify(res)});
    }
    if(action==='flush-ai-queue'){
      const r=db.prepare("UPDATE ai_jobs SET state='failed' WHERE state IN ('running','queued')").run();
      audit(me.username,'flush-ai-queue',String(r.changes));
      return send(200,{ok:true,changes:r.changes,message:`Đã hủy ${r.changes} tác vụ AI đang bị nghẽn trong hàng chờ.`});
    }
    if(action==='toggle-ai-moderation'){
      const cur=social.ai.status();
      const nCfg=social.ai.configure({moderation:!cur.moderation});
      audit(me.username,'toggle-ai-moderation',nCfg.moderation?'ON':'OFF');
      return send(200,{ok:true,moderation:nCfg.moderation,message:nCfg.moderation?'Đã BẬT Kiểm duyệt AI tự động.':'Đã TẮT Kiểm duyệt AI tự động.'});
    }
    if(action==='toggle-ai-support'){
      const cur=social.ai.status();
      const nCfg=social.ai.configure({support:!cur.support});
      audit(me.username,'toggle-ai-support',nCfg.support?'ON':'OFF');
      return send(200,{ok:true,support:nCfg.support,message:nCfg.support?'Đã BẬT Trợ lý AI hỗ trợ tự động.':'Đã TẮT Trợ lý AI hỗ trợ tự động.'});
    }
    if(action==='restart-server'){
      if(!restartServer)fail(503,'Máy chủ này chưa được cấu hình bộ điều khiển khởi động lại. Không có tiến trình nào bị dừng.');
      const job=await restartServer({res});audit(me.username,'restart-server',job.id);
      return send(202,{ok:true,...job,instanceId});
    }
    fail(400,'Hành động không hợp lệ: '+action);
   }
   if(path==='/api/console/operations/logs'&&req.method==='GET'){
    if(me.role!=='admin'&&me.team!=='operations')fail(403,'Chỉ Bộ phận Kỹ thuật và Admin được xem nhật ký hệ thống.');
    const service=url.searchParams.get('service')||'all';
    let logs=[];
    try{
      const serverLogFile=new URL('../data/startup-server.log',import.meta.url);
      const text=await readFile(serverLogFile,'utf8');
      const lines=text.split('\n').filter(Boolean).slice(-60).map(l=>({service:'server',time:Date.now(),msg:l}));
      logs.push(...lines);
    }catch{}
    try{
      const tunnelLogFile=new URL('../data/startup-tunnel.log',import.meta.url);
      const text=await readFile(tunnelLogFile,'utf8');
      const lines=text.split('\n').filter(Boolean).slice(-40).map(l=>{
        try{const j=JSON.parse(l);return {service:'tunnel',time:j.time?new Date(j.time).getTime():Date.now(),level:j.level||'info',msg:j.message||j.error||l};}
        catch{return {service:'tunnel',time:Date.now(),level:'info',msg:l};}
      });
      logs.push(...lines);
    }catch{}
    if(service!=='all')logs=logs.filter(l=>l.service===service);
    return send(200,{logs:logs.slice(-100)});
   }
   if(path.startsWith('/api/console/post-media/')&&req.method==='GET'){
    const postId=path.slice('/api/console/post-media/'.length);
    const media=one('SELECT type,data FROM post_media WHERE post_id=?',postId);
    if(!media)return send(404,{error:'Không tìm thấy tệp ảnh/video.'});
    res.writeHead(200,{...headers,'Content-Type':media.type,'Cache-Control':'private, max-age=86400'});
    res.end(media.data);
    return true;
   }
   if(path==='/api/console/content'&&req.method==='GET'){
    const q=String(url.searchParams.get('q')||'').trim().slice(0,80);
    const filter=url.searchParams.get('filter')||'all';
    let filterCond='';
    if(filter==='active')filterCond=' AND p.hidden=0';
    else if(filter==='hidden')filterCond=' AND p.hidden=1';
    else if(filter==='media')filterCond=' AND m.type IS NOT NULL';
    const where=(q?' WHERE (p.body LIKE ? OR u.username LIKE ? OR u.name LIKE ?)':' WHERE 1=1')+filterCond;
    const args=q?['%'+q+'%','%'+q+'%','%'+q+'%']:[];
    const posts=all('SELECT p.id,p.user_id,p.body,p.visibility,p.hidden,p.created,u.username,u.name,m.type AS media_type FROM posts p JOIN users u ON u.id=p.user_id LEFT JOIN post_media m ON m.post_id=p.id'+where+' ORDER BY p.created DESC LIMIT 150',...args).map(p=>({
      ...p,
      has_media:!!p.media_type,
      media_url:p.media_type?('/api/console/post-media/'+p.id):null
    }));
    return send(200,{posts});
   }
   if(path==='/api/console/overview'&&req.method==='GET'){
    let baseCounts=null;
    if(authority)baseCounts=await authority.counts();
    if(!baseCounts)baseCounts={users:one('SELECT count(*) n FROM users').n,suspended:one('SELECT count(*) n FROM users WHERE suspended=1').n};
    let pendingWalletOps=0;
    try{pendingWalletOps=one("SELECT count(*) n FROM console_wallet_operations WHERE state='pending'")?.n||0;}catch{}
    const deptRows=all("SELECT team,count(*) n FROM console_tickets WHERE status!='resolved' GROUP BY team");
    const departmentQueues={admin:0,support:0,finance:0,operations:0};
    for(const r of deptRows)if(departmentQueues[r.team]!==undefined)departmentQueues[r.team]=r.n;
    const urgentTickets=one("SELECT count(*) n FROM console_tickets WHERE status!='resolved' AND priority IN ('urgent','high')")?.n||0;
    return send(200,{
     ...baseCounts,
     reports:one("SELECT count(*) n FROM reports WHERE status='open'").n,
     resets:one("SELECT count(*) n FROM password_resets WHERE status='open'").n,
     pendingWalletOps,
     departmentQueues,
     urgentTickets,
     staffCount:one('SELECT count(*) n FROM console_staff WHERE suspended=0')?.n||0
    });
   }
   const m360Match=/^\/api\/console\/member-360\/([a-zA-Z0-9_.-]{1,80})$/.exec(path);
   if(m360Match&&req.method==='GET'){
    const target=m360Match[1].replace(/^@/,'').toLowerCase();
    let u=one('SELECT id,username,name,role,suspended,created,COALESCE(reputation_score,100) AS reputation_score FROM users WHERE id=? OR LOWER(username)=?',target,target);
    if(authority){
      const ru=await authority.user(target)||(await authority.users(target,'all'))?.users?.find(x=>x.username.toLowerCase()===target||x.id===target);
      u=ru?{id:ru.id,username:ru.username,name:ru.name,role:ru.role,suspended:ru.suspended,created:ru.created,reputation_score:u?.id===ru.id?u.reputation_score:100}:null;
    }
    if(!u)fail(404,'Không tìm thấy hồ sơ thành viên: '+target);
    const score=Number.isInteger(u.reputation_score)?u.reputation_score:100;
    const dossier=getAccountViolationDossier(db,u.id)||{
     reputation:{userId:u.id,username:u.username,name:u.name,score,tier:score>=90?'excellent':score>=70?'good':score>=50?'warning':'restricted',tierLabel:score>=90?'Chuẩn mực (90–100 điểm)':score>=70?'Khá (70–89 điểm)':score>=50?'Cảnh báo (50–69 điểm)':'Hạn chế (<50 điểm)',tierColor:score>=90?'#10B981':score>=70?'#F59E0B':'#EF4444',canGoLive:score>=50&&u.suspended===0,canPost:score>=30&&u.suspended===0,canComment:score>=30&&u.suspended===0,isSuspended:u.suspended===1||score<30,logs:[]},
     totalViolations:0,
     violations:[]
    };
    const canContent=me.role==='admin'||me.team==='support';
    const canFinance=me.role==='admin'||me.team==='finance';
    const posts=canContent?all('SELECT p.id,p.user_id,p.body,p.visibility,p.hidden,p.created,m.type AS media_type FROM posts p LEFT JOIN post_media m ON m.post_id=p.id WHERE p.user_id=? ORDER BY p.created DESC LIMIT 12',u.id).map(p=>({...p,username:u.username,name:u.name,has_media:!!p.media_type,media_url:p.media_type?('/api/console/post-media/'+p.id):null})):[];
    const ticketScope=me.role==='admin'?'':' AND EXISTS(SELECT 1 FROM console_ticket_teams p WHERE p.ticket_id=t.id AND p.team=?)';
    const memberTickets=all('SELECT t.id,t.subject,t.team,t.priority,t.status,t.created,t.updated FROM console_tickets t WHERE (LOWER(t.member)=? OR LOWER(t.member)=? OR LOWER(t.member)=?)'+ticketScope+' ORDER BY t.updated DESC LIMIT 20',u.username.toLowerCase(),'@'+u.username.toLowerCase(),u.id.toLowerCase(),...(me.role==='admin'?[]:[me.team]));
    const memberReports=canContent?all("SELECT id,target_type,target_id,reason,status,created FROM reports WHERE target_id=? OR target_id IN (SELECT id FROM posts WHERE user_id=?) ORDER BY created DESC LIMIT 15",u.id,u.id):[];
    let wallet=null;
    if(canFinance){
     const entries=all('SELECT id,reference,kind,coins,net_vnd,created FROM wallet_entries WHERE user_id=? ORDER BY created DESC LIMIT 20',u.id);
     const balance=one('SELECT COALESCE(sum(coins),0) AS total_coins,COALESCE(sum(net_vnd),0) AS total_vnd FROM wallet_entries WHERE user_id=?',u.id);
     wallet=authority?await authority.memberLedger(u.id):{entries,totalCoins:balance?.total_coins||0,totalVnd:balance?.total_vnd||0,source:'sqlite'};
    }
    const member={id:u.id,username:u.username,name:u.name,role:u.role,suspended:u.suspended,created:u.created,reputation_score:u.reputation_score};
    return send(200,{user:member,dossier,posts,tickets:memberTickets,reports:memberReports,wallet});
   }
   if(path.startsWith('/api/console/reputation')){
    if(me.role!=='admin'&&me.team!=='support')fail(403,'Chỉ Admin và Hỗ trợ được quản lý điểm uy tín.');
    if(path==='/api/console/reputation/overview'&&req.method==='GET'){
     const policy=[
      {case:'Ảnh đại diện (Avatar) nhạy cảm',old:'-15 điểm',new:'-3 điểm',action:'Gỡ avatar về mặc định, gửi thông báo nhắc nhở'},
      {case:'Video / Bài viết nhạy cảm 18+',old:'-25 điểm',new:'-5 điểm',action:'Ẩn nội dung (hidden = 1), gửi thông báo kèm lý do'},
      {case:'Tin nhắn rác / Spam nhẹ',old:'-5 điểm',new:'-2 điểm',action:'Ẩn bình luận spam'},
      {case:'Quấy rối, xúc phạm nhẹ',old:'-10 điểm',new:'-5 điểm',action:'Cảnh báo chuẩn mực ứng xử'},
      {case:'Lừa đảo xu / Kỳ thị thù ghét',old:'-25 điểm',new:'-10 điểm',action:'Chuyển Hỗ trợ & Tài chính đối soát'},
      {case:'Đe dọa bạo lực thể xác nguy cấp',old:'-50 điểm',new:'-25 điểm',action:'Tạm đình chỉ ngắn hạn, chuyển thẳng Admin'},
      {case:'Ảnh khoe body / gym / bikini',old:'Bị phạt nhầm',new:'0 điểm (HỢP LỆ)',action:'Được duyệt bình thường'},
      {case:'Ảnh riêng tư (DM / Private post)',old:'Không rõ',new:'0 điểm (BẢO VỆ)',action:'Không cấm, không kiểm duyệt'}
     ];
     const tiers={
      excellent:one("SELECT count(*) n FROM users WHERE suspended=0 AND role='user' AND COALESCE(reputation_score,100)>=90").n,
      good:one("SELECT count(*) n FROM users WHERE suspended=0 AND role='user' AND COALESCE(reputation_score,100)>=70 AND COALESCE(reputation_score,100)<90").n,
      warning:one("SELECT count(*) n FROM users WHERE suspended=0 AND role='user' AND COALESCE(reputation_score,100)>=50 AND COALESCE(reputation_score,100)<70").n,
      restricted:one("SELECT count(*) n FROM users WHERE (suspended=1 OR COALESCE(reputation_score,100)<50) AND role='user'").n
     };
     const violationsCount=one('SELECT count(*) n FROM account_violations').n;
     const deductedTotal=one('SELECT COALESCE(sum(deducted_points),0) n FROM account_violations').n;
     return send(200,{tiers,violationsCount,deductedTotal,policy,violationTypes:VIOLATION_TYPES,penaltyPoints:PENALTY_POINTS});
    }
    if(path==='/api/console/reputation/violations'&&req.method==='GET'){
     const violations=all("SELECT v.*, u.name, COALESCE(u.reputation_score,100) AS current_score FROM account_violations v LEFT JOIN users u ON u.id=v.user_id ORDER BY v.created DESC LIMIT 100");
     return send(200,{violations,violationTypes:VIOLATION_TYPES});
    }
    const userMatch=/^\/api\/console\/reputation\/user\/([a-zA-Z0-9_.-]{1,80})$/.exec(path);
    if(userMatch&&req.method==='GET'){
     const target=userMatch[1].replace(/^@/,'').toLowerCase();
     let dossier=getAccountViolationDossier(db,target);
     if(!dossier){
      const u=one('SELECT id,username,name,suspended,role,COALESCE(reputation_score,100) AS score FROM users WHERE id=? OR LOWER(username)=?',target,target);
      if(u){
       dossier=getAccountViolationDossier(db,u.id)||{
        reputation:{userId:u.id,username:u.username,name:u.name,score:u.score,tier:u.score>=90?'excellent':u.score>=70?'good':u.score>=50?'warning':'restricted',tierLabel:u.score>=90?'Chuẩn mực (90–100 điểm)':u.score>=70?'Khá (70–89 điểm)':u.score>=50?'Cảnh báo (50–69 điểm)':'Hạn chế (<50 điểm)',tierColor:u.score>=90?'#10B981':u.score>=70?'#F59E0B':'#EF4444',canGoLive:u.score>=50&&u.suspended===0,canPost:u.score>=30&&u.suspended===0,canComment:u.score>=30&&u.suspended===0,isSuspended:u.suspended===1||u.score<30,logs:[]},
        totalViolations:0,
        violations:[]
       };
      } else if(authority){
       let ru;
       try{ru=await authority.user(target);}catch{}
       if(!ru){
        try{const sres=await authority.users(target,'all');ru=sres.users?.find(x=>x.username.toLowerCase()===target||x.id===target);}catch{}
       }
       if(ru){
        dossier={
         reputation:{userId:ru.id,username:ru.username,name:ru.name,score:100,tier:'excellent',tierLabel:'Chuẩn mực (90–100 điểm)',tierColor:'#10B981',canGoLive:ru.suspended===0,canPost:ru.suspended===0,canComment:ru.suspended===0,isSuspended:ru.suspended===1,logs:[]},
         totalViolations:0,
         violations:[]
        };
       }
      }
     }
     if(!dossier)fail(404,'Không tìm thấy thành viên: '+target);
     return send(200,dossier);
    }
    if(path==='/api/console/reputation/adjust'&&req.method==='POST'){
     const userId=String(b.userId||'').trim(),action=String(b.action||'').trim(),points=Number(b.points),reason=String(b.reason||'').trim();
     if(!userId)fail(400,'Thiếu mã thành viên.');
     if(!['restore','deduct'].includes(action))fail(400,'Hành động không hợp lệ (chỉ chấp nhận khôi phục hoặc trừ điểm).');
     if(!Number.isInteger(points)||points<1||points>100)fail(400,'Số điểm phải từ 1 đến 100.');
     if(reason.length<5||reason.length>500)fail(400,'Nhập lý do từ 5 đến 500 ký tự.');
     let target=one('SELECT id,role FROM users WHERE id=?',userId);
     if(!target&&authority){
      const ru=await authority.user(userId);
      if(ru&&ru.role==='user'){
       try{db.prepare('INSERT OR IGNORE INTO users(id,username,name,role,password,salt,created,reputation_score) VALUES(?,?,?,?,?,?,?,100)').run(ru.id,ru.username,ru.name||ru.username,ru.role,'','',Date.now());}catch{}
       target=one('SELECT id,role FROM users WHERE id=?',userId);
      }
     }
     if(!target||target.role!=='user')fail(403,'Chỉ điều chỉnh điểm cho thành viên thường.');
     const actor=me.name?me.name+' (@'+me.username+')':'@'+me.username;
     const result=action==='restore'?restoreReputation(db,{userId,points,reason,actor}):deductReputation(db,{userId,points,reason,actor});
     audit(me.username,'reputation-'+action,userId);
     const dossier=getAccountViolationDossier(db,userId);
     return send(200,{ok:true,result,dossier});
    }
   }
   if(path==='/api/console/users'&&req.method==='GET'){
    const q=String(url.searchParams.get('q')||'').slice(0,60),state=url.searchParams.get('state')||'all';if(!['all','active','suspended','admin'].includes(state))fail(400,'Bộ lọc không hợp lệ.');const cond=state==='active'?' AND suspended=0':state==='suspended'?' AND suspended=1':state==='admin'?" AND role='admin'":'';
    const score=url.searchParams.get('score')||'all';
    const scoreCond=score==='excellent'?' AND COALESCE(reputation_score,100)>=90':score==='good'?' AND COALESCE(reputation_score,100)>=70 AND COALESCE(reputation_score,100)<90':score==='warning'?' AND COALESCE(reputation_score,100)>=50 AND COALESCE(reputation_score,100)<70':score==='restricted'?' AND (suspended=1 OR COALESCE(reputation_score,100)<50)':'';
    let remoteRes=null;
    if(authority)remoteRes=await authority.users(q,state);
    if(remoteRes&&Array.isArray(remoteRes.users)){
      const userList=remoteRes.users.map(u=>{
        const local=one('SELECT COALESCE(reputation_score,100) AS reputation_score FROM users WHERE id=? OR username=?',u.id,u.username);
        return {...u,reputation_score:local?local.reputation_score:100};
      });
      const filtered=score==='all'?userList:userList.filter(u=>{
        const s=u.reputation_score;
        if(score==='excellent')return s>=90;
        if(score==='good')return s>=70&&s<90;
        if(score==='warning')return s>=50&&s<70;
        if(score==='restricted')return s<50||u.suspended===1;
        return true;
      });
      return send(200,{total:score==='all'?remoteRes.total:filtered.length,users:filtered,source:'cloud'});
    }
    const where=' WHERE (username LIKE ? OR name LIKE ?)'+cond+scoreCond,values=['%'+q+'%','%'+q+'%'];return send(200,{total:one('SELECT count(*) n FROM users'+where,...values).n,users:all('SELECT id,username,name,role,suspended,created,COALESCE(reputation_score,100) AS reputation_score FROM users'+where+' ORDER BY created DESC LIMIT 100',...values)});
   }
   if(path==='/api/console/reports'&&req.method==='GET'){
    const reports=all("SELECT * FROM reports ORDER BY status='open' DESC,created DESC LIMIT 200").map(r=>{
      let subject=null;
      if(r.target_type==='post'){
        const p=one('SELECT p.id,p.body,p.hidden,p.visibility,p.created,p.user_id AS userId,u.username,u.name,m.type AS media_type FROM posts p LEFT JOIN users u ON u.id=p.user_id LEFT JOIN post_media m ON m.post_id=p.id WHERE p.id=?',r.target_id);
        if(p)subject={id:p.id,body:p.body,hidden:p.hidden,visibility:p.visibility,created:p.created,userId:p.userId,username:p.username,name:p.name,media_type:p.media_type,has_media:!!p.media_type,media_url:p.media_type?('/api/console/post-media/'+r.target_id):null};
      }
      if(r.target_type==='short'){
        const s=one('SELECT s.caption AS body,s.hidden,s.user_id AS userId,u.username,u.name FROM shorts s LEFT JOIN users u ON u.id=s.user_id WHERE s.id=?',r.target_id);
        if(s)subject=s;
      }
      if(r.target_type==='user')subject=one('SELECT username,name,role,suspended,id AS userId FROM users WHERE id=?',r.target_id);
      return {...r,subject};
    });
    return send(200,{reports});
   }
   if(path==='/api/console/moderate'&&req.method==='POST'){
    if(!['suspend-user','restore-user','hide-post','show-post','hide-short','show-short','close-report'].includes(b.action))fail(400,'Thao tác không được hỗ trợ.');
    if(b.action.endsWith('-user')){const target=authority?await authority.user(b.target):one('SELECT role FROM users WHERE id=?',b.target);if(!target||target.role!=='user')fail(403,'Không thể thay đổi tài khoản quản trị hoặc nhân viên hỗ trợ tại đây.');}
    try{if(authority&&b.action.endsWith('-user')){await authority.suspend(b.target,b.action==='suspend-user');if(one('SELECT id FROM users WHERE id=?',b.target))applyModeration(db,b.action,b.target,'console-'+me.username);}else applyModeration(db,b.action,b.target,'console-'+me.username);}catch(e){fail(e.status||400,e.message);}audit(me.username,b.action,b.target);if(authority&&['hide-post','show-post','hide-short','show-short'].includes(b.action))await authority.syncContent(db);return send(200,{ok:true});
   }
   if(path==='/api/console/resets'&&req.method==='GET')return send(200,{requests:all("SELECT p.id,p.username,p.user_id,p.contact,p.note,p.status,p.created,u.role FROM password_resets p LEFT JOIN users u ON u.id=p.user_id ORDER BY p.status='open' DESC,p.created DESC LIMIT 100")});
   if(path==='/api/console/resets'&&req.method==='POST'){
    const request=one('SELECT p.*,u.role FROM password_resets p LEFT JOIN users u ON u.id=p.user_id WHERE p.id=?',b.id);if(!request||request.status!=='open')fail(409,'Yêu cầu không còn chờ xử lý.');
    if(b.action==='dismiss'){db.prepare("UPDATE password_resets SET status='dismissed',handled=? WHERE id=?").run(Date.now(),b.id);audit(me.username,'dismiss-reset',request.username);return send(200,{ok:true});}
    if(b.action!=='reset'||!request.user_id||request.role!=='user')fail(403,'Chỉ được khôi phục tài khoản thành viên thường.');let password;if(authority){const result=await authority.reset(request.user_id);password=result.password;db.prepare('UPDATE users SET password=?,salt=? WHERE id=?').run(result.hash,result.salt,request.user_id);db.prepare('DELETE FROM sessions WHERE user_id=?').run(request.user_id);db.prepare("UPDATE password_resets SET status='done',handled=? WHERE user_id=? AND status='open'").run(Date.now(),request.user_id);}else password=await social.resetPassword(request.user_id);audit(me.username,'reset-user-password',request.username);return send(200,{username:request.username,temporaryPassword:password});
   }
   if(path==='/api/console/activity'&&req.method==='GET')return send(200,{entries:me.role==='admin'?all('SELECT * FROM console_audit ORDER BY created DESC,rowid DESC LIMIT 150'):all('SELECT * FROM console_audit WHERE actor=? ORDER BY created DESC,rowid DESC LIMIT 100',me.username)});
   return send(404,{error:'Không tìm thấy chức năng.'});
  }catch(e){return send(e.status||500,{error:e.status?e.message:'Không xử lý được yêu cầu. Vui lòng thử lại.'});}
 };
 consoleRoute.close=()=>walletTools.close?.();
 return consoleRoute;
}
