export const REPLICA_TABLES=['users','posts','post_media','post_categories','post_stories','post_likes','post_comments','shorts','short_likes','short_comments','short_comments_likes','reports','password_resets','ai_jobs','ai_settings','economy_config','wallet_entries','moderation','account_violations','reputation_logs'];
export const OWNED_TABLES=['console_staff','console_audit','console_messages','console_tickets','console_ticket_teams','console_ticket_events'];
export const ALL_TABLES=[...REPLICA_TABLES,...OWNED_TABLES,'sessions'];
export function tableKeys(db,table){const primary=db.prepare('PRAGMA table_info('+table+')').all().filter(c=>c.pk).sort((a,b)=>a.pk-b.pk).map(c=>c.name);if(primary.length)return primary;const unique=db.prepare('PRAGMA index_list('+table+')').all().find(i=>i.unique&&!i.partial&&/^[a-z0-9_]+$/i.test(i.name));return unique?db.prepare('PRAGMA index_info('+unique.name+')').all().map(c=>c.name):[];}
export function importRows(db,table,columns,rows,{localTest=false}={}){
 if(!ALL_TABLES.includes(table)||!Array.isArray(columns)||columns.some(c=>!/^[a-z_][a-z0-9_]*$/i.test(c))||!Array.isArray(rows)||rows.length>10000)throw Error('Invalid import');
 const actual=db.prepare('PRAGMA table_info('+table+')').all().map(c=>c.name);if(columns.some(c=>!actual.includes(c)))throw Error('Unknown import columns');
 const keys=tableKeys(db,table),updates=columns.filter(c=>!keys.includes(c));
 const base='INSERT INTO '+table+'('+columns.join(',')+') VALUES('+columns.map(()=>'?').join(',')+')';
 const sql=OWNED_TABLES.includes(table)?base+' ON CONFLICT DO NOTHING':keys.length?base+' ON CONFLICT('+keys.join(',')+') '+(updates.length?'DO UPDATE SET '+updates.map(c=>c+'=excluded.'+c).join(','):'DO NOTHING'):base+' ON CONFLICT DO NOTHING';
 for(const row of rows){if(!Array.isArray(row)||row.length!==columns.length)throw Error('Invalid row');const values=row.map((v,i)=>{if(table==='users'&&!localTest&&['password','salt'].includes(columns[i]))return '';if(v&&typeof v==='object'&&typeof v.__blob==='string')return Uint8Array.from(Buffer.from(v.__blob,'base64'));return v;});db.prepare(sql).run(...values);}
}
