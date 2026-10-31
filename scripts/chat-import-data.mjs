import {createHash} from 'node:crypto';
export const CHAT_IMPORT_TABLES=Object.freeze(['messages','message_receipts','chat_groups','group_members','group_messages','group_deputies','group_mentions','group_message_receipts','group_avatars','chat_attachments','chat_message_reactions','manual_unread_conversations','pinned_conversations','pinned_chat_messages','muted_conversations','hidden_chat_messages','recalled_chat_messages','hidden_conversations','private_album_messages']);
export const sha256=value=>createHash('sha256').update(value).digest('hex');
export function encodeChatRow(row){
 const value={};
 for(const key of Object.keys(row).sort()){
  const item=row[key];
  value[key]=item instanceof Uint8Array?{localBlob:true,bytes:item.byteLength,sha256:sha256(item)}:item;
 }
 const payload=JSON.stringify(value);
 if(payload.includes('\u0000'))throw Error('NUL in message requires an encoded migration transport.');
 return {payload,sha256:sha256(payload)};
}
export function sqlText(text){return "'"+text.replaceAll("'","''")+"'";}
export function verifyChatRows(expected,actual){
 if(expected.length!==actual.length)throw Error('Import row count mismatch.');
 const byKey=new Map(actual.map(row=>[row.table_name+':'+row.row_number,row]));
 for(const row of expected){const found=byKey.get(row.table_name+':'+row.row_number);if(!found||found.payload!==row.payload||found.sha256!==row.sha256||sha256(found.payload)!==row.sha256)throw Error('Import payload mismatch.');}
 return true;
}
