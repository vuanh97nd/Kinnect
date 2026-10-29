// Both Workers AI and OpenAI-compatible providers use SSE. Decode across UTF-8
// and network chunk boundaries; a truncated stream must never become a final reply.
export async function readAIStream(response, onText) {
 const reader=response.body.getReader(),decoder=new TextDecoder();let pending='',answer='',finished=false;
 const frame=text=>{const data=text.split(/\r?\n/).filter(l=>l.startsWith('data:')).map(l=>l.slice(5).trimStart()).join('\n');if(!data)return;if(data==='[DONE]'){finished=true;return;}const value=JSON.parse(data);if(value.error)throw Error('provider_stream');const delta=value.response??value.choices?.[0]?.delta?.content??'';if(typeof delta!=='string')throw Error('stream_schema');answer+=delta;if(answer.length>10000)throw Error('stream_size');if(delta)onText(answer.slice(0,5000));};
 try{while(true){const {done,value}=await reader.read();pending+=decoder.decode(value,{stream:!done});if(pending.length>64000)throw Error('stream_frame_size');let match;while((match=/\r?\n\r?\n/.exec(pending))){frame(pending.slice(0,match.index));pending=pending.slice(match.index+match[0].length);}if(done)break;}if(pending.trim())frame(pending);if(!finished||!answer.trim())throw Error('stream_incomplete');return answer.slice(0,5000);}finally{await reader.cancel().catch(()=>{});reader.releaseLock();}
}
