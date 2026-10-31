import {DatabaseSync} from 'node:sqlite';
import {readFileSync,writeFileSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {CHAT_IMPORT_TABLES,sha256,encodeChatRow,sqlText,verifyChatRows} from './chat-import-data.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
if(!process.argv[2])throw Error('Provide a consistent SQLite backup path.');
const snapshot=resolve(process.argv[2]);
const db=new DatabaseSync(snapshot,{readOnly:true});
const runId=randomUUID();
const base=['--yes','wrangler','d1','execute','kinnect-chat','--remote','--config','cloud-chat/wrangler.jsonc'];
function cli(args){
 // Capture all CLI output; never print statements or private payloads on failure.
 const command=process.platform==='win32'?process.execPath:'npx';
 const cliArgs=process.platform==='win32'?[resolve(dirname(process.execPath),'node_modules/npm/bin/npx-cli.js'),...base,...args]:[...base,...args];
 return execFileSync(command,cliArgs,{cwd:root,encoding:'utf8',windowsHide:true,maxBuffer:32*1024*1024,stdio:['ignore','pipe','pipe']});
}
try{
 if(db.prepare('PRAGMA integrity_check').get().integrity_check!=='ok')throw Error('Invalid snapshot.');
 const expected=[],counts=[];
 for(const table of CHAT_IMPORT_TABLES){
  if(!db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?").get(table))continue;
  const rows=db.prepare('SELECT * FROM "'+table+'" ORDER BY rowid').all();
  counts.push({table,rows:rows.length});
  rows.forEach((row,index)=>expected.push({table_name:table,row_number:index,...encodeChatRow(row)}));
 }
 const sourceSha256=sha256(readFileSync(snapshot));
 const sql=[`INSERT INTO chat_import_runs VALUES(${sqlText(runId)},${sqlText(sourceSha256)},${Date.now()},'imported',${expected.length});`,...expected.map(row=>`INSERT INTO chat_import_rows VALUES(${sqlText(runId)},${sqlText(row.table_name)},${row.row_number},${sqlText(row.payload)},${sqlText(row.sha256)});`)];
 const file=resolve(dirname(snapshot),'d1-chat-'+runId+'.sql');
 writeFileSync(file,sql.join('\n'),{flag:'wx',mode:0o600});
 if(process.platform==='win32'){
  const sid=execFileSync('whoami.exe',['/user','/fo','csv','/nh'],{encoding:'utf8',windowsHide:true}).match(/S-1-\d+(?:-\d+)+/)?.[0];
  if(!sid)throw Error('Cannot secure migration file.');
  execFileSync('icacls.exe',[file,'/inheritance:r','/grant:r',`*${sid}:(F)`],{stdio:'pipe',windowsHide:true});
 }
 cli(['--file',file,'--yes']);
 // UUID is generated here; SQL input contains no client-supplied values.
 const output=JSON.parse(cli(['--command',`SELECT table_name,row_number,payload,sha256 FROM chat_import_rows WHERE run_id='${runId}' ORDER BY table_name,row_number`,'--json']));
 verifyChatRows(expected,output.flatMap(x=>x.results||[]));
 cli(['--command',`UPDATE chat_import_runs SET state='verified' WHERE id='${runId}'`,'--json']);
 const report={runId,sourceSha256,mode:'staging-only',verified:true,counts,totalRows:expected.length,media:'local BLOB references only',productionActivated:false};
 writeFileSync(resolve(dirname(snapshot),'d1-chat-staging-report.json'),JSON.stringify(report,null,2));
 console.log(JSON.stringify(report));
}catch{console.error('D1 staging import failed or remains unverified. Production unchanged; inspect run metadata before retry. No message contents printed.');process.exitCode=1;}
finally{db.close();}
