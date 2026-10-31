import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import {createCloudChatRepository} from '../lib/cloud-chat-repository.js';
function fixture(){
 const sql=new DatabaseSync(':memory:');sql.exec(readFileSync(new URL('../cloud-chat/migrations/0001_chat.sql',import.meta.url),'utf8'));sql.exec(readFileSync(new URL('../cloud-chat/migrations/0003_visibility.sql',import.meta.url),'utf8'));
 sql.exec("INSERT INTO chat_conversations VALUES('room','group',NULL,'Test','a',1); INSERT INTO chat_members VALUES('room','a','owner',1,NULL),('room','b','member',1,NULL),('room','left','member',1,2)");
 const db={prepare(query){return{bind(...args){return{async first(){const row=sql.prepare(query).get(...args);return row?{...row}:null;},async all(){return{results:sql.prepare(query).all(...args)};},async run(){return{meta:{changes:Number(sql.prepare(query).run(...args).changes)}};}};}};}};
 let now=100;const blocked=new Set();const repo=createCloudChatRepository({db,authorize:async actor=>!blocked.has(actor),clock:()=>now});
 return{repo,sql,blocked,time(value){now=value;}};
}
test('send retries are idempotent, conflicting nonce cannot overwrite',async()=>{
 const f=fixture();try{const input={actor:'a',conversationId:'room',nonce:'nonce_1234567890123',body:'Chào 😀'};const first=await f.repo.send(input);assert.equal((await f.repo.send(input)).id,first.id);await assert.rejects(f.repo.send({...input,body:'changed'}),{status:409});assert.equal(f.sql.prepare('SELECT COUNT(*) n FROM chat_messages').get().n,1);}finally{f.sql.close();}
});
test('outsiders, former members and revoked identities cannot read or send',async()=>{
 const f=fixture();try{for(const actor of ['stranger','left'])await assert.rejects(f.repo.list({actor,conversationId:'room'}),{status:404});f.blocked.add('a');await assert.rejects(f.repo.send({actor:'a',conversationId:'room',nonce:'nonce_1234567890123',body:'x'}),{status:404});}finally{f.sql.close();}
});
test('seen implies delivered, duplicate delivered does not clear seen',async()=>{
 const f=fixture();try{const m=await f.repo.send({actor:'a',conversationId:'room',nonce:'nonce_1234567890123',body:'hello'});f.time(200);assert.deepEqual(await f.repo.receipt({actor:'b',conversationId:'room',messageId:m.id,seen:true}),{delivered_at:200,seen_at:200});f.time(300);assert.deepEqual(await f.repo.receipt({actor:'b',conversationId:'room',messageId:m.id}),{delivered_at:200,seen_at:200});await assert.rejects(f.repo.receipt({actor:'a',conversationId:'room',messageId:m.id,seen:true}),{status:404});}finally{f.sql.close();}
});
test('reply cannot reference another conversation; cursor is bounded',async()=>{
 const f=fixture();try{f.sql.exec("INSERT INTO chat_conversations VALUES('other','group',NULL,'Other','a',1); INSERT INTO chat_messages VALUES('foreign','other','a','foreignnonce123456','secret','text',NULL,NULL,1,NULL,NULL)");await assert.rejects(f.repo.send({actor:'a',conversationId:'room',nonce:'nonce_1234567890123',body:'hello',replyTo:'foreign'}),{status:404});await assert.rejects(f.repo.list({actor:'a',conversationId:'room',limit:101}));for(let n=0;n<3;n++){f.time(100+n);await f.repo.send({actor:'a',conversationId:'room',nonce:'nonce_123456789012'+n,body:'m'+n});}const page=await f.repo.list({actor:'b',conversationId:'room',limit:2});const next=await f.repo.list({actor:'b',conversationId:'room',before:{created:page[1].created_at,id:page[1].id}});assert.equal(next.length,1);}finally{f.sql.close();}
});
