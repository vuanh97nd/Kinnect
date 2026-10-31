import {randomUUID,randomBytes,scrypt as callback} from 'node:crypto';
import {promisify} from 'node:util';
import {PRIVACY_VERSION} from '../lib/privacy-notice.js';
const scrypt=promisify(callback);
export async function register(client,input){
 const username=typeof input.username==='string'?input.username.trim().toLowerCase():'';
 if(!/^[a-z0-9_]{3,30}$/.test(username)||typeof input.password!=='string'||input.password.length<6||input.password.length>128)throw Object.assign(Error('Tên đăng nhập 3–30 chữ/số/gạch dưới; mật khẩu 6–128 ký tự.'),{status:400});
 if(input.agree18!==true)throw Object.assign(Error('Cần xác nhận bạn đủ 18 tuổi.'),{status:400});
 const salt=randomBytes(16).toString('hex'),hash=(await scrypt(input.password,salt,64)).toString('hex'),id=randomUUID(),now=Date.now(),name=typeof input.name==='string'?input.name.trim().slice(0,60)||username:username;
 const p={bio:'',interests:'[]',birth_date:'',discoverable:1,dm_mode:'everyone',identity_public:0,show_activity:1,show_distance:1,profile_visibility:'{}',profile_details:'{}'};
 await client.query('INSERT INTO kinnect_core.users VALUES($1,$2,$3,$4,$5,\'user\',0,$6,$7::jsonb)',[id,username,hash,salt,name,now,JSON.stringify(p)]);
 const economy=(await client.query('SELECT data FROM kinnect_core.economy_config WHERE id=1')).rows[0]?.data;
 if(economy?.signupBonusEnabled===true&&Number.isSafeInteger(economy.signupBonusCoins)&&economy.signupBonusCoins>0)await client.query('INSERT INTO kinnect_core.wallet_entries VALUES($1,$2,\'signup-trial-v1\',\'signup_trial\',$3,0,0,0,$4)',[randomUUID(),id,economy.signupBonusCoins,now]);
 if(input.acceptPrivacyNotice===true)await client.query('INSERT INTO kinnect_core.privacy_consents VALUES($1,$2,$3)',[id,PRIVACY_VERSION,now]);
 return{id,username,name,role:'user',suspended:0,created:now,profile:p};
}
