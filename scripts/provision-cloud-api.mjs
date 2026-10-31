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
const config=parse(readFileSync(resolve(root,'cloud-db.env'),'utf8'));
const secretFile=resolve(root,'cloud-api-server.env');
const admin=new Client(postgresOptions(config));
try{
 let secrets;
 if(existsSync(secretFile))secrets=JSON.parse(readFileSync(secretFile,'utf8'));
 else{
  const password=randomBytes(32).toString('hex'),url=new URL(config.KINNECT_DATABASE_URL);
  url.username='kinnect_api.fetzoqpdxoaxfqqrcfci';url.password=password;
  secrets={PG_CONNECTION_STRING:url.toString(),PG_CA:readFileSync(config.KINNECT_DATABASE_CA_FILE,'utf8'),PREVIEW_KEY:randomBytes(32).toString('base64url')};
  const fd=openSync(secretFile,'wx',0o600);
  try{const sid=execFileSync('whoami.exe',['/user','/fo','csv','/nh'],{encoding:'utf8',windowsHide:true}).match(/S-1-\d+(?:-\d+)+/)?.[0];if(!sid)throw Error('ACL');execFileSync('icacls.exe',[secretFile,'/inheritance:r','/grant:r',`*${sid}:(F)`],{stdio:'pipe',windowsHide:true});writeFileSync(fd,JSON.stringify(secrets));}finally{closeSync(fd);}
 }
 await admin.connect();await admin.query('BEGIN');
 const exists=await admin.query("SELECT 1 FROM pg_roles WHERE rolname='kinnect_api'");
 if(!exists.rows.length){const password=decodeURIComponent(new URL(secrets.PG_CONNECTION_STRING).password);if(!/^[a-f0-9]{64}$/.test(password))throw Error('Unexpected generated credential');await admin.query(`CREATE ROLE kinnect_api LOGIN PASSWORD '${password}' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION`);}
 await admin.query(`GRANT USAGE ON SCHEMA kinnect_core TO kinnect_api;
 GRANT SELECT ON kinnect_core.users,kinnect_core.wallet_entries TO kinnect_api;
 GRANT SELECT,INSERT,DELETE ON kinnect_core.sessions TO kinnect_api;
 DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='kinnect_core' AND tablename='users' AND policyname='api_identity_read') THEN CREATE POLICY api_identity_read ON kinnect_core.users FOR SELECT TO kinnect_api USING(true); END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='kinnect_core' AND tablename='wallet_entries' AND policyname='api_wallet_read') THEN CREATE POLICY api_wallet_read ON kinnect_core.wallet_entries FOR SELECT TO kinnect_api USING(true); END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='kinnect_core' AND tablename='sessions' AND policyname='api_session_access') THEN CREATE POLICY api_session_access ON kinnect_core.sessions FOR ALL TO kinnect_api USING(true) WITH CHECK(true); END IF; END $$;`);
 await admin.query('COMMIT');
 // Only secret values, no provisioning admin credential, are uploaded to Worker.
 execFileSync(process.execPath,[resolve(dirname(process.execPath),'node_modules/npm/bin/npx-cli.js'),'--yes','wrangler','secret','bulk','--config','cloud-api/wrangler.jsonc'],{cwd:root,input:JSON.stringify(secrets),windowsHide:true,stdio:['pipe','pipe','pipe']});
 console.log('Cloud API private preview secrets configured; dedicated PostgreSQL role provisioned.');
}catch{await admin.query('ROLLBACK').catch(()=>{});console.error('Cloud API provisioning failed; no credentials printed. Private recovery file retained.');process.exitCode=1;}
finally{await admin.end().catch(()=>{});}
