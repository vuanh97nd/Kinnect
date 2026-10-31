import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {resolve,dirname} from 'node:path';
import {createHash} from 'node:crypto';
import pg from '../cloud-api/node_modules/pg/lib/index.js';
import {postgresOptions} from '../lib/cloud-postgres.js';
const tables=['chat_conversations','chat_members','chat_messages','chat_receipts','chat_hidden_messages','chat_reactions','chat_preferences','chat_pins','chat_attachment_refs'];
const config=Object.fromEntries(readFileSync('chat-db.env','utf8').split(/\r?\n/).filter(x=>x&&!x.startsWith('#')).map(x=>{const i=x.indexOf('=');return[x.slice(0,i),x.slice(i+1)];}));
const canonical=rows=>JSON.stringify(rows.map(row=>Object.fromEntries(Object.entries(row).sort(([a],[b])=>a.localeCompare(b)))).sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b))));
const digest=rows=>createHash('sha256').update(canonical(rows)).digest('hex');
let client,stage="source";try{
 const source={};
 // Preview writers must be idle during the import. Production is not changed here.
 for(const table of tables){stage="source-"+table;const out=execFileSync(process.execPath,[resolve(dirname(process.execPath),'node_modules/npm/bin/npx-cli.js'),'--yes','wrangler','d1','execute','kinnect-chat','--remote','--config','cloud-chat/wrangler.jsonc','--command','SELECT * FROM '+table,'--json'],{encoding:'utf8',windowsHide:true,maxBuffer:32*1024*1024,stdio:['ignore','pipe','pipe']});source[table]=JSON.parse(out).flatMap(x=>x.results||[]);}
 stage="connect";client=new pg.Client(postgresOptions(config));await client.connect();await client.query('BEGIN');
 await client.query("SELECT pg_advisory_xact_lock(hashtext('kinnect-chat-import-v1'))");
 for(const table of tables)if((await client.query('SELECT 1 FROM kinnect_chat.'+table+' LIMIT 1')).rowCount)throw Error('Target is nonempty; refusing overwrite');
 for(const table of tables){stage="insert-"+table;
  // Insert messages without reply references first; apply links after all IDs exist.
  for(const original of source[table]){const row={...original};if(table==='chat_messages')row.reply_to=null;const keys=Object.keys(row);if(keys.some(k=>!/^[_a-z][_a-z0-9]*$/.test(k)))throw Error('Invalid source column');await client.query('INSERT INTO kinnect_chat.'+table+'('+keys.join(',')+') VALUES('+keys.map((_,i)=>'$'+(i+1)).join(',')+')',keys.map(k=>row[k]));}
  if(table==='chat_messages')for(const row of source[table].filter(x=>x.reply_to))await client.query('UPDATE kinnect_chat.chat_messages SET reply_to=$1 WHERE id=$2',[row.reply_to,row.id]);
 }
 const checks=[];
 for(const table of tables){stage="verify-"+table;const target=(await client.query('SELECT * FROM kinnect_chat.'+table)).rows.map(row=>Object.fromEntries(Object.entries(row).map(([k,v])=>[k,typeof v==='string'&&source[table].some(r=>typeof r[k]==='number')?Number(v):v])));if(digest(target)!==digest(source[table]))throw Error('Data verification failed');checks.push({table,count:target.length,sha256:digest(target)});}
 await client.query('COMMIT');mkdirSync('data/reports',{recursive:true});writeFileSync('data/reports/chat-postgres-import.json',JSON.stringify({at:new Date().toISOString(),source:'D1 preview',target:'mmxqhcngrejxyhhfirzo',checks,productionRouting:false},null,2));console.log('SUCCESS: all preview chat tables imported and content hashes verified; production app unchanged.');
}catch(e){if(client)await client.query('ROLLBACK').catch(()=>{});console.error('Chat import stopped at '+stage+'; no partial import committed. '+(/^[A-Z0-9_]+$/.test(e.code||'')?e.code:['Target is nonempty; refusing overwrite','Data verification failed'].includes(e.message)?e.message:'IMPORT_FAILED'));process.exitCode=1;}finally{if(client)await client.end().catch(()=>{});}
