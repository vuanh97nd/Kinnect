import {randomUUID} from 'node:crypto';
import {sendCachedMedia} from './post-media.js';
export function chatAttachments({db,fail,blocked,user,messageState}){
 db.exec(`CREATE TABLE IF NOT EXISTS chat_attachments(id TEXT PRIMARY KEY,kind TEXT NOT NULL,message_id TEXT NOT NULL,name TEXT NOT NULL,type TEXT NOT NULL,data BLOB NOT NULL);CREATE INDEX IF NOT EXISTS chat_attachment_message ON chat_attachments(kind,message_id);`);
 const get=(s,...p)=>db.prepare(s).get(...p),run=(s,...p)=>db.prepare(s).run(...p);
 function decode(file){if(!file)return null;if(typeof file.name!=='string'||typeof file.data!=='string')fail(400,'Tệp đính kèm không hợp lệ.');const match=file.data.match(/^data:([^;,]*)(?:;[^,;]*)*;base64,([A-Za-z0-9+/=]+)$/);if(!match)fail(400,'Không đọc được tệp.');const bytes=Buffer.from(match[2],'base64');if(!bytes.length||bytes.length>20*1024*1024)fail(400,'Tệp tối đa 20 MB.');const isMp3Frame=bytes.length>=4&&bytes[0]===255&&(bytes[1]&224)===224&&(bytes[1]&24)!==8&&(bytes[1]&6)===2&&(bytes[2]&240)!==240&&(bytes[2]&12)!==12;let type='application/octet-stream';if(bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])))type='image/png';else if(bytes[0]===255&&bytes[1]===216&&bytes[2]===255)type='image/jpeg';else if(bytes.toString('ascii',0,4)==='RIFF'&&bytes.toString('ascii',8,12)==='WEBP')type='image/webp';else if(bytes.toString('ascii',4,8)==='ftyp')type=match[1].startsWith('audio/')?'audio/mp4':'video/mp4';else if(bytes.subarray(0,4).equals(Buffer.from([26,69,223,163])))type=match[1].startsWith('audio/')?'audio/webm':'video/webm';else if(bytes.toString('ascii',0,3)==='ID3'||isMp3Frame)type='audio/mpeg';else if(bytes.toString('ascii',0,4)==='RIFF'&&bytes.toString('ascii',8,12)==='WAVE')type='audio/wav';const name=file.name.replace(/[\\/\x00-\x1f\x7f]/g,'_').slice(0,180)||'tep-dinh-kem';return {id:randomUUID(),name,type,bytes};}
 function save(kind,messageId,file){if(!file)return;run('INSERT INTO chat_attachments VALUES(?,?,?,?,?,?)',file.id,kind,messageId,file.name,file.type,file.bytes);}
 function metadata(kind,messageId){const file=get('SELECT id,name,type,length(data) AS size FROM chat_attachments WHERE kind=? AND message_id=?',kind,messageId);return file?{...file,url:'/api/chat-attachments/'+file.id,kind:file.type.startsWith('image/')?'image':file.type.startsWith('video/')?'video':file.type.startsWith('audio/')?'audio':'file'}:null;}
 function serve(req,res,path,me){const match=path.match(/^\/api\/chat-attachments\/([a-zA-Z0-9-]+)$/);if(!match)return false;if(!['GET','HEAD'].includes(req.method))fail(405,'Phương thức không hợp lệ.');const file=get('SELECT * FROM chat_attachments WHERE id=?',match[1]);if(!file||!messageState.visible(file.kind,file.message_id,me.id)||messageState.recalled(file.kind,file.message_id))fail(404,'Không tìm thấy tệp.');
 if(file.kind==='direct'){const m=get('SELECT * FROM messages WHERE id=?',file.message_id);if(!m||![m.sender,m.recipient].includes(me.id)||blocked(m.sender,m.recipient)||user(m.sender)?.suspended!==0||user(m.recipient)?.suspended!==0)fail(404,'Không tìm thấy tệp.');}
 else{const m=get('SELECT * FROM group_messages WHERE id=?',file.message_id);if(!m||!get('SELECT 1 FROM group_members WHERE group_id=? AND user_id=?',m.group_id,me.id)||blocked(me.id,m.sender)||user(m.sender)?.suspended!==0)fail(404,'Không tìm thấy tệp.');}
 const inline=file.type.startsWith('image/')||file.type.startsWith('video/')||file.type.startsWith('audio/');
 sendCachedMedia(req, res, {
  bytes: file.data,
  type: file.type,
  maxAge: 120,
  allowRange: true,
  extraHeaders: {
   'Content-Disposition': (inline ? 'inline' : 'attachment') + "; filename*=UTF-8''" + encodeURIComponent(file.name),
   'Content-Security-Policy': "default-src 'none'; sandbox",
  },
 });
 return true;
 }
 return {decode,save,metadata,serve};
}
