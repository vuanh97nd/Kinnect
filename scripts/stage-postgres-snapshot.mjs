// Migration staging only; never used by the production runtime.
import {DatabaseSync} from 'node:sqlite';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash,randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const require=createRequire(import.meta.url);
const {Client}=require(resolve(root,'work/pg-tools/node_modules/pg'));
const config=Object.fromEntries(readFileSync(resolve(root,'cloud-db.env'),'utf8').split(/\r?\n/).filter(x=>x&&!x.startsWith('#')).map(x=>{const n=x.indexOf('=');return[x.slice(0,n),x.slice(n+1)];}));
const snapshot=resolve(process.argv[2]||'');
if(!process.argv[2])throw Error('Provide a consistent SQLite backup path.');
const source=new DatabaseSync(snapshot,{readOnly:true});
const tables=['users','oauth_accounts','recovery_emails','privacy_consents','blocks','follows','friendships','economy_config','economy_audit','wallet_entries','wallet_trial_gifts','gift_inventory','store_packages','package_preferences','admin_package_events','admin_coin_grants','store_purchases','store_preferences'];
const canonical=x=>JSON.stringify(x,(_,v)=>v&&typeof v==='object'&&!Array.isArray(v)?Object.fromEntries(Object.keys(v).sort().map(k=>[k,v[k]])):v);
const sha=x=>createHash('sha256').update(x).digest('hex');
const url=new URL(config.KINNECT_DATABASE_URL);url.searchParams.delete('sslmode');
const client=new Client({connectionString:url.toString(),ssl:{ca:readFileSync(config.KINNECT_DATABASE_CA_FILE,'utf8'),rejectUnauthorized:true},connectionTimeoutMillis:10000,query_timeout:30000});
const runId=randomUUID(),report={runId,mode:'staging-only',sourceSha256:sha(readFileSync(snapshot)),tables:[],productionActivated:false,media:'BLOB values replaced by size/hash references; original bytes remain in SQLite snapshot',sessions:'Not migrated; runtime cutover/session policy pending'};
try{
 if(source.prepare('PRAGMA integrity_check').get().integrity_check!=='ok')throw Error('Snapshot integrity failed.');
 await client.connect();await client.query('BEGIN');
 await client.query('CREATE SCHEMA IF NOT EXISTS kinnect_migration');
 await client.query(`CREATE TABLE IF NOT EXISTS kinnect_migration.runs(id text PRIMARY KEY,source_sha256 text NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),verified boolean NOT NULL DEFAULT false);
 CREATE TABLE IF NOT EXISTS kinnect_migration.rows(run_id text NOT NULL REFERENCES kinnect_migration.runs(id),table_name text NOT NULL,row_number bigint NOT NULL,payload jsonb NOT NULL,sha256 text NOT NULL,PRIMARY KEY(run_id,table_name,row_number));`);
 await client.query('INSERT INTO kinnect_migration.runs(id,source_sha256) VALUES($1,$2)',[runId,report.sourceSha256]);
 for(const table of tables){
  if(!source.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?").get(table))continue;
  const rows=source.prepare('SELECT * FROM "'+table+'" ORDER BY rowid').all();
  for(let index=0;index<rows.length;index++){
   const row=rows[index];for(const [key,value]of Object.entries(row))if(value instanceof Uint8Array)row[key]={localBlob:true,bytes:value.byteLength,sha256:sha(value)};
   const payload=JSON.stringify(row);
   await client.query('INSERT INTO kinnect_migration.rows VALUES($1,$2,$3,$4::jsonb,$5)',[runId,table,index,payload,sha(payload)]);
  }
  const check=await client.query('SELECT payload,sha256 FROM kinnect_migration.rows WHERE run_id=$1 AND table_name=$2 ORDER BY row_number',[runId,table]);
  if(check.rows.length!==rows.length)throw Error('Row count mismatch.');
  for(let i=0;i<rows.length;i++){
   // jsonb reorders keys; compare values using source column order.
   const normalized=Object.fromEntries(Object.keys(rows[i]).map(key=>[key,check.rows[i].payload[key]]));
   if(sha(canonical(normalized))!==sha(canonical(rows[i])))throw Error('Payload mismatch.');
  }
  report.tables.push({table,rows:rows.length,verified:true});
 }
 await client.query('UPDATE kinnect_migration.runs SET verified=true WHERE id=$1',[runId]);
 await client.query('COMMIT');
 writeFileSync(resolve(dirname(snapshot),'postgres-staging-report.json'),JSON.stringify(report,null,2));
 console.log(JSON.stringify(report));
}catch(error){await client.query('ROLLBACK').catch(()=>{});console.error('Staging failed; transaction rolled back. Code: '+(/^[A-Z0-9_]{2,40}$/.test(error.code||'')?error.code:'VALIDATION_OR_CONNECTION'));process.exitCode=1;}
finally{source.close();await client.end().catch(()=>{});}
