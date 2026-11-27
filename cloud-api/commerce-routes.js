import {randomUUID} from 'node:crypto';
import {STORE_PACKAGES} from '../lib/store-packages.js';
import {STORE_PRODUCTS,storeAccountId} from '../lib/store.js';
import {createPostgresWallet} from '../lib/postgres-wallet.js';
import {DEFAULT_ECONOMY} from '../lib/economy.js';
const fail=(status,message)=>{throw Object.assign(Error(message),{status});};
const effectivePrice=(p,giftPrices={})=>{
 if(p.kind==='gifts'&&Array.isArray(p.contents)){
  const floor=p.contents.reduce((sum,[g,q])=>sum+(Number(giftPrices[g])||0)*q,0);
  return Math.max(p.priceCoins,floor);
 }
 return p.priceCoins;
};
const GIFT_PACKAGES_BY_ID=new Map(STORE_PACKAGES.filter(p=>p.kind==='gifts'&&Array.isArray(p.contents)).map(p=>[p.id,p]));
export async function commerceState(client,userId){
 const account=(await client.query('SELECT role,suspended FROM kinnect_core.users WHERE id=$1',[userId])).rows[0];if(!account||account.suspended)fail(401,'Tài khoản không còn hoạt động.');
 const now=Date.now();
 const configRow=(await client.query('SELECT data,version FROM kinnect_core.economy_config WHERE id=1')).rows[0];
 const config={version:Number(configRow?.version||1),data:{...DEFAULT_ECONOMY,...(configRow?.data||{})}};
 const wallet=await createPostgresWallet({client}).state(userId);
 const purchases=(await client.query('SELECT product_id,expires FROM kinnect_core.store_packages WHERE user_id=$1 AND expires>$2',[userId,now])).rows;
 const playPermanent=(await client.query("SELECT product_id FROM kinnect_core.store_purchases WHERE user_id=$1 AND state='PURCHASED'",[userId])).rows.map(x=>x.product_id);
 let applePermanent=[];
 try{
  const hasApple=await client.query("SELECT 1 FROM information_schema.tables WHERE table_schema='kinnect_core' AND table_name='apple_store_transactions' LIMIT 1");
  if(hasApple?.rows?.length){
   applePermanent=(await client.query("SELECT DISTINCT product_id FROM kinnect_core.apple_store_transactions WHERE user_id=$1 AND state='PURCHASED'",[userId])).rows.map(x=>x.product_id);
  }
 }catch(err){if(err?.code!=='42P01')throw err;}
 const permanent=[...new Set([...playPermanent,...applePermanent])];
 const inventory=(await client.query('SELECT gift_id AS "giftId",source,SUM(quantity)::text quantity FROM kinnect_core.gift_inventory WHERE user_id=$1 AND quantity>0 GROUP BY gift_id,source',[userId])).rows.map(x=>({...x,quantity:Number(x.quantity)}));
 const remainingGifts=new Set(inventory.filter(x=>Number(x.quantity)>0).map(x=>x.giftId));
 const packages=[...new Set(purchases.map(x=>x.product_id))].filter(pid=>{if(!pid.startsWith('gift_'))return true;const pkg=GIFT_PACKAGES_BY_ID.get(pid);return Boolean(pkg&&pkg.contents.some(([giftId])=>remainingGifts.has(giftId)));});
 const until=ids=>Math.max(0,...purchases.filter(x=>ids.includes(x.product_id)).map(x=>Number(x.expires)));
 const studioVideoUntil=until(['studio_video_7','studio_video_30','studio_video_180','studio_video_365']);
 const studioPhotoUntil=until(['studio_photo_7','studio_photo_30','studio_photo_180','studio_photo_365']);
 const studioUntil=permanent.includes('kinnect_studio_pro')?253402300799000:Math.max(0,...purchases.filter(x=>x.product_id.startsWith('studio_')).map(x=>Number(x.expires)));
 const owned=[...new Set([...permanent,...packages,...(studioUntil>now?['kinnect_studio_pro']:[])])];
 const live=(await client.query('SELECT live FROM kinnect_core.package_preferences WHERE user_id=$1',[userId])).rows[0]?.live||'';
 const style=(await client.query('SELECT style FROM kinnect_core.store_preferences WHERE user_id=$1',[userId])).rows[0]?.style||'';
 const membership=packages.includes('member_creator')?'member_creator':packages.includes('member_plus')?'member_plus':'';
 const packageExpiries=Object.fromEntries(purchases.filter(x=>!x.product_id.startsWith('gift_')).reduce((acc,x)=>{const cur=acc.get(x.product_id)||0;const exp=Number(x.expires);if(exp>cur)acc.set(x.product_id,exp);return acc;},new Map()));
 return {...wallet,adminAccess:false,unlimitedCoins:false,trialCoins:wallet.giftedCoins,packages:STORE_PACKAGES.map(x=>{const priceCoins=effectivePrice(x,config.data.giftPrices);return {...x,priceCoins,referenceVnd:priceCoins*config.data.vndPerCoin};}),packageExpiries,trialPackagePurchases:config.data.trialPackagePurchases,liveGameUntil:until(['live_game_30']),studioProUntil:studioUntil,studioVideoUntil,studioPhotoUntil,chatLiveFree:true,ownedPackages:packages,liveTheme:packages.includes(live)?live:'',membership,giftInventory:inventory,studioProFree:false,studioProPermanent:permanent.includes('kinnect_studio_pro'),products:STORE_PRODUCTS,owned,appearance:owned.includes(style)?style:'',accountId:storeAccountId(userId),billingReady:false,packageName:'app.kinnect.live',vndPerCoin:config.data.vndPerCoin,configVersion:Number(config.version)};
}
export async function commerceRoute({request,client,user,json}){
 const path=new URL(request.url).pathname;if(!path.startsWith('/api/store')&&path!=='/api/economy')return null;
 try{
  if(path==='/api/economy'&&request.method==='GET'){const row=(await client.query('SELECT data,version FROM kinnect_core.economy_config WHERE id=1')).rows[0];const data={...DEFAULT_ECONOMY,...(row?.data||{})};return json({version:Number(row?.version||1),vndPerCoin:data.vndPerCoin,signupBonusCoins:data.signupBonusEnabled?data.signupBonusCoins:0,coinPacks:data.coinPacks.map(coins=>({id:'coins_'+coins,coins,referenceVnd:coins*data.vndPerCoin,checkoutEnabled:false})),checkoutEnabled:false});}
  if(path==='/api/store'&&request.method==='GET')return json(await commerceState(client,user.id));
  if(request.method!=='POST')return json({error:'Phương thức không hỗ trợ.'},405);
  const raw=await request.text();if(raw.length>8192)return json({error:'Dữ liệu quá lớn.'},413);let body;try{body=JSON.parse(raw);}catch{return json({error:'JSON không hợp lệ.'},400);}
  if(!body||typeof body!=='object'||Array.isArray(body))return json({error:'JSON không hợp lệ.'},400);
  if(path==='/api/store/verify')return json({error:'Cửa hàng chưa mở thanh toán Google Play.'},503);
  if(path==='/api/store/style'||path==='/api/store/packages/apply'){
   const state=await commerceState(client,user.id),live=path.endsWith('/apply');
   const catalog=live?STORE_PACKAGES.filter(x=>x.kind==='live'&&x.id!=='live_game_30'):[...STORE_PACKAGES,...STORE_PRODUCTS].filter(x=>x.kind==='style');
   if(typeof body.productId!=='string'||body.productId&&(!state.owned.includes(body.productId)||!catalog.some(x=>x.id===body.productId)))return json({error:'Bạn chưa sở hữu phong cách này.'},403);
   await client.query(live?'INSERT INTO kinnect_core.package_preferences VALUES($1,$2) ON CONFLICT(user_id) DO UPDATE SET live=excluded.live':'INSERT INTO kinnect_core.store_preferences VALUES($1,$2) ON CONFLICT(user_id) DO UPDATE SET style=excluded.style',[user.id,body.productId]);
   return json(live?await commerceState(client,user.id):{ok:true,appearance:body.productId});
  }
  if(path!=='/api/store/packages/buy'&&path!=='/api/store/buy')return json({error:'Không tìm thấy tính năng cửa hàng.'},404);
  const targetId=path==='/api/store/buy'?(body.productId||body.packageId):body.productId;
  const baseProduct=STORE_PACKAGES.find(x=>x.id===targetId&&x.available);
  if(!baseProduct||typeof body.requestId!=='string'||!/^[A-Za-z0-9_-]{16,80}$/.test(body.requestId))return json({error:'Gói hoặc giá không hợp lệ.'},400);
  const econRow=(await client.query('SELECT data FROM kinnect_core.economy_config WHERE id=1')).rows[0];
  const econData={...DEFAULT_ECONOMY,...(econRow?.data||{})};
  const product={...baseProduct,priceCoins:effectivePrice(baseProduct,econData.giftPrices)};
  if(body.priceCoins!==undefined&&body.priceCoins!==null&&body.priceCoins!==product.priceCoins)return json({error:'Gói hoặc giá không hợp lệ.'},400);
  await client.query('BEGIN');try{
   const account=(await client.query('SELECT role,suspended FROM kinnect_core.users WHERE id=$1 FOR UPDATE',[user.id])).rows[0];if(!account||account.suspended)fail(401,'Tài khoản không còn hoạt động.');
   const adminPrior=(await client.query('SELECT product_id FROM kinnect_core.admin_package_events WHERE user_id=$1 AND request_id=$2',[user.id,body.requestId])).rows[0];
   const prior=(await client.query('SELECT product_id FROM kinnect_core.store_packages WHERE user_id=$1 AND request_id=$2',[user.id,body.requestId])).rows[0];
   if((adminPrior||prior)&&(adminPrior||prior).product_id!==product.id)fail(409,'Mã giao dịch không khớp.');
   const duplicate=!!(adminPrior||prior);
   if(!duplicate){
    const state=await commerceState(client,user.id),source=body.coinSource||'gifted';
    if(!['gifted','purchased'].includes(source))fail(400,'Nguồn xu không hợp lệ.');
    if(source==='gifted'&&!state.trialPackagePurchases)fail(403,'Thử nghiệm đã kết thúc. Gói mới cần Xu mua.');
    if(product.kind==='gifts'&&source==='purchased')fail(503,'Gói quà bằng Xu mua chờ kết nối thanh toán và chi trả.');
    if(product.kind==='studio'&&state.studioProPermanent)fail(409,'Gói vẫn còn hạn.');
    if(product.kind!=='gifts'&&product.kind!=='studio'&&(state.ownedPackages.includes(product.id)||product.kind==='member'&&state.membership))fail(409,'Gói vẫn còn hạn.');
    if((source==='gifted'?state.giftedCoins:state.purchasedCoins)<product.priceCoins)fail(402,'Chưa đủ xu.');
    const now=Date.now();
    const lineUntil=product.kind==='studio'?(product.line==='video'?state.studioVideoUntil:product.line==='photo'?state.studioPhotoUntil:state.studioProUntil):0;
    const expires=product.days?(product.kind==='studio'?Math.max(now,lineUntil):now)+product.days*86400000:253402300799000;
    await client.query('INSERT INTO kinnect_core.wallet_entries VALUES($1,$2,$3,$4,$5,0,0,0,$6)',[randomUUID(),user.id,'store-package:'+body.requestId,source==='gifted'?'store_trial':'store_paid',-product.priceCoins,now]);
    await client.query('INSERT INTO kinnect_core.store_packages VALUES($1,$2,$3,$4,$5)',[user.id,body.requestId,product.id,expires,now]);
    if(product.kind==='gifts'&&Array.isArray(product.contents)){for(const [gift,qty]of product.contents)await client.query('INSERT INTO kinnect_core.gift_inventory VALUES($1,$2,$3,$4,$5,$6)',[randomUUID(),user.id,gift,qty,source,now]);}
   }
   await client.query('COMMIT');return json({...await commerceState(client,user.id),duplicate,adminPurchase:false});
  }catch(error){await client.query('ROLLBACK');throw error;}
 }catch(error){if(error.status)return json({error:error.message},error.status);throw error;}
}
