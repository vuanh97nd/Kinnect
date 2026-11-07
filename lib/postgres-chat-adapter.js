import {D1_QUERIES} from '../cloud-api/d1-queries.js';
const normalize=sql=>sql.replace(/\s+/g,' ').trim();
const allowed=new Set(D1_QUERIES.map(normalize));
export function postgresChatQuery(sql){
 let result=normalize(sql);if(!allowed.has(result))throw Error('Unregistered chat query');
 result=result.replace(/json_extract\((n\.value|value),'\$\.created'\)/g,"(($1::jsonb ->> 'created')::bigint)")
  .replace(/json_extract\((n\.value|value),'\$\.([a-z_]+)'\)/g,"($1::jsonb ->> '$2')")
  .replace(/json_each\(\?\)/g,'jsonb_array_elements_text(?::jsonb)')
  .replace(/json_group_array\(/g,'json_agg(').replace(/json_object\(/g,'json_build_object(')
  .replace(/\bMIN\(chat_receipts\.delivered_at,excluded\.delivered_at\)/g,'LEAST(chat_receipts.delivered_at,excluded.delivered_at)')
  .replace(/\bMAX\(chat_receipts\.delivered_at,excluded\.seen_at\)/g,'GREATEST(chat_receipts.delivered_at,excluded.seen_at)')
  .replace(/\b(FROM|JOIN|INTO|UPDATE) (chat_[a-z_]+)/g,'$1 kinnect_chat.$2');
 let i=0;result=result.replace(/\?/g,()=>'$'+(++i));return result;
}
function normalizeRow(row){
 if(!row)return null;const result={...row};
 for(const [key,value] of Object.entries(result)){
  if(['members_json','last_json'].includes(key)&&value!==null&&typeof value==='object')result[key]=JSON.stringify(value);
  if(['created_at','edited_at','recalled_at','joined_at','left_at','delivered_at','seen_at','byte_size','unread_count','n','hidden','muted','pinned','unread'].includes(key)&&value!==null){const n=Number(value);if(!Number.isSafeInteger(n))throw Error('Chat numeric value out of range');result[key]=n;}
 }
 return result;
}
export function createPostgresChatAdapter(client){
 return {prepare(sql){const compiled=postgresChatQuery(sql);return{bind(...params){
  const statement={sql:compiled,params};
  async function execute(mode){const r=await client.query(compiled,params);return mode==='first'?normalizeRow(r.rows[0]):{results:r.rows.map(normalizeRow),success:true,meta:{changes:r.rowCount}};}
  return {_postgresStatement:statement,first:()=>execute('first'),all:()=>execute('all'),run:()=>execute('run')};
 }};},async batch(statements){
  if(!Array.isArray(statements)||statements.length>50||statements.some(s=>!s._postgresStatement))throw Error('Invalid PostgreSQL chat batch');
  await client.query('BEGIN');try{const out=[];for(const s of statements){const r=await client.query(s._postgresStatement.sql,s._postgresStatement.params);out.push({results:r.rows.map(normalizeRow),success:true,meta:{changes:r.rowCount}});}await client.query('COMMIT');return out;}catch(e){await client.query('ROLLBACK');throw e;}
 }};
}
