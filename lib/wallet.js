import {randomUUID} from 'node:crypto';

// Payment and payout adapters are deliberately required before money can move.
export function createWallet({db,body,fail}) {
 db.exec(`CREATE TABLE IF NOT EXISTS wallet_entries(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,reference TEXT NOT NULL,kind TEXT NOT NULL,coins INTEGER NOT NULL DEFAULT 0,net_vnd INTEGER NOT NULL DEFAULT 0,creator_vnd INTEGER NOT NULL DEFAULT 0,platform_vnd INTEGER NOT NULL DEFAULT 0,created INTEGER NOT NULL,UNIQUE(user_id,reference));
 CREATE INDEX IF NOT EXISTS wallet_owner ON wallet_entries(user_id,created);`);
 function state(userId){
  const entries=db.prepare('SELECT id,kind,coins,net_vnd AS netVnd,creator_vnd AS creatorVnd,platform_vnd AS platformVnd,created FROM wallet_entries WHERE user_id=? ORDER BY created DESC LIMIT 50').all(userId);
  const totals=db.prepare('SELECT COALESCE(SUM(coins),0) coins,COALESCE(SUM(creator_vnd),0) earningsVnd FROM wallet_entries WHERE user_id=?').get(userId);
  return {...totals,entries,creatorPercent:75,platformPercent:25,topUpEnabled:false,payoutEnabled:false,currency:'VND',status:'awaiting_payment_and_payout_providers'};
 }
 // Internal settlement only: never exposed as an HTTP credit endpoint.
 function recordCreatorSettlement({userId,reference,netVnd}){
  if(typeof reference!=='string'||reference.length<8||reference.length>200||!Number.isSafeInteger(netVnd)||netVnd<=0||netVnd>100000000)throw Error('Invalid settlement');
  const prior=db.prepare('SELECT * FROM wallet_entries WHERE user_id=? AND reference=?').get(userId,reference);
  if(prior){if(prior.net_vnd!==netVnd)throw Error('Settlement reference mismatch');return state(userId);}
  const creator=Math.floor(netVnd*75/100),platform=netVnd-creator;
  db.prepare('INSERT INTO wallet_entries VALUES(?,?,?,?,?,?,?,?,?)').run(randomUUID(),userId,reference,'creator_settlement',0,netVnd,creator,platform,Date.now());return state(userId);
 }
 return {state,recordCreatorSettlement,async route(req,res,path,json,me){
  if(path==='/api/wallet'&&req.method==='GET'){json(200,state(me.id));return true;}
  if(['/api/wallet/top-up','/api/wallet/withdraw','/api/wallet/gift','/api/wallet/buy'].includes(path)&&req.method==='POST'){
   await body(req,4096);fail(503,'Ví đang chờ kết nối thanh toán và chi trả. Chưa phát sinh giao dịch.');
  }
  return false;
 }};
}
