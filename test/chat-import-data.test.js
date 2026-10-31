import {test} from 'node:test';
import assert from 'node:assert/strict';
import {encodeChatRow,verifyChatRows,sqlText} from '../scripts/chat-import-data.mjs';
test('preserve Vietnamese, quotes, newlines and receipt nulls',()=>{
 const row={body:"Chào Ánh's\n😀",seen_at:null,delivered_at:1790000000000};
 const encoded=encodeChatRow(row);assert.deepEqual(JSON.parse(encoded.payload),row);assert.equal(sqlText("a'b"),"'a''b'");
});
test('attachment bytes remain local, represented by checksum',()=>{
 const value=JSON.parse(encodeChatRow({data:Buffer.from('private')}).payload);assert.equal(value.data.localBlob,true);assert.equal(value.data.bytes,7);assert.equal(value.data.sha256.length,64);
});
test('verification rejects missing and changed message content',()=>{
 const row={table_name:'messages',row_number:0,...encodeChatRow({body:'test'})};assert.equal(verifyChatRows([row],[row]),true);
 assert.throws(()=>verifyChatRows([row],[]));assert.throws(()=>verifyChatRows([row],[{...row,payload:'{}'}]));
});
