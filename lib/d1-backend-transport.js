import {createHash} from 'node:crypto';
import {D1_QUERIES} from '../cloud-api/d1-queries.js';
export const normalizeQuery=sql=>sql.replace(/\s+/g,' ').trim();
export const queryId=sql=>createHash('sha256').update(normalizeQuery(sql)).digest('hex');
export function createD1BackendTransport({url,secret,fetchImpl=fetch}){
 const allowed=new Set(D1_QUERIES.map(queryId));
 async function executeBatch(statements){
  const batch=statements.map(x=>x._statement);if(batch.some(x=>!x||!allowed.has(x.key)))throw Error('Unregistered D1 batch');
  const response=await fetchImpl(new URL('/internal/d1-query',url),{method:'POST',headers:{'Content-Type':'application/json','X-Kinnect-Preview':secret},body:JSON.stringify({batch}),signal:AbortSignal.timeout(10000),redirect:'error'});if(!response.ok)throw Error('D1 backend temporarily unavailable');return response.json();
 }
 return {batch:executeBatch,prepare(sql){const key=queryId(sql);if(!allowed.has(key))throw Error('Unregistered D1 query');return {bind(...params){
  async function execute(mode){
   const response=await fetchImpl(new URL('/internal/d1-query',url),{method:'POST',headers:{'Content-Type':'application/json','X-Kinnect-Preview':secret},body:JSON.stringify({key,params,mode}),signal:AbortSignal.timeout(10000),redirect:'error'});
   if(!response.ok)throw Error('D1 backend temporarily unavailable');return response.json();
  }
  return {_statement:{key,params},first:()=>execute('first'),all:()=>execute('all'),run:()=>execute('run')};
 }};}};
}
