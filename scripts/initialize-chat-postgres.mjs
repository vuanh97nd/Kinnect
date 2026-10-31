import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import pg from '../cloud-api/node_modules/pg/lib/index.js';
import {postgresOptions} from '../lib/cloud-postgres.js';

const root=resolve(fileURLToPath(new URL('..',import.meta.url)));
process.chdir(root);
let client;
let stage="configuration";
try {
 const config={};
 for(const line of readFileSync('chat-db.env','utf8').split(/\r?\n/)){
  if(!line.trim()||line.startsWith('#'))continue;
  const at=line.indexOf('=');if(at<1)throw Error('Invalid config');
  const key=line.slice(0,at);if(Object.hasOwn(config,key))throw Error('Duplicate key');config[key]=line.slice(at+1);
 }
 const url=new URL(config.KINNECT_DATABASE_URL);
 if(decodeURIComponent(url.username)!=='postgres.mmxqhcngrejxyhhfirzo'||url.hostname!=='aws-0-ap-southeast-1.pooler.supabase.com'||url.port!=='5432'||url.pathname!=='/postgres')throw Error('Unexpected chat project');
 stage="connection";client=new pg.Client(postgresOptions(config));await client.connect();
 stage="tls-check";
 // pg_stat_ssl describes the pooler's backend connection, not our TLS socket.
 // Verify the actual PC -> Supabase pooler connection and its certificate.
 const socket=client.connection.stream;
 if(socket.encrypted!==true||socket.authorized!==true)throw Error('TLS required');
 stage="schema";await client.query('BEGIN');
 await client.query("SELECT pg_advisory_xact_lock(hashtext('kinnect-chat-schema-v1'))");
 await client.query('CREATE SCHEMA IF NOT EXISTS kinnect_chat');
 await client.query('CREATE TABLE IF NOT EXISTS kinnect_chat.schema_migrations(version text PRIMARY KEY, checksum text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())');
 const sql=readFileSync('cloud-chat-postgres/migrations/0001_chat.sql','utf8'),checksum=createHash('sha256').update(sql).digest('hex');
 const previous=(await client.query('SELECT checksum FROM kinnect_chat.schema_migrations WHERE version=$1',['0001'])).rows[0];
 if(previous&&previous.checksum!==checksum)throw Error('Migration checksum changed');
 if(!previous){
  const existing=await client.query("SELECT 1 FROM information_schema.tables WHERE table_schema='kinnect_chat' AND table_name<>'schema_migrations' LIMIT 1");
  if(existing.rowCount)throw Error('Unmanaged chat schema exists');
  await client.query(sql);
  const names=['chat_conversations','chat_members','chat_messages','chat_receipts','chat_hidden_messages','chat_reactions','chat_preferences','chat_pins','chat_attachment_refs'];
  for(const name of names)await client.query(`ALTER TABLE kinnect_chat.${name} ENABLE ROW LEVEL SECURITY`);
  await client.query('INSERT INTO kinnect_chat.schema_migrations(version,checksum) VALUES($1,$2)',['0001',checksum]);
 }
 await client.query('COMMIT');
 const tables=await client.query("SELECT relname name,relrowsecurity rls FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='kinnect_chat' AND relkind='r' ORDER BY relname");
 mkdirSync('data/reports',{recursive:true});
 writeFileSync('data/reports/chat-postgres-setup.json',JSON.stringify({at:new Date().toISOString(),project:'mmxqhcngrejxyhhfirzo',tls:true,tables:tables.rows,productionRouting:false,dataMigrated:false},null,2));
 console.log('SUCCESS: verified TLS, chat schema initialized. Existing app and messages unchanged.');
}catch(error){
 if(client)await client.query('ROLLBACK').catch(()=>{});
 // Never print a driver message: it may include connection details or SQL parameters.
 const code=/^[A-Z0-9_]{2,32}$/.test(error.code||'')?error.code:'SETUP_FAILED';
 const known=['Invalid config','Duplicate key','Unexpected chat project','TLS required','Migration checksum changed','Unmanaged chat schema exists'];
 console.error('Chat PostgreSQL setup failed ('+code+', stage='+stage+(known.includes(error.message)?', reason='+error.message:'')+'). Configuration retained for retry.');process.exitCode=1;
}finally{if(client)await client.end().catch(()=>{});}
