import {randomUUID} from 'node:crypto';
export const STORE_PACKAGES=Object.freeze([
 ...[['neon','Neon',300,'#7c3aed','#06b6d4'],['aurora','Cực quang',500,'#8b5cf6','#ec4899'],['galaxy','Galaxy',800,'#312e81','#a855f7']].map(([id,name,priceCoins,...colors])=>({id:'style_'+id,kind:'style',name,priceCoins,colors,period:'Vĩnh viễn',description:'Khung avatar, nền hồ sơ và màu hội thoại.',available:false})),
 ...[['chill','Chill',500,'#0d9488','#38bdf8'],['gaming','Gaming',800,'#4f46e5','#f43f5e'],['spotlight','Spotlight',1200,'#a16207','#fbbf24']].map(([id,name,priceCoins,...colors])=>({id:'live_'+id,kind:'live',name,priceCoins,colors,period:'Vĩnh viễn',description:'Bộ trang trí phòng Live. Không bao gồm quyền phát Live Game.',available:false})),
 {id:'live_game_30',kind:'live',name:'Live Game',priceCoins:490,days:30,period:'30 ngày',colors:['#6d28d9','#db2777'],description:'Phát màn hình game, bình luận nổi và trả lời bình luận. Live trò chuyện và xem Live luôn miễn phí.',available:true},
 ...[['love','Yêu thương',300,'#db2777','#fb7185'],['speed','Tốc độ',1000,'#2563eb','#06b6d4'],['royal','Hoàng gia',2000,'#7e22ce','#eab308']].map(([id,name,priceCoins,...colors])=>({id:'gift_'+id,kind:'gifts',name,priceCoins,colors,period:'Bộ quà',description:'Quà tiêu hao khi gửi. Bộ quà đang được chuẩn bị; có thể tặng từng quà trong phòng Live.',available:false})),
 ...[['plus','Plus',490,'#4338ca','#a78bfa'],['creator','Creator',990,'#c026d3','#fb923c']].map(([id,name,priceCoins,...colors])=>({id:'member_'+id,kind:'member',name,priceCoins,days:30,colors,period:'30 ngày',description:'Huy hiệu và bộ tùy chỉnh thành viên đang được chuẩn bị.',available:false})),
 ...[[7,190,'7 ngày'],[30,490,'1 tháng'],[365,3990,'1 năm']].map(([days,priceCoins,period])=>({id:'studio_'+days,kind:'studio',name:'Studio Pro',priceCoins,days,period,colors:['#7c3aed','#c026d3'],description:'Chỉnh ảnh và video nâng cao trong cùng một gói. Không tự gia hạn hay tự trừ xu.',available:true}))
]);
export function createPackageStore({db,wallet,economy,body,fail,clock=Date.now}){
 db.exec(`CREATE TABLE IF NOT EXISTS store_packages(user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,request_id TEXT NOT NULL,product_id TEXT NOT NULL,expires INTEGER NOT NULL,created INTEGER NOT NULL,PRIMARY KEY(user_id,request_id));`);
 const gameUntil=id=>Number(db.prepare("SELECT COALESCE(MAX(expires),0) n FROM store_packages WHERE user_id=? AND product_id='live_game_30'").get(id).n);
 const studioUntil=id=>Number(db.prepare("SELECT COALESCE(MAX(expires),0) n FROM store_packages WHERE user_id=? AND product_id IN ('studio_7','studio_30','studio_365')").get(id).n);
 const state=id=>({packages:STORE_PACKAGES.map(p=>({...p,referenceVnd:p.priceCoins*economy.read().config.vndPerCoin})),trialCoins:wallet.trialBalance(id),liveGameUntil:gameUntil(id),studioProUntil:studioUntil(id),chatLiveFree:true});
 return {state,studioAllowed:id=>studioUntil(id)>clock(),gameAllowed:id=>gameUntil(id)>clock(),async route(req,res,path,json,me){
 if(path!=='/api/store/packages/buy')return false;if(req.method!=='POST')fail(405,'Phương thức không hợp lệ.');const b=await body(req,2048);
 const product=STORE_PACKAGES.find(p=>p.id===b.productId&&p.available);if(!product||b.priceCoins!==product.priceCoins||typeof b.requestId!=='string'||!/^[A-Za-z0-9_-]{16,80}$/.test(b.requestId))fail(400,'Gói hoặc giá không hợp lệ.');
 db.exec('BEGIN IMMEDIATE');try{const prior=db.prepare('SELECT * FROM store_packages WHERE user_id=? AND request_id=?').get(me.id,b.requestId);if(prior){if(prior.product_id!==b.productId)fail(409,'Mã giao dịch đã dùng cho gói khác.');db.exec('COMMIT');json(200,{...state(me.id),duplicate:true});return true;}
 if((product.kind==='studio'?studioUntil(me.id):gameUntil(me.id))>clock())fail(409,'Gói vẫn còn hạn.');if(wallet.trialBalance(me.id)<product.priceCoins)fail(402,'Chưa đủ xu.');const at=clock();db.prepare('INSERT INTO wallet_entries VALUES(?,?,?,?,?,?,?,?,?)').run(randomUUID(),me.id,'store-trial:'+b.requestId,'store_trial',-product.priceCoins,0,0,0,at);db.prepare('INSERT INTO store_packages VALUES(?,?,?,?,?)').run(me.id,b.requestId,b.productId,at+product.days*86400000,at);db.exec('COMMIT');json(200,state(me.id));return true;
 }catch(e){if(db.isTransaction)db.exec('ROLLBACK');throw e;}
 }};
}
