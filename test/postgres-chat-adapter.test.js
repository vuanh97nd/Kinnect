import {test} from 'node:test';
import assert from 'node:assert/strict';
import {D1_QUERIES} from '../cloud-api/d1-queries.js';
import {postgresChatQuery,createPostgresChatAdapter} from '../lib/postgres-chat-adapter.js';
test('only registered statements compile; values remain bound',async()=>{
 assert.throws(()=>postgresChatQuery('DELETE FROM chat_messages'),/Unregistered/);
 for(const query of D1_QUERIES){const pg=postgresChatQuery(query);assert.ok(!pg.includes('?'));assert.ok(!pg.includes('json_each('));}
 const calls=[],db=createPostgresChatAdapter({query:async(sql,params)=>{calls.push({sql,params});return{rows:[{created_at:'1793349180252',body:"quote ' ?"}],rowCount:1};}});
 const result=await db.prepare(D1_QUERIES[0]).bind("' OR 1=1",'user').first();
 assert.equal(result.created_at,1793349180252);assert.equal(calls[0].params[0],"' OR 1=1");assert.ok(!calls[0].sql.includes('OR 1=1'));
});
test('batch failure rolls back instead of committing partial membership',async()=>{
 const calls=[],db=createPostgresChatAdapter({query:async sql=>{calls.push(sql);if(sql.startsWith('SELECT'))throw Error('connection lost');return{rows:[],rowCount:0};}});
 await assert.rejects(db.batch([db.prepare(D1_QUERIES[0]).bind('c','u')]),/connection lost/);
 assert.equal(calls[0],'BEGIN');assert.equal(calls.at(-1),'ROLLBACK');assert.ok(!calls.includes('COMMIT'));
});
