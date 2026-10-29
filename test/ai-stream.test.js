import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readAIStream} from '../lib/ai-stream.js';
test('SSE decodes split Vietnamese UTF-8 before the provider finishes',async()=>{
 const bytes=new TextEncoder().encode('data: {"response":"Chào "}\r\n\r\ndata: {"response":"bạn"}\n\ndata: [DONE]\n\n');let index=0;const seen=[];
 const response=new Response(new ReadableStream({pull(c){if(index===bytes.length)c.close();else c.enqueue(bytes.slice(index,index+=1));}}));
 assert.equal(await readAIStream(response,text=>seen.push(text)),'Chào bạn');assert.deepEqual(seen,['Chào ','Chào bạn']);
});
test('OpenAI deltas skip reasoning and reject truncated/error streams',async()=>{
 const sse=text=>new Response(text);
 assert.equal(await readAIStream(sse('data: {"choices":[{"delta":{"reasoning_content":"private"}}]}\n\ndata: {"choices":[{"delta":{"content":"Hello"}}]}\n\ndata: [DONE]\n\n'),()=>{}),'Hello');
 await assert.rejects(readAIStream(sse('data: {"response":"partial"}\n\n'),()=>{}),/incomplete/);
 await assert.rejects(readAIStream(sse('data: {"error":"quota"}\n\n'),()=>{}),/provider/);
});
