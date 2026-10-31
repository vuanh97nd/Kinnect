// Phiên dùng chung Postgres cho đăng nhập OAuth khi cầu PC↔cloud đang bật.
// Các API chia sẻ (login/me/notifications/chat...) xác thực phiên ở Postgres, nên phiên
// do luồng OAuth cục bộ tạo ra trước đây bị từ chối (401). Hàm này tạo phiên đúng thẩm quyền.
import {existsSync,readFileSync} from 'node:fs';
import {createHash,randomBytes} from 'node:crypto';
import {createRequire} from 'node:module';
import {postgresOptions} from './cloud-postgres.js';
const require=createRequire(new URL('../cloud-api/package.json',import.meta.url));
const pg=require('pg');
export function createSharedSession(){
  if(!existsSync('data/shared-core-enabled.json')||!existsSync('cloud-db.env'))return null;
  const config=Object.fromEntries(
    readFileSync('cloud-db.env','utf8')
      .split(/\r?\n/)
      .filter(x=>x&&!x.startsWith('#'))
      .map(x=>{const i=x.indexOf('=');return [x.slice(0,i),x.slice(i+1)];}),
  );
  const options=postgresOptions(config);
  return async function sharedSession(user){
    const client=new pg.Client(options);
    await client.connect();
    try{
      const existing=await client.query('SELECT 1 FROM kinnect_core.users WHERE id=$1',[user.id]);
      if(!existing.rows.length){
        const username=String(user.username||'').trim().toLowerCase().slice(0,30)||('u'+user.id.replace(/-/g,'').slice(0,12));
        const name=String(user.name||'').trim().slice(0,60)||username;
        const profile={bio:'',interests:'[]',birth_date:'',discoverable:1,dm_mode:'everyone',identity_public:0,show_activity:1,show_distance:1,profile_visibility:'{}',profile_details:'{}'};
        // Mật khẩu ngẫu nhiên không dùng được: tài khoản OAuth đăng nhập bằng nhà cung cấp.
        await client.query(
          "INSERT INTO kinnect_core.users VALUES($1,$2,$3,$4,$5,$6,0,$7,$8::jsonb)",
          [user.id,username,randomBytes(64).toString('hex'),randomBytes(16).toString('hex'),name,user.role==='admin'?'admin':'user',Date.now(),JSON.stringify(profile)],
        );
      }
      const token=randomBytes(32).toString('base64url');
      const digest=createHash('sha256').update(token).digest('hex');
      const inserted=await client.query(
        'INSERT INTO kinnect_core.sessions(token_hash,user_id,expires) SELECT $1,id,$3 FROM kinnect_core.users WHERE id=$2 AND suspended=0 RETURNING user_id',
        [digest,user.id,Date.now()+7*86400000],
      );
      if(!inserted.rows.length)throw Error('Tài khoản không khả dụng.');
      return token;
    } finally {
      await client.end().catch(()=>{});
    }
  };
}
