import { mp4Duration } from './shorts.js';
export function decodePostMedia(value, fail) {
 if(value == null) return null;
 const match=typeof value==='string' && /^data:(image\/(?:png|jpeg|webp)|video\/mp4);base64,([A-Za-z0-9+/=]+)$/.exec(value);
 if(!match)fail(400,'Chọn ảnh PNG/JPEG/WebP hoặc video MP4.');
 const type=match[1], bytes=Buffer.from(match[2],'base64'),video=type==='video/mp4';
 if(!bytes.length)fail(400,'Tệp media rỗng.');
 if(video){try{mp4Duration(bytes);}catch(e){fail(400,e.message);}}
 else {
  const valid=type==='image/png'?bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])):type==='image/jpeg'?bytes[0]===255&&bytes[1]===216&&bytes[2]===255:bytes.toString('ascii',0,4)==='RIFF'&&bytes.toString('ascii',8,12)==='WEBP';
  if(!valid)fail(400,'Nội dung ảnh không đúng định dạng.');
 }
 return {type,bytes,kind:video?'video':'image'};
}
export function sendPostMedia(req,res,row,fail){
 const bytes=Buffer.from(row.data),total=bytes.length;let start=0,end=total-1,status=200;
 if(req.headers.range){const m=/^bytes=(\d*)-(\d*)$/.exec(req.headers.range);if(!m||(!m[1]&&!m[2])){res.writeHead(416,{'Content-Range':'bytes */'+total});return res.end();}
 start=m[1]?Number(m[1]):Math.max(0,total-Number(m[2]));if(m[1]&&m[2])end=Math.min(end,Number(m[2]));
 if(!Number.isSafeInteger(start)||!Number.isSafeInteger(end)||start>end||start>=total){res.writeHead(416,{'Content-Range':'bytes */'+total});return res.end();}status=206;}
 res.writeHead(status,{'Content-Type':row.type,'Content-Length':end-start+1,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Accept-Ranges':'bytes',...(status===206?{'Content-Range':`bytes ${start}-${end}/${total}`}:{})});
 res.end(req.method==='HEAD'?undefined:bytes.subarray(start,end+1));
}
