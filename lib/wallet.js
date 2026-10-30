import {randomUUID} from 'node:crypto';

// Payment and payout adapters are deliberately required before money can move.
export function createWallet({db,body,fail,economy}) {
 db.exec(`CREATE TABLE IF NOT EXISTS wallet_entries(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,reference TEXT NOT NULL,kind TEXT NOT NULL,coins INTEGER NOT NULL DEFAULT 0,net_vnd INTEGER NOT NULL DEFAULT 0,creator_vnd INTEGER NOT NULL DEFAULT 0,platform_vnd INTEGER NOT NULL DEFAULT 0,created INTEGER NOT NULL,UNIQUE(user_id,reference));
 CREATE INDEX IF NOT EXISTS wallet_owner ON wallet_entries(user_id,created);`);
 db.exec(`CREATE TABLE IF NOT EXISTS wallet_trial_gifts(user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,request_id TEXT NOT NULL,room_id TEXT NOT NULL,gift_id TEXT NOT NULL,cost INTEGER NOT NULL,created INTEGER NOT NULL,PRIMARY KEY(user_id,request_id));`);
 if(!db.prepare("PRAGMA table_info(wallet_trial_gifts)").all().some(c=>c.name==='recipient_id'))db.exec('ALTER TABLE wallet_trial_gifts ADD COLUMN recipient_id TEXT REFERENCES users(id) ON DELETE SET NULL');
 if(economy)db.exec(`CREATE TRIGGER IF NOT EXISTS wallet_signup_trial_v1 AFTER INSERT ON users
 WHEN COALESCE((SELECT json_extract(data,'$.signupBonusEnabled') FROM economy_config WHERE id=1),0)=1
 BEGIN INSERT OR IGNORE INTO wallet_entries(id,user_id,reference,kind,coins,net_vnd,creator_vnd,platform_vnd,created)
 SELECT lower(hex(randomblob(16))),NEW.id,'signup-trial-v1','signup_trial',json_extract(data,'$.signupBonusCoins'),0,0,0,NEW.created FROM economy_config WHERE id=1; END;`);
 db.exec("CREATE TABLE IF NOT EXISTS gift_inventory(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,gift_id TEXT NOT NULL,quantity INTEGER NOT NULL CHECK(quantity>=0),source TEXT NOT NULL,created INTEGER NOT NULL)");
 const unlimited=id=>{try{return db.prepare("SELECT 1 FROM users WHERE id=? AND role='admin' AND suspended=0").get(id)!==undefined;}catch{return false;}};
 const purchasedBalance=id=>Number(db.prepare("SELECT COALESCE(SUM(coins),0) n FROM wallet_entries WHERE user_id=? AND kind IN ('coin_purchase','live_gift_paid','store_paid')").get(id).n);
 const trialBalance=id=>Number(db.prepare("SELECT COALESCE(SUM(coins),0) n FROM wallet_entries WHERE user_id=? AND kind IN ('signup_trial','live_gift_trial','store_trial','admin_trial')").get(id).n);
 function spendTrialGift({userId,requestId,roomId,giftId,version,recipientId=null}){
  if(typeof requestId!=='string'||!/^[A-Za-z0-9_-]{16,80}$/.test(requestId))throw Object.assign(Error('Hãy cập nhật ứng dụng để tặng quà bằng xu.'),{status:400});
  db.exec('BEGIN IMMEDIATE');try{const {version:current,config}=economy.read(),cost=config.giftPrices[giftId];if((!config.trialGiftsEnabled&&!unlimited(userId))||!Number.isSafeInteger(cost))throw Object.assign(Error('Quà trải nghiệm đang tạm dừng.'),{status:503});const prior=db.prepare('SELECT * FROM wallet_trial_gifts WHERE user_id=? AND request_id=?').get(userId,requestId);if(prior){if(prior.room_id!==roomId||prior.gift_id!==giftId)throw Object.assign(Error('Yêu cầu quà không khớp.'),{status:409});db.exec('COMMIT');return {duplicate:true,balance:trialBalance(userId),costCoins:Math.abs(db.prepare("SELECT coins FROM wallet_entries WHERE user_id=? AND reference=?").get(userId,'trial-gift:'+requestId)?.coins||0),requestId};}
   if(version!==current)throw Object.assign(Error('Giá quà vừa thay đổi. Mở lại bảng quà.'),{status:409});const stock=db.prepare("SELECT id FROM gift_inventory WHERE user_id=? AND gift_id=? AND source='gifted' AND quantity>0 ORDER BY created,id LIMIT 1").get(userId,giftId),spend=unlimited(userId)||stock?0:cost;if(trialBalance(userId)<spend)throw Object.assign(Error('Chưa đủ xu trải nghiệm.'),{status:402});const at=Date.now();if(stock&&!unlimited(userId))db.prepare('UPDATE gift_inventory SET quantity=quantity-1 WHERE id=? AND quantity>0').run(stock.id);db.prepare('INSERT INTO wallet_entries VALUES(?,?,?,?,?,?,?,?,?)').run(randomUUID(),userId,'trial-gift:'+requestId,'live_gift_trial',-spend,0,0,0,at);db.prepare('INSERT INTO wallet_trial_gifts(user_id,request_id,room_id,gift_id,cost,created,recipient_id) VALUES(?,?,?,?,?,?,?)').run(userId,requestId,roomId,giftId,cost,at,recipientId);const balance=trialBalance(userId);db.exec('COMMIT');return {duplicate:false,balance,costCoins:spend,fromInventory:!!stock,requestId};
  }catch(e){db.exec('ROLLBACK');throw e;}
 }
 function state(userId){
  const entries=db.prepare('SELECT id,kind,coins,net_vnd AS netVnd,creator_vnd AS creatorVnd,platform_vnd AS platformVnd,created FROM wallet_entries WHERE user_id=? ORDER BY created DESC LIMIT 50').all(userId);
  const totals=db.prepare('SELECT COALESCE(SUM(coins),0) coins,COALESCE(SUM(creator_vnd),0) earningsVnd FROM wallet_entries WHERE user_id=?').get(userId);
  const rate=economy?economy.read().config.vndPerCoin:100,paid=purchasedBalance(userId),giftedGiftValueCoins=Number(db.prepare("SELECT COALESCE(SUM(cost),0) n FROM wallet_trial_gifts WHERE recipient_id=?").get(userId).n);
  return {...totals,unlimitedCoins:unlimited(userId),giftedGiftValueCoins,purchasedRefundableVnd:paid*rate,giftIncomeWithdrawableVnd:totals.earningsVnd,giftedCoins:trialBalance(userId),purchasedCoins:purchasedBalance(userId),withdrawableVnd:paid*rate+totals.earningsVnd,coinPolicy:{giftedWithdrawable:false,purchasedGiftIncomeWithdrawable:true,purchasedCoinsDirectWithdrawal:true},trialCoins:trialBalance(userId),coinPacks:economy?economy.packs():[],vndPerCoin:economy?economy.read().config.vndPerCoin:100,entries,creatorPercent:75,platformPercent:25,topUpEnabled:false,payoutEnabled:false,currency:'VND',status:'awaiting_payment_and_payout_providers'};
 }
 // Internal settlement only: never exposed as an HTTP credit endpoint.
 function recordCreatorSettlement({userId,reference,netVnd}){
  if(typeof reference!=='string'||reference.length<8||reference.length>200||!Number.isSafeInteger(netVnd)||netVnd<=0||netVnd>100000000)throw Error('Invalid settlement');
  const prior=db.prepare('SELECT * FROM wallet_entries WHERE user_id=? AND reference=?').get(userId,reference);
  if(prior){if(prior.net_vnd!==netVnd)throw Error('Settlement reference mismatch');return state(userId);}
  const creator=Math.floor(netVnd*75/100),platform=netVnd-creator;
  db.prepare('INSERT INTO wallet_entries VALUES(?,?,?,?,?,?,?,?,?)').run(randomUUID(),userId,reference,'creator_settlement',0,netVnd,creator,platform,Date.now());return state(userId);
 }
 return {state,unlimited,trialBalance,purchasedBalance,spendTrialGift,recordCreatorSettlement,async route(req,res,path,json,me){
  if(path==='/api/wallet'&&req.method==='GET'){json(200,state(me.id));return true;}
  if(['/api/wallet/top-up','/api/wallet/withdraw','/api/wallet/gift','/api/wallet/buy'].includes(path)&&req.method==='POST'){
   await body(req,4096);fail(503,'Ví đang chờ kết nối thanh toán và chi trả. Chưa phát sinh giao dịch.');
  }
  return false;
 }};
}
