import {scrypt as callback,timingSafeEqual,randomBytes,createHash} from 'node:crypto';
import {promisify} from 'node:util';
const scrypt=promisify(callback);
export function createPostgresIdentity({client,clock=Date.now}){
 return {
  async verify(username,password){
   if(typeof username!=='string'||username.length>100||typeof password!=='string'||password.length>128)return null;
   const result=await client.query('SELECT id,username,password,salt,role,suspended,name,created,profile FROM kinnect_core.users WHERE username=$1',[username]);
   const row=result.rows[0];
   const calculated=await scrypt(password,row?.salt||'kinnect-dummy-salt',64);
   const stored=row&&/^[0-9a-f]{128}$/i.test(row.password)?Buffer.from(row.password,'hex'):Buffer.alloc(64);
   if(!timingSafeEqual(calculated,stored)||!row||row.suspended)return null;
   return {id:row.id,username:row.username,name:row.name,role:row.role,created:row.created,profile:row.profile};
  },
  async createSession(userId,ttlMs=7*86400000){
   if(!Number.isSafeInteger(ttlMs)||ttlMs<60000||ttlMs>30*86400000)throw Error('Invalid session lifetime');
   const token=randomBytes(32).toString('base64url'),digest=createHash('sha256').update(token).digest('hex');
   const result=await client.query(`INSERT INTO kinnect_core.sessions(token_hash,user_id,expires)
    SELECT $1,id,$3 FROM kinnect_core.users WHERE id=$2 AND suspended=0 RETURNING user_id`,[digest,userId,clock()+ttlMs]);
   if(!result.rows.length)throw Error('Account unavailable');return token;
  },
  async authenticate(token){
   if(typeof token!=='string'||!(/^[a-f0-9]{64}$/.test(token)||/^[-_A-Za-z0-9]{43}$/.test(token)))return null;
   const digest=createHash('sha256').update(token).digest('hex');
   const result=await client.query(`SELECT u.id,u.username,u.name,u.role FROM kinnect_core.sessions s
    JOIN kinnect_core.users u ON u.id=s.user_id WHERE s.token_hash=$1 AND s.expires>$2 AND u.suspended=0`,[digest,clock()]);
   return result.rows[0]||null;
  }
 };
}
