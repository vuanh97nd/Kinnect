import{DatabaseSync,backup}from'node:sqlite';
import{readFileSync,writeFileSync,mkdirSync,existsSync}from'node:fs';
import{createHash}from'node:crypto';
import pg from'../cloud-api/node_modules/pg/lib/index.js';
import{postgresOptions}from'../lib/cloud-postgres.js';
const parse=file=>Object.fromEntries(readFileSync(file,'utf8').split(/\r?\n/).filter(x=>x&&!x.startsWith('#')).map(x=>{const i=x.indexOf('=');return[x.slice(0,i),x.slice(i+1)];}));
if(existsSync('data/shared-core-enabled.json'))throw Error('Already activated; use a reviewed incremental migration');
const source=new DatabaseSync('data/kinnect.sqlite',{readOnly:true}),core=new pg.Client(postgresOptions(parse('cloud-db.env'))),chat=new pg.Client(postgresOptions(parse('chat-db.env')));
const hash=value=>createHash('sha256').update(value).digest('hex'),pair=(a,b)=>'dm-'+hash(JSON.stringify([a,b].sort())).slice(0,32);
let stage='backup';
try{
 mkdirSync('data/backups',{recursive:true});await backup(source,'data/backups/before-shared-core-'+Date.now()+'.sqlite');
 source.exec('BEGIN');const read=t=>source.prepare('SELECT * FROM '+t).all();
 const users=read('users'),direct=read('messages'),groupMessages=read('group_messages'),all=[...direct,...groupMessages],groups=read('chat_groups'),members=read('group_members');
 stage='identity';await core.connect();await chat.connect();await core.query('BEGIN');await chat.query('BEGIN');
 for(const u of users){
  const previous=(await core.query('SELECT username,password,salt,role,suspended FROM kinnect_core.users WHERE id=$1',[u.id])).rows[0];
  if(previous&&['username','password','salt','role','suspended'].some(k=>previous[k]!==u[k]))throw Error('Identity conflict');
  if(!previous){const{id,username,password,salt,name,role,suspended,created,...profile}=u;for(const[k,v]of Object.entries(profile))if(v instanceof Uint8Array)profile[k]={localMedia:true,userId:id,kind:k};await core.query('INSERT INTO kinnect_core.users VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb)',[id,username,password,salt,name,role,suspended,created,JSON.stringify(profile)]);}
 }
 for(const s of read('sessions').filter(s=>s.expires>Date.now()))await core.query('INSERT INTO kinnect_core.sessions VALUES($1,$2,$3) ON CONFLICT(token_hash) DO NOTHING',[s.token,s.user_id,s.expires]);
 const insert=async(table,row)=>{const keys=Object.keys(row);await chat.query('INSERT INTO kinnect_chat.'+table+'('+keys.join(',')+') VALUES('+keys.map((_,i)=>'$'+(i+1)).join(',')+') ON CONFLICT DO NOTHING',Object.values(row));};
 stage='conversations';const pairs=new Map();for(const m of direct){const id=pair(m.sender,m.recipient);if(!pairs.has(id))pairs.set(id,{ids:[m.sender,m.recipient].sort(),created:m.created});}
 for(const[id,p]of pairs){await insert('chat_conversations',{id,kind:'direct',direct_pair:JSON.stringify(p.ids),name:'',created_by:p.ids[0],created_at:p.created});for(const uid of new Set(p.ids))await insert('chat_members',{conversation_id:id,user_id:uid,role:'member',joined_at:0,left_at:null});}
 const deputies=new Set(read('group_deputies').map(x=>x.group_id+':'+x.user_id));
 for(const g of groups){await insert('chat_conversations',{id:g.id,kind:'group',direct_pair:null,name:g.name,created_by:g.owner,created_at:g.created});for(const m of members.filter(x=>x.group_id===g.id))await insert('chat_members',{conversation_id:g.id,user_id:m.user_id,role:m.user_id===g.owner?'owner':deputies.has(g.id+':'+m.user_id)?'deputy':'member',joined_at:m.joined,left_at:null});}
 stage='messages';const recalls=new Map(read('recalled_chat_messages').map(x=>[x.message_id,x.created]));
 for(const m of all){
  await insert('chat_messages',{id:m.id,conversation_id:m.group_id||pair(m.sender,m.recipient),sender_id:m.sender,client_nonce:'legacy_'+m.id,body:recalls.has(m.id)?'':m.body,kind:'text',attachment_key:null,reply_to:null,created_at:m.created,edited_at:null,recalled_at:recalls.get(m.id)||null});
  const r=(await chat.query('SELECT sender_id,conversation_id FROM kinnect_chat.chat_messages WHERE id=$1',[m.id])).rows[0];if(r.sender_id!==m.sender||r.conversation_id!==(m.group_id||pair(m.sender,m.recipient)))throw Error('Message identity conflict');
  if(recalls.has(m.id))await chat.query('UPDATE kinnect_chat.chat_messages SET body=\'\',recalled_at=COALESCE(recalled_at,$2) WHERE id=$1',[m.id,recalls.get(m.id)]);
 }
 const ids=new Set(all.map(x=>x.id));
 for(const table of ['message_receipts','group_message_receipts'])for(const r of read(table))if(ids.has(r.message_id)){
  const m=all.find(m=>m.id===r.message_id),uid=r.user_id||m.recipient,seen=r.seen_at??null,delivered=seen==null?r.delivered_at??null:Math.min(r.delivered_at??seen,seen);
  await chat.query('INSERT INTO kinnect_chat.chat_receipts VALUES($1,$2,$3,$4) ON CONFLICT(message_id,user_id) DO UPDATE SET delivered_at=COALESCE(kinnect_chat.chat_receipts.delivered_at,excluded.delivered_at),seen_at=COALESCE(kinnect_chat.chat_receipts.seen_at,excluded.seen_at)',[r.message_id,uid,delivered,seen]);
 }
 for(const r of read('hidden_chat_messages'))if(ids.has(r.message_id))await insert('chat_hidden_messages',{message_id:r.message_id,user_id:r.user_id});
 for(const r of read('chat_message_reactions'))if(ids.has(r.message_id)&&!recalls.has(r.message_id))await insert('chat_reactions',{message_id:r.message_id,user_id:r.user_id,reaction:r.reaction});
 stage='verify';const count=Number((await chat.query('SELECT COUNT(*) n FROM kinnect_chat.chat_messages WHERE id=ANY($1::text[])',[[...ids]])).rows[0].n);if(count!==ids.size)throw Error('Message verification failed');
 await core.query('GRANT INSERT,DELETE ON kinnect_core.blocks TO kinnect_api');
 await core.query("DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='kinnect_core' AND tablename='blocks' AND policyname='api_blocks_write') THEN CREATE POLICY api_blocks_write ON kinnect_core.blocks FOR ALL TO kinnect_api USING(true) WITH CHECK(true); END IF; END $$;");
 await chat.query('COMMIT');await core.query('COMMIT');source.exec('ROLLBACK');
 const report={at:new Date().toISOString(),users:users.length,messages:ids.size,groups:groups.length,verified:true,authority:'PostgreSQL',pcBridge:true};
 mkdirSync('data/reports',{recursive:true});writeFileSync('data/reports/shared-core-cutover.json',JSON.stringify(report,null,2));writeFileSync('data/shared-core-enabled.json',JSON.stringify(report));console.log(JSON.stringify(report));
}catch(e){await core.query('ROLLBACK').catch(()=>{});await chat.query('ROLLBACK').catch(()=>{});console.error(JSON.stringify({stage,code:e.code||'CUTOVER_FAILED'}));process.exitCode=1;}finally{source.close();await core.end().catch(()=>{});await chat.end().catch(()=>{});}
