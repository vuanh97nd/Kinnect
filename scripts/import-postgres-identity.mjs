import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {DatabaseSync} from 'node:sqlite';
import {randomUUID,scryptSync,randomBytes} from 'node:crypto';
import {postgresOptions} from '../lib/cloud-postgres.js';
import {createPostgresIdentity} from '../lib/postgres-identity.js';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const {Client}=createRequire(import.meta.url)(resolve(root,'work/pg-tools/node_modules/pg'));
const config=Object.fromEntries(readFileSync(resolve(root,'cloud-db.env'),'utf8').split(/\r?\n/).filter(x=>x&&!x.startsWith('#')).map(x=>{const i=x.indexOf('=');return[x.slice(0,i),x.slice(i+1)];}));
if(!process.argv[2])throw Error('SQLite snapshot required');
const snapshot=resolve(process.argv[2]),source=new DatabaseSync(snapshot,{readOnly:true}),client=new Client(postgresOptions(config));
try{
 await client.connect();await client.query('BEGIN');
 await client.query(readFileSync(resolve(root,'cloud-postgres/0001_core.sql'),'utf8'));
 if(Number((await client.query('SELECT COUNT(*) n FROM kinnect_core.users')).rows[0].n)!==0)throw Error('Target is not empty; no automatic overwrite allowed');
 const users=source.prepare('SELECT * FROM users ORDER BY id').all();
 for(const user of users){
  const {id,username,password,salt,name,role,suspended,created,...profile}=user;
  for(const [key,value]of Object.entries(profile))if(value instanceof Uint8Array)profile[key]={localMedia:true,userId:id,kind:key};
  await client.query('INSERT INTO kinnect_core.users VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb)',[id,username,password,salt,name,role,suspended,created,JSON.stringify(profile)]);
 }
 const oauth=source.prepare('SELECT * FROM oauth_accounts').all();
 for(const row of oauth)await client.query('INSERT INTO kinnect_core.oauth_accounts VALUES($1,$2,$3,$4,$5)',[row.provider,row.subject,row.user_id,row.email,row.created]);
 const actual=(await client.query('SELECT id,username,password,salt,role,suspended FROM kinnect_core.users ORDER BY id')).rows;
 if(actual.length!==users.length||actual.some((row,i)=>Object.entries(row).some(([key,value])=>users[i][key]!==value)))throw Error('Identity comparison failed');
 // Real PostgreSQL behavioral test; synthetic account and sessions rolled back to savepoint.
 await client.query('SAVEPOINT identity_probe');
 const probe=randomUUID(),username='probe-'+probe,password=randomBytes(24).toString('hex'),salt=randomBytes(16).toString('hex'),hash=scryptSync(password,salt,64).toString('hex');
 await client.query("INSERT INTO kinnect_core.users VALUES($1,$2,$3,$4,'Probe','user',0,$5,'{}')",[probe,username,hash,salt,Date.now()]);
 const identity=createPostgresIdentity({client});
 if(!(await identity.verify(username,password))||await identity.verify(username,'wrong'))throw Error('Password probe failed');
 const token=await identity.createSession(probe);if(!(await identity.authenticate(token)))throw Error('Session probe failed');
 await client.query('UPDATE kinnect_core.users SET suspended=1 WHERE id=$1',[probe]);
 if(await identity.verify(username,password)||await identity.authenticate(token))throw Error('Suspension probe failed');
 await client.query('ROLLBACK TO SAVEPOINT identity_probe');
 await client.query('COMMIT');
 const report={users:users.length,oauth:oauth.length,hashSaltRoleComparison:true,realPostgresProbe:{validPassword:true,wrongPasswordRejected:true,session:true,suspension:true},productionActivated:false,sessionsMigrated:false};
 writeFileSync(resolve(dirname(snapshot),'postgres-identity-report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
}catch{await client.query('ROLLBACK').catch(()=>{});console.error('Identity import aborted; transaction rolled back. Credentials not printed.');process.exitCode=1;}
finally{source.close();await client.end().catch(()=>{});}
