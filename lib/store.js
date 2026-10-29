import {createHash,createPrivateKey,sign,createCipheriv,createDecipheriv,randomBytes} from 'node:crypto';
import {readFile} from 'node:fs/promises';

export const STORE_PRODUCTS=Object.freeze([
 {id:'kinnect_style_aurora',kind:'style',name:'Aurora',description:'Khung ảnh tím hồng và màu hội thoại Aurora.',descriptionEn:'Purple-pink profile frame and Aurora conversation colors.',colors:['#8b5cf6','#ec4899'],referenceVnd:29000},
 {id:'kinnect_style_ocean',kind:'style',name:'Ocean',description:'Khung ảnh xanh biển và màu hội thoại Ocean.',descriptionEn:'Blue profile frame and Ocean conversation colors.',colors:['#0284c7','#14b8a6'],referenceVnd:29000},
 {id:'kinnect_style_sunset',kind:'style',name:'Sunset',description:'Khung ảnh hoàng hôn và màu hội thoại Sunset.',descriptionEn:'Sunset profile frame and conversation colors.',colors:['#f97316','#db2777'],referenceVnd:29000},
 {id:'kinnect_studio_pro',kind:'studio',name:'Studio Pro',description:'Ba mẫu dựng video: Aurora, Travel và Cinema. Mua một lần, dùng trên tài khoản này.',descriptionEn:'Three video templates: Aurora, Travel and Cinema. One-time purchase for this account.',colors:['#7c3aed','#c026d3'],referenceVnd:149000},
]);
const hash=s=>createHash('sha256').update(s).digest('hex');
export const storeAccountId=id=>hash('kinnect-store-v1:'+id);
const httpError=(status,message)=>Object.assign(new Error(message),{status});
const PACKAGE='app.kinnect.live';

/** All Google requests have fixed trusted destinations; credentials never reach clients. */
export function googlePlayVerifier({env=process.env,send=fetch,clock=Date.now}={}){
 let auth=null,until=0;
 const enabled=()=>env.PLAY_STORE_ENABLED==='true'&&!!env.PLAY_SERVICE_ACCOUNT_FILE&&/^[a-f0-9]{64}$/i.test(env.PLAY_PURCHASE_TOKEN_KEY||'');
 async function access(){
  if(auth&&until>clock()+60000)return auth;
  const account=JSON.parse(await readFile(env.PLAY_SERVICE_ACCOUNT_FILE,'utf8'));
  if(!account.client_email||!account.private_key)throw httpError(503,'Cửa hàng chưa được cấu hình.');
  const now=Math.floor(clock()/1000),encode=o=>Buffer.from(JSON.stringify(o)).toString('base64url');
  const data=encode({alg:'RS256',typ:'JWT'})+'.'+encode({iss:account.client_email,scope:'https://www.googleapis.com/auth/androidpublisher',aud:'https://oauth2.googleapis.com/token',iat:now,exp:now+3600});
  const jwt=data+'.'+sign('RSA-SHA256',Buffer.from(data),createPrivateKey(account.private_key)).toString('base64url');
  const response=await send('https://oauth2.googleapis.com/token',{method:'POST',redirect:'error',signal:AbortSignal.timeout(15000),headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:jwt}).toString()});
  if(!response.ok)throw httpError(503,'Chưa kết nối được dịch vụ xác minh Google Play.');
  const payload=await response.json();if(!payload.access_token)throw httpError(503,'Không nhận được quyền xác minh Google Play.');auth=payload.access_token;until=clock()+Math.min(Number(payload.expires_in)||3600,3600)*1000;return auth;
 }
 async function request(path,method='GET'){
  if(!enabled())throw httpError(503,'Cửa hàng chưa mở thanh toán.');
  const response=await send('https://androidpublisher.googleapis.com/androidpublisher/v3/applications/'+PACKAGE+'/purchases/'+path,{method,redirect:'error',signal:AbortSignal.timeout(15000),headers:{Authorization:'Bearer '+await access(),'Content-Type':'application/json'},...(method==='POST'?{body:'{}'}:{})});
  if(!response.ok)throw httpError(response.status===404||response.status===410?422:503,'Không xác minh được giao dịch Google Play.');
  return response.status===204||method==='POST'?{}:response.json();
 }
 return {enabled,verify:token=>request('productsv2/tokens/'+encodeURIComponent(token)),acknowledge:(id,token)=>request('products/'+encodeURIComponent(id)+'/tokens/'+encodeURIComponent(token)+':acknowledge','POST')};
}

