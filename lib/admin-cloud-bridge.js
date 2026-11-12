import {existsSync,readFileSync} from 'node:fs';
import {createHash,timingSafeEqual} from 'node:crypto';
import {consoleSnapshot} from '../cloud-admin/export.js';
import {tableKeys} from '../cloud-admin/schema.js';
import {restoreReputation,deductReputation} from './ai-violation-reporter.js';
export function createAdminCloudBridge(social,{dispatch,connection,fetchImpl=fetch,automatic=true,appStatus}={}){
 if(!connection&&(process.env.NODE_TEST_CONTEXT||!existsSync('private/admin-cloud.json')))return null;
 const config=connection||JSON.parse(readFileSync('private/admin-cloud.json','utf8')),db=social.db,principalKey=Symbol('cloud-console-principal');
 if(!config.secret||config.secret.length<32||new URL(config.origin).protocol!=='https:')throw Error('Invalid cloud console connection');
 const digest=v=>createHash('sha256').update(v).digest();
 const authorized=req=>timingSafeEqual(digest(req.headers.authorization||''),digest('Bearer '+config.secret));
 const cloud=async(path,body)=>{const r=await fetchImpl(config.origin+'/_internal/'+path,{method:body===undefined?'GET':'POST',headers:{Authorization:'Bearer '+config.secret,'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(60000)});if(!r.ok)throw Error('Cloud console synchronization unavailable');return r.json();};
 db.exec('CREATE TABLE IF NOT EXISTS console_cloud_applied(id TEXT PRIMARY KEY,applied INTEGER NOT NULL)');
 function apply(event){
  if(db.prepare('SELECT 1 FROM console_cloud_applied WHERE id=?').get(event.id))return;
  db.exec('BEGIN IMMEDIATE');try{
   if(['hide-post','show-post','hide-short','show-short','close-report'].includes(event.action))applyModerationNested(event);
   else if(['reputation-restore','reputation-deduct'].includes(event.action)){
    const p=event.payload;if(!p||!Number.isInteger(p.points)||p.points<1||p.points>100)throw Error('Invalid reputation event');
    const nested={prepare:sql=>db.prepare(sql),exec:sql=>{if(/^(BEGIN IMMEDIATE|COMMIT)$/.test(sql.trim()))return;if(/^ROLLBACK/.test(sql))throw Error('Reputation rollback');return db.exec(sql);}};
    (event.action==='reputation-restore'?restoreReputation:deductReputation)(nested,{userId:event.target,points:p.points,reason:p.reason,actor:p.actor});
   }else if(event.action==='reset-status'){
    if(!['done','dismissed'].includes(event.payload?.status))throw Error('Invalid reset state');
    db.prepare('UPDATE password_resets SET status=?,handled=? WHERE id=?').run(event.payload.status,event.payload.handled,event.target);
   }else throw Error('Unsupported cloud action');
   db.prepare('INSERT INTO console_cloud_applied VALUES(?,?)').run(event.id,Date.now());db.exec('COMMIT');
  }catch(e){db.exec('ROLLBACK');throw e;}
 }
 function applyModerationNested(event){
  const table=event.action.endsWith('-post')?'posts':event.action.endsWith('-short')?'shorts':'reports';
  if(!db.prepare('SELECT id FROM '+table+' WHERE id=?').get(event.target))return; // target was already deleted
  if(table==='reports')db.prepare("UPDATE reports SET status='closed' WHERE id=?").run(event.target);
  else db.prepare('UPDATE '+table+' SET hidden=? WHERE id=?').run(event.action.startsWith('hide-')?1:0,event.target);
 }
 let busy=false,lastSuccess=0,lastError=null;const signatures=new Map(),pruned=new Map();
 let pulling=null;
 function pullActions(){if(pulling)return pulling;pulling=(async()=>{for(let batch=0;batch<20;batch++){const {actions}=await cloud('actions',{});if(!actions.length)return;for(const action of actions)apply(action);await cloud('ack',{ids:actions.map(x=>x.id)});if(actions.length<100)return;}throw Error('Cloud changes still queued');})().finally(()=>{pulling=null;});return pulling;}
 async function sync(){if(busy)return;busy=true;try{
  if(!(await cloud('status')).ready)return;
  await pullActions();
  const snapshot=consoleSnapshot(db);
  for(const table of snapshot.tables){const signature=createHash('sha256').update(JSON.stringify(table)).digest('hex');if(signatures.get(table.name)===signature)continue;let rows=[],size=0;for(const row of table.rows){const bytes=JSON.stringify(row).length;if(rows.length&&(size+bytes>400000||rows.length>=100)){await cloud('replica',{tables:[{...table,rows}]});rows=[];size=0;}rows.push(row);size+=bytes;}if(rows.length)await cloud('replica',{tables:[{...table,rows}]});signatures.set(table.name,signature);}
  for(const table of [...snapshot.tables].reverse()){const signature=signatures.get(table.name);if(pruned.get(table.name)===signature)continue;const columns=tableKeys(db,table.name).map(c=>table.columns.indexOf(c));if(columns.length)await cloud('prune',{table:table.name,keys:table.rows.map(row=>columns.map(i=>row[i]))});pruned.set(table.name,signature);}
  await cloud('replica',{tables:[]});
  lastSuccess=Date.now();lastError=null;
 }catch{lastError='Cloud console replica is retrying';}finally{busy=false;}}
 const timer=automatic?setInterval(sync,30000):null;timer?.unref();if(automatic)setTimeout(sync,1500).unref();
 async function handle(req,res){const path=new URL(req.url,'http://localhost').pathname;if(path!=='/internal/admin/action'&&path!=='/internal/admin/status')return false;
  const send=(status,data)=>{res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify(data));return true;};
  if(path==='/internal/admin/status'){if(req.method!=='GET'||!authorized(req))return send(401,{error:'Unauthorized'});return send(200,appStatus?appStatus():{ok:true});}
  if(req.method!=='POST'||!authorized(req))return send(401,{error:'Unauthorized'});
  let input;try{const chunks=[];let size=0;for await(const c of req){size+=c.length;if(size>8192)throw Error();chunks.push(c);}input=JSON.parse(Buffer.concat(chunks).toString());}catch{return send(400,{error:'Invalid action'});}
  const me=input.actor,allowed=['toggle-maintenance','purge-cache','optimize-db','check-integrity','flush-ai-queue','toggle-ai-moderation','toggle-ai-support','restart-server'];
  if(!me||!['admin','support'].includes(me.role)||me.role!=='admin'&&me.team!=='operations'||!allowed.includes(input.action))return send(403,{error:'Forbidden'});
  const bytes=Buffer.from(JSON.stringify({action:input.action}));
  const proxy={method:'POST',url:'/api/console/operations/action',headers:{host:'admin.kinnect.io.vn',origin:'https://admin.kinnect.io.vn'},socket:req.socket,[principalKey]:me,async *[Symbol.asyncIterator](){yield bytes;}};
  return dispatch(proxy,res);
 }
 return{handle,trustedPrincipal:req=>req[principalKey],close:()=>clearInterval(timer),sync,pullActions,status:()=>({lastSuccess,lastError})};
}
