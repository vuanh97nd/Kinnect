import {randomUUID} from 'node:crypto';
import {liveRoomBlocks} from './live-access.js';
export const LIVE_GIFTS=Object.freeze([
 {id:'rose',name:'Hoa hồng',legacy:'rose'},
 {id:'star',name:'Sao pha lê',legacy:'star'},
 {id:'crown',name:'Vương miện',legacy:'crown'},
 {id:'aurora',name:'Cực quang',legacy:'star'},
 {id:'meteor',name:'Sao băng',legacy:'star'},
 {id:'butterfly',name:'Bướm mộng',legacy:'star'},
 {id:'lotus',name:'Sen ánh sáng',legacy:'rose'},
 {id:'car',name:'Siêu xe',legacy:'crown'},
 {id:'yacht',name:'Du thuyền',legacy:'crown'},
 {id:'castle',name:'Lâu đài',legacy:'crown'},
]);
/** Trial-coin gifts: atomic server debit, no payment or withdrawable creator settlement. */
export function createLiveGifts({send,social,env=process.env,now=Date.now}={}){
 const enabled=()=>env.KINNECT_LIVE_GIFTS_FREE!=='false'&&social.economy.read().config.trialGiftsEnabled;
 const catalog=userId=>({...social.economy.giftCatalog(),enabled:enabled(),balance:userId?social.wallet.trialBalance(userId):0});
 function handle(room,ws,m,account){if(m.type!=='live-reaction')return false;const gift=LIVE_GIFTS.find(g=>g.id===m.kind),heart=m.kind==='heart';if(!heart&&!gift)return true;const time=now();if(time-((heart?ws.reactionAt:ws.giftAt)||0)<(heart?350:1200))return true;
  if(!heart&&!enabled()){send(ws,{type:'live-mode-error',room:room.id,message:'Quà trải nghiệm đang tạm dừng.'});return true;}
  room.giftBudget??={at:time,gifts:0,hearts:0};if(time-room.giftBudget.at>=1000)room.giftBudget={at:time,gifts:0,hearts:0};const bucket=heart?'hearts':'gifts';if(room.giftBudget[bucket]>=(heart?20:6)){if(!heart)send(ws,{type:'live-mode-error',room:room.id,message:'Phòng đang có nhiều quà. Thử lại sau.'});return true;}
  let receipt;if(gift&&m.fundingSource&&m.fundingSource!=="gifted"){send(ws,{type:"live-gift-error",room:room.id,message:"Xu mua chưa mở. Hãy dùng xu tặng.",balance:social.wallet.trialBalance(ws.userId)});return true;}if(gift){try{receipt=social.wallet.spendTrialGift({userId:ws.userId,roomId:room.id,giftId:gift.id,requestId:m.requestId,version:m.priceVersion,recipientId:room.host.userId});send(ws,{type:'live-gift-receipt',room:room.id,fundingSource:'gifted',withdrawable:false,...receipt});if(receipt.duplicate)return true;}catch(e){send(ws,{type:'live-gift-error',room:room.id,message:e.message,balance:social.wallet.trialBalance(ws.userId),catalog:catalog(ws.userId)});return true;}}
  if(heart)ws.reactionAt=time;else ws.giftAt=time;room.giftBudget[bucket]++;const blocked=liveRoomBlocks(social,room),event={type:'live-reaction',room:room.id,id:randomUUID(),kind:heart?'heart':gift.legacy,...(gift?{giftId:gift.id,giftName:gift.name,fundingSource:"gifted",withdrawable:false}:{}),name:account.name,senderId:ws.userId,free:heart,experience:!!gift,costCoins:receipt?.costCoins||0,created:time};
  for(const peer of room.members.values())if(!blocked.has(peer.userId,ws.userId))send(peer,event);return true;
 }
 return {catalog,handle};
}
