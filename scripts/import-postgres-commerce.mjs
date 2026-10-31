import {DatabaseSync} from 'node:sqlite';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {randomUUID} from 'node:crypto';
import {postgresOptions} from '../lib/cloud-postgres.js';
import {createPostgresWallet} from '../lib/postgres-wallet.js';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const {Client}=createRequire(import.meta.url)(resolve(root,'work/pg-tools/node_modules/pg'));
const config=Object.fromEntries(readFileSync(resolve(root,'cloud-db.env'),'utf8').split(/\r?\n/).filter(x=>x&&!x.startsWith('#')).map(x=>{const i=x.indexOf('=');return[x.slice(0,i),x.slice(i+1)];}));
if(!process.argv[2])throw Error('Snapshot required');
const snapshot=resolve(process.argv[2]),source=new DatabaseSync(snapshot,{readOnly:true}),client=new Client(postgresOptions(config));
const tables=['wallet_entries','store_packages','gift_inventory','economy_config','package_preferences'];
try{
 await client.connect();await client.query('BEGIN');await client.query(readFileSync(resolve(root,'cloud-postgres/0002_commerce.sql'),'utf8'));
 const counts=[];
 for(const table of tables){
  if(Number((await client.query('SELECT COUNT(*) n FROM kinnect_core.'+table)).rows[0].n))throw Error('Target nonempty; no overwrite');
  const rows=source.prepare('SELECT * FROM '+table+' ORDER BY rowid').all();
  for(const row of rows){const keys=Object.keys(row);await client.query('INSERT INTO kinnect_core.'+table+'('+keys.map(k=>'"'+k+'"').join(',')+') VALUES('+keys.map((_,i)=>'$'+(i+1)).join(',')+')',Object.values(row));}
  const actual=(await client.query('SELECT * FROM kinnect_core.'+table)).rows;
  // Source IDs/compound keys are included; compare the complete set, not just totals.
  const canonical=row=>JSON.stringify(Object.fromEntries(Object.entries(row).map(([k,v])=>[k,k==='data'?(typeof v==='string'?JSON.parse(v):v):v===null?null:String(v)])),(_,v)=>v&&typeof v==='object'&&!Array.isArray(v)?Object.fromEntries(Object.keys(v).sort().map(k=>[k,v[k]])):v);
  if(JSON.stringify(rows.map(canonical).sort())!==JSON.stringify(actual.map(canonical).sort()))throw Error('Data comparison failed');
  counts.push({table,rows:rows.length,verified:true});
 }
 // Synthetic ledger probes only; all probe writes rolled back.
 await client.query('SAVEPOINT wallet_probe');
 const uid=randomUUID(),salt='0'.repeat(32),hash='0'.repeat(128);
 await client.query("INSERT INTO kinnect_core.users VALUES($1,$1,$2,$3,'Probe','user',0,$4,'{}')",[uid,hash,salt,Date.now()]);
 for(const [kind,coins,earnings]of [['signup_trial',2000,0],['store_trial',-490,0],['coin_purchase',1000,0],['store_paid',-300,0],['creator_settlement',0,750]]){
  await client.query('INSERT INTO kinnect_core.wallet_entries VALUES($1,$2,$3,$4,$5,0,$6,0,$7)',[randomUUID(),uid,kind,kind,coins,earnings,Date.now()]);
 }
 const wallet=createPostgresWallet({client});const state=await wallet.state(uid);
 if(state.giftedCoins!==1510||state.purchasedCoins!==700||state.giftIncomeWithdrawableVnd!==750||state.unlimitedCoins)throw Error('Wallet probe failed');
 await client.query("UPDATE kinnect_core.users SET role='admin' WHERE id=$1",[uid]);if(!(await wallet.state(uid)).unlimitedCoins)throw Error('Admin probe failed');
 await client.query('ROLLBACK TO SAVEPOINT wallet_probe');await client.query('COMMIT');
 const report={counts,syntheticProbe:{gifted1510:true,purchased700:true,earnings750:true,adminUnlimited:true,rolledBack:true},productionActivated:false};
 writeFileSync(resolve(dirname(snapshot),'postgres-commerce-report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
}catch{await client.query('ROLLBACK').catch(()=>{});console.error('Commerce import aborted; transaction rolled back. No financial data printed.');process.exitCode=1;}
finally{source.close();await client.end().catch(()=>{});}
