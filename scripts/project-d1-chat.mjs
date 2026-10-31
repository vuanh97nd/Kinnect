import {DatabaseSync} from 'node:sqlite';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {execFileSync} from 'node:child_process';
import {sha256,sqlText} from './chat-import-data.mjs';
if(!process.argv[2])throw Error('Consistent SQLite snapshot required');
const snapshot=resolve(process.argv[2]),db=new DatabaseSync(snapshot,{readOnly:true});
const cli=args=>execFileSync(process.execPath,[resolve(dirname(process.execPath),'node_modules/npm/bin/npx-cli.js'),'--yes','wrangler','d1','execute','kinnect-chat','--remote','--config','cloud-chat/wrangler.jsonc',...args],{encoding:'utf8',windowsHide:true,maxBuffer:32*1024*1024,stdio:['ignore','pipe','pipe']});
const query=sql=>JSON.parse(cli(['--command',sql,'--json'])).flatMap(x=>x.results||[]);
const read=table=>db.prepare('SELECT * FROM '+table).all();
const statements=[];
const insert=(table,row)=>statements.push('INSERT INTO '+table+'('+Object.keys(row).join(',')+') VALUES('+Object.values(row).map(x=>x===null?'NULL':typeof x==='number'?String(x):sqlText(x)).join(',')+');');
const directId=(a,b)=>'dm-'+sha256(JSON.stringify([a,b].sort())).slice(0,32);
try{
 if(query('SELECT COUNT(*) n FROM chat_messages')[0].n||query('SELECT COUNT(*) n FROM chat_conversations')[0].n)throw Error('Nonempty target; refuses overwrite');
 const messages=read('messages'),groups=read('chat_groups'),groupMessages=read('group_messages'),members=read('group_members');
 const allMessages=new Map([...messages,...groupMessages].map(m=>[m.id,m]));
 const pairs=new Map();
 for(const m of messages){const pair=[m.sender,m.recipient].sort(),id=directId(...pair);if(!pairs.has(id))pairs.set(id,{pair,created:m.created});else pairs.get(id).created=Math.min(pairs.get(id).created,m.created);}
 for(const [id,{pair,created}]of pairs){insert('chat_conversations',{id,kind:'direct',direct_pair:JSON.stringify(pair),name:'',created_by:pair[0],created_at:created});for(const uid of [...new Set(pair)])insert('chat_members',{conversation_id:id,user_id:uid,role:'member',joined_at:0,left_at:null});}
 const deputies=new Set(read('group_deputies').map(x=>x.group_id+':'+x.user_id));
 for(const g of groups){insert('chat_conversations',{id:g.id,kind:'group',direct_pair:null,name:g.name,created_by:g.owner,created_at:g.created});for(const m of members.filter(m=>m.group_id===g.id))insert('chat_members',{conversation_id:g.id,user_id:m.user_id,role:m.user_id===g.owner?'owner':deputies.has(g.id+':'+m.user_id)?'deputy':'member',joined_at:m.joined,left_at:null});}
 const recalls=new Map(read('recalled_chat_messages').map(x=>[x.message_id,x.created]));
 for(const m of [...messages,...groupMessages])insert('chat_messages',{id:m.id,conversation_id:m.group_id||directId(m.sender,m.recipient),sender_id:m.sender,client_nonce:'legacy_'+m.id,body:recalls.has(m.id)?'':m.body,kind:'text',attachment_key:null,reply_to:null,created_at:m.created,edited_at:null,recalled_at:recalls.get(m.id)||null});
 let receipts=0;
 const receipt=(r,uid)=>{if(!allMessages.has(r.message_id))return;const delivered=r.seen_at!==null?Math.min(r.delivered_at??r.seen_at,r.seen_at):r.delivered_at;insert('chat_receipts',{message_id:r.message_id,user_id:uid,delivered_at:delivered,seen_at:r.seen_at});receipts++;};
 for(const r of read('message_receipts')){const m=allMessages.get(r.message_id);if(m)receipt(r,m.recipient);}
 for(const r of read('group_message_receipts'))receipt(r,r.user_id);
 let hidden=0,reactions=0;
 for(const row of read('hidden_chat_messages'))if(allMessages.has(row.message_id)){insert('chat_hidden_messages',{message_id:row.message_id,user_id:row.user_id});hidden++;}
 for(const row of read('chat_message_reactions'))if(allMessages.has(row.message_id)&&!recalls.has(row.message_id)){insert('chat_reactions',{message_id:row.message_id,user_id:row.user_id,reaction:row.reaction});reactions++;}
 for(const row of read('pinned_chat_messages'))if(allMessages.has(row.message_id)&&!recalls.has(row.message_id))insert('chat_pins',{message_id:row.message_id,pinned_by:row.pinned_by});
 const preferences=new Map();
 for(const [table,key]of [['hidden_conversations','hidden'],['muted_conversations','muted'],['pinned_conversations','pinned'],['manual_unread_conversations','unread']])for(const row of read(table)){
  const id=row.kind==='group'?row.conversation_id:directId(row.user_id,row.conversation_id);if(row.kind==='direct'&&!pairs.has(id))continue;
  const pkey=id+':'+row.user_id;if(!preferences.has(pkey))preferences.set(pkey,{conversation_id:id,user_id:row.user_id,hidden:0,muted:0,pinned:0,unread:0});preferences.get(pkey)[key]=1;
 }
 for(const row of preferences.values())insert('chat_preferences',row);
 let attachments=0;
 for(const row of read('chat_attachments'))if(allMessages.has(row.message_id)&&!recalls.has(row.message_id)){
  insert('chat_attachment_refs',{id:row.id,message_id:row.message_id,name:row.name,mime_type:row.type,byte_size:row.data.byteLength,source_sha256:sha256(row.data),local_key:row.kind+'/'+row.message_id+'/'+row.id});attachments++;
 }
 const file=resolve(dirname(snapshot),'d1-chat-runtime.sql');writeFileSync(file,statements.join('\n'),{mode:0o600});
 const sid=execFileSync('whoami.exe',['/user','/fo','csv','/nh'],{encoding:'utf8',windowsHide:true}).match(/S-1-\d+(?:-\d+)+/)?.[0];if(!sid)throw Error('ACL');execFileSync('icacls.exe',[file,'/inheritance:r','/grant:r',`*${sid}:(F)`],{stdio:'pipe',windowsHide:true});
 cli(['--file',file,'--yes']);
 const actual=query('SELECT id,body,sender_id,conversation_id FROM chat_messages ORDER BY id');
 if(actual.length!==allMessages.size)throw Error('Message count mismatch');
 for(const row of actual){const source=allMessages.get(row.id);if(!source||row.body!==(recalls.has(row.id)?'':source.body)||row.sender_id!==source.sender||row.conversation_id!==(source.group_id||directId(source.sender,source.recipient)))throw Error('Message content mismatch');}
 if(query('PRAGMA foreign_key_check').length)throw Error('Foreign key mismatch');
 const report={messages:actual.length,directConversations:pairs.size,groups:groups.length,receipts,hidden,reactions,attachmentRefs:attachments,sourceSha256:sha256(readFileSync(snapshot)),verified:true,productionActivated:false};
 writeFileSync(resolve(dirname(snapshot),'d1-chat-runtime-report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
}catch{console.error('D1 runtime projection failed or remains unverified; app routing unchanged. Do not rerun against nonempty tables.');process.exitCode=1;}
finally{db.close();}
