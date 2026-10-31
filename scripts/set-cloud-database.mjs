import {existsSync,openSync,writeFileSync,closeSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {resolve,dirname} from 'node:path';
import {execFileSync} from 'node:child_process';
const target=resolve(dirname(fileURLToPath(import.meta.url)),'../cloud-db.env');
async function hiddenPassword(){
 if(!process.stdin.isTTY)throw Error('Run this file in an interactive terminal.');
 process.stdout.write('Supabase database password (hidden): ');
 const input=process.stdin;const wasRaw=input.isRaw;input.setRawMode(true);input.resume();input.setEncoding('utf8');
 return await new Promise((ok,bad)=>{
  let value='';
  function finish(error){input.removeListener('data',receive);input.setRawMode(wasRaw);input.pause();process.stdout.write('\n');error?bad(error):ok(value);}
  function receive(chunk){for(const char of chunk){
   if(char==='\u0003'){finish(Error('Cancelled.'));return;}
   if(char==='\r'||char==='\n'){finish();return;}
   if(char==='\u007f'||char==='\b'){value=Array.from(value).slice(0,-1).join('');continue;}
   if(char>=' '&&char!=='\u001b')value+=char;
  }}
  input.on('data',receive);
 });
}
try{
 if(existsSync(target))throw Error('cloud-db.env already exists; it was left unchanged.');
 let password=await hiddenPassword();if(!password.trim())throw Error('Password is required.');
 const fd=openSync(target,'wx',0o600);
 try{
  if(process.platform==='win32'){
   const sid=execFileSync('whoami.exe',['/user','/fo','csv','/nh'],{encoding:'utf8',windowsHide:true}).match(/S-1-\d+(?:-\d+)+/)?.[0];
   if(!sid)throw Error('Cannot determine Windows user security ID.');
   execFileSync('icacls.exe',[target,'/inheritance:r','/grant:r',`*${sid}:(F)`],{stdio:'pipe',windowsHide:true});
  }
  const encoded=encodeURIComponent(password);password='';
  writeFileSync(fd,`# Preparation only; current SQLite backend does not load this file.
KINNECT_DATABASE_PROVIDER=postgres
KINNECT_DATABASE_URL=postgresql://postgres.fetzoqpdxoaxfqqrcfci:${encoded}@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres?sslmode=verify-full
KINNECT_DATABASE_CA_FILE=
KINNECT_DATABASE_POOL_MAX=5
KINNECT_DATABASE_CONNECT_TIMEOUT_MS=10000
KINNECT_MEDIA_PROVIDER=local
`);
 }finally{closeSync(fd);}
 console.log('Saved private connection configuration. No database connection or migration was performed.');
}catch(error){
 // Avoid echoing passwords or subprocess output.
 const safe=['cloud-db.env already exists; it was left unchanged.','Password is required.','Cancelled.','Run this file in an interactive terminal.'];
 console.error(safe.includes(error.message)?error.message:'Configuration failed. Credentials were not printed; check file permissions.');process.exitCode=1;
}
