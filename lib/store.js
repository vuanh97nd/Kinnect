import {createHash,createPrivateKey,sign,createCipheriv,createDecipheriv,randomBytes} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {readFileSync} from 'node:fs';
import {SignedDataVerifier,Environment} from '@apple/app-store-server-library';

export const STORE_PRODUCTS=Object.freeze([
 {id:'kinnect_style_aurora',kind:'style',name:'Aurora',description:'Khung ảnh tím hồng và màu hội thoại Aurora.',descriptionEn:'Purple-pink profile frame and Aurora conversation colors.',colors:['#8b5cf6','#ec4899'],referenceVnd:29000},
 {id:'kinnect_style_ocean',kind:'style',name:'Ocean',description:'Khung ảnh xanh biển và màu hội thoại Ocean.',descriptionEn:'Blue profile frame and Ocean conversation colors.',colors:['#0284c7','#14b8a6'],referenceVnd:29000},
 {id:'kinnect_style_sunset',kind:'style',name:'Sunset',description:'Khung ảnh hoàng hôn và màu hội thoại Sunset.',descriptionEn:'Sunset profile frame and conversation colors.',colors:['#f97316','#db2777'],referenceVnd:29000},
 {id:'kinnect_studio_pro',kind:'studio',name:'Studio Pro',description:'Ba mẫu dựng video Aurora, Travel, Cinema và trình sửa ảnh nâng cao: lớp ảnh/chữ, mặt nạ, Curves/HSL, lưu nháp và xuất ảnh. Mua một lần, dùng trên tài khoản này.',descriptionEn:'Aurora, Travel and Cinema video templates plus advanced photo editing: layers, masks, Curves/HSL, drafts and image export. One-time purchase for this account.',colors:['#7c3aed','#c026d3'],referenceVnd:149000},
]);
const hash=s=>createHash('sha256').update(s).digest('hex');
export const storeAccountId=id=>hash('kinnect-store-v1:'+id);
export function storeAccountUuid(userId) {
  const h = createHash('sha256').update('kinnect-store-uuid-v1:' + userId).digest('hex');
  const p1 = h.slice(0, 8);
  const p2 = h.slice(8, 12);
  const p3 = '4' + h.slice(13, 16);
  const p4 = ((parseInt(h.slice(16, 18), 16) & 0x3f) | 0x80).toString(16).padStart(2, '0') + h.slice(18, 20);
  const p5 = h.slice(20, 32);
  return `${p1}-${p2}-${p3}-${p4}-${p5}`.toLowerCase();
}
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

/** Official Apple App Store JWS transaction verification using Apple App Store Server Library. */
export function appleAppStoreVerifier({
  env = process.env,
  rootCertificates = [],
  bundleId = env.APPLE_BUNDLE_ID || PACKAGE,
  environment = env.APPLE_ENVIRONMENT || 'Sandbox',
  appAppleId = env.APPLE_APP_ID ? Number(env.APPLE_APP_ID) : undefined
} = {}) {
  let verifier = null;
  const isProduction = env.NODE_ENV === 'production' || env.KINNECT_ENV === 'production';
  if (isProduction && (environment === 'Xcode' || environment === 'LocalTesting')) {
    throw httpError(503, 'Môi trường kiểm thử Xcode/LocalTesting bị nghiêm cấm trên máy chủ production.');
  }
  const isLocalOrXcode = environment === 'Xcode' || environment === 'LocalTesting';
  const enabled = () => env.APPLE_APP_STORE_ENABLED === 'true' && (isLocalOrXcode || rootCertificates.length > 0 || !!env.APPLE_ROOT_CERT_FILE);

  function getVerifier() {
    if (verifier) return verifier;
    let certs = rootCertificates;
    if (certs.length === 0 && env.APPLE_ROOT_CERT_FILE) {
      try { certs = [readFileSync(env.APPLE_ROOT_CERT_FILE)]; }
      catch (e) { throw httpError(503, 'Không đọc được chứng chỉ gốc Apple: ' + e.message); }
    }
    const envEnum = environment === 'Production' ? Environment.PRODUCTION :
                    environment === 'Xcode' ? Environment.XCODE :
                    environment === 'LocalTesting' ? Environment.LOCAL_TESTING : Environment.SANDBOX;
    verifier = new SignedDataVerifier(certs, environment === 'Production', envEnum, bundleId, appAppleId);
    return verifier;
  }

  return {
    enabled,
    bundleId,
    environment,
    async verify(signedPayload) {
      if (!enabled()) throw httpError(503, 'Cửa hàng Apple chưa mở thanh toán.');
      const v = getVerifier();
      return await v.verifyAndDecodeTransaction(signedPayload);
    },
    async verifyNotification(signedPayload) {
      if (!enabled()) throw httpError(503, 'Cửa hàng Apple chưa mở thanh toán.');
      const v = getVerifier();
      return await v.verifyAndDecodeNotification(signedPayload);
    }
  };
}

