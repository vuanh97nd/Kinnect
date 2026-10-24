import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { WebSocketServer, WebSocket } from 'ws';
import { fileURLToPath } from 'node:url';

export function createApp() {
  const rooms = new Map();
  const server = http.createServer(async (req, res) => {
    const path = new URL(req.url, 'http://localhost').pathname;
    if (path === '/health') { res.writeHead(200, {'Content-Type':'application/json'}); return res.end(JSON.stringify({ok:true})); }
    const files = {'/kinnect-icon.png':['kinnect-icon.png','image/png'], '/':['index.html','text/html'], '/app.js':['app.js','text/javascript'], '/style.css':['style.css','text/css']};
    if (!files[path]) { res.writeHead(404); return res.end(); }
    try {
      const [file,type] = files[path];
      res.writeHead(200, {'Content-Type':type+'; charset=utf-8','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer','Content-Security-Policy':"default-src 'self'; connect-src 'self' ws: wss:; media-src 'self' blob:; style-src 'self'; script-src 'self'"});
      res.end(await readFile(new URL('./public/'+file, import.meta.url)));
    } catch { res.writeHead(500);res.end(); }
  });
  const wss = new WebSocketServer({server, maxPayload:32768});
  const send = (ws,data) => {if(ws.readyState===WebSocket.OPEN)ws.send(JSON.stringify(data));};
  const broadcast = (room,data) => room.members.forEach(ws=>send(ws,data));
  const listing = () => {const data={type:'rooms',rooms:[...rooms.values()].map(r=>({id:r.id,title:r.title,host:r.host.name,viewers:r.members.size-1}))};wss.clients.forEach(ws=>send(ws,data));};
  function leave(ws) {
    const room=rooms.get(ws.room);ws.room=null;
    if(!room)return;
    room.members.delete(ws.id);
    if(room.host===ws){broadcast(room,{type:'ended'});room.members.forEach(peer=>peer.room=null);rooms.delete(room.id);}
    else {send(room.host,{type:'peer-left',id:ws.id});broadcast(room,{type:'count',viewers:room.members.size-1});}
    listing();
  }
  wss.on('connection',(ws,req)=>{
    // Browser connections must originate from the same host.
    if(req.headers.origin){try{if(new URL(req.headers.origin).host!==req.headers.host)return ws.close(1008,'Invalid origin');}catch{return ws.close(1008);}}
    ws.id=randomUUID();ws.room=null;ws.name='Bạn';ws.window=Date.now();ws.messages=0;
    send(ws,{type:'welcome',id:ws.id});listing();
    ws.on('message',raw=>{
      if(Date.now()-ws.window>1000){ws.window=Date.now();ws.messages=0;}
      if(++ws.messages>30)return ws.close(1008,'Rate limit');
      let m;try{m=JSON.parse(raw);}catch{return send(ws,{type:'error',message:'Dữ liệu không hợp lệ'});}
      if(!m || typeof m!=='object')return;
      const error=message=>send(ws,{type:'error',message});
      if(m.type==='create'){
        if(ws.room)return error('Hãy rời phòng hiện tại trước.');
        if(rooms.size>=100)return error('Máy chủ đã đầy.');
        ws.name=String(m.name||'Bạn').trim().slice(0,40)||'Bạn';
        const room={id:randomUUID(),title:String(m.title||'Cùng trò chuyện').trim().slice(0,100),host:ws,members:new Map([[ws.id,ws]])};
        rooms.set(room.id,room);ws.room=room.id;send(ws,{type:'joined',role:'host',room:{id:room.id,title:room.title}});listing();return;
      }
      if(m.type==='join'){
        const room=rooms.get(m.room);if(!room)return error('Phòng đã kết thúc.');
        if(ws.room)return error('Hãy rời phòng hiện tại trước.');
        if(room.members.size>=7)return error('Bản thử nghiệm giới hạn 6 người xem mỗi phòng.');
        ws.name=String(m.name||'Bạn').trim().slice(0,40)||'Bạn';ws.room=room.id;room.members.set(ws.id,ws);
        send(ws,{type:'joined',role:'viewer',room:{id:room.id,title:room.title},host:room.host.id});
        send(room.host,{type:'peer',id:ws.id});broadcast(room,{type:'count',viewers:room.members.size-1});listing();return;
      }
      if(m.type==='leave'){leave(ws);return;}
      const room=rooms.get(ws.room);if(!room)return error('Bạn chưa tham gia phòng.');
      if(m.type==='chat'){
        const text=typeof m.text==='string'?m.text.trim().slice(0,500):'';
        if(text)broadcast(room,{type:'chat',name:ws.name,text});
      }
      if(m.type==='signal'){
        const target=room.members.get(m.to);
        if(!target || target===ws || (ws!==room.host && target!==room.host))return;
        if(m.description && ['offer','answer'].includes(m.description.type) && typeof m.description.sdp==='string')send(target,{type:'signal',from:ws.id,description:m.description});
        else if(m.candidate && typeof m.candidate==='object')send(target,{type:'signal',from:ws.id,candidate:m.candidate});
      }
    });
    ws.on('close',()=>leave(ws));ws.on('error',()=>{});
  });
  return {server,wss,rooms};
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
  const {server}=createApp();server.listen(Number(process.env.PORT||3000),'0.0.0.0',()=>console.log('Kinnect Live listening on port '+(process.env.PORT||3000)));
}
