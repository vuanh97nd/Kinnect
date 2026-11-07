import {readFile,stat} from 'node:fs/promises';
import {createReadStream} from 'node:fs';
import {createHash} from 'node:crypto';
import {join} from 'node:path';

// Serve only the published, checksum-verified artifact, never the newest work build.
export function createApkDownload(directory,metadataFile){
 let verified;
 return async function download(req,res){
  if(!directory)return false;
  let metadata,file,info;
  try{
   metadata=JSON.parse(await readFile(metadataFile,'utf8'));
   if(!/^\d+\.\d+\.\d+$/.test(metadata.version)||metadata.filename!==`Kinnect-${metadata.version}-native.apk`||! /^[a-f0-9]{64}$/.test(metadata.sha256)||metadata.publishedRelease!==`https://github.com/vuanh97nd/Kinnect/releases/tag/v${metadata.version}`)return false;
   file=join(directory,metadata.filename);info=await stat(file);
   const key=[file,info.size,info.mtimeMs,metadata.sha256].join(':');
   if(verified!==key){const hash=createHash('sha256');for await(const part of createReadStream(file))hash.update(part);if(hash.digest('hex')!==metadata.sha256)return false;verified=key;}
  }catch{return false;}
  const headers={'Content-Type':'application/vnd.android.package-archive','Content-Disposition':`attachment; filename="${metadata.filename}"`,'Accept-Ranges':'bytes','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','ETag':`"${metadata.sha256}"`};
  let start=0,end=info.size-1,status=200;
  const range=req.headers.range;
  if(range&&(!req.headers['if-range']||req.headers['if-range']===headers.ETag)){
   const match=/^bytes=(\d*)-(\d*)$/.exec(range);
   if(!match||!match[1]&&!match[2]){res.writeHead(416,{...headers,'Content-Range':`bytes */${info.size}`});res.end();return true;}
   if(!match[1])start=Math.max(0,info.size-Number(match[2]));else{start=Number(match[1]);if(match[2])end=Math.min(end,Number(match[2]));}
   if(!Number.isSafeInteger(start)||!Number.isSafeInteger(end)||start>end||start>=info.size){res.writeHead(416,{...headers,'Content-Range':`bytes */${info.size}`});res.end();return true;}
   status=206;headers['Content-Range']=`bytes ${start}-${end}/${info.size}`;
  }
  headers['Content-Length']=end-start+1;res.writeHead(status,headers);
  if(req.method==='HEAD'){res.end();return true;}
  const stream=createReadStream(file,{start,end});stream.on('error',()=>res.destroy());res.on('close',()=>stream.destroy());stream.pipe(res);return true;
 };
}