export function createStore({db,body,fail,verifier,env=process.env,clock=Date.now}){
 verifier ||= googlePlayVerifier({env,clock});
 db.exec(`CREATE TABLE IF NOT EXISTS store_purchases(token_hash TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,product_id TEXT NOT NULL,token_cipher TEXT NOT NULL,state TEXT NOT NULL,verified INTEGER NOT NULL,created INTEGER NOT NULL);
 CREATE INDEX IF NOT EXISTS store_purchase_owner ON store_purchases(user_id);
 CREATE TABLE IF NOT EXISTS store_preferences(user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,style TEXT NOT NULL DEFAULT '');`);
 const find=id=>STORE_PRODUCTS.find(p=>p.id===id);
 const key=()=>Buffer.from(env.PLAY_PURCHASE_TOKEN_KEY||'','hex');
 function seal(token){if(key().length!==32)throw httpError(503,'Thiếu khóa bảo vệ giao dịch.');const nonce=randomBytes(12),cipher=createCipheriv('aes-256-gcm',key(),nonce);return Buffer.concat([nonce,cipher.update(token,'utf8'),cipher.final(),cipher.getAuthTag()]).toString('base64');}
 function unseal(value){const raw=Buffer.from(value,'base64'),d=createDecipheriv('aes-256-gcm',key(),raw.subarray(0,12));d.setAuthTag(raw.subarray(-16));return Buffer.concat([d.update(raw.subarray(12,-16)),d.final()]).toString('utf8');}
 function owned(userId){return db.prepare("SELECT DISTINCT product_id FROM store_purchases WHERE user_id=? AND state='PURCHASED' AND verified>?").all(userId,clock()-86400000).map(p=>p.product_id);}
 function appearance(id){const style=db.prepare('SELECT style FROM store_preferences WHERE user_id=?').get(id)?.style;return style&&owned(id).includes(style)?find(style):null;}
 async function verify(userId,productId,token){
  if(!find(productId)||typeof token!=='string'||token.length<8||token.length>4096)fail(400,'Giao dịch không hợp lệ.');
  if(!verifier.enabled())fail(503,'Cửa hàng chưa mở thanh toán.');
  const digest=hash(token),prior=db.prepare('SELECT * FROM store_purchases WHERE token_hash=?').get(digest);
  if(prior&&(prior.user_id!==userId||prior.product_id!==productId))fail(409,'Giao dịch đã gắn với tài khoản khác.');
  const purchase=await verifier.verify(token);
  if(purchase.obfuscatedExternalAccountId!==storeAccountId(userId))fail(403,'Giao dịch không thuộc tài khoản Kinnect này.');
  const lines=purchase.productLineItem||[],line=lines.find(p=>p.productId===productId);
  if(lines.length!==1||!line||Number(line.quantity||1)!==1)fail(422,'Sản phẩm giao dịch không khớp.');
  let state=purchase.purchaseStateContext?.purchaseState;
  if(!['PURCHASED','PENDING','CANCELLED'].includes(state))fail(422,'Trạng thái giao dịch không hợp lệ.');
  if(line.consumptionState==='CONSUMPTION_STATE_CONSUMED'||line.refundableQuantity!==undefined&&Number(line.refundableQuantity)===0)state='CANCELLED';
  // Acknowledge on the secure server; a failed acknowledgement grants nothing.
  if(state==='PURCHASED'&&purchase.acknowledgementState!=='ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED')await verifier.acknowledge(productId,token);
  // A deleted/suspended user must never regain access after an asynchronous verification.
  if(!db.prepare('SELECT 1 FROM users WHERE id=? AND suspended=0').get(userId))fail(401,'Tài khoản không còn hoạt động.');
  db.prepare('INSERT INTO store_purchases VALUES(?,?,?,?,?,?,?) ON CONFLICT(token_hash) DO UPDATE SET state=excluded.state,verified=excluded.verified').run(digest,userId,productId,seal(token),state,clock(),clock());
  return {state,owned:owned(userId)};
 }
 const busy=new Set(),attempts=new Map(),verifyLimits=new Map();
 async function refresh(userId){
  if(!verifier.enabled()||busy.has(userId)||clock()-(attempts.get(userId)||0)<60000)return;busy.add(userId);attempts.set(userId,clock());
  try{for(const purchase of db.prepare('SELECT * FROM store_purchases WHERE user_id=? AND verified<? LIMIT 20').all(userId,clock()-3600000)){
   try{await verify(userId,purchase.product_id,unseal(purchase.token_cipher));}catch(error){if(error.status===422)db.prepare("UPDATE store_purchases SET state='CANCELLED',verified=? WHERE token_hash=?").run(clock(),purchase.token_hash);}
  }}finally{busy.delete(userId);}
 }
 return {owned,appearance,verify,refresh,async route(req,res,path,json,me){
  if(!path.startsWith('/api/store'))return false;
  if(req.method==='GET'&&path==='/api/store'){
   await refresh(me.id);const products=owned(me.id);json(200,{products:STORE_PRODUCTS,owned:products,appearance:appearance(me.id)?.id||'',accountId:storeAccountId(me.id),billingReady:verifier.enabled(),packageName:PACKAGE});return true;
  }
  if(req.method==='POST'&&path==='/api/store/verify'){
   const bucket=verifyLimits.get(me.id)||{at:clock(),count:0};if(clock()-bucket.at>=60000){bucket.at=clock();bucket.count=0;}bucket.count++;verifyLimits.set(me.id,bucket);if(bucket.count>12)fail(429,'Vui lòng đợi trước khi xác minh lại.');
   if(verifyLimits.size>10000)for(const [id,value]of verifyLimits)if(clock()-value.at>60000)verifyLimits.delete(id);
   const b=await body(req,8192);try{json(200,await verify(me.id,b.productId,b.purchaseToken));}catch(error){if(error.status)fail(error.status,error.message);fail(503,'Chưa xác minh được giao dịch. Hãy thử khôi phục sau.');}return true;}
  if(req.method==='POST'&&path==='/api/store/style'){
   const b=await body(req,1024);if(typeof b.productId!=='string'||b.productId&&(!find(b.productId)||find(b.productId).kind!=='style'))fail(400,'Phong cách không hợp lệ.');
   await refresh(me.id);if(b.productId&&!owned(me.id).includes(b.productId))fail(403,'Bạn chưa sở hữu phong cách này.');
   db.prepare('INSERT INTO store_preferences VALUES(?,?) ON CONFLICT(user_id) DO UPDATE SET style=excluded.style').run(me.id,b.productId);json(200,{ok:true,appearance:appearance(me.id)?.id||''});return true;
  }
  fail(404,'Không tìm thấy tính năng cửa hàng.');
 }};
}
