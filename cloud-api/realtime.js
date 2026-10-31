import pg from 'pg';
// Per-user, hibernating invalidation stream. Never send message bodies or wallet balances.
export class UserEvents {
 constructor(ctx,env){this.ctx=ctx;this.env=env;}
 async fetch(request){
  const path=new URL(request.url).pathname;
  if(path==='/connect'||path==='/api/cloud/events'){
   if(request.headers.get('Upgrade')?.toLowerCase()!=='websocket')return new Response('Upgrade required',{status:426});
   const data={userId:request.headers.get('X-User-Id'),tokenHash:request.headers.get('X-Session-Hash'),expires:Number(request.headers.get('X-Session-Expires'))};
   const pair=new WebSocketPair(),[client,server]=Object.values(pair);
   this.ctx.acceptWebSocket(server);
   server.serializeAttachment({userId:data.userId,tokenHash:data.tokenHash,expires:data.expires});
   await this.ctx.storage.setAlarm(Date.now()+60000);
   return new Response(null,{status:101,webSocket:client});
  }
  if(path==='/revoke'){
   const {tokenHash}=await request.json();for(const socket of this.ctx.getWebSockets())if(socket.deserializeAttachment()?.tokenHash===tokenHash)socket.close(1008,'Session ended');
   return Response.json({ok:true});
  }
  if(path==='/notify'){
   const sockets=this.ctx.getWebSockets();if(!sockets.length)return Response.json({ok:true});
   const client=new pg.Client({connectionString:this.env.HYPERDRIVE.connectionString,connectionTimeoutMillis:10000,query_timeout:10000});
   try{
    await client.connect();
    const stamps=[...new Set(sockets.map(s=>s.deserializeAttachment()?.tokenHash).filter(Boolean))];
    const live=await client.query(`SELECT s.token_hash FROM kinnect_core.sessions s JOIN kinnect_core.users u ON u.id=s.user_id WHERE s.token_hash=ANY($1::text[]) AND s.expires>$2 AND u.suspended=0`,[stamps,Date.now()]);
    const valid=new Set(live.rows.map(x=>x.token_hash));
    for(const socket of sockets){if(!valid.has(socket.deserializeAttachment()?.tokenHash)){socket.close(1008,'Session ended');continue;}socket.send(JSON.stringify({type:'chat:changed'}));}
    return Response.json({ok:true});
   }catch{return Response.json({error:'Temporarily unavailable'},{status:503});}
   finally{await client.end().catch(()=>{});}
  }
  return new Response('Not found',{status:404});
 }
 async webSocketMessage(socket,message){
  if(typeof message!=='string'||message.length>64){socket.close(1008,'Invalid message');return;}
  if(socket.deserializeAttachment()?.expires<=Date.now()){socket.close(1008,'Session ended');return;}
  if(message==='ping')socket.send('pong');else socket.close(1008,'Invalid message');
 }
 async alarm(){
  for(const socket of this.ctx.getWebSockets())if(socket.deserializeAttachment()?.expires<=Date.now())socket.close(1008,'Session ended');
  if(this.ctx.getWebSockets().length)await this.ctx.storage.setAlarm(Date.now()+60000);
 }
}
export async function invalidateUsers(env,userIds){
 return Promise.allSettled([...new Set(userIds)].map(userId=>env.USER_EVENTS.get(env.USER_EVENTS.idFromName(userId)).fetch('https://events/notify',{method:'POST'})));
}
