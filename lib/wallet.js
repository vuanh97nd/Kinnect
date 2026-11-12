import {randomUUID} from 'node:crypto';
import {LIVE_GIFTS} from './live-gifts.js';
import {STORE_PACKAGES} from './store-packages.js';

// Payment and payout adapters are deliberately required before money can move.
export function createWallet({db,body,fail,economy}) {
 db.exec(`CREATE TABLE IF NOT EXISTS wallet_entries(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,reference TEXT NOT NULL,kind TEXT NOT NULL,coins INTEGER NOT NULL DEFAULT 0,net_vnd INTEGER NOT NULL DEFAULT 0,creator_vnd INTEGER NOT NULL DEFAULT 0,platform_vnd INTEGER NOT NULL DEFAULT 0,created INTEGER NOT NULL,UNIQUE(user_id,reference));
 CREATE INDEX IF NOT EXISTS wallet_owner ON wallet_entries(user_id,created);`);
 db.exec(`CREATE TABLE IF NOT EXISTS wallet_trial_gifts(user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,request_id TEXT NOT NULL,room_id TEXT NOT NULL,gift_id TEXT NOT NULL,cost INTEGER NOT NULL,created INTEGER NOT NULL,PRIMARY KEY(user_id,request_id));`);
 if(!db.prepare("PRAGMA table_info(wallet_trial_gifts)").all().some(c=>c.name==='recipient_id'))db.exec('ALTER TABLE wallet_trial_gifts ADD COLUMN recipient_id TEXT REFERENCES users(id) ON DELETE SET NULL');
 if(!db.prepare("PRAGMA table_info(wallet_trial_gifts)").all().some(c=>c.name==='quantity'))db.exec('ALTER TABLE wallet_trial_gifts ADD COLUMN quantity INTEGER NOT NULL DEFAULT 1');
 if(economy)db.exec(`CREATE TRIGGER IF NOT EXISTS wallet_signup_trial_v1 AFTER INSERT ON users
 WHEN COALESCE((SELECT json_extract(data,'$.signupBonusEnabled') FROM economy_config WHERE id=1),0)=1
 BEGIN INSERT OR IGNORE INTO wallet_entries(id,user_id,reference,kind,coins,net_vnd,creator_vnd,platform_vnd,created)
 SELECT lower(hex(randomblob(16))),NEW.id,'signup-trial-v1','signup_trial',json_extract(data,'$.signupBonusCoins'),0,0,0,NEW.created FROM economy_config WHERE id=1; END;`);
 db.exec("CREATE TABLE IF NOT EXISTS gift_inventory(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,gift_id TEXT NOT NULL,quantity INTEGER NOT NULL CHECK(quantity>=0),source TEXT NOT NULL,created INTEGER NOT NULL)");

 const purchasedBalance=id=>Number(db.prepare("SELECT COALESCE(SUM(coins),0) n FROM wallet_entries WHERE user_id=? AND kind IN ('coin_purchase','live_gift_paid','store_paid')").get(id).n);
 const receivedGiftValue=id=>Number(db.prepare("SELECT COALESCE(SUM(cost),0) n FROM wallet_trial_gifts WHERE recipient_id=?").get(id).n);
 const trialBalance=id=>Number(db.prepare("SELECT COALESCE(SUM(coins),0) n FROM wallet_entries WHERE user_id=? AND kind IN ('signup_trial','live_gift_trial','store_trial','admin_trial','farm_trial')").get(id).n)+receivedGiftValue(id);
 const giftName=id=>LIVE_GIFTS.find(g=>g.id===id)?.name||id;
 const packageName=id=>STORE_PACKAGES.find(p=>p.id===id)?.name||id;
 function spendTrialGift({userId,requestId,roomId,giftId,quantity=1,version,recipientId=null}){
  if(recipientId&&recipientId===userId&&roomId!=='private')throw Object.assign(Error('Không thể tự tặng quà cho chính mình.'),{status:400});
  if(typeof requestId!=='string'||!/^[A-Za-z0-9_-]{16,80}$/.test(requestId))throw Object.assign(Error('Hãy cập nhật ứng dụng để tặng quà bằng xu.'),{status:400});
  const qty=Number.isSafeInteger(quantity)&&quantity>=1&&quantity<=99?quantity:1;
  db.exec('BEGIN IMMEDIATE');try{const {version:current,config}=economy.read(),unit=config.giftPrices[giftId];if(!config.trialGiftsEnabled||!Number.isSafeInteger(unit))throw Object.assign(Error('Quà trải nghiệm đang tạm dừng.'),{status:503});const prior=db.prepare('SELECT * FROM wallet_trial_gifts WHERE user_id=? AND request_id=?').get(userId,requestId);if(prior){if(prior.room_id!==roomId||prior.gift_id!==giftId)throw Object.assign(Error('Yêu cầu quà không khớp.'),{status:409});db.exec('COMMIT');return {duplicate:true,balance:trialBalance(userId),costCoins:Math.abs(db.prepare("SELECT coins FROM wallet_entries WHERE user_id=? AND reference=?").get(userId,'trial-gift:'+requestId)?.coins||0),quantity:prior.quantity||1,requestId};}
   if(version!==current)throw Object.assign(Error('Giá quà vừa thay đổi. Mở lại bảng quà.'),{status:409});
   const stocks=db.prepare("SELECT id,quantity FROM gift_inventory WHERE user_id=? AND gift_id=? AND source='gifted' AND quantity>0 ORDER BY created,id").all(userId,giftId);
   let fromStock=0;{let need=qty;for(const s of stocks){if(need<=0)break;const use=Math.min(need,s.quantity);fromStock+=use;need-=use;}}
   const cost=unit*qty,spend=unit*(qty-fromStock);if(trialBalance(userId)<spend)throw Object.assign(Error('Chưa đủ xu trải nghiệm.'),{status:402});const at=Date.now();
   if(fromStock>0){let need=fromStock;for(const s of stocks){if(need<=0)break;const use=Math.min(need,s.quantity);db.prepare('UPDATE gift_inventory SET quantity=quantity-? WHERE id=? AND quantity>=?').run(use,s.id,use);need-=use;}}
   db.prepare('INSERT INTO wallet_entries VALUES(?,?,?,?,?,?,?,?,?)').run(randomUUID(),userId,'trial-gift:'+requestId,'live_gift_trial',-spend,0,0,0,at);db.prepare('INSERT INTO wallet_trial_gifts(user_id,request_id,room_id,gift_id,cost,created,recipient_id,quantity) VALUES(?,?,?,?,?,?,?,?)').run(userId,requestId,roomId,giftId,cost,at,recipientId,qty);const balance=trialBalance(userId);db.exec('COMMIT');return {duplicate:false,balance,costCoins:spend,quantity:qty,fromInventory:fromStock>0,fromInventoryCount:fromStock,requestId};
  }catch(e){db.exec('ROLLBACK');throw e;}
 }
 function enrichEntries(userId,rows){
  return rows.map(e=>{
   const ref=e.reference||'';let title='',subtitle='',category='other',currency='trial';
   if(e.kind==='signup_trial'){title='Xu chào mừng';subtitle='Tặng khi đăng ký';category='grant';}
   else if(e.kind==='admin_trial'){title='Xu được tặng';subtitle='Quản trị viên Kinnect';category='grant';}
   else if(e.kind==='coin_purchase'){title='Nạp xu';subtitle='Xu mua';category='topup';currency='purchased';}
   else if(e.kind==='live_gift_trial'||e.kind==='live_gift_paid'){
    currency=e.kind==='live_gift_paid'?'purchased':'trial';category='spend';
    const reqId=ref.startsWith('trial-gift:')?ref.slice(11):ref;
    const g=db.prepare('SELECT g.gift_id,g.quantity,g.recipient_id,u.name recipientName FROM wallet_trial_gifts g LEFT JOIN users u ON u.id=g.recipient_id WHERE g.user_id=? AND g.request_id=?').get(userId,reqId);
    const qty=g?.quantity>1?' ×'+g.quantity:'';
    title=g?('Tặng '+giftName(g.gift_id)+qty):'Quà Live';
    subtitle=g?.recipientName?('Người nhận: '+g.recipientName):(currency==='purchased'?'Xu mua':'Xu tặng');
   }else if(e.kind==='store_trial'||e.kind==='store_paid'){
    currency=e.kind==='store_paid'?'purchased':'trial';category='spend';
    const reqId=ref.startsWith('store-package:')?ref.slice(14):ref;
    let p=null;try{p=db.prepare('SELECT product_id FROM store_packages WHERE user_id=? AND request_id=?').get(userId,reqId);}catch{}
    title=p?('Mua '+packageName(p.product_id)):'Gói cửa hàng';
    subtitle=currency==='purchased'?'Xu mua':'Xu tặng';
   }else if(e.kind==='farm_trial'){
    currency='trial';category=e.coins>=0?'grant':'spend';
    title=e.coins>=0?'Thu hoạch nông trại':'Mua vật phẩm nông trại';
    subtitle=e.coins>=0?'Xu tặng từ nông trại':'Xu tặng';
   }else if(e.kind==='creator_settlement'){
    currency='vnd';category='income';title='Thu nhập quà Live';subtitle='75% sau phí nền tảng';
   }
   const {reference,...rest}=e;return {...rest,title,subtitle,category,currency};
  });
 }
 function state(userId){
  const rawEntries=db.prepare('SELECT id,reference,kind,coins,net_vnd AS netVnd,creator_vnd AS creatorVnd,platform_vnd AS platformVnd,created FROM wallet_entries WHERE user_id=? ORDER BY created DESC LIMIT 50').all(userId);
  const entries=enrichEntries(userId,rawEntries);
  const totals=db.prepare('SELECT COALESCE(SUM(coins),0) coins,COALESCE(SUM(creator_vnd),0) earningsVnd FROM wallet_entries WHERE user_id=?').get(userId);
  const rate=economy?economy.read().config.vndPerCoin:100,paid=purchasedBalance(userId),trial=trialBalance(userId);
  const giftStats=db.prepare("SELECT COALESCE(SUM(cost),0) coins,COALESCE(SUM(COALESCE(quantity,1)),0) count FROM wallet_trial_gifts WHERE recipient_id=?").get(userId);
  const giftedGiftValueCoins=Number(giftStats.coins),receivedGiftCount=Number(giftStats.count);
  const spendStats=db.prepare("SELECT COALESCE(SUM(CASE WHEN coins<0 THEN -coins ELSE 0 END),0) spentCoins,COALESCE(SUM(CASE WHEN coins>0 THEN coins ELSE 0 END),0) grantedCoins FROM wallet_entries WHERE user_id=?").get(userId);
  return {...totals,unlimitedCoins:false,totalUsableCoins:trial+paid,giftedGiftValueCoins,receivedGiftCount,spentCoins:Number(spendStats.spentCoins),grantedCoins:Number(spendStats.grantedCoins),purchasedRefundableVnd:paid*rate,giftIncomeWithdrawableVnd:totals.earningsVnd,giftedCoins:trial,purchasedCoins:paid,withdrawableVnd:paid*rate+totals.earningsVnd,coinPolicy:{giftedWithdrawable:false,purchasedGiftIncomeWithdrawable:true,purchasedCoinsDirectWithdrawal:true},trialCoins:trial,coinPacks:economy?economy.packs():[],vndPerCoin:rate,entries,creatorPercent:75,platformPercent:25,topUpEnabled:false,payoutEnabled:false,currency:'VND',status:'awaiting_payment_and_payout_providers'};
 }
 // Internal settlement only: never exposed as an HTTP credit endpoint.
 function recordCreatorSettlement({userId,reference,netVnd}){
  if(typeof reference!=='string'||reference.length<8||reference.length>200||!Number.isSafeInteger(netVnd)||netVnd<=0||netVnd>100000000)throw Error('Invalid settlement');
  const prior=db.prepare('SELECT * FROM wallet_entries WHERE user_id=? AND reference=?').get(userId,reference);
  if(prior){if(prior.net_vnd!==netVnd)throw Error('Settlement reference mismatch');return state(userId);}
  const creator=Math.floor(netVnd*75/100),platform=netVnd-creator;
  db.prepare('INSERT INTO wallet_entries VALUES(?,?,?,?,?,?,?,?,?)').run(randomUUID(),userId,reference,'creator_settlement',0,netVnd,creator,platform,Date.now());return state(userId);
 }
 return {state,trialBalance,purchasedBalance,spendTrialGift,recordCreatorSettlement,async route(req,res,path,json,me){
  if(path==='/api/wallet'&&req.method==='GET'){json(200,state(me.id));return true;}
  if(path==='/api/wallet/entries'&&req.method==='GET'){
   const u=new URL(req.url,'http://localhost'),cat=u.searchParams.get('category')||'all',before=Number(u.searchParams.get('before'))||Date.now()+1000;
   const raw=db.prepare('SELECT id,reference,kind,coins,net_vnd AS netVnd,creator_vnd AS creatorVnd,platform_vnd AS platformVnd,created FROM wallet_entries WHERE user_id=? AND created<? ORDER BY created DESC LIMIT 50').all(me.id,before);
   const list=enrichEntries(me.id,raw).filter(e=>cat==='all'||e.category===cat);
   json(200,{entries:list});return true;
  }
  if(['/api/wallet/top-up','/api/wallet/withdraw','/api/wallet/gift','/api/wallet/buy'].includes(path)&&req.method==='POST'){
   await body(req,4096);fail(503,'Ví đang chờ kết nối thanh toán và chi trả. Chưa phát sinh giao dịch.');
  }
  return false;
 }};
}
