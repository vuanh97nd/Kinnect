import {DatabaseSync} from 'node:sqlite';
import {mkdirSync,writeFileSync,renameSync,statSync,openSync,readSync,closeSync} from 'node:fs';
import {join} from 'node:path';
import {createHash,randomUUID} from 'node:crypto';
export const hash=data=>createHash('sha256').update(data).digest('hex');
export class MediaStore{
 constructor(root){this.root=root;mkdirSync(join(root,'objects'),{recursive:true});mkdirSync(join(root,'partial'),{recursive:true});this.db=new DatabaseSync(join(root,'media-index.sqlite'));this.db.exec(`PRAGMA journal_mode=WAL;PRAGMA busy_timeout=5000;
 CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
 CREATE TABLE IF NOT EXISTS entries(key TEXT PRIMARY KEY,hash TEXT,size INTEGER NOT NULL,type TEXT NOT NULL,revision INTEGER NOT NULL,origin TEXT NOT NULL,deleted INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS changes(seq INTEGER PRIMARY KEY AUTOINCREMENT,payload TEXT NOT NULL);
 CREATE TABLE IF NOT EXISTS cursors(peer TEXT PRIMARY KEY,seq INTEGER NOT NULL);
 `);this.nodeId=this.db.prepare("SELECT value FROM metadata WHERE key='nodeId'").get()?.value||randomUUID();this.db.prepare("INSERT OR IGNORE INTO metadata VALUES('nodeId',?)").run(this.nodeId);}
 objectPath(digest){if(!/^[a-f0-9]{64}$/.test(digest))throw Error('Mã tệp không hợp lệ.');return join(this.root,'objects',digest);}
 has(digest,size){let fd;try{const path=this.objectPath(digest);if(statSync(path).size!==size)return false;fd=openSync(path,'r');const buffer=Buffer.alloc(1024*1024),h=createHash('sha256');let count;while((count=readSync(fd,buffer,0,buffer.length,null)))h.update(buffer.subarray(0,count));return h.digest('hex')===digest;}catch{return false;}finally{if(fd!==undefined)closeSync(fd);}}
 current(key){return this.db.prepare('SELECT * FROM entries WHERE key=?').get(key);}
 apply(entry){
  if(!entry||typeof entry.key!=='string'||!entry.key.length||entry.key.length>500||!Number.isSafeInteger(entry.revision)||entry.revision<1||!Number.isSafeInteger(entry.size)||entry.size<0||entry.size>2*1024**3||typeof entry.type!=='string'||entry.type.length>200||!/^[-a-zA-Z0-9]{1,80}$/.test(entry.origin)||![0,1].includes(entry.deleted)||(!entry.deleted&&!this.has(entry.hash,entry.size)))throw Error('Bản ghi hoặc tệp đồng bộ không hợp lệ.');
  const old=this.current(entry.key);if(old&&(old.revision>entry.revision||(old.revision===entry.revision&&old.origin>=entry.origin)))return false;
  const row={key:entry.key,hash:entry.deleted?null:entry.hash,size:entry.deleted?0:entry.size,type:entry.type,revision:entry.revision,origin:entry.origin,deleted:entry.deleted};
  this.db.exec('BEGIN IMMEDIATE');try{this.db.prepare('INSERT INTO entries VALUES(?,?,?,?,?,?,?) ON CONFLICT(key) DO UPDATE SET hash=excluded.hash,size=excluded.size,type=excluded.type,revision=excluded.revision,origin=excluded.origin,deleted=excluded.deleted').run(...Object.values(row));this.db.prepare('INSERT INTO changes(payload) VALUES(?)').run(JSON.stringify(row));this.db.exec('COMMIT');return true;}catch(e){this.db.exec('ROLLBACK');throw e;}
 }
 put(key,data,type){const digest=hash(data),old=this.current(key);if(old&&!old.deleted&&old.hash===digest&&this.has(digest,data.length))return false;
  if(!this.has(digest,data.length)){const tmp=join(this.root,'partial',randomUUID());writeFileSync(tmp,data,{flag:'wx'});renameSync(tmp,this.objectPath(digest));}
  const revision=Number(this.db.prepare('SELECT COALESCE(MAX(revision),0)+1 n FROM entries').get().n);return this.apply({key,hash:digest,size:data.length,type,revision,origin:this.nodeId,deleted:0});
 }
 remove(key){const old=this.current(key);if(!old||old.deleted)return false;return this.apply({...old,hash:null,size:0,deleted:1,revision:Number(this.db.prepare('SELECT MAX(revision)+1 n FROM entries').get().n),origin:this.nodeId});}
 changes(after=0){return this.db.prepare('SELECT seq,payload FROM changes WHERE seq>? ORDER BY seq LIMIT 100').all(after).map(x=>({seq:x.seq,entry:JSON.parse(x.payload)}));}
 cursor(peer){return this.db.prepare('SELECT seq FROM cursors WHERE peer=?').get(peer)?.seq||0;}
 acknowledge(peer,seq){this.db.prepare('INSERT INTO cursors VALUES(?,?) ON CONFLICT(peer) DO UPDATE SET seq=MAX(cursors.seq,excluded.seq)').run(peer,seq);}
 status(){return{nodeId:this.nodeId,...this.db.prepare('SELECT COUNT(*) files,COALESCE(SUM(size),0) bytes FROM entries WHERE deleted=0').get()};}
 close(){this.db.close();}
}
