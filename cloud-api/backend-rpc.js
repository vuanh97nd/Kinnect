import {D1_QUERIES} from './d1-queries.js';
import {queryId} from '../lib/d1-backend-transport.js';
const queries=new Map(D1_QUERIES.map(sql=>[queryId(sql),sql]));
export async function backendRpc(request,env){
 if(request.method!=='POST')return Response.json({error:'Method not allowed'},{status:405});
 const raw=await request.text();if(raw.length>16384)return Response.json({error:'Too large'},{status:413});
 let input;try{input=JSON.parse(raw);}catch{return Response.json({error:'Invalid JSON'},{status:400});}
 if(Array.isArray(input?.batch)){
  if(!input.batch.length||input.batch.length>50||input.batch.some(x=>!queries.has(x?.key)||!Array.isArray(x.params)||x.params.length>20||x.params.some(p=>p!==null&&!['string','number'].includes(typeof p))))return Response.json({error:'Invalid batch'},{status:400});
  try{return Response.json(await env.CHAT_DB.batch(input.batch.map(x=>env.CHAT_DB.prepare(queries.get(x.key)).bind(...x.params))),{headers:{'Cache-Control':'no-store'}});}catch{return Response.json({error:'Database temporarily unavailable'},{status:503});}
 }
 const sql=queries.get(input?.key);
 if(!sql||!['first','all','run'].includes(input.mode)||!Array.isArray(input.params)||input.params.length>20||input.params.some(x=>x!==null&&!['string','number'].includes(typeof x)))return Response.json({error:'Unregistered query'},{status:400});
 try{return Response.json(await env.CHAT_DB.prepare(sql).bind(...input.params)[input.mode](),{headers:{'Cache-Control':'no-store'}});}
 catch{return Response.json({error:'Database temporarily unavailable'},{status:503});}
}
