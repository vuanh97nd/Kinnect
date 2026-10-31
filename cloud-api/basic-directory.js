import {profile} from './profile.js';
export async function basicDirectory({request,client,user,json}){
 const url=new URL(request.url),path=url.pathname,match=path.match(/^\/api\/users\/([A-Za-z0-9-]+)(?:\/(block))?$/);
 if(!['/api/discover','/api/friends','/api/friend-requests','/api/friend-suggestions'].includes(path)&&!match)return null;
 if(match?.[2]){
  if(match[1]===user.id)return json({error:'Không thể chặn tài khoản của bạn.'},400);
  if(request.method==='POST')await client.query('INSERT INTO kinnect_core.blocks(actor,target) SELECT $1,id FROM kinnect_core.users WHERE id=$2 ON CONFLICT DO NOTHING',[user.id,match[1]]);
  else if(request.method==='DELETE')await client.query('DELETE FROM kinnect_core.blocks WHERE actor=$1 AND target=$2',[user.id,match[1]]);
  else return json({error:'Phương thức không hỗ trợ.'},405);
  return json({ok:true});
 }
 if(request.method!=='GET')return json({error:'Chức năng này cần máy chủ PC.'},503);
 const excluded=(await client.query('SELECT target id FROM kinnect_core.blocks WHERE actor=$1 UNION SELECT actor id FROM kinnect_core.blocks WHERE target=$1',[user.id])).rows.map(x=>x.id);
 const friends=(await client.query('SELECT * FROM kinnect_core.friendships WHERE low_id=$1 OR high_id=$1',[user.id])).rows;
 const following=(await client.query('SELECT target FROM kinnect_core.follows WHERE actor=$1',[user.id])).rows.map(x=>x.target);
 const rows=(await client.query('SELECT * FROM kinnect_core.users WHERE suspended=0 AND NOT(id=ANY($1::text[])) ORDER BY created DESC LIMIT 500',[excluded])).rows;
 const render=row=>{const peer=friends.find(f=>[f.low_id,f.high_id].includes(row.id));return {...profile(row,row.id===user.id),following:following.includes(row.id),friendship:peer?(peer.status==='accepted'?'friends':peer.requester===user.id?'outgoing':'incoming'):'none',posts:0,followers:0,followingCount:0};};
 if(match){const person=rows.find(r=>r.id===match[1]);return person?json({user:render(person)}):json({error:'Không tìm thấy người dùng.'},404);}
 const q=(url.searchParams.get('q')||'').toLowerCase();
 if(path==='/api/friend-requests'){const pending=rows.filter(r=>r.id!==user.id).map(render);return json({incoming:pending.filter(r=>r.friendship==='incoming'),outgoing:pending.filter(r=>r.friendship==='outgoing')});}
 if(path==='/api/friend-suggestions')return json({users:[]});
 let people=rows.filter(r=>r.id!==user.id&&(!q||[r.name,r.username].some(s=>s.toLowerCase().includes(q))));
 if(path==='/api/friends'){
  const kind=url.searchParams.get('kind')||'friends';people=people.filter(r=>{const f=friends.find(f=>[f.low_id,f.high_id].includes(r.id));return f&&(kind==='friends'?f.status==='accepted':f.status==='pending'&&(kind==='incoming'?f.requester!==user.id:f.requester===user.id));});
 }else{
  people=people.filter(r=>r.profile.discoverable!==0&&r.profile.discoverable!==false);
  if(url.searchParams.get('following')==='1')people=people.filter(r=>following.includes(r.id));
  if(url.searchParams.get('nearby')==='1')return json({error:'Tìm quanh đây cần máy chủ vị trí đang hoạt động.'},503);
  const ranges=[['age','age'],['Weight','weight'],['Height','height']];
  for(const[key,column]of ranges){const cap=key==='age'?'Age':key,min=Number(url.searchParams.get('min'+cap)||0),max=Number(url.searchParams.get('max'+cap)||0);if(min||max)people=people.filter(r=>{const p=render(r),v=Number(p[column]||r.profile.profile_details?.[column]);return v>0&&(!min||v>=min)&&(!max||v<=max);});}
  for(const key of ['gender','orientation','communityRole','intent']){const val=url.searchParams.get(key);if(val)people=people.filter(r=>String(render(r)[key==='intent'?'lookingFor':key]||'')===val);}
  if(url.searchParams.get('recent')==='1')people=people.filter(r=>r.profile.show_activity&&Date.now()-Number(r.profile.last_active||0)<86400000);
 }
 return json({users:people.map(render),filterVersion:2});
}
