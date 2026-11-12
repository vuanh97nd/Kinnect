import {randomUUID} from 'node:crypto';
import {liveRoomBlocks} from './live-access.js';
export const LIVE_GIFTS=Object.freeze([
 {id:'rose',name:'Hoa hồng',legacy:'rose',tier:'small',comboable:true},
 {id:'heart',name:'Trái tim',legacy:'heart',tier:'small',comboable:true},
 {id:'coffee',name:'Cà phê',legacy:'star',tier:'small',comboable:true},
 {id:'love_gun',name:'Súng tình yêu',legacy:'star',tier:'medium',comboable:true},
 {id:'fireworks',name:'Pháo hoa',legacy:'star',tier:'medium',comboable:true},
 {id:'star',name:'Sao pha lê',legacy:'star',tier:'small',comboable:true},
 {id:'crown',name:'Vương miện',legacy:'crown',tier:'medium',comboable:true},
 {id:'diamond',name:'Kim cương',legacy:'crown',tier:'medium',comboable:true},
 {id:'car',name:'Siêu xe',legacy:'crown',tier:'large',comboable:true},
 {id:'sports_car',name:'Siêu xe thể thao',legacy:'crown',tier:'large',comboable:true},
 {id:'yacht',name:'Du thuyền',legacy:'crown',tier:'large',comboable:false},
 {id:'castle',name:'Lâu đài',legacy:'crown',tier:'legendary',comboable:false},
 {id:'aurora',name:'Cực quang',legacy:'star',tier:'medium',comboable:true},
 {id:'meteor',name:'Sao băng',legacy:'star',tier:'medium',comboable:true},
 {id:'butterfly',name:'Bướm mộng',legacy:'star',tier:'small',comboable:true},
 {id:'lotus',name:'Sen ánh sáng',legacy:'rose',tier:'medium',comboable:true},
]);
/** Trial-coin gifts: atomic server debit, no payment or withdrawable creator settlement. */
export function createLiveGifts({send,social,env=process.env,now=Date.now}={}){
 const enabled=()=>env.KINNECT_LIVE_GIFTS_FREE!=='false'&&social.economy.read().config.trialGiftsEnabled;
 const enabledFor=id=>enabled();
 const catalog=userId=>({...social.economy.giftCatalog(),enabled:!!enabledFor(userId),unlimitedCoins:false,balance:userId?social.wallet.trialBalance(userId):0,inventory:userId&&social.packageStore?social.packageStore.inventory(userId).filter(x=>x.source==='gifted'):[]});
 function ranking(room){const list=[...(room.giftSenders?.values()||[])].sort((a,b)=>b.coins-a.coins||b.gifts-a.gifts||a.updated-b.updated).slice(0,10);return {totalCoins:room.giftTotalCoins||0,totalGifts:room.giftTotalCount||0,topSenders:list,goal:room.giftGoal||null};}
 function handle(room,ws,m,account){
  if(m.type==='live-gift-ranking'){send(ws,{type:'live-gift-ranking',room:room.id,...ranking(room),history:(room.giftHistory||[]).slice(-30).reverse()});return true;}
  if(m.type==='live-gift-goal'){if(ws!==room.host)return true;const target=Number(m.targetCoins)||0,title=typeof m.title==='string'?m.title.trim().slice(0,60):'';room.giftGoal=target>=50&&target<=1000000?{title:title||'Mục tiêu quà Live',targetCoins:Math.floor(target),progressCoins:room.giftTotalCoins||0}:null;const payload={type:'live-gift-goal',room:room.id,...ranking(room)};for(const peer of room.members.values())send(peer,payload);return true;}
  if(m.type!=='live-reaction')return false;
  const isFreeHeart=(m.free===true||(m.kind==='heart'&&!m.isGift&&!m.requestId&&!m.giftId));
  const gift=isFreeHeart?null:LIVE_GIFTS.find(g=>g.id===(m.giftId||m.gift||m.kind));
  const heart=isFreeHeart||(!gift&&m.kind==='heart');
  if(!heart&&!gift)return true;const time=now(),combo=!!(gift&&gift.comboable&&typeof m.comboId==='string'&&/^[A-Za-z0-9_-]{6,64}$/.test(m.comboId));if(time-((heart?ws.reactionAt:ws.giftAt)||0)<(heart?350:combo?350:1200))return true;
  if(!heart&&!enabledFor(ws.userId)){send(ws,{type:'live-mode-error',room:room.id,message:'Quà trải nghiệm đang tạm dừng.'});return true;}
  room.giftBudget??={at:time,gifts:0,hearts:0};if(time-room.giftBudget.at>=1000)room.giftBudget={at:time,gifts:0,hearts:0};const bucket=heart?'hearts':'gifts';if(room.giftBudget[bucket]>=(heart?20:6)){if(!heart)send(ws,{type:'live-mode-error',room:room.id,message:'Phòng đang có nhiều quà. Thử lại sau.'});return true;}
  const qty=gift&&Number.isSafeInteger(m.quantity)&&[1,2,5,10,50,99].includes(m.quantity)?m.quantity:1;
  const targetUserId=gift&&typeof m.targetUserId==='string'&&[...room.members.values()].some(p=>p.userId===m.targetUserId)?m.targetUserId:room.host.userId;
  if(gift&&targetUserId===ws.userId){send(ws,{type:'live-mode-error',room:room.id,message:'Bạn không thể tự tặng quà cho chính mình.'});return true;}
  const targetName=[...room.members.values()].find(p=>p.userId===targetUserId)?.name||social.user?.(targetUserId)?.name||room.host.name;
  let receipt;if(gift&&m.fundingSource&&m.fundingSource!=="gifted"){send(ws,{type:"live-gift-error",room:room.id,message:"Xu mua chưa mở. Hãy dùng xu tặng.",balance:social.wallet.trialBalance(ws.userId)});return true;}if(gift){try{receipt=social.wallet.spendTrialGift({userId:ws.userId,roomId:room.id,giftId:gift.id,quantity:qty,requestId:m.requestId,version:m.priceVersion,recipientId:targetUserId});send(ws,{type:'live-gift-receipt',room:room.id,fundingSource:'gifted',withdrawable:false,catalog:catalog(ws.userId),...receipt});if(receipt.duplicate)return true;}catch(e){send(ws,{type:'live-gift-error',room:room.id,message:e.message,balance:social.wallet.trialBalance(ws.userId),catalog:catalog(ws.userId)});return true;}}
  if(heart)ws.reactionAt=time;else ws.giftAt=time;room.giftBudget[bucket]++;
  let comboCount=1;if(gift){const unit=social.economy.read().config.giftPrices?.[gift.id]||receipt?.unitCostCoins||(receipt?.costCoins?Math.round(receipt.costCoins/qty):0),value=unit*qty;room.giftCombos??=new Map();const key=ws.userId+':'+gift.id+':'+(combo?m.comboId:'');const prior=combo?room.giftCombos.get(key):null;comboCount=prior&&time-prior.at<5000?prior.count+1:1;if(combo)room.giftCombos.set(key,{count:comboCount,at:time});room.giftSenders??=new Map();const senderStat=room.giftSenders.get(ws.userId)||{userId:ws.userId,name:account.name,coins:0,gifts:0,updated:time};senderStat.name=account.name;senderStat.coins+=value;senderStat.gifts+=qty;senderStat.updated=time;room.giftSenders.set(ws.userId,senderStat);room.giftTotalCoins=(room.giftTotalCoins||0)+value;room.giftTotalCount=(room.giftTotalCount||0)+qty;if(room.giftGoal)room.giftGoal.progressCoins=room.giftTotalCoins;room.giftHistory??=[];room.giftHistory.push({id:randomUUID(),senderId:ws.userId,name:account.name,recipientId:targetUserId,recipientName:targetName,giftId:gift.id,giftName:gift.name,tier:gift.tier,quantity:qty,comboCount,valueCoins:value,created:time});if(room.giftHistory.length>60)room.giftHistory.splice(0,room.giftHistory.length-60);}
  const blocked=liveRoomBlocks(social,room),rank=gift?ranking(room):null,event={type:'live-reaction',room:room.id,id:randomUUID(),kind:heart?'heart':gift.legacy,...(gift?{giftId:gift.id,giftName:gift.name,tier:gift.tier,quantity:qty,comboCount,comboId:combo?m.comboId:'',recipientId:targetUserId,recipientName:targetName,fundingSource:"gifted",withdrawable:false,ranking:rank}:{}),name:account.name,senderId:ws.userId,free:heart,experience:!!gift,costCoins:receipt?.costCoins||0,created:time};
  for(const peer of room.members.values())if(!blocked.has(peer.userId,ws.userId))send(peer,event);return true;
 }
 return {catalog,handle,ranking};
}
