import http from 'node:http';
import {readFileSync,writeFileSync,mkdirSync,existsSync,createReadStream,statSync,statfsSync} from 'node:fs';
import {resolve,join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomBytes,timingSafeEqual} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {MediaStore,hash} from './store.mjs';
import {pull,peerUrl} from './sync.mjs';
const here=dirname(fileURLToPath(import.meta.url));
const adminPort=Number(process.env.KINNECT_MANAGER_PORT||3128),syncPort=Number(process.env.KINNECT_SYNC_PORT||3129);
const home=resolve(process.env.KINNECT_MANAGER_HOME||join(process.env.LOCALAPPDATA||here,'KinnectServer'));
mkdirSync(home,{recursive:true});const configPath=join(home,'settings.json');
function privateFile(path,body){writeFileSync(path,'',{flag:'wx'});if(process.platform==='win32'){const sid=execFileSync('whoami.exe',['/user','/fo','csv','/nh'],{encoding:'utf8',windowsHide:true}).match(/S-1-\d+(?:-\d+)+/)?.[0];if(!sid)throw Error('Không xác định được quyền lưu cấu hình.');execFileSync('icacls.exe',[path,'/inheritance:r','/grant:r',`*${sid}:(F)`],{stdio:'pipe',windowsHide:true});}writeFileSync(path,body,{mode:0o600});}
let config=existsSync(configPath)?JSON.parse(readFileSync(configPath,'utf8')):{root:null,source:null,adminKey:randomBytes(32).toString('hex'),syncKey:randomBytes(32).toString('hex'),peers:[],network:false};
if(!existsSync(configPath))privateFile(configPath,JSON.stringify(config));
const save=()=>writeFileSync(configPath,JSON.stringify(config,null,2));
let store=config.root?new MediaStore(config.root):null,enabled=config.enabled===true,busy=false,lastSync=null,lastError='',networkServer=null;
const equal=(a,b)=>typeof a==='string'&&a.length===b.length&&timingSafeEqual(Buffer.from(a),Buffer.from(b));
const json=(res,status,data)=>{res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(JSON.stringify(data));};
async function body(req){const chunks=[];let n=0;for await(const chunk of req){n+=chunk.length;if(n>8192)throw Error('Dữ liệu quá lớn.');chunks.push(chunk);}return JSON.parse(Buffer.concat(chunks).toString());}
async function scan(){if(!store||!config.source)return;const {DatabaseSync}=await import('node:sqlite');const source=new DatabaseSync(config.source,{readOnly:true});try{
 source.exec('BEGIN');const tables=new Set(source.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map(x=>x.name));
 const stamp='source:'+hash(Buffer.from(config.source)),previous=JSON.parse(store.db.prepare('SELECT value FROM metadata WHERE key=?').get(stamp)?.value||'[]'),seen=[];
 for(const [table,id,field,type]of [['post_media','post_id','data','type'],['shorts','id','data',null],['private_photos','id','data','type'],['chat_attachments','id','data','type'],['users','id','avatar','avatar_type'],['users','id','cover','cover_type']]){
  if(!tables.has(table)||!source.prepare('PRAGMA table_info('+table+')').all().some(c=>c.name===field))continue;
  const rows=source.prepare(`SELECT ${id} id,${field} data,${type||"'video/mp4'"} type FROM ${table} WHERE ${field} IS NOT NULL`).iterate();
  for(const row of rows)if(row.data?.length){const key=table+'/'+field+'/'+row.id;seen.push(key);if(!store.current(key)?.deleted)store.put(key,Buffer.from(row.data),row.type||'application/octet-stream');}
 }
 source.exec('COMMIT');
 const present=new Set(seen);for(const key of previous)if(!present.has(key)&&store.current(key)?.origin===store.nodeId)store.remove(key);
 store.db.prepare('INSERT INTO metadata VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value').run(stamp,JSON.stringify(seen));
}finally{source.close();}}
async function cycle(){if(busy||!enabled||!store)return;busy=true;try{await scan();for(const peer of config.peers){let pages=0,result;do{if(!enabled)break;result=await pull(store,peer,{signal:AbortSignal.timeout(120000)});pages++;}while(result.more&&pages<10);}lastSync=new Date().toISOString();lastError='';}catch(e){lastError=e.message;}finally{busy=false;}}
function syncHandler(req,res){try{
 if(!equal(req.headers.authorization,'Bearer '+config.syncKey))return json(res,401,{error:'Không có quyền đồng bộ.'});
 if(req.method!=='GET'||!store)return json(res,503,{error:'Kho chưa sẵn sàng.'});const url=new URL(req.url,'http://localhost');
 if(url.pathname==='/sync/identity')return json(res,200,{nodeId:store.nodeId});
 if(url.pathname==='/sync/changes'){const after=Number(url.searchParams.get('after')||0);if(!Number.isSafeInteger(after)||after<0)throw Error('Mốc không hợp lệ.');return json(res,200,{nodeId:store.nodeId,changes:store.changes(after)});}
 const match=url.pathname.match(/^\/sync\/objects\/([a-f0-9]{64})$/);if(!match)return json(res,404,{});
 const path=store.objectPath(match[1]),size=statSync(path).size;let start=0;
 if(req.headers.range){const range=/^bytes=(\d+)-$/.exec(req.headers.range);if(!range||Number(range[1])>=size){res.writeHead(416);return res.end();}start=Number(range[1]);}
 res.writeHead(start?206:200,{'Content-Type':'application/octet-stream','Content-Length':size-start,'Cache-Control':'no-store',...(start?{'Content-Range':`bytes ${start}-${size-1}/${size}`}:{})});createReadStream(path,{start}).on('error',()=>res.destroy()).pipe(res);
}catch{if(!res.headersSent)json(res,404,{error:'Không tìm thấy tệp.'});else res.destroy();}}
async function network(on){if(!on&&networkServer){await new Promise(r=>networkServer.close(r));networkServer=null;}if(on&&!networkServer){const next=http.createServer(syncHandler);await new Promise((ok,bad)=>{next.once('error',bad);next.listen(syncPort,'0.0.0.0',ok);});networkServer=next;}config.network=on;save();}
const local=http.createServer(async(req,res)=>{try{
 if(req.headers.host!=='127.0.0.1:'+adminPort)return json(res,403,{});
 if(req.url==='/'&&req.method==='GET')return json(res,200,{service:'kinnect-media-manager',desktop:true});
 if(!equal(req.headers['x-admin-key'],config.adminKey))return json(res,401,{});
 if(req.headers.origin&&req.headers.origin!=='http://127.0.0.1:'+adminPort)return json(res,403,{});
 if(req.url==='/status'&&req.method==='GET'){let disk=null;try{const s=statfsSync(config.root);disk={free:s.bavail*s.bsize,total:s.blocks*s.bsize};}catch{}return json(res,200,{configured:!!store,root:config.root,source:config.source,enabled,busy,lastSync,lastError,network:!!networkServer,peers:config.peers.map(({id,url})=>({id,url})),disk,media:store?.status(),productionIntegrated:false});}
 if(req.method!=='POST')return json(res,404,{});const b=await body(req);
 if(req.url==='/choose-storage'){
  if(process.platform!=='win32')throw Error('Nhập đường dẫn thư mục vào ô bên trên.');
  const {execFile}=await import('node:child_process');const path=await new Promise((ok,bad)=>execFile('powershell.exe',['-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',join(here,'choose-folder.ps1')],{windowsHide:true,encoding:'utf8',timeout:120000},(error,stdout)=>error?bad(Error('Chưa chọn được thư mục.')):ok(stdout.trim())));return json(res,200,{path});
 }
 if(req.url==='/storage'){
  if(enabled||busy)throw Error('Tạm dừng đồng bộ trước khi đổi kho.');if(typeof b.path!=='string'||!b.path.trim())throw Error('Chọn thư mục lưu.');
  const path=resolve(b.path);mkdirSync(path,{recursive:true});const probe=join(path,'.kinnect-write-'+randomBytes(6).toString('hex'));writeFileSync(probe,'test',{flag:'wx'});const {unlinkSync}=await import('node:fs');unlinkSync(probe);
  const next=new MediaStore(path);store?.close();store=next;config.root=path;save();return json(res,200,{ok:true});
 }
 if(req.url==='/source'){if(enabled||busy)throw Error('Tạm dừng trước khi đổi nguồn.');if(b.path&&(!existsSync(resolve(b.path))||!statSync(resolve(b.path)).isFile()))throw Error('Không tìm thấy database nguồn.');config.source=b.path?resolve(b.path):null;save();return json(res,200,{ok:true});}
 if(req.url==='/pairing')return json(res,200,{id:store?.nodeId,key:config.syncKey,port:3129});
 if(req.url==='/peer'){if(!store)throw Error('Chọn kho lưu trước.');const url=peerUrl(b.url);if(!/^[a-f0-9]{64}$/.test(b.key))throw Error('Mã ghép nối không hợp lệ.');const r=await fetch(url+'/sync/identity',{headers:{Authorization:'Bearer '+b.key},signal:AbortSignal.timeout(5000),redirect:'error'});if(!r.ok)throw Error('Không kết nối được. Kiểm tra địa chỉ và mã.');const p=await r.json();if(!/^[-a-zA-Z0-9]{1,80}$/.test(p.nodeId)||p.nodeId===store.nodeId)throw Error('Máy ghép nối không hợp lệ.');config.peers=config.peers.filter(x=>x.id!==p.nodeId);config.peers.push({id:p.nodeId,url,key:b.key});save();return json(res,200,{ok:true});}
 if(req.url==='/network'){await network(b.enabled===true);return json(res,200,{ok:true});}
 if(req.url==='/toggle'){if(!store)throw Error('Chọn thư mục lưu trước.');enabled=b.enabled===true;config.enabled=enabled;save();void cycle();return json(res,200,{ok:true});}
 if(req.url==='/sync'){if(!store||!enabled)throw Error('Bật đồng bộ trước.');void cycle();return json(res,200,{ok:true});}
 json(res,404,{});
}catch(e){json(res,400,{error:e.message||'Chưa thực hiện được.'});}});
local.listen(adminPort,'127.0.0.1',()=>{writeFileSync(join(home,'manager.pid'),String(process.pid));console.log('Kinnect Media Manager ready.');});
if(config.network)await network(true);setInterval(()=>void cycle(),30000).unref();void cycle();
