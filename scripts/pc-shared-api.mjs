import http from 'node:http';
import {readFileSync,existsSync} from 'node:fs';
import {resolve} from 'node:path';
import app from '../cloud-api/worker.js';
import {postgresOptions} from '../lib/cloud-postgres.js';
import {createD1BackendTransport} from '../lib/d1-backend-transport.js';
const origin='https://kinnect-cloud-api.vuanh97nd.workers.dev';
const secrets=JSON.parse(readFileSync(resolve('cloud-api-server.env'),'utf8'));
const opts=postgresOptions({KINNECT_DATABASE_URL:secrets.PG_CONNECTION_STRING,KINNECT_DATABASE_CA_FILE:resolve('data/certificates/supabase-prod-ca-2021.crt')});
const events={idFromName:userId=>userId,get(userId){return{async fetch(url,options={}){
 const action=new URL(url).pathname.slice(1);let input={};if(options.body)input=JSON.parse(options.body);
 return fetch(origin+'/internal/events',{method:'POST',headers:{'Content-Type':'application/json','X-Kinnect-Preview':secrets.PREVIEW_KEY},body:JSON.stringify({userId,action,tokenHash:input.tokenHash}),signal:AbortSignal.timeout(10000)});
}};}};
// Realtime upgrades are still served on cloud; Node API does not pretend to proxy WebSockets.
const limits={idFromName:key=>key,get(key){return{fetch:()=>fetch(origin+'/internal/auth-limit',{method:'POST',headers:{'Content-Type':'application/json','X-Kinnect-Preview':secrets.PREVIEW_KEY},body:JSON.stringify({key}),signal:AbortSignal.timeout(10000)})};}};
const env={PREVIEW_KEY:secrets.PREVIEW_KEY,HYPERDRIVE:{connectionString:secrets.PG_CONNECTION_STRING},PC_POSTGRES_OPTIONS:opts,CHAT_DB:createD1BackendTransport({url:origin,secret:secrets.PREVIEW_KEY}),USER_EVENTS:events,AUTH_LIMITS:limits};
if(existsSync('chat-api-server.env')){
 const chat=JSON.parse(readFileSync('chat-api-server.env','utf8'));
 env.CHAT_POSTGRES_OPTIONS=postgresOptions({KINNECT_DATABASE_URL:chat.PG_CONNECTION_STRING,KINNECT_DATABASE_CA_FILE:resolve('data/certificates/supabase-prod-ca-2021.crt')});
}
const server=http.createServer(async(req,res)=>{
 try{
  if(req.url==='/health'){res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify({ok:true,service:'kinnect-pc-shared-api',preview:true,productionRouting:false}));return;}
  if(req.headers.upgrade){res.writeHead(426);res.end();return;}
  const chunks=[];let size=0;for await(const chunk of req){size+=chunk.length;if(size>16384){res.writeHead(413);res.end();return;}chunks.push(chunk);}
  const original=req.headers['x-kinnect-preview']===secrets.PREVIEW_KEY?req.headers['x-kinnect-original-url']:null;
  const request=new Request(original||'http://127.0.0.1:3001'+req.url,{method:req.method,headers:req.headers,...(!['GET','HEAD'].includes(req.method)?{body:Buffer.concat(chunks)}:{})});
  const response=await app.fetch(request,env);res.writeHead(response.status,Object.fromEntries(response.headers));res.end(Buffer.from(await response.arrayBuffer()));
 }catch{res.writeHead(503,{'Content-Type':'application/json'});res.end(JSON.stringify({error:'Máy chủ tạm thời chưa phản hồi.'}));}
});
server.listen(3001,'127.0.0.1',()=>console.log('PC shared API preview listening on loopback3001; production routing disabled.'));
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>server.close(()=>process.exit(0)));
