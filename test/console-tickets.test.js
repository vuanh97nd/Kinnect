import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { createConsoleTickets } from '../lib/console-tickets.js';

function setup(t) {
 const db = new DatabaseSync(':memory:'); db.exec('PRAGMA foreign_keys=ON; CREATE TABLE console_staff(id TEXT PRIMARY KEY,username TEXT,team TEXT,suspended INTEGER DEFAULT 0);');
 db.prepare('INSERT INTO console_staff VALUES(?,?,?,?)').run('support-one','hotro01','support',0);
  db.prepare('INSERT INTO console_staff VALUES(?,?,?,?)').run('operations-one','vanhanh01','operations',0);
 db.prepare('INSERT INTO console_staff VALUES(?,?,?,?)').run('finance-one','taichinh01','finance',0);
 db.prepare('INSERT INTO console_staff VALUES(?,?,?,?)').run('finance-disabled','taichinh_disabled','finance',1);
 const handle=createConsoleTickets(db); t.after(()=>db.close());
 const admin={id:'root',username:'admin',name:'Admin',role:'admin'}, support={id:'support-one',username:'hotro01',name:'Hỗ trợ 01',role:'support',team:'support'}, operations={id:'operations-one',username:'vanhanh01',name:'Vận hành 01',role:'support',team:'operations'}, finance={id:'finance-one',username:'taichinh01',name:'Tài chính 01',role:'support',team:'finance'};
 const call=(me,method,path,body={},query='')=>handle({me,method,path,body,url:new URL('http://test'+path+query)});
 const create=(me=support,data={})=>call(me,'POST','/tickets',{subject:'Không nhận được quà',description:'Khách hàng báo lỗi sau khi gửi quà.',priority:'high',team:'support',member:'customer01',...data}).ticket;
 const mutate=(me,ticket,data)=>call(me,'POST',`/tickets/${ticket.id}/events`,{version:ticket.version,...data}).ticket;
 return {db,call,create,mutate,admin,support,operations,finance};
}
const status=(fn,expected)=>assert.throws(fn,e=>e.status===expected);

test('support hands a case to finance and admin with one preserved collaborative history',t=>{
 const a=setup(t); let ticket=a.create();assert.equal(ticket.status,'open');assert.deepEqual(ticket.participantTeams,['support']);
 assert.equal(a.call(a.finance,'GET','/tickets').summary.total,0);
 ticket=a.mutate(a.support,ticket,{action:'transfer',team:'finance',message:'Tài chính kiểm tra giao dịch gửi quà.'});
 assert.deepEqual(ticket.participantTeams,['finance','support']);
 ticket=a.mutate(a.finance,ticket,{action:'status',status:'in_progress',message:'Đang đối soát giao dịch.'});
 ticket=a.mutate(a.finance,ticket,{action:'note',message:'Đã tìm thấy giao dịch cần admin xem xét.'});
 ticket=a.mutate(a.finance,ticket,{action:'transfer',team:'admin',message:'Trình admin quyết định hướng xử lý.'});
 ticket=a.mutate(a.admin,ticket,{action:'transfer',team:'finance',assignee:'finance-one',message:'Tài chính hoàn tất đối soát.'});
 assert.equal(ticket.assigneeUsername,'taichinh01');
 ticket=a.mutate(a.finance,ticket,{action:'status',status:'resolved',message:'Đã đối soát và phản hồi nhóm hỗ trợ.'});
 const detail=a.call(a.support,'GET',`/tickets/${ticket.id}`);
 assert.equal(detail.events.length,7);assert.equal(detail.eventTotal,7);assert.equal(detail.ticket.status,'resolved');assert.deepEqual(detail.ticket.participantTeams,['admin','finance','support']);
 assert.deepEqual(detail.events.map(x=>x.actor_team),['support','support','finance','finance','finance','admin','finance']);
 assert.equal(detail.events[0].before,null);assert.equal(detail.events[6].before.status,'open');assert.equal(detail.events[6].after.status,'resolved');
 assert.equal(a.call(a.finance,'GET','/tickets',{},'?state=resolved&q=customer01').total,1);
 assert.equal(a.call(a.support,'GET','/tickets').summary.resolved,1);
});

test('unrelated teams cannot list, read, mutate or infer private tickets',t=>{
 const a=setup(t),ticket=a.create();
 assert.equal(a.call(a.finance,'GET','/tickets').tickets.length,0);
 status(()=>a.call(a.finance,'GET',`/tickets/${ticket.id}`),404);
 status(()=>a.mutate(a.finance,ticket,{action:'note',message:'Unauthorized'}),404);
 assert.equal(a.call(a.admin,'GET','/tickets').tickets.length,1);
 status(()=>a.call({id:'u',username:'regular',role:'user'},'GET','/tickets'),403);
 status(()=>a.call({...a.support,team:'untrusted'},'GET','/tickets'),403);
 const count=a.db.prepare('SELECT count(*) n FROM console_ticket_events').get().n;assert.equal(count,1);
 assert.equal(a.call(a.support,'GET','/unrelated'),null);
});

