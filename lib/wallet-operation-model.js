import {randomUUID} from 'node:crypto';
export const walletFailure=(status,message)=>{const e=new Error(message);e.status=status;throw e;};
export const walletTTL=kind=>kind==='gift'?600000:86400000;
export function walletDraft(input,me){
 const fail=walletFailure;if(!input||typeof input!=='object'||Array.isArray(input))fail(400,'Dữ liệu đề nghị không hợp lệ.');const kind=input.kind;
 if(!['gift','paid_correction'].includes(kind))fail(400,'Chọn loại nghiệp vụ hợp lệ.');
 if(me.role!=='admin'&&(me.team!=='finance'||kind==='gift'))fail(403,'Chỉ Admin tặng xu; bộ phận tài chính chỉ lập đề nghị bù xu mua.');
 const title=typeof input.title==='string'?input.title.trim():'',reason=typeof input.reason==='string'?input.reason.trim():'';
 if(title.length<3||title.length>120||reason.length<10||reason.length>2000)fail(400,'Nhập tiêu đề 3–120 ký tự và lý do 10–2.000 ký tự.');
 if(!Number.isSafeInteger(input.coins)||input.coins<1||input.coins>1000000||typeof input.all!=='boolean')fail(400,'Số xu mỗi người phải từ 1 đến 1.000.000.');
 const ids=input.userIds;if(!Array.isArray(ids)||ids.some(x=>typeof x!=='string'||x.length>100)||ids.length>500||new Set(ids).size!==ids.length)fail(400,'Danh sách người nhận không hợp lệ.');
 if(input.all?(ids.length||kind!=='gift'):!ids.length)fail(400,'Chọn toàn bộ hoặc danh sách người nhận cụ thể.');
 if(kind==='paid_correction'&&(input.all||ids.length!==1))fail(400,'Mỗi đề nghị bù chỉ dành cho một tài khoản.');
 const reference=kind==='paid_correction'&&typeof input.reference==='string'?input.reference.trim().toLowerCase():'';
 if(kind==='paid_correction'&&!/^[a-z0-9][a-z0-9._:/-]{5,119}$/.test(reference))fail(400,'Nhập mã giao dịch gốc 6–120 ký tự, không chứa khoảng trắng.');
 const ticketId=typeof input.ticketId==='string'?input.ticketId.trim():'';if(ticketId.length>100)fail(400,'Mã phiếu quá dài.');
 return {id:randomUUID(),kind,title,coins:input.coins,all:input.all,userIds:ids,reference:reference||'gift:'+randomUUID(),reason,ticketId};
}
export function walletSummary(row,now=Date.now()){
 const ids=typeof row.targets==='string'?JSON.parse(row.targets):row.targets;
 return {id:row.id,kind:row.kind,title:row.title,coins:Number(row.coins),count:ids.length,totalCoins:Number(row.coins)*ids.length,state:row.state==='pending'&&Number(row.created)+walletTTL(row.kind)<now?'expired':row.state,created:Number(row.created),completed:row.completed===null?null:Number(row.completed),createdBy:row.created_by,approvedBy:row.approved_by,reference:row.kind==='gift'?'':row.reference,reason:row.reason,ticketId:row.ticket_id||'',expiresAt:Number(row.created)+walletTTL(row.kind),rejectionReason:row.rejection_reason||''};
}
export function verifyWalletTargets(draft,people){if(!people.length||people.length>10000||people.length*draft.coins>1000000000)walletFailure(400,'Chọn 1–10.000 thành viên và tổng không quá 1 tỷ xu.');if(!draft.all&&(people.length!==draft.userIds.length||people.some(p=>!draft.userIds.includes(p.id))))walletFailure(409,'Danh sách người nhận đã thay đổi. Chỉ chọn thành viên thường đang hoạt động.');}
