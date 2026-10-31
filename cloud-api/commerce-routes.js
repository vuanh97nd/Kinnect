import {randomUUID} from 'node:crypto';
import {STORE_PACKAGES} from '../lib/store-packages.js';
import {STORE_PRODUCTS,storeAccountId} from '../lib/store.js';
import {createPostgresWallet} from '../lib/postgres-wallet.js';
import {DEFAULT_ECONOMY} from '../lib/economy.js';
const fail=(status,message)=>{throw Object.assign(Error(message),{status});};
export async function commerceState(client,userId){
 const account=(await client.query('SELECT role,suspended FROM kinnect_core.users WHERE id=$1',[userId])).rows[0];if(!account||account.suspended)fail(401,'Tài khoản không còn hoạt động.');
 const admin=account.role==='admin',now=Date.now();
 const config=(await client.query('SELECT data,version FROM kinnect_core.economy_config WHERE id=1')).rows[0];
 config.data={...DEFAULT_ECONOMY,...config.data};
 const wallet=await createPostgresWallet({client}).state(userId);
 const purchases=(await client.query('SELECT product_id,expires FROM kinnect_core.store_packages WHERE user_id=$1 AND expires>$2',[userId,now])).rows;
 const permanent=(await client.query("SELECT product_id FROM kinnect_core.store_purchases WHERE user_id=$1 AND state='PURCHASED' AND verified>$2",[userId,now-86400000])).rows.map(x=>x.product_id);
 const packages=admin?STORE_PACKAGES.map(x=>x.id):[...new Set(purchases.map(x=>x.product_id))];
 const until=ids=>admin?253402300799000:Math.max(0,...purchases.filter(x=>ids.includes(x.product_id)).map(x=>Number(x.expires)));
 const studioUntil=permanent.includes('kinnect_studio_pro')?253402300799000:until(['studio_7','studio_30','studio_365']);
 const owned=[...new Set([...permanent,...packages,...(admin?STORE_PRODUCTS.map(x=>x.id):[]),...(studioUntil>now?['kinnect_studio_pro']:[])])];
 const live=(await client.query('SELECT live FROM kinnect_core.package_preferences WHERE user_id=$1',[userId])).rows[0]?.live||'';
 const style=(await client.query('SELECT style FROM kinnect_core.store_preferences WHERE user_id=$1',[userId])).rows[0]?.style||'';
 const membership=packages.includes('member_creator')?'member_creator':packages.includes('member_plus')?'member_plus':'';
 const inventory=(await client.query('SELECT gift_id AS "giftId",source,SUM(quantity)::text quantity FROM kinnect_core.gift_inventory WHERE user_id=$1 AND quantity>0 GROUP BY gift_id,source',[userId])).rows.map(x=>({...x,quantity:Number(x.quantity)}));
 return {...wallet,adminAccess:admin,trialCoins:wallet.giftedCoins,packages:STORE_PACKAGES.map(x=>({...x,referenceVnd:x.priceCoins*config.data.vndPerCoin})),trialPackagePurchases:config.data.trialPackagePurchases,liveGameUntil:until(['live_game_30']),studioProUntil:studioUntil,chatLiveFree:true,ownedPackages:packages,liveTheme:packages.includes(live)?live:'',membership,giftInventory:inventory,studioProFree:false,studioProPermanent:admin||permanent.includes('kinnect_studio_pro'),products:STORE_PRODUCTS,owned,appearance:owned.includes(style)?style:'',accountId:storeAccountId(userId),billingReady:false,packageName:'app.kinnect.live',vndPerCoin:config.data.vndPerCoin,configVersion:Number(config.version)};
}
export async function commerceRoute({request,client,user,json}){
 const path=new URL(request.url).pathname;if(!path.startsWith('/api/store')&&path!=='/api/economy')return null;
 try{
  if(path==='/api/economy'&&request.method==='GET'){const row=(await client.query('SELECT data,version FROM kinnect_core.economy_config WHERE id=1')).rows[0];row.data={...DEFAULT_ECONOMY,...row.data};return json({version:Number(row.version),vndPerCoin:row.data.vndPerCoin,signupBonusCoins:row.data.signupBonusEnabled?row.data.signupBonusCoins:0,coinPacks:row.data.coinPacks.map(coins=>({id:'coins_'+coins,coins,referenceVnd:coins*row.data.vndPerCoin,checkoutEnabled:false})),checkoutEnabled:false});}
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
  if(path!=='/api/store/packages/buy')return json({error:'Không tìm thấy tính năng cửa hàng.'},404);
  const product=STORE_PACKAGES.find(x=>x.id===body.productId&&x.available);
  if(!product||body.priceCoins!==product.priceCoins||typeof body.requestId!=='string'||!/^[A-Za-z0-9_-]{16,80}$/.test(body.requestId))return json({error:'Gói hoặc giá không hợp lệ.'},400);
  await client.query('BEGIN');try{
   const account=(await client.query('SELECT role,suspended FROM kinnect_core.users WHERE id=$1 FOR UPDATE',[user.id])).rows[0];if(!account||account.suspended)fail(401,'Tài khoản không còn hoạt động.');
   const adminPrior=(await client.query('SELECT product_id FROM kinnect_core.admin_package_events WHERE user_id=$1 AND request_id=$2',[user.id,body.requestId])).rows[0];
   const prior=(await client.query('SELECT product_id FROM kinnect_core.store_packages WHERE user_id=$1 AND request_id=$2',[user.id,body.requestId])).rows[0];
   if((adminPrior||prior)&&((adminPrior||prior).product_id!==product.id||adminPrior&&account.role!=='admin'))fail(409,'Mã giao dịch không khớp.');
   const duplicate=!!(adminPrior||prior);
   if(!duplicate){
    if(account.role==='admin')await client.query('INSERT INTO kinnect_core.admin_package_events VALUES($1,$2,$3,$4)',[user.id,body.requestId,product.id,Date.now()]);
    else{
     const state=await commerceState(client,user.id),source=body.coinSource||'gifted';
     if(!['gifted','purchased'].includes(source))fail(400,'Nguồn xu không hợp lệ.');
     if(source==='gifted'&&!state.trialPackagePurchases)fail(403,'Thử nghiệm đã kết thúc. Gói mới cần Xu mua.');
     if(product.kind==='gifts'&&source==='purchased')fail(503,'Gói quà bằng Xu mua chờ kết nối thanh toán và chi trả.');
     if(product.kind!=='gifts'&&(state.ownedPackages.includes(product.id)||product.kind==='studio'&&state.studioProUntil>Date.now()||product.kind==='member'&&state.membership))fail(409,'Gói vẫn còn hạn.');
     if((source==='gifted'?state.giftedCoins:state.purchasedCoins)<product.priceCoins)fail(402,'Chưa đủ xu.');
     const now=Date.now();await client.query('INSERT INTO kinnect_core.wallet_entries VALUES($1,$2,$3,$4,$5,0,0,0,$6)',[randomUUID(),user.id,'store-package:'+body.requestId,source==='gifted'?'store_trial':'store_paid',-product.priceCoins,now]);
     await client.query('INSERT INTO kinnect_core.store_packages VALUES($1,$2,$3,$4,$5)',[user.id,body.requestId,product.id,product.days?now+product.days*86400000:253402300799000,now]);
     if(product.kind==='gifts'){const contents=product.id==='gift_love'?[['rose',6]]:product.id==='gift_speed'?[['car',1],['star',2]]:[['castle',1]];for(const [gift,qty]of contents)await client.query('INSERT INTO kinnect_core.gift_inventory VALUES($1,$2,$3,$4,$5,$6)',[randomUUID(),user.id,gift,qty,source,now]);}
    }
   }
   await client.query('COMMIT');return json({...await commerceState(client,user.id),duplicate,adminPurchase:account.role==='admin'});
  }catch(error){await client.query('ROLLBACK');throw error;}
 }catch(error){if(error.status)return json({error:error.message},error.status);throw error;}
}
