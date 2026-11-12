import {spawn} from 'node:child_process';
import {openSync,closeSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
export function createServerRestart({serverFile,dbPath,port,shutdown,spawnImpl=spawn}){
 let scheduled=false;
 return async function restart({res}){
  if(scheduled)throw Object.assign(Error('Đã có yêu cầu khởi động lại đang chờ.'),{status:409});
  scheduled=true;const id=randomUUID(),data=dirname(resolve(dbPath)),log=openSync(resolve(data,'admin-restart.log'),'a');let child;
  try{
   child=spawnImpl(process.execPath,[fileURLToPath(new URL('../scripts/restart-active-server.mjs',import.meta.url)),String(process.pid),serverFile,String(port()),data,id],{cwd:dirname(serverFile),env:{...process.env,PORT:String(port()),DATA_DIR:data,SECURE_COOKIES:'1'},detached:true,windowsHide:true,stdio:['ignore',log,log,'ipc']});
   await new Promise((ok,bad)=>{const timer=setTimeout(()=>bad(Error('Restart helper not ready')),5000);const finish=(fn,value)=>{clearTimeout(timer);fn(value);};child.once('error',e=>finish(bad,e));child.once('exit',()=>finish(bad,Error('Restart helper stopped')));child.on('message',m=>{if(m?.ready)finish(ok);});});
   child.unref();res.once('finish',()=>{if(res.statusCode===202)setTimeout(shutdown,100);else{scheduled=false;child.kill();}});
   // Success here means accepted, not that a new server has already started.
   return{id,scheduled:true,message:'Đã tiếp nhận yêu cầu khởi động lại. Đang chờ tiến trình mới được xác nhận.'};
  }catch{scheduled=false;child?.kill?.();throw Object.assign(Error('Không khởi chạy được bộ điều khiển restart. Máy chủ hiện tại vẫn hoạt động.'),{status:503});}
  finally{closeSync(log);}
 };
}
