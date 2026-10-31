import {readFileSync,writeFileSync,existsSync,openSync,closeSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {randomBytes} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {postgresOptions} from '../lib/cloud-postgres.js';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const {Client}=createRequire(import.meta.url)(resolve(root,'work/pg-tools/node_modules/pg'));
const parse=text=>Object.fromEntries(text.split(/\r?\n/).filter(x=>x&&!x.startsWith('#')).map(x=>{const n=x.indexOf('=');return[x.slice(0,n),x.slice(n+1)];}));
const config=parse(readFileSync(resolve(root,'chat-db.env'),'utf8'));
const secretFile=resolve(root,'chat-api-server.env');
const admin=new Client(postgresOptions(config));
try{
 let secrets;
 if(existsSync(secretFile))secrets=JSON.parse(readFileSync(secretFile,'utf8'));
 else{
  const password=randomBytes(32).toString('hex'),url=new URL(config.KINNECT_DATABASE_URL);
  url.username='kinnect_chat_api.mmxqhcngrejxyhhfirzo';url.password=password;
  secrets={PG_CONNECTION_STRING:url.toString(),PG_CA:readFileSync(config.KINNECT_DATABASE_CA_FILE,'utf8'),PREVIEW_KEY:randomBytes(32).toString('base64url')};
  const fd=openSync(secretFile,'wx',0o600);
  try{const sid=execFileSync('whoami.exe',['/user','/fo','csv','/nh'],{encoding:'utf8',windowsHide:true}).match(/S-1-\d+(?:-\d+)+/)?.[0];if(!sid)throw Error('ACL');execFileSync('icacls.exe',[secretFile,'/inheritance:r','/grant:r',`*${sid}:(F)`],{stdio:'pipe',windowsHide:true});writeFileSync(fd,JSON.stringify(secrets));}finally{closeSync(fd);}
 }
 await admin.connect();await admin.query('BEGIN');
 const exists=await admin.query("SELECT 1 FROM pg_roles WHERE rolname='kinnect_chat_api'");
 if(!exists.rows.length){const password=decodeURIComponent(new URL(secrets.PG_CONNECTION_STRING).password);if(!/^[a-f0-9]{64}$/.test(password))throw Error('Unexpected generated credential');await admin.query(`CREATE ROLE kinnect_chat_api LOGIN PASSWORD '${password}' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION`);}
 await admin.query('GRANT USAGE ON SCHEMA kinnect_chat TO kinnect_chat_api');
 const tables=['chat_conversations','chat_members','chat_messages','chat_receipts','chat_hidden_messages','chat_reactions','chat_preferences','chat_pins','chat_attachment_refs'];
 for(const table of tables){
  await admin.query('GRANT SELECT,INSERT,UPDATE,DELETE ON kinnect_chat.'+table+' TO kinnect_chat_api');
  if(!(await admin.query("SELECT 1 FROM pg_policies WHERE schemaname='kinnect_chat' AND tablename=$1 AND policyname='backend_chat_access'",[table])).rowCount)await admin.query('CREATE POLICY backend_chat_access ON kinnect_chat.'+table+' FOR ALL TO kinnect_chat_api USING(true) WITH CHECK(true)');
 }
 await admin.query('COMMIT');

 console.log('Dedicated chat backend role ready; no credentials printed.');
}catch{await admin.query('ROLLBACK').catch(()=>{});console.error('Chat role provisioning failed; private recovery file retained.');process.exitCode=1;}
finally{await admin.end().catch(()=>{});}
