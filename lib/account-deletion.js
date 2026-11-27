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
  if(table==='posts'||table==='shorts'){
   const kind=table==='posts'?'post':'short';
   cleanup('media_thumbnails','kind=? AND target_id IN ('+ids+')',[kind,...args]);
  }
  if(table==='post_comments'||table==='short_comments'){
   const kind=table==='post_comments'?'post':'short';
   cleanup('comment_reactions','kind=? AND comment_id IN ('+ids+')',[kind,...args]);
   cleanup('comment_threads','kind=? AND (comment_id IN ('+ids+') OR parent_id IN ('+ids+'))',[kind,...args,...args]);
   cleanup('notification_targets','comment_id IN ('+ids+')',args);
  }
  if(table==='messages'||table==='group_messages'){
   const kind=table==='messages'?'direct':'group';
   for(const auxiliary of ['chat_attachments','pinned_chat_messages','chat_message_reactions','hidden_chat_messages','recalled_chat_messages','edited_chat_messages'])cleanup(auxiliary,'kind=? AND message_id IN ('+ids+')',[kind,...args]);
   cleanup('chat_message_replies','kind=? AND (message_id IN ('+ids+') OR reply_to_id IN ('+ids+'))',[kind,...args,...args]);
   for(const auxiliary of table==='messages'?['message_receipts','ai_welcome']:['group_mentions','group_message_receipts'])cleanup(auxiliary,'message_id IN ('+ids+')',args);
  }
  if(table==='chat_groups'){
   for(const auxiliary of ['group_deputies','group_avatars'])cleanup(auxiliary,'group_id IN ('+ids+')',args);
   for(const auxiliary of ['manual_unread_conversations','pinned_conversations','muted_conversations','hidden_conversations'])cleanup(auxiliary,"kind='group' AND conversation_id IN ("+ids+')',args);
   cleanup('chat_request_ids',"kind='group' AND target_id IN ("+ids+')',args);
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
  // Keep shared groups usable, prefer active (non-suspended) members, and remove the departing owner's avatar.
  const nextOwnerSql=exists('group_deputies')
   ?'SELECT gm.user_id FROM group_members gm JOIN users u ON u.id=gm.user_id WHERE gm.group_id=? AND gm.user_id<>? ORDER BY u.suspended ASC, EXISTS(SELECT 1 FROM group_deputies d WHERE d.group_id=gm.group_id AND d.user_id=gm.user_id) DESC, gm.joined ASC, gm.user_id ASC LIMIT 1'
   :'SELECT gm.user_id FROM group_members gm JOIN users u ON u.id=gm.user_id WHERE gm.group_id=? AND gm.user_id<>? ORDER BY u.suspended ASC, gm.joined ASC, gm.user_id ASC LIMIT 1';
  for(const group of db.prepare('SELECT id FROM chat_groups WHERE owner=?').all(account.id)){
   const next=db.prepare(nextOwnerSql).get(group.id,account.id);
   if(next){run('UPDATE chat_groups SET owner=? WHERE id=?',next.user_id,group.id);cleanup('group_deputies','group_id=? AND user_id=?',[group.id,next.user_id]);cleanup('group_avatars','group_id=?',[group.id]);}
  }
  run("UPDATE ai_settings SET support=0,moderation=0,admin_id='' WHERE admin_id=?",account.id);
  if(exists('wallet_trial_gifts')&&exists('wallet_entries')){
   run(`INSERT OR IGNORE INTO wallet_entries(id,user_id,reference,kind,coins,net_vnd,creator_vnd,platform_vnd,created)
        SELECT lower(hex(randomblob(16))),g.recipient_id,'settled-gift:'||lower(hex(randomblob(12))),'live_gift_received_trial',g.cost,0,0,0,g.created
        FROM wallet_trial_gifts g JOIN users u ON u.id=g.recipient_id
        WHERE g.user_id=? AND g.recipient_id IS NOT NULL AND g.recipient_id<>? AND g.cost>0`,account.id,account.id);
  }
  if(exists('console_tickets'))run("UPDATE console_tickets SET subject='[Đã xóa tài khoản]',description='[Đã xóa theo yêu cầu xóa tài khoản]',member='',created_by='deleted' WHERE created_by IN (?,?) OR member IN (?,?)",account.id,account.username,account.id,account.username);
  if(exists('security_events'))run("UPDATE security_events SET actor_id='deleted' WHERE actor_id IN (?,?)",account.id,account.username);
  if(exists('security_alerts'))run("UPDATE security_alerts SET subject_actor='deleted' WHERE subject_actor IN (?,?)",account.id,account.username);
  for(const table of tables){
   if(table==='users')continue;
   const refs=columns.get(table).filter(c=>['user_id','actor','sender','recipient','owner','viewer','requester','low_id','high_id','pinned_by','creator_id'].includes(c.name));
   if(refs.length)purge(table,refs.map(c=>quote(c.name)+'=?').join(' OR '),refs.map(()=>account.id));
  }
  for(const table of ['manual_unread_conversations','pinned_conversations','muted_conversations','hidden_conversations'])cleanup(table,"kind='direct' AND conversation_id=?",[account.id]);
  cleanup('chat_request_ids',"kind='direct' AND target_id=?",[account.id]);
  cleanup('password_resets','username=?',[account.username]);
  cleanup('recovery_limits','key IN (?,?,?,?)',['bind-user:'+account.id,'reset:'+account.id,'reset:'+account.username,'delete:'+account.id]);
  for(const email of emails)cleanup('recovery_limits','key IN (?,?)',['bind-email:'+email,'reset:'+email]);
  purge('users','id=?',[account.id]);
  if(db.prepare('PRAGMA foreign_key_check').all().length)throw Error('Account deletion left broken references');
  db.exec('COMMIT');
 }catch(error){db.exec('ROLLBACK');throw error;}
 // Best effort: truncate old WAL frames after secure deletion. Not a substitute
 // for the operator's backup policy; the privacy notice documents that boundary.
 try{db.exec('PRAGMA wal_checkpoint(TRUNCATE)');}catch{}
}
