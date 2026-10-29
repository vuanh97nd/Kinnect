// Hard deletion uses the live FK graph plus explicit cleanup for polymorphic
// references. No foreign-key disabling, account tombstone, or suspended-account substitute.
export function deleteAccountData(db,account){
 const tables=db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").all().map(x=>x.name);
 const quote=name=>'"'+name.replaceAll('"','""')+'"';
 const columns=new Map(tables.map(name=>[name,db.prepare('PRAGMA table_info('+quote(name)+')').all()]));
 const run=(sql,...args)=>db.prepare(sql).run(...args);
 const exists=name=>columns.has(name);
 const cleanup=(table,where,args)=>{if(exists(table))run('DELETE FROM '+quote(table)+' WHERE '+where,...args);};
 function purge(table,where,args,stack=[]){
  if(stack.includes(table))throw Error('Cyclic deletion dependency: '+table);
  const target=quote(table),ids='SELECT id FROM '+target+' WHERE '+where;
  if(columns.get(table).some(c=>c.name==='id')){
   cleanup('notifications','ref IN ('+ids+')',args);
   cleanup('reports','target_id IN ('+ids+')',args);
   cleanup('moderation','target IN ('+ids+')',args);
   cleanup('ai_jobs','target IN ('+ids+')',args);
  }
  if(table==='post_comments'||table==='short_comments'){
   const kind=table==='post_comments'?'post':'short';
   cleanup('comment_reactions','kind=? AND comment_id IN ('+ids+')',[kind,...args]);
   cleanup('comment_threads','kind=? AND (comment_id IN ('+ids+') OR parent_id IN ('+ids+'))',[kind,...args,...args]);
   cleanup('notification_targets','comment_id IN ('+ids+')',args);
  }
  if(table==='messages'||table==='group_messages'){
   const kind=table==='messages'?'direct':'group';
   for(const auxiliary of ['chat_attachments','pinned_chat_messages','chat_message_reactions','hidden_chat_messages','recalled_chat_messages'])cleanup(auxiliary,'kind=? AND message_id IN ('+ids+')',[kind,...args]);
   for(const auxiliary of table==='messages'?['message_receipts','ai_welcome']:['group_mentions','group_message_receipts'])cleanup(auxiliary,'message_id IN ('+ids+')',args);
  }
  if(table==='chat_groups'){
   for(const auxiliary of ['group_deputies','group_avatars'])cleanup(auxiliary,'group_id IN ('+ids+')',args);
   for(const auxiliary of ['manual_unread_conversations','pinned_conversations','muted_conversations','hidden_conversations'])cleanup(auxiliary,"kind='group' AND conversation_id IN ("+ids+')',args);
  }
  for(const child of children.filter(f=>f.parent===table)){
   const parentColumn=child.to||columns.get(table).find(c=>c.pk)?.name;
   purge(child.child,quote(child.from)+' IN (SELECT '+quote(parentColumn)+' FROM '+target+' WHERE '+where+')',args,[...stack,table]);
  }
  run('DELETE FROM '+target+' WHERE '+where,...args);
 }
 const children=tables.flatMap(child=>db.prepare('PRAGMA foreign_key_list('+quote(child)+')').all().map(f=>({child,parent:f.table,from:f.from,to:f.to})));
 db.exec('PRAGMA secure_delete=ON; BEGIN IMMEDIATE');
 try{
  const emails=[...db.prepare('SELECT email FROM recovery_codes WHERE user_id=?').all(account.id),...db.prepare('SELECT email FROM recovery_emails WHERE user_id=?').all(account.id)].map(x=>x.email).filter(Boolean);
  // Keep shared groups usable, but remove the departing owner's avatar.
  for(const group of db.prepare('SELECT id FROM chat_groups WHERE owner=?').all(account.id)){
   const next=db.prepare('SELECT user_id FROM group_members WHERE group_id=? AND user_id<>? ORDER BY joined,user_id LIMIT 1').get(group.id,account.id);
   if(next){run('UPDATE chat_groups SET owner=? WHERE id=?',next.user_id,group.id);cleanup('group_deputies','group_id=? AND user_id=?',[group.id,next.user_id]);cleanup('group_avatars','group_id=?',[group.id]);}
  }
  run("UPDATE ai_settings SET support=0,moderation=0,admin_id='' WHERE admin_id=?",account.id);
  for(const table of tables){
   if(table==='users')continue;
   const refs=columns.get(table).filter(c=>['user_id','actor','sender','recipient','owner','viewer','requester','low_id','high_id','pinned_by'].includes(c.name));
   if(refs.length)purge(table,refs.map(c=>quote(c.name)+'=?').join(' OR '),refs.map(()=>account.id));
  }
  for(const table of ['manual_unread_conversations','pinned_conversations','muted_conversations','hidden_conversations'])cleanup(table,"kind='direct' AND conversation_id=?",[account.id]);
  cleanup('password_resets','username=?',[account.username]);
  cleanup('recovery_limits','key IN (?,?,?)',['bind-user:'+account.id,'reset:'+account.id,'delete:'+account.id]);
  for(const email of emails)cleanup('recovery_limits','key=?',['bind-email:'+email]);
  purge('users','id=?',[account.id]);
  if(db.prepare('PRAGMA foreign_key_check').all().length)throw Error('Account deletion left broken references');
  db.exec('COMMIT');
 }catch(error){db.exec('ROLLBACK');throw error;}
 // Best effort: truncate old WAL frames after secure deletion. Not a substitute
 // for the operator's backup policy; the privacy notice documents that boundary.
 try{db.exec('PRAGMA wal_checkpoint(TRUNCATE)');}catch{}
}
