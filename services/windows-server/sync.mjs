import {createWriteStream,createReadStream,statSync,renameSync,truncateSync} from 'node:fs';
import {join} from 'node:path';
import {pipeline} from 'node:stream/promises';
import {Readable,Transform} from 'node:stream';
import {createHash} from 'node:crypto';
export function peerUrl(input){const u=new URL(input);if(u.username||u.password||u.search||u.hash||u.pathname!=='/')throw Error('Địa chỉ máy chỉ gồm giao thức và tên máy.');const parts=u.hostname.split('.').map(Number);const privateIp=parts.length===4&&parts.every(n=>Number.isInteger(n)&&n>=0&&n<=255)&&(parts[0]===10||(parts[0]===192&&parts[1]===168)||(parts[0]===172&&parts[1]>=16&&parts[1]<=31));if(u.protocol!=='https:'&&!(u.protocol==='http:'&&(u.hostname==='localhost'||u.hostname==='127.0.0.1'||privateIp)))throw Error('Máy khác mạng cần địa chỉ HTTPS.');return u.origin;}
export async function pull(store,peer,{fetchImpl=fetch,signal}={}){
 const base=peerUrl(peer.url),headers={Authorization:'Bearer '+peer.key};let changed=0;
 const r=await fetchImpl(base+'/sync/changes?after='+store.cursor(peer.id),{headers,signal,redirect:'error'});if(!r.ok)throw Error(r.status===401?'Mã ghép nối chưa đúng.':'Chưa kết nối được máy kia.');const page=await r.json();
 if(page.nodeId!==peer.id)throw Error('Mã máy không khớp. Hãy ghép nối lại.');
 if(!Array.isArray(page.changes)||page.changes.length>100)throw Error('Danh sách đồng bộ không hợp lệ.');
 for(const change of page.changes){
  if(!Number.isSafeInteger(change.seq)||change.seq<=store.cursor(peer.id))throw Error('Thứ tự đồng bộ không hợp lệ.');const e=change.entry,old=store.current(e.key);
  const needed=!old||e.revision>old.revision||(e.revision===old.revision&&e.origin>old.origin);
  if(needed&&!e.deleted&&!store.has(e.hash,e.size)){
   store.objectPath(e.hash);if(!Number.isSafeInteger(e.size)||e.size<0||e.size>2*1024**3)throw Error('Tệp quá lớn.');
   const temp=join(store.root,'partial',e.hash+'.part');let offset=0;try{offset=statSync(temp).size;}catch{}
   if(offset>e.size)offset=0;
   if(offset<e.size){const res=await fetchImpl(base+'/sync/objects/'+e.hash,{headers:{...headers,...(offset?{Range:'bytes='+offset+'-'}:{})},signal,redirect:'error'});
    if(res.status!==200&&res.status!==206)throw Error('Tải tệp bị gián đoạn.');
    if(res.status===206&&(!offset||res.headers.get('content-range')!==`bytes ${offset}-${e.size-1}/${e.size}`))throw Error('Vị trí tải tiếp không hợp lệ.');
    if(res.status===200)offset=0;let received=offset;
    const limit=new Transform({transform(chunk,_,done){received+=chunk.length;done(received>e.size?Error('Kích thước tệp không khớp.'):null,chunk);}});
    await pipeline(Readable.fromWeb(res.body),limit,createWriteStream(temp,{flags:offset?'a':'w'}),{signal});
   }
   const digest=createHash('sha256');let size=0;for await(const chunk of createReadStream(temp)){digest.update(chunk);size+=chunk.length;}
   if(size!==e.size||digest.digest('hex')!==e.hash){truncateSync(temp,0);throw Error('Tệp chưa khớp mã kiểm tra.');}renameSync(temp,store.objectPath(e.hash));
  }
  if(needed&&store.apply(e))changed++;store.acknowledge(peer.id,change.seq);
 }
 return{changed,more:page.changes.length===100};
}
