import {existsSync,openSync,writeFileSync,closeSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import {dirname,resolve} from 'node:path';
const target=resolve('gateway.env');
if(existsSync(target))throw Error('Secret file already exists; no rotation performed');
const secret=randomBytes(48).toString('base64url');
const fd=openSync(target,'wx',0o600);
try{
 const sid=execFileSync('whoami.exe',['/user','/fo','csv','/nh'],{encoding:'utf8',windowsHide:true}).match(/S-1-\d+(?:-\d+)+/)?.[0];
 if(!sid)throw Error('Cannot set private file ACL');
 execFileSync('icacls.exe',[target,'/inheritance:r','/grant:r',`*${sid}:(F)`],{stdio:'pipe',windowsHide:true});
 writeFileSync(fd,'GATEWAY_INTERNAL_SECRET='+secret+'\n');
}finally{closeSync(fd);}
try{
 execFileSync(process.execPath,[resolve(dirname(process.execPath),'node_modules/npm/bin/npx-cli.js'),'--yes','wrangler','secret','put','GATEWAY_INTERNAL_SECRET','--config','cloud-gateway/wrangler.jsonc'],{input:secret,stdio:['pipe','pipe','pipe'],windowsHide:true});
 console.log('Private allocation secret provisioned. No credential printed.');
}catch{console.error('Secret upload failed; service remains unauthorized. Local secret retained for recovery.');process.exitCode=1;}
