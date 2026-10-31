import {readFileSync,writeFileSync,mkdirSync,openSync,closeSync,renameSync} from 'node:fs';
import {resolve} from 'node:path';
import {execFileSync} from 'node:child_process';
import {createHash,randomUUID} from 'node:crypto';
import {gzipSync,gunzipSync} from 'node:zlib';
import pg from '../cloud-api/node_modules/pg/lib/index.js';
import {postgresOptions} from '../lib/cloud-postgres.js';
const tables=['chat_conversations','chat_members','chat_messages','chat_receipts','chat_hidden_messages','chat_reactions','chat_preferences','chat_pins','chat_attachment_refs'];
let client;try{
 const secret=JSON.parse(readFileSync('chat-api-server.env','utf8'));
 client=new pg.Client(postgresOptions({KINNECT_DATABASE_URL:secret.PG_CONNECTION_STRING,KINNECT_DATABASE_CA_FILE:'data/certificates/supabase-prod-ca-2021.crt'}));
 await client.connect();await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
 const snapshot={format:'kinnect-chat-backup-v1',project:'mmxqhcngrejxyhhfirzo',created:new Date().toISOString(),tables:{}};
 for(const table of tables)snapshot.tables[table]=(await client.query('SELECT * FROM kinnect_chat.'+table)).rows;
 await client.query('COMMIT');
 const raw=Buffer.from(JSON.stringify(snapshot)),compressed=gzipSync(raw);
 if(!gunzipSync(compressed).equals(raw))throw Error('Backup verification failed');
 const directory=resolve('data/backups/chat-postgres');mkdirSync(directory,{recursive:true});
 const name='chat-'+Date.now()+'-'+randomUUID()+'.json.gz',path=resolve(directory,name),fd=openSync(path,'wx',0o600);
 try{
  const sid=execFileSync('whoami.exe',['/user','/fo','csv','/nh'],{encoding:'utf8',windowsHide:true}).match(/S-1-\d+(?:-\d+)+/)?.[0];if(!sid)throw Error('ACL unavailable');
  execFileSync('icacls.exe',[path,'/inheritance:r','/grant:r',`*${sid}:(F)`],{stdio:'pipe',windowsHide:true});writeFileSync(fd,compressed);
 }finally{closeSync(fd);}
 mkdirSync('data/reports',{recursive:true});const report={at:snapshot.created,file:name,sha256:createHash('sha256').update(compressed).digest('hex'),counts:Object.fromEntries(tables.map(t=>[t,snapshot.tables[t].length])),verified:true,automaticSync:false,offlineApiEnabled:false};
 writeFileSync('data/reports/chat-postgres-backup.json',JSON.stringify(report,null,2));console.log('SUCCESS: consistent private PC backup created and compression verified. No credentials or message contents printed.');
}catch{if(client)await client.query('ROLLBACK').catch(()=>{});console.error('Chat backup failed; existing backups left unchanged.');process.exitCode=1;}finally{if(client)await client.end().catch(()=>{});}
