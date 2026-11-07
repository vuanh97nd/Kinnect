import {existsSync,readFileSync} from 'node:fs';
import {createHash,randomBytes} from 'node:crypto';
import {sharedApiPath} from './shared-api-paths.js';
import {feedSnapshot,videoSnapshot} from './feed-snapshot.js';
export function createPcCloudBridge(social,{syncFeedEnabled=true}={}){
 if(!existsSync('data/shared-core-enabled.json'))return null;
 const config=JSON.parse(readFileSync('cloud-api-server.env','utf8'));
 if(!config.PREVIEW_KEY)throw Error('Shared API credential missing');
 const origin='https://kinnect-cloud-api.vuanh97nd.workers.dev';
 let lastFeedSync=0,feedSyncing=false;
 async function cloud(path,method,cookie,body,ip){
  return fetch(origin+path,{method,headers:{'Content-Type':'application/json','X-Kinnect-Preview':config.PREVIEW_KEY,'X-Kinnect-Client-IP':ip||'unknown',Cookie:cookie||''},body,redirect:'manual',signal:AbortSignal.timeout(15000)});
 }
 function mirror(user,cookie){
  const token=(cookie||'').split(';').map(x=>x.trim()).find(x=>x.startsWith('kinnect_session='))?.slice(16);
  if(!user?.id||!token)return;
  const db=social.db;
  if(!social.user(user.id))db.prepare("INSERT INTO users(id,username,password,salt,name,created,role,suspended,birth_date) VALUES(?,?,?,?,?,?,?,0,'')").run(user.id,user.username,randomBytes(64).toString('hex'),randomBytes(16).toString('hex'),user.name,Number(user.joinedAt)||Date.now(),user.role==='admin'?'admin':'user');
  db.prepare('UPDATE users SET role=?,suspended=? WHERE id=?').run(user.role==='admin'?'admin':'user',user.suspended?1:0,user.id);
  if(typeof user.cloudChatSync==='boolean')db.prepare('UPDATE users SET cloud_chat_sync=? WHERE id=?').run(user.cloudChatSync?1:0,user.id);
  db.prepare('INSERT INTO sessions(token,user_id,expires) VALUES(?,?,?) ON CONFLICT(token) DO UPDATE SET expires=excluded.expires').run(createHash('sha256').update(token).digest('hex'),user.id,Date.now()+30*86400000);
  if(Array.isArray(user.blockedUserIds)){
   db.prepare('DELETE FROM blocks WHERE actor=?').run(user.id);
   for(const id of user.blockedUserIds)if(social.user(id))db.prepare('INSERT OR IGNORE INTO blocks(actor,target) VALUES(?,?)').run(user.id,id);
  }
 }
 return async(req,res)=>{
  const url=new URL(req.url,'http://localhost'),path=url.pathname;
  if(!path.startsWith('/api/'))return false;
  const cookie=req.headers.cookie||'',ip=req.headers['cf-connecting-ip']||req.socket.remoteAddress;
  try{
   if(sharedApiPath(path,req.method)&&!(path==='/api/me'&&url.searchParams.get('legacy')==='1')){
    let body;if(!['GET','HEAD'].includes(req.method)){const chunks=[];let size=0;for await(const chunk of req){size+=chunk.length;if(size>25*1024*1024){res.writeHead(413);res.end();return true;}chunks.push(chunk);}body=Buffer.concat(chunks);}
    const response=await cloud(req.url,req.method,cookie,body,ip),bytes=Buffer.from(await response.arrayBuffer());
    if(response.ok&&path==='/api/logout'){const token=cookie.split(';').map(x=>x.trim()).find(x=>x.startsWith('kinnect_session='))?.slice(16);if(token)social.db.prepare('DELETE FROM sessions WHERE token=?').run(createHash('sha256').update(token).digest('hex'));}
    if(response.status===200&&['/api/me','/api/login','/api/register'].includes(path)){
     const result=JSON.parse(bytes.toString());mirror(result.user,response.headers.get('Set-Cookie')||cookie);
    }
    const headers=Object.fromEntries(response.headers);for(const key of ['content-encoding','content-length','transfer-encoding','connection'])delete headers[key];headers['content-length']=String(bytes.length);res.writeHead(response.status,headers);res.end(bytes);return true;
   }
   if(cookie.includes('kinnect_session=')){
    const response=await cloud('/api/me','GET',cookie,undefined,ip);
    if(response.status!==200){res.writeHead(response.status===401?401:503,{'Content-Type':'application/json'});res.end(JSON.stringify({error:response.status===401?'Vui lòng đăng nhập.':'Dịch vụ tài khoản đang kết nối lại.'}));return true;}
    mirror((await response.json()).user,cookie);
   }
   res.once('finish',()=>{
    if(!syncFeedEnabled||res.statusCode>=400||feedSyncing||Date.now()-lastFeedSync<30000&&req.method==='GET')return;
    feedSyncing=true;
    cloud('/internal/feed-sync','POST','',JSON.stringify({posts:feedSnapshot(social.db),videos:videoSnapshot(social.db)}),ip).then(r=>{if(r.ok)lastFeedSync=Date.now();}).catch(()=>{}).finally(()=>{feedSyncing=false;});
   });
   return false;
  }catch{res.writeHead(503,{'Content-Type':'application/json'});res.end(JSON.stringify({error:'Dịch vụ tài khoản đang kết nối lại. Vui lòng thử lại.'}));return true;}
 };
}
