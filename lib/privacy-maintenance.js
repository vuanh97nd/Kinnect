import {readdir,stat,unlink,realpath} from 'node:fs/promises';import {resolve,sep} from 'node:path';
export async function maintainPrivacy(db,backupDirectory,now=Date.now()){
 db.prepare('DELETE FROM recovery_codes WHERE expires<? OR used=1').run(now);
 db.prepare('DELETE FROM recovery_limits WHERE last<?').run(now-86400000);
 db.prepare('DELETE FROM password_resets WHERE created<?').run(now-90*86400000);
 db.prepare('DELETE FROM session_info WHERE token IN (SELECT token FROM sessions WHERE expires<?)').run(now);
 db.prepare('DELETE FROM sessions WHERE expires<?').run(now);
 db.prepare('DELETE FROM remembered_accounts WHERE expires<?').run(now);
 if(!backupDirectory)return;
 let root;try{root=await realpath(backupDirectory);}catch(error){if(error.code==='ENOENT')return;throw error;}
 for(const entry of await readdir(root,{withFileTypes:true})){
  if(!entry.isFile()||!/^kinnect-[A-Za-z0-9._-]+\.sqlite$/.test(entry.name))continue;
  const file=await realpath(resolve(root,entry.name));if(!file.startsWith(root+sep))throw Error('Backup path escapes retention directory');
  if((await stat(file)).mtimeMs<now-30*86400000)await unlink(file);
 }
}
