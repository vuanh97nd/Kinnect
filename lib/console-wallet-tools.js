import {ensureWalletCreditMirror,stageWalletCredits} from './wallet-credit-mirror.js';
import {randomUUID} from 'node:crypto';
import {walletDraft,walletSummary,walletFailure as fail,walletTTL,verifyWalletTargets} from './wallet-operation-model.js';
export function createConsoleWalletTools({db,authority,clock=Date.now,replicateCredits=true}){
 db.exec(`CREATE TABLE IF NOT EXISTS console_wallet_operations(id TEXT PRIMARY KEY,kind TEXT NOT NULL,title TEXT NOT NULL,coins INTEGER NOT NULL,targets TEXT NOT NULL,state TEXT NOT NULL,created_by TEXT NOT NULL,approved_by TEXT,reference TEXT NOT NULL,reason TEXT NOT NULL,ticket_id TEXT NOT NULL DEFAULT '',created INTEGER NOT NULL,completed INTEGER,rejection_reason TEXT);
 CREATE UNIQUE INDEX IF NOT EXISTS console_wallet_reference ON console_wallet_operations(reference) WHERE kind='paid_correction' AND state IN ('pending','done');
 CREATE TABLE IF NOT EXISTS wallet_entries(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,reference TEXT NOT NULL,kind TEXT NOT NULL,coins INTEGER NOT NULL DEFAULT 0,net_vnd INTEGER NOT NULL DEFAULT 0,creator_vnd INTEGER NOT NULL DEFAULT 0,platform_vnd INTEGER NOT NULL DEFAULT 0,created INTEGER NOT NULL,UNIQUE(user_id,reference));
 CREATE TABLE IF NOT EXISTS console_audit(id TEXT PRIMARY KEY,actor TEXT NOT NULL,action TEXT NOT NULL,target TEXT,created INTEGER NOT NULL);`);
 ensureWalletCreditMirror(db);
 db.exec('CREATE TABLE IF NOT EXISTS console_wallet_sync_operations(id TEXT PRIMARY KEY,created INTEGER NOT NULL,synced INTEGER)');
 const get=(s,...v)=>db.prepare(s).get(...v),all=(s,...v)=>db.prepare(s).all(...v);
 const canSee=(r,me)=>r&&(me.role==='admin'||r.created_by===me.username);
 const detail=(id,me)=>{const r=get('SELECT * FROM console_wallet_operations WHERE id=?',id);if(!canSee(r,me))fail(404,'Không tìm thấy đề nghị.');const ids=JSON.parse(r.targets),recipients=ids.map(id=>get('SELECT id,username,name FROM users WHERE id=?',id)||{id,username:'(đã xóa)',name:'Không còn tồn tại'});return{operation:walletSummary(r,clock()),recipients};};
 const local={
  people(q){const values=['%'+q+'%','%'+q+'%'];return{people:all("SELECT id,username,name FROM users WHERE suspended=0 AND role='user' AND (username LIKE ? OR name LIKE ?) ORDER BY username LIMIT 50",...values),total:get("SELECT count(*) n FROM users WHERE suspended=0 AND role='user'").n};},
  list(me){return{operations:(me.role==='admin'?all('SELECT * FROM console_wallet_operations ORDER BY created DESC,rowid DESC LIMIT 100'):all('SELECT * FROM console_wallet_operations WHERE created_by=? ORDER BY created DESC,rowid DESC LIMIT 100',me.username)).map(r=>walletSummary(r,clock())),canApprove:me.role==='admin'};},
  detail,
  preview(draft,me){db.exec('BEGIN IMMEDIATE');try{
   const people=draft.all?all("SELECT id,username,name FROM users WHERE suspended=0 AND role='user' ORDER BY id LIMIT 10001"):draft.userIds.map(id=>get("SELECT id,username,name FROM users WHERE id=? AND suspended=0 AND role='user'",id)).filter(Boolean);verifyWalletTargets(draft,people);
   if(draft.kind==='paid_correction'){
    db.prepare("UPDATE console_wallet_operations SET state='expired' WHERE kind='paid_correction' AND reference=? AND state='pending' AND created<?").run(draft.reference,clock()-walletTTL('paid_correction'));
    if(get("SELECT id FROM console_wallet_operations WHERE kind='paid_correction' AND reference=? AND state IN ('pending','done')",draft.reference)||get("SELECT id FROM wallet_entries WHERE kind='coin_purchase' AND (lower(reference)=? OR lower(reference)=?)",draft.reference,'console-paid:'+draft.reference))fail(409,'Mã giao dịch đã có đề nghị hoặc đã được ghi nhận. Hãy đối soát trước khi tạo lại.');
   }
   if(draft.ticketId&&!get('SELECT id FROM console_tickets WHERE id=?',draft.ticketId))fail(400,'Không tìm thấy phiếu phối hợp.');
   const row={...draft,targets:JSON.stringify(people.map(p=>p.id)),state:'pending',created_by:me.username,approved_by:null,ticket_id:draft.ticketId,created:clock(),completed:null};
   db.prepare('INSERT INTO console_wallet_operations(id,kind,title,coins,targets,state,created_by,approved_by,reference,reason,ticket_id,created,completed,rejection_reason) VALUES(?,?,?,?,?,?,?,NULL,?,?,?,?,NULL,NULL)').run(row.id,row.kind,row.title,row.coins,row.targets,row.state,row.created_by,row.reference,row.reason,row.ticket_id,row.created);db.exec('COMMIT');return{operation:walletSummary(row,clock()),recipients:people,expiresIn:walletTTL(row.kind)/1000};
  }catch(e){if(db.isTransaction)db.exec('ROLLBACK');throw e;}},
  confirm(id,me){db.exec('BEGIN IMMEDIATE');try{
   const row=get('SELECT * FROM console_wallet_operations WHERE id=?',id);if(!row)fail(404,'Không tìm thấy lượt xử lý.');if(row.state==='done'){db.exec('COMMIT');return{operation:walletSummary(row,clock()),duplicate:true};}if(walletSummary(row,clock()).state!=='pending')fail(409,'Đề nghị đã kết thúc hoặc hết hạn.');
   const ids=JSON.parse(row.targets);for(const id of ids)if(!get("SELECT id FROM users WHERE id=? AND suspended=0 AND role='user'",id))fail(409,'Có tài khoản đã thay đổi trạng thái. Chưa cộng xu cho ai.');
   if(row.kind==='paid_correction'&&get("SELECT id FROM wallet_entries WHERE kind='coin_purchase' AND (lower(reference)=? OR lower(reference)=?)",row.reference,'console-paid:'+row.reference))fail(409,'Giao dịch đã được ghi nhận; không cộng bù lần nữa.');
   const at=clock(),reference=row.kind==='gift'?'console-gift:'+row.id:'console-paid:'+row.reference;
   for(const id of ids)db.prepare('INSERT INTO wallet_entries(id,user_id,reference,kind,coins,net_vnd,creator_vnd,platform_vnd,created) VALUES(?,?,?,?,?,0,0,0,?)').run(randomUUID(),id,reference,row.kind==='gift'?'admin_trial':'coin_purchase',row.coins,at);
   db.prepare("UPDATE console_wallet_operations SET state='done',approved_by=?,completed=? WHERE id=?").run(me.username,at,id);db.exec('COMMIT');return{operation:walletSummary({...row,state:'done',approved_by:me.username,completed:at},clock()),duplicate:false};
  }catch(e){if(db.isTransaction)db.exec('ROLLBACK');throw e;}},
  reject(id,reason,me){const row=get('SELECT * FROM console_wallet_operations WHERE id=?',id);if(!row)fail(404,'Không tìm thấy đề nghị.');if(walletSummary(row,clock()).state!=='pending')fail(409,'Đề nghị không còn chờ duyệt.');db.prepare("UPDATE console_wallet_operations SET state='rejected',approved_by=?,completed=?,rejection_reason=? WHERE id=? AND state='pending'").run(me.username,clock(),reason,id);return detail(id,me);}
 };
 async function mirrorCompleted(id,result){
  if(!authority||!replicateCredits)return;
  if(!Array.isArray(result.ledger))fail(503,'Chưa đọc được sổ cái nguồn để đồng bộ. Hãy kiểm tra lại cùng mã thao tác.');
  const entries=result.ledger.map(e=>({id:e.id,user_id:e.user_id,reference:e.reference,kind:e.kind,coins:Number(e.coins),net_vnd:Number(e.net_vnd),creator_vnd:Number(e.creator_vnd),platform_vnd:Number(e.platform_vnd),created:Number(e.created)}));
  db.exec('SAVEPOINT console_wallet_sync');try{stageWalletCredits(db,entries);db.prepare('UPDATE console_wallet_sync_operations SET synced=? WHERE id=?').run(clock(),id);db.exec('RELEASE SAVEPOINT console_wallet_sync');}catch(e){db.exec('ROLLBACK TO SAVEPOINT console_wallet_sync');db.exec('RELEASE SAVEPOINT console_wallet_sync');throw Object.assign(new Error('Sổ cái nguồn đã ghi nhận, chưa xác nhận đồng bộ về app. Hãy thử lại cùng mã thao tác.'),{status:503});}
 }
 async function recoverCredits(){
  if(!authority||!replicateCredits)return;
  const pending=all('SELECT id FROM console_wallet_sync_operations WHERE synced IS NULL ORDER BY created LIMIT 20');
  for(const row of pending){
   const result=await authority.walletOperations.credits(row.id);
   if(result.state==='done')await mirrorCompleted(row.id,result);
   else if(['rejected','expired','missing'].includes(result.state))db.prepare('UPDATE console_wallet_sync_operations SET synced=? WHERE id=?').run(clock(),row.id);
  }
 }
 const route=async function route({path,method,body={},url,me}){
  if(!path.startsWith('/wallet-tools'))return null;
  if(me.role!=='admin'&&me.team!=='finance')fail(403,'Chỉ Admin và bộ phận tài chính được truy cập nghiệp vụ ví.');
  const repository=authority?authority.walletOperations:local;
  if(path==='/wallet-tools'&&method==='GET'){const history=await repository.list(me);if(authority&&replicateCredits)for(const op of history.operations.filter(o=>o.state==='done'))db.prepare('INSERT OR IGNORE INTO console_wallet_sync_operations VALUES(?,?,NULL)').run(op.id,clock());await recoverCredits();return history;}
  if(path==='/wallet-tools/people'&&method==='GET')return await repository.people(String(url.searchParams.get('q')||'').trim().slice(0,80));
  if(path==='/wallet-tools/preview'&&method==='POST'){
   const draft=walletDraft(body,me);if(draft.ticketId){const t=get('SELECT id FROM console_tickets WHERE id=?',draft.ticketId);if(!t)fail(400,'Không tìm thấy phiếu phối hợp.');if(me.role!=='admin'&&!get('SELECT 1 FROM console_ticket_teams WHERE ticket_id=? AND team=?',draft.ticketId,me.team))fail(404,'Không tìm thấy phiếu trong nhóm của bạn.');}
   const result=await repository.preview(draft,me);db.prepare('INSERT INTO console_audit VALUES(?,?,?,?,?)').run(randomUUID(),me.username,'wallet-preview:'+draft.kind,result.operation.id,clock());return result;
  }
  if(['/wallet-tools/confirm','/wallet-tools/reject'].includes(path)&&method==='POST'){
   if(me.role!=='admin')fail(403,'Chỉ Admin được duyệt hoặc từ chối điều chỉnh ví.');if(typeof body.id!=='string'||body.id.length>100)fail(400,'Thiếu mã lượt xử lý.');
   const reason=typeof body.reason==='string'?body.reason.trim():'';if(path.endsWith('/reject')&&(reason.length<5||reason.length>1000))fail(400,'Nhập lý do từ chối 5–1.000 ký tự.');
   if(authority&&replicateCredits&&path.endsWith('/confirm'))db.prepare('INSERT OR IGNORE INTO console_wallet_sync_operations VALUES(?,?,NULL)').run(body.id,clock());
   const result=path.endsWith('/confirm')?await repository.confirm(body.id,me):await repository.reject(body.id,reason,me);
   if(authority&&replicateCredits&&path.endsWith('/confirm'))await mirrorCompleted(body.id,result);
   db.prepare('INSERT INTO console_audit VALUES(?,?,?,?,?)').run(randomUUID(),me.username,path.endsWith('/confirm')?'wallet-confirm':'wallet-reject',body.id,clock());const {ledger,...response}=result;return response;
  }
  const match=/^\/wallet-tools\/([a-f0-9-]{36})$/.exec(path);if(match&&method==='GET')return await repository.detail(match[1],me);
  fail(404,'Không tìm thấy nghiệp vụ ví.');
 };
 const recoveryTimer=replicateCredits&&authority?.walletOperations?.credits?setInterval(()=>recoverCredits().catch(()=>console.error('Console wallet replica recovery unavailable; pending work retained.')),60000):null;
 recoveryTimer?.unref();if(recoveryTimer)queueMicrotask(()=>recoverCredits().catch(()=>console.error('Console wallet replica recovery unavailable; pending work retained.')));
 route.close=()=>clearInterval(recoveryTimer);
 return route;
}
