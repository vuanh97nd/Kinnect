import{readFileSync}from'node:fs';import{execFileSync}from'node:child_process';import{resolve,dirname}from'node:path';
const cli=resolve(dirname(process.execPath),'node_modules/npm/bin/npx-cli.js');
const run=(args,input)=>execFileSync(process.execPath,[cli,'--yes','wrangler',...args],{input,encoding:'utf8',windowsHide:true,maxBuffer:4*1024*1024,stdio:['pipe','pipe','pipe']});
let stage='cloud-api';try{
 console.log(run(['deploy','--config','cloud-api/wrangler.jsonc']));
 stage='gateway-secret';const config=JSON.parse(readFileSync('cloud-api-server.env','utf8'));
 run(['secret','bulk','--config','cloud-gateway/wrangler.jsonc'],JSON.stringify({PREVIEW_KEY:config.PREVIEW_KEY}));console.log('Gateway service credential configured privately.');
 stage='gateway';console.log(run(['deploy','--config','cloud-gateway/wrangler.jsonc']));
}catch{console.error('Deployment stopped at '+stage+'; inspect authenticated CLI status. No credentials printed.');process.exitCode=1;}
