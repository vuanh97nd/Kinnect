import {loadMailEnv} from '../lib/mailer.js';
loadMailEnv('sfu.env');
try{
 const app=await (await fetch('http://127.0.0.1:3000/health',{signal:AbortSignal.timeout(3000)})).json();
 const url=new URL(process.env.KINNECT_SFU_URL||'ws://127.0.0.1:7885/control');url.protocol=url.protocol==='wss:'?'https:':'http:';url.pathname='/metrics';
 const response=await fetch(url,{headers:{Authorization:'Bearer '+process.env.KINNECT_SFU_SECRET},signal:AbortSignal.timeout(3000)});if(!response.ok)throw Error('SFU metrics unavailable');
 console.log(JSON.stringify({liveSfu:app.liveSfu,media:await response.json()},null,2));
}catch(error){console.error('SFU status check failed: '+error.message);process.exitCode=1;}
