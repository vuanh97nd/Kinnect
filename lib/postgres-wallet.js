// Internal repository only. No public credit/top-up/payout endpoint.
export function createPostgresWallet({client}){
 return {async state(userId){
  const account=await client.query('SELECT role,suspended FROM kinnect_core.users WHERE id=$1',[userId]);
  if(!account.rows.length||account.rows[0].suspended)throw Object.assign(Error('Account unavailable'),{status:403});
  const totals=await client.query(`SELECT
   COALESCE(SUM(coins) FILTER(WHERE kind IN ('signup_trial','live_gift_trial','live_gift_received_trial','store_trial','admin_trial','farm_trial')),0)::text AS gifted,
   COALESCE(SUM(coins) FILTER(WHERE kind IN ('coin_purchase','live_gift_paid','store_paid')),0)::text AS purchased,
   COALESCE(SUM(creator_vnd),0)::text AS earnings
   FROM kinnect_core.wallet_entries WHERE user_id=$1`,[userId]);
  const value=totals.rows[0];
  const safe=raw=>{const n=Number(raw);if(!Number.isSafeInteger(n))throw Error('Wallet value exceeds safe integer range');return n;};
  let receivedGifts=0;
  const giftTable=await client.query("SELECT 1 FROM information_schema.columns WHERE table_schema='kinnect_core' AND table_name='wallet_trial_gifts' AND column_name='recipient_id' LIMIT 1");
  if(giftTable?.rows?.length){
   const gifts=await client.query('SELECT COALESCE(SUM(cost),0)::text AS received FROM kinnect_core.wallet_trial_gifts WHERE recipient_id=$1',[userId]);
   receivedGifts=safe(gifts.rows[0]?.received??0);
  }
  const gifted=safe(safe(value.gifted)+receivedGifts);
  return {unlimitedCoins:false,giftedCoins:gifted,purchasedCoins:safe(value.purchased),giftIncomeWithdrawableVnd:safe(value.earnings),topUpEnabled:false,payoutEnabled:false};
 }};
}
