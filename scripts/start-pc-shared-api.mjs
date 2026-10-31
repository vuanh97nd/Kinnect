import{spawn}from'node:child_process';
import{mkdirSync,openSync,closeSync,writeFileSync}from'node:fs';
try{const r=await fetch('http://127.0.0.1:3001/health',{signal:AbortSignal.timeout(1500)});if(r.ok){console.log('Port3001 already serving; no second process started.');process.exit(0);}}catch{}
mkdirSync('data',{recursive:true});const out=openSync('data/pc-shared-api.log','a');
try{const child=spawn(process.execPath,['scripts/pc-shared-api.mjs'],{cwd:process.cwd(),windowsHide:true,detached:true,stdio:['ignore',out,out]});await new Promise((ok,bad)=>{child.once('spawn',ok);child.once('error',bad);});writeFileSync('data/pc-shared-api.pid',String(child.pid));child.unref();console.log('PC shared API preview started PID '+child.pid);}finally{closeSync(out);}
