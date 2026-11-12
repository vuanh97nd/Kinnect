import {randomUUID} from 'node:crypto';
import {walletFailure as fail,walletSummary,walletTTL,verifyWalletTargets} from './wallet-operation-model.js';
export const CONSOLE_WALLET_SCHEMA=`CREATE TABLE IF NOT EXISTS kinnect_core.console_wallet_operations(
 id text PRIMARY KEY,kind text NOT NULL CHECK(kind IN ('gift','paid_correction')),title text NOT NULL,
 coins bigint NOT NULL CHECK(coins BETWEEN 1 AND 1000000),targets text NOT NULL,
 state text NOT NULL CHECK(state IN ('pending','done','rejected','expired')),created_by text NOT NULL,approved_by text,
 reference text NOT NULL,reason text NOT NULL,ticket_id text NOT NULL DEFAULT '',created bigint NOT NULL,completed bigint,rejection_reason text);
 CREATE UNIQUE INDEX IF NOT EXISTS console_wallet_reference ON kinnect_core.console_wallet_operations(reference) WHERE kind='paid_correction' AND state IN ('pending','done');
 ALTER TABLE kinnect_core.console_wallet_operations ENABLE ROW LEVEL SECURITY;`;
export function createPostgresWalletOperations({query,transaction,clock=Date.now,schemaManaged=false}){
 let initialized;
 const ensure=()=>initialized||(initialized=(schemaManaged?query('SELECT id FROM kinnect_core.console_wallet_operations LIMIT 0'):transaction(async c=>{await c.query(CONSOLE_WALLET_SCHEMA);})).catch(e=>{initialized=null;throw e;}));
 const canSee=(r,me)=>r&&(me.role==='admin'||r.created_by===me.username);
 const detail=async(id,me)=>{
  await ensure();const row=(await query('SELECT * FROM kinnect_core.console_wallet_operations WHERE id=$1',[id])).rows[0];if(!canSee(row,me))fail(404,'Không tìm thấy đề nghị.');
  const ids=JSON.parse(row.targets),people=(await query('SELECT id,username,name FROM kinnect_core.users WHERE id=ANY($1::text[])',[ids])).rows;
  return{operation:walletSummary(row,clock()),recipients:ids.map(id=>people.find(p=>p.id===id)||{id,username:'(đã xóa)',name:'Không còn tồn tại'})};
 };
 return {
  ensure,
  async people(q){const [people,total]=await Promise.all([query("SELECT id,username,name FROM kinnect_core.users WHERE suspended=0 AND role='user' AND (username ILIKE $1 OR name ILIKE $1) ORDER BY username LIMIT 50",['%'+q+'%']),query("SELECT count(*)::int AS n FROM kinnect_core.users WHERE suspended=0 AND role='user'")]);return{people:people.rows,total:total.rows[0].n};},
  async list(me){await ensure();const rows=me.role==='admin'?await query('SELECT * FROM kinnect_core.console_wallet_operations ORDER BY created DESC,id LIMIT 100'):await query('SELECT * FROM kinnect_core.console_wallet_operations WHERE created_by=$1 ORDER BY created DESC,id LIMIT 100',[me.username]);return{operations:rows.rows.map(r=>walletSummary(r,clock())),canApprove:me.role==='admin'};},
  detail,
  async preview(draft,me){await ensure();return transaction(async c=>{
   const people=(await c.query(draft.all?"SELECT id,username,name FROM kinnect_core.users WHERE suspended=0 AND role='user' ORDER BY id LIMIT 10001 FOR SHARE":"SELECT id,username,name FROM kinnect_core.users WHERE id=ANY($1::text[]) AND suspended=0 AND role='user' ORDER BY id FOR SHARE",draft.all?[]:[draft.userIds])).rows;verifyWalletTargets(draft,people);
   if(draft.kind==='paid_correction'){
    await c.query('SELECT pg_advisory_xact_lock(hashtext($1))',['console-paid:'+draft.reference]);
    await c.query("UPDATE kinnect_core.console_wallet_operations SET state='expired' WHERE kind='paid_correction' AND reference=$1 AND state='pending' AND created<$2",[draft.reference,clock()-walletTTL('paid_correction')]);
    const prior=(await c.query("SELECT id FROM kinnect_core.console_wallet_operations WHERE kind='paid_correction' AND reference=$1 AND state IN ('pending','done')",[draft.reference])).rows[0];
    const booked=(await c.query("SELECT id FROM kinnect_core.wallet_entries WHERE kind='coin_purchase' AND lower(reference)=ANY($1::text[]) LIMIT 1",[[draft.reference,'console-paid:'+draft.reference]])).rows[0];
    if(prior||booked)fail(409,'Mã giao dịch đã có đề nghị hoặc đã được ghi nhận. Hãy đối soát trước khi tạo lại.');
   }
   const row={...draft,targets:JSON.stringify(people.map(p=>p.id)),state:'pending',created_by:me.username,approved_by:null,ticket_id:draft.ticketId,created:clock(),completed:null};
   try{await c.query('INSERT INTO kinnect_core.console_wallet_operations(id,kind,title,coins,targets,state,created_by,approved_by,reference,reason,ticket_id,created,completed) VALUES($1,$2,$3,$4,$5,$6,$7,NULL,$8,$9,$10,$11,NULL)',[row.id,row.kind,row.title,row.coins,row.targets,row.state,row.created_by,row.reference,row.reason,row.ticket_id,row.created]);}catch(e){if(e.code==='23505')fail(409,'Mã giao dịch đã được tiếp nhận trước đó.');throw e;}
   return{operation:walletSummary(row,clock()),recipients:people,expiresIn:walletTTL(row.kind)/1000};
  });},
  async credits(id){await ensure();const row=(await query('SELECT * FROM kinnect_core.console_wallet_operations WHERE id=$1',[id])).rows[0];if(!row)return{state:'missing',ledger:[]};if(walletSummary(row,clock()).state!=='done')return{state:walletSummary(row,clock()).state,ledger:[]};const ids=JSON.parse(row.targets),reference=row.kind==='gift'?'console-gift:'+row.id:'console-paid:'+row.reference;const entries=(await query('SELECT * FROM kinnect_core.wallet_entries WHERE reference=$1 AND user_id=ANY($2::text[]) ORDER BY user_id',[reference,ids])).rows;if(entries.length!==ids.length)fail(503,'Sổ cái nguồn chưa khớp; cần đối soát trước khi đồng bộ.');return{state:'done',ledger:entries};},
  async confirm(id,me){await ensure();return transaction(async c=>{
   const row=(await c.query('SELECT * FROM kinnect_core.console_wallet_operations WHERE id=$1 FOR UPDATE',[id])).rows[0];if(!row)fail(404,'Không tìm thấy lượt xử lý.');
   const ids=JSON.parse(row.targets),reference=row.kind==='gift'?'console-gift:'+row.id:'console-paid:'+row.reference;
   if(row.state==='done'){const entries=(await c.query('SELECT * FROM kinnect_core.wallet_entries WHERE reference=$1 AND user_id=ANY($2::text[]) ORDER BY user_id',[reference,ids])).rows;if(entries.length!==ids.length)fail(503,'Cần đối soát sổ cái trước khi thử lại.');return{operation:walletSummary(row,clock()),duplicate:true,ledger:entries};}
   if(walletSummary(row,clock()).state!=='pending')fail(409,'Đề nghị đã kết thúc hoặc hết hạn.');
   const users=(await c.query("SELECT id FROM kinnect_core.users WHERE id=ANY($1::text[]) AND suspended=0 AND role='user' ORDER BY id FOR UPDATE",[ids])).rows;if(users.length!==ids.length)fail(409,'Có tài khoản đã thay đổi trạng thái. Chưa cộng xu cho ai.');
   if(row.kind==='paid_correction'){
    await c.query('SELECT pg_advisory_xact_lock(hashtext($1))',[reference]);
    if((await c.query("SELECT id FROM kinnect_core.wallet_entries WHERE kind='coin_purchase' AND lower(reference)=ANY($1::text[]) LIMIT 1",[[row.reference,reference]])).rows.length)fail(409,'Giao dịch đã được ghi nhận; không cộng bù lần nữa.');
   }
   const at=clock(),ledger=[];
   for(const userId of ids){const entry={id:randomUUID(),user_id:userId,reference,kind:row.kind==='gift'?'admin_trial':'coin_purchase',coins:Number(row.coins),net_vnd:0,creator_vnd:0,platform_vnd:0,created:at};await c.query('INSERT INTO kinnect_core.wallet_entries(id,user_id,reference,kind,coins,net_vnd,creator_vnd,platform_vnd,created) VALUES($1,$2,$3,$4,$5,0,0,0,$6)',[entry.id,entry.user_id,entry.reference,entry.kind,entry.coins,entry.created]);ledger.push(entry);}
   await c.query("UPDATE kinnect_core.console_wallet_operations SET state='done',approved_by=$1,completed=$2 WHERE id=$3",[me.username,at,id]);
   return{operation:walletSummary({...row,state:'done',approved_by:me.username,completed:at},clock()),duplicate:false,ledger};
  });},
  async reject(id,reason,me){await ensure();await transaction(async c=>{const row=(await c.query('SELECT * FROM kinnect_core.console_wallet_operations WHERE id=$1 FOR UPDATE',[id])).rows[0];if(!row)fail(404,'Không tìm thấy đề nghị.');if(walletSummary(row,clock()).state!=='pending')fail(409,'Đề nghị không còn chờ duyệt.');await c.query("UPDATE kinnect_core.console_wallet_operations SET state='rejected',approved_by=$1,completed=$2,rejection_reason=$3 WHERE id=$4",[me.username,clock(),reason,id]);});return detail(id,me);}
 };
}