test('admin alone assigns active staff from the responsible team; failed transfers roll back participant changes',t=>{
 const a=setup(t);let ticket=a.create(a.support,{team:'finance'});
 status(()=>a.mutate(a.finance,ticket,{action:'assign',assignee:'finance-one'}),403);
 status(()=>a.create(a.support,{team:'finance',assignee:'finance-one'}),403);
 status(()=>a.mutate(a.admin,ticket,{action:'assign',assignee:'support-one'}),400);
 status(()=>a.mutate(a.admin,ticket,{action:'assign',assignee:'finance-disabled'}),400);
 status(()=>a.mutate(a.admin,ticket,{action:'transfer',team:'admin',assignee:'finance-one',message:'Invalid assignee'}),400);
 assert.equal(a.db.prepare('SELECT 1 FROM console_ticket_teams WHERE ticket_id=? AND team=?').get(ticket.id,'admin'),undefined);
 assert.equal(a.call(a.admin,'GET',`/tickets/${ticket.id}`).ticket.version,1);
 ticket=a.mutate(a.admin,ticket,{action:'assign',assignee:'finance-one'});assert.equal(ticket.assignee,'finance-one');
 ticket=a.mutate(a.admin,ticket,{action:'assign',assignee:null});assert.equal(ticket.assignee,null);
 assert.equal(a.call(a.admin,'GET',`/tickets/${ticket.id}`).events.length,3);
});

test('optimistic locking preserves newer edits, immutable history and admin-only reopening',t=>{
 const a=setup(t);const stale=a.create();let ticket=a.mutate(a.support,stale,{action:'note',message:'<script>untrusted text</script>'});
 status(()=>a.mutate(a.support,stale,{action:'status',status:'waiting'}),409);
 let detail=a.call(a.support,'GET',`/tickets/${ticket.id}`);assert.equal(detail.events.length,2);assert.equal(detail.events[1].message,'<script>untrusted text</script>');
 ticket=a.mutate(a.support,ticket,{action:'status',status:'resolved'});
 status(()=>a.mutate(a.support,ticket,{action:'status',status:'open'}),403);
 status(()=>a.mutate(a.support,ticket,{action:'transfer',team:'finance',message:'Reopen without admin'}),409);
 ticket=a.mutate(a.admin,ticket,{action:'status',status:'open',message:'Cần kiểm tra thêm.'});assert.equal(ticket.status,'open');
 const eventId=detail.events[0].id;
 assert.throws(()=>a.db.prepare('UPDATE console_ticket_events SET message=? WHERE id=?').run('tampered',eventId),/immutable/);
 assert.throws(()=>a.db.prepare('DELETE FROM console_ticket_events WHERE id=?').run(eventId),/immutable/);
 detail=a.call(a.admin,'GET',`/tickets/${ticket.id}`);assert.equal(detail.events.length,4);assert.equal(detail.events[0].message,'Khách hàng báo lỗi sau khi gửi quà.');
});

test('bounded input, allowed enums and mutation versions are enforced',t=>{
 const a=setup(t);
 status(()=>a.create(a.support,{subject:' '}),400);
 status(()=>a.create(a.support,{subject:'a'.repeat(181)}),400);
 status(()=>a.create(a.support,{description:'x'.repeat(6001)}),400);
 status(()=>a.create(a.support,{priority:'critical'}),400);
 status(()=>a.create(a.support,{team:'unknown'}),400);
 status(()=>a.create(a.support,{team:'marketing'}),400);
 const ticket=a.create();
 status(()=>a.call(a.support,'POST',`/tickets/${ticket.id}/events`,{action:'note',message:'No version'}),400);
 status(()=>a.mutate(a.support,ticket,{action:'transfer',team:'finance',message:''}),400);
 status(()=>a.mutate(a.support,ticket,{action:'delete'}),400);
 status(()=>a.call(a.support,'GET','/tickets',{},'?state=deleted'),400);
 status(()=>a.call(a.support,'GET','/tickets',{},'?q='+encodeURIComponent('a'.repeat(101))),400);
 status(()=>a.call(a.support,'DELETE',`/tickets/${ticket.id}`),405);
 assert.equal(a.db.prepare('SELECT count(*) n FROM console_tickets').get().n,1);
 assert.equal(a.db.prepare('SELECT count(*) n FROM console_ticket_events').get().n,1);
});

test('detail bounds event payload to the latest 200 while preserving the immutable full history',t=>{
 const a=setup(t);let ticket=a.create();
 for(let i=1;i<=205;i++)ticket=a.mutate(a.support,ticket,{action:'note',message:'Ghi chú '+i});
 const detail=a.call(a.support,'GET',`/tickets/${ticket.id}`);
 assert.equal(detail.eventTotal,206);assert.equal(detail.events.length,200);
 assert.equal(detail.events[0].message,'Ghi chú 6');assert.equal(detail.events[199].message,'Ghi chú 205');
 assert.equal(a.db.prepare('SELECT count(*) n FROM console_ticket_events WHERE ticket_id=?').get(ticket.id).n,206);
 assert.equal(Object.hasOwn(detail.events[0],'event_order'),false);
});

test('operations participates only after a support handoff and admin can assign active operations staff',t=>{
 const a=setup(t);let ticket=a.create();
 status(()=>a.call(a.operations,'GET',`/tickets/${ticket.id}`),404);
 ticket=a.mutate(a.support,ticket,{action:'transfer',team:'operations',message:'Kiểm tra lỗi ứng dụng và nội dung bị báo cáo.'});
 ticket=a.mutate(a.admin,ticket,{action:'assign',assignee:'operations-one'});
 assert.equal(ticket.assigneeUsername,'vanhanh01');
 ticket=a.mutate(a.operations,ticket,{action:'status',status:'in_progress'});
 ticket=a.mutate(a.operations,ticket,{action:'transfer',team:'finance',message:'Lỗi đã xử lý; cần đối soát số dư.'});
 assert.equal(ticket.assignee,null);
 assert.deepEqual(ticket.participantTeams,['finance','operations','support']);
 assert.equal(a.call(a.operations,'GET',`/tickets/${ticket.id}`).eventTotal,5);
 assert.equal(a.call(a.finance,'GET','/tickets').total,1);
});