export function createStore({db,body,fail,packages,verifier,appleVerifier,env=process.env,clock=Date.now}){
 verifier ||= googlePlayVerifier({env,clock});
 appleVerifier ||= appleAppStoreVerifier({env});
 db.exec(`CREATE TABLE IF NOT EXISTS store_purchases(token_hash TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,product_id TEXT NOT NULL,token_cipher TEXT NOT NULL,state TEXT NOT NULL,verified INTEGER NOT NULL,created INTEGER NOT NULL,platform TEXT NOT NULL DEFAULT 'android');
 CREATE INDEX IF NOT EXISTS store_purchase_owner ON store_purchases(user_id);
 CREATE TABLE IF NOT EXISTS store_preferences(user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,style TEXT NOT NULL DEFAULT '');
 CREATE TABLE IF NOT EXISTS store_apple_notifications(notification_uuid TEXT PRIMARY KEY,notification_type TEXT NOT NULL,transaction_id TEXT,signed_date INTEGER NOT NULL,created INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS store_apple_revocations(transaction_id TEXT PRIMARY KEY,notification_type TEXT NOT NULL,revocation_date INTEGER NOT NULL,created INTEGER NOT NULL);`);
 try{db.exec("ALTER TABLE store_purchases ADD COLUMN platform TEXT NOT NULL DEFAULT 'android'");}catch{}
 const find=id=>STORE_PRODUCTS.find(p=>p.id===id)||packages?.style(id);
 const key=()=>Buffer.from(env.PLAY_PURCHASE_TOKEN_KEY||'','hex');
 function seal(token){if(key().length!==32)throw httpError(503,'Thiếu khóa bảo vệ giao dịch.');const nonce=randomBytes(12),cipher=createCipheriv('aes-256-gcm',key(),nonce);return Buffer.concat([nonce,cipher.update(token,'utf8'),cipher.final(),cipher.getAuthTag()]).toString('base64');}
 function unseal(value){const raw=Buffer.from(value,'base64'),d=createDecipheriv('aes-256-gcm',key(),raw.subarray(0,12));d.setAuthTag(raw.subarray(-16));return Buffer.concat([d.update(raw.subarray(12,-16)),d.final()]).toString('utf8');}
 function owned(userId){const ids=db.prepare("SELECT DISTINCT product_id FROM store_purchases WHERE user_id=? AND state='PURCHASED' AND verified>?").all(userId,clock()-86400000).map(p=>p.product_id);if(packages)for(const id of packages.owned(userId))if(!ids.includes(id))ids.push(id);if(packages?.studioAllowed(userId)&&!ids.includes('kinnect_studio_pro'))ids.push('kinnect_studio_pro');return ids;}
 function appearance(id){const style=db.prepare('SELECT style FROM store_preferences WHERE user_id=?').get(id)?.style;return style&&owned(id).includes(style)?find(style):null;}
 async function verifyGoogle(userId,productId,token){
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
  if(state==='PURCHASED'&&purchase.acknowledgementState!=='ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED')await verifier.acknowledge(productId,token);
  if(!db.prepare('SELECT 1 FROM users WHERE id=? AND suspended=0').get(userId))fail(401,'Tài khoản không còn hoạt động.');
  db.prepare('INSERT INTO store_purchases VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(token_hash) DO UPDATE SET state=excluded.state,verified=excluded.verified,platform=excluded.platform').run(digest,userId,productId,seal(token),state,clock(),clock(),'android');
  return {state,owned:owned(userId),platform:'android'};
 }

 async function verifyApple(userId,productId,token,payload={}){
  if(!appleVerifier||!appleVerifier.enabled())fail(503,'Cửa hàng Apple chưa mở thanh toán hoặc chưa cấu hình.');
  if(typeof token!=='string'||token.length<10||token.length>16384||!token.includes('.'))fail(400,'Chữ ký giao dịch StoreKit không hợp lệ.');
  let decoded;
  try{
   decoded=await appleVerifier.verify(token);
  }catch(err){
   const httpCode=(typeof err.status==='number'&&err.status>=400&&err.status<600)?err.status:422;
   fail(httpCode,'Xác minh chữ ký giao dịch Apple không thành công: '+(err.message||'Chữ ký không hợp lệ.'));
  }
  if(!decoded||typeof decoded!=='object')fail(422,'Dữ liệu giao dịch Apple không hợp lệ.');
  const isProduction=env.NODE_ENV==='production'||env.KINNECT_ENV==='production';
  if(isProduction&&(decoded.environment==='Xcode'||decoded.environment==='LocalTesting'))fail(403,'Giao dịch từ môi trường Xcode/LocalTesting bị từ chối trên production.');
  if(decoded.productId!==productId)fail(422,'Sản phẩm giao dịch không khớp.');
  if(decoded.bundleId&&appleVerifier.bundleId&&decoded.bundleId!==appleVerifier.bundleId)fail(422,'Bundle ID không khớp.');
  const txId=String(decoded.transactionId||'');
  if(!txId)fail(422,'Thiếu mã định danh giao dịch Apple.');
  const digest=hash('apple:'+txId);
  const prior=db.prepare('SELECT * FROM store_purchases WHERE token_hash=?').get(digest);
  if(prior&&prior.user_id!==userId)fail(409,'Giao dịch Apple đã được gắn với tài khoản khác.');
  const expectedUuid=storeAccountUuid(userId);
  if(!decoded.appAccountToken){
   const isAllowedLegacy=env.APPLE_ALLOW_LEGACY_UNBOUND==='true'&&prior&&prior.user_id===userId;
   if(!isAllowedLegacy)fail(403,'Giao dịch thiếu thông tin ràng buộc appAccountToken với tài khoản Kinnect.');
  }else if(decoded.appAccountToken.toLowerCase()!==expectedUuid.toLowerCase()&&decoded.appAccountToken!==userId){
   fail(403,'Giao dịch không thuộc tài khoản Kinnect này (appAccountToken không khớp).');
  }
  const isTombstoned=!!db.prepare('SELECT 1 FROM store_apple_revocations WHERE transaction_id=?').get(txId);
  const isRevoked=decoded.revocationDate!=null||isTombstoned;
  if(prior&&prior.user_id===userId){
   if(isRevoked){
    db.prepare("UPDATE store_purchases SET state='CANCELLED',verified=? WHERE token_hash=?").run(clock(),digest);
    fail(422,'Giao dịch đã bị Apple thu hồi hoặc hoàn tiền.');
   }
   db.prepare("UPDATE store_purchases SET verified=? WHERE token_hash=?").run(clock(),digest);
   return {state:prior.state,owned:owned(userId),idempotent:true,platform:'ios',transactionId:txId};
  }
  if(isRevoked)fail(422,'Giao dịch đã bị Apple thu hồi hoặc hoàn tiền.');
  if(!db.prepare('SELECT 1 FROM users WHERE id=? AND suspended=0').get(userId))fail(401,'Tài khoản không còn hoạt động.');
  db.prepare('INSERT INTO store_purchases VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(token_hash) DO UPDATE SET state=excluded.state,verified=excluded.verified,platform=excluded.platform').run(digest,userId,productId,seal(token),'PURCHASED',clock(),Number(decoded.purchaseDate)||clock(),'ios');
  return {state:'PURCHASED',owned:owned(userId),platform:'ios',transactionId:txId};
 }

 async function verify(userId,productId,token,payload={}){
  if(!find(productId)||typeof token!=='string'||token.length<8||token.length>16384)fail(400,'Giao dịch không hợp lệ.');
  const isApple=payload?.platform==='ios'||token.includes('.');
  if(isApple)return await verifyApple(userId,productId,token,payload);
  return await verifyGoogle(userId,productId,token);
 }
 const busy=new Set(),attempts=new Map(),verifyLimits=new Map();
 async function refresh(userId){
  if((!verifier.enabled()&&!appleVerifier?.enabled())||busy.has(userId)||clock()-(attempts.get(userId)||0)<60000)return;busy.add(userId);attempts.set(userId,clock());
  try{for(const purchase of db.prepare('SELECT * FROM store_purchases WHERE user_id=? AND verified<? LIMIT 20').all(userId,clock()-3600000)){
   try{
    const t=unseal(purchase.token_cipher);
    const p=purchase.platform||(t.includes('.')?'ios':'android');
    if(p==='ios'){
     if(appleVerifier?.enabled())await verifyApple(userId,purchase.product_id,t,{platform:'ios'});
    }else{
     if(verifier.enabled())await verifyGoogle(userId,purchase.product_id,t);
    }
   }catch(error){if(error.status===422)db.prepare("UPDATE store_purchases SET state='CANCELLED',verified=? WHERE token_hash=?").run(clock(),purchase.token_hash);}
  }}finally{busy.delete(userId);}
 }
  function inTransaction(fn){
   db.exec('BEGIN');
   try{
    const res=fn();
    db.exec('COMMIT');
    return res;
   }catch(err){
    try{db.exec('ROLLBACK');}catch{}
    throw err;
   }
  }
  async function handleAppleNotification(signedPayload){
   if(!appleVerifier||!appleVerifier.enabled())fail(503,'Cửa hàng Apple chưa mở thanh toán hoặc chưa cấu hình.');
   if(typeof signedPayload!=='string'||signedPayload.length<10||!signedPayload.includes('.'))fail(400,'Chữ ký thông báo Apple không hợp lệ.');
   let notif;
   try{notif=await appleVerifier.verifyNotification(signedPayload);}
   catch(err){
    const status=(typeof err.status==='number'&&err.status>=400&&err.status<600)?err.status:(err.status===503||err.code==='ECONNREFUSED'||err.code==='ETIMEDOUT'?503:422);
    fail(status,'Chữ ký thông báo Apple không hợp lệ: '+(err.message||''));
   }
   if(!notif||typeof notif!=='object'||!notif.notificationUUID)fail(422,'Dữ liệu thông báo Apple không hợp lệ.');
   let tx=null;
   if(notif.data?.signedTransactionInfo){
    try{
     tx=await appleVerifier.verify(notif.data.signedTransactionInfo);
    }catch(err){
     const status=(typeof err.status==='number'&&err.status>=400&&err.status<600)?err.status:(err.status===503||err.code==='ECONNREFUSED'||err.code==='ETIMEDOUT'?503:422);
     fail(status,'Chữ ký signedTransactionInfo không hợp lệ: '+(err.message||''));
    }
   }
   const txId=tx?String(tx.transactionId||''):null;
   const isRevocation=['REFUND','REVOKE','EXPIRED'].includes(notif.notificationType)||(tx&&tx.revocationDate!=null);
   if(isRevocation&&!txId)fail(422,'Thông báo thu hồi/hoàn tiền thiếu mã định danh giao dịch.');

   return inTransaction(()=>{
    const ins=db.prepare('INSERT INTO store_apple_notifications VALUES(?,?,?,?,?) ON CONFLICT(notification_uuid) DO NOTHING')
      .run(notif.notificationUUID,notif.notificationType,txId,Number(notif.signedDate)||clock(),clock());
    if(ins.changes===0)return {ok:true,duplicate:true,notificationUUID:notif.notificationUUID};

    if(isRevocation&&txId){
     const revDate=Number(tx?.revocationDate)||Number(notif.signedDate)||clock();
     db.prepare('INSERT INTO store_apple_revocations VALUES(?,?,?,?) ON CONFLICT(transaction_id) DO UPDATE SET notification_type=excluded.notification_type,revocation_date=excluded.revocation_date,created=excluded.created')
       .run(txId,notif.notificationType,revDate,clock());
     const digest=hash('apple:'+txId);
     db.prepare("UPDATE store_purchases SET state='CANCELLED',verified=? WHERE token_hash=?").run(clock(),digest);
    }
    return {ok:true,processed:true,notificationType:notif.notificationType,transactionId:txId};
   });
  }
 return {owned,appearance,verify,refresh,handleAppleNotification,async route(req,res,path,json,me){
  if(!path.startsWith('/api/store'))return false;
  if(req.method==='GET'&&path==='/api/store'){
   await refresh(me.id);const products=owned(me.id);json(200,{...(packages?packages.state(me.id):{}),studioProFree:false,studioProPermanent:db.prepare("SELECT 1 FROM store_purchases WHERE user_id=? AND product_id='kinnect_studio_pro' AND state='PURCHASED' AND verified>?").get(me.id,clock()-86400000)!==undefined,products:STORE_PRODUCTS,owned:products,appearance:appearance(me.id)?.id||'',accountId:storeAccountId(me.id),accountUuid:storeAccountUuid(me.id),billingReady:verifier.enabled()||(appleVerifier?appleVerifier.enabled():false),packageName:PACKAGE});return true;
  }
   if(req.method==='POST'&&path==='/api/store/apple-notifications'){
    const b=await body(req,65536);
    if(!b.signedPayload)fail(400,'Thiếu signedPayload trong thông báo Apple.');
    json(200,await handleAppleNotification(b.signedPayload));return true;
   }
  if(req.method==='POST'&&path==='/api/store/verify'){
   const bucket=verifyLimits.get(me.id)||{at:clock(),count:0};if(clock()-bucket.at>=60000){bucket.at=clock();bucket.count=0;}bucket.count++;verifyLimits.set(me.id,bucket);if(bucket.count>12)fail(429,'Vui lòng đợi trước khi xác minh lại.');
   if(verifyLimits.size>10000)for(const [id,value]of verifyLimits)if(clock()-value.at>60000)verifyLimits.delete(id);
   const b=await body(req,16384);try{json(200,await verify(me.id,b.productId,b.purchaseToken,b));}catch(error){if(error.status)fail(error.status,error.message);fail(503,'Chưa xác minh được giao dịch. Hãy thử khôi phục sau.');}return true;}
  if(req.method==='POST'&&path==='/api/store/style'){
   const b=await body(req,1024);if(typeof b.productId!=='string'||b.productId&&(!find(b.productId)||find(b.productId).kind!=='style'))fail(400,'Phong cách không hợp lệ.');
   await refresh(me.id);if(b.productId&&!owned(me.id).includes(b.productId))fail(403,'Bạn chưa sở hữu phong cách này.');
   db.prepare('INSERT INTO store_preferences VALUES(?,?) ON CONFLICT(user_id) DO UPDATE SET style=excluded.style').run(me.id,b.productId);json(200,{ok:true,appearance:appearance(me.id)?.id||''});return true;
  }
  fail(404,'Không tìm thấy tính năng cửa hàng.');
 }};
}