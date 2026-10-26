// Report configuration readiness without printing any credential value.
import {existsSync} from 'node:fs';
import {loadMailEnv} from '../lib/mailer.js';
import {createCallConfig} from '../lib/call-config.js';
loadMailEnv('oauth.env');loadMailEnv('turn.env');
let failed=false;
for(const [provider,id,secret] of [['Google','GOOGLE_CLIENT_ID','GOOGLE_CLIENT_SECRET'],['Facebook','FACEBOOK_APP_ID','FACEBOOK_APP_SECRET']]){
 const ready=!!(process.env[id]&&process.env[secret]);console.log(provider+': '+(ready?'đã có đủ biến cấu hình':'chưa cấu hình đủ khóa'));
}
console.log('oauth.env: '+(existsSync('oauth.env')?'đã có':'chưa có'));
const base=process.env.PUBLIC_URL;
try{const url=new URL(base);if(!['http:','https:'].includes(url.protocol)||url.username||url.password||url.search||url.hash||url.pathname!=='/')throw Error();for(const provider of ['google','facebook'])console.log(provider+' callback: '+url.origin+'/api/oauth/'+provider+'/callback');}catch{console.error('PUBLIC_URL cần là origin HTTP(S) hợp lệ, không chứa đường dẫn.');failed=true;}
if(process.argv.includes('--turn')){
 try{const c=await createCallConfig()();const relays=c.iceServers.filter(s=>(Array.isArray(s.urls)?s.urls:[s.urls]).some(u=>/^turns?:/i.test(u)));console.log('TURN: '+relays.length+' cấu hình relay hợp lệ (không in credentials)');if(!relays.length)failed=true;}
 catch(e){console.error('TURN: '+e.message);failed=true;}
}
if(failed)process.exitCode=1;
