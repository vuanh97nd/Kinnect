import {readFileSync,existsSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

export function inspectCloudConfig(text, {fileExists=existsSync}={}) {
 const config={};
 for(const raw of text.split(/\r?\n/)) {
  const line=raw.trim(); if(!line||line.startsWith('#'))continue;
  const at=line.indexOf('='); if(at<1)throw Error('Invalid configuration line.');
  const key=line.slice(0,at).trim(); if(Object.hasOwn(config,key))throw Error('Duplicate configuration key.');
  config[key]=line.slice(at+1).trim();
 }
 const errors=[];
 if(config.KINNECT_DATABASE_PROVIDER!=='postgres')errors.push('Database provider must be postgres.');
 let url;
 try{url=new URL(config.KINNECT_DATABASE_URL);}catch{errors.push('A PostgreSQL URL is required.');}
 if(url){
  if(!['postgres:','postgresql:'].includes(url.protocol))errors.push('URL must use PostgreSQL.');
  if(!url.hostname||/YOUR_HOST/i.test(url.hostname)||!url.username||!url.password||/CHANGE_ME/i.test(url.password)||url.pathname==='/')errors.push('Replace all connection placeholders.');
  if(url.searchParams.get('sslmode')!=='verify-full')errors.push('Use sslmode=verify-full to verify server identity.');
 }
 for(const [key,min,max] of [['KINNECT_DATABASE_POOL_MAX',1,30],['KINNECT_DATABASE_CONNECT_TIMEOUT_MS',1000,60000]]){
  const value=Number(config[key]);if(!Number.isInteger(value)||value<min||value>max)errors.push(`${key} is out of range.`);
 }
 if(config.KINNECT_MEDIA_PROVIDER!=='local')errors.push('Media provider must remain local for this deployment.');
 if(config.KINNECT_DATABASE_CA_FILE&&!fileExists(config.KINNECT_DATABASE_CA_FILE))errors.push('Configured CA file does not exist.');
 return {valid:errors.length===0,errors,productionReady:false,reason:'PostgreSQL runtime adapter and data/media migration are not implemented. No database connection was attempted.'};
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{
  const path=resolve(process.argv[2]||'cloud-db.env');
  const result=inspectCloudConfig(readFileSync(path,'utf8'));
  console.log(JSON.stringify(result,null,2));
  process.exitCode=result.valid?0:1;
 }catch{console.error('Cannot read cloud configuration. Create cloud-db.env from cloud-db.env.example; connection details are not printed.');process.exitCode=1;}
}
