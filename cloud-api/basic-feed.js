import{profile}from'./profile.js';
export async function basicFeed({request,client,user,json}){
 const url=new URL(request.url);if(url.pathname!=='/api/posts'||request.method!=='GET')return null;
 const rows=(await client.query(`SELECT s.*,u.profile,u.username,u.name,u.role,u.suspended,u.created user_created FROM kinnect_core.feed_snapshot s JOIN kinnect_core.users u ON u.id=s.author_id
 WHERE s.hidden=0 AND u.suspended=0 AND NOT EXISTS(SELECT 1 FROM kinnect_core.blocks b WHERE (b.actor=$1 AND b.target=u.id) OR (b.target=$1 AND b.actor=u.id))
 AND (s.visibility='public' OR s.author_id=$1 OR EXISTS(SELECT 1 FROM kinnect_core.follows f WHERE f.actor=$1 AND f.target=u.id))
 AND ($2::text IS NULL OR s.author_id=$2) AND ($3::text IS NULL OR s.id=$3) ORDER BY s.created DESC LIMIT 100`,[user.id,url.searchParams.get('user'),url.searchParams.get('post')])).rows;
 const posts=rows.map(r=>{const p=r.data,reactions={};for(const l of p.reactions||[])reactions[l.reaction]=(reactions[l.reaction]||0)+1;const mine=(p.reactions||[]).find(l=>l.user_id===user.id)?.reaction||null;const{reactions:ignored,media_type,...data}=p;
  return{...data,author:profile({id:r.author_id,username:r.username,name:r.name,role:r.role,suspended:r.suspended,created:r.user_created,profile:r.profile},r.author_id===user.id),created:Number(r.created),likes:(p.reactions||[]).length,liked:!!mine,myReaction:mine,reactions,media:media_type?{kind:media_type.startsWith('video/')?'video':'image',url:'/api/posts/'+r.id+'/media',offline:true}:null};});
 return json({posts,offline:true});
}
export async function syncFeed(request,client,json){
 if(request.method!=='POST')return json({error:'Method not allowed'},405);
 const raw=await request.text();if(raw.length>1048576)return json({error:'Too large'},413);
 let rows,videos=[];try{const payload=JSON.parse(raw);rows=Array.isArray(payload)?payload:payload.posts;videos=Array.isArray(payload)?[]:payload.videos||[];}catch{return json({error:'Invalid JSON'},400);}
 if(!Array.isArray(rows)||rows.length>1000||rows.some(p=>typeof p.id!=='string'||typeof p.user_id!=='string'||typeof p.body!=='string'||!Number.isSafeInteger(p.created)||!['public','followers'].includes(p.visibility)))return json({error:'Invalid snapshot'},400);
 if(!Array.isArray(videos)||videos.length>1000||videos.some(v=>typeof v.id!=='string'||typeof v.user_id!=='string'||!Number.isSafeInteger(v.created)))return json({error:'Invalid video snapshot'},400);
 await client.query('BEGIN');try{
  for(const p of rows)await client.query('INSERT INTO kinnect_core.feed_snapshot(id,author_id,body,visibility,hidden,created,data) VALUES($1,$2,$3,$4,$5,$6,$7::jsonb) ON CONFLICT(id) DO UPDATE SET body=excluded.body,visibility=excluded.visibility,hidden=excluded.hidden,data=excluded.data',[p.id,p.user_id,p.body,p.visibility,p.hidden?1:0,p.created,JSON.stringify(p)]);
  await client.query('UPDATE kinnect_core.feed_snapshot SET hidden=1 WHERE NOT(id=ANY($1::text[]))',[rows.map(p=>p.id)]);
  for(const v of videos)await client.query('INSERT INTO kinnect_core.video_snapshot VALUES($1,$2,$3,$4,$5::jsonb) ON CONFLICT(id) DO UPDATE SET hidden=excluded.hidden,data=excluded.data',[v.id,v.user_id,v.hidden?1:0,v.created,JSON.stringify(v)]);
  await client.query('UPDATE kinnect_core.video_snapshot SET hidden=1 WHERE NOT(id=ANY($1::text[]))',[videos.map(v=>v.id)]);
  await client.query('COMMIT');
 }catch(e){await client.query('ROLLBACK');throw e;}
 return json({ok:true,count:rows.length});
}
export async function basicVideos({request,client,user,json}){
 const url=new URL(request.url);if(url.pathname!=='/api/shorts'||request.method!=='GET')return null;
 const rows=(await client.query(`SELECT s.*,u.profile,u.username,u.name,u.role,u.suspended,u.created user_created FROM kinnect_core.video_snapshot s JOIN kinnect_core.users u ON u.id=s.author_id WHERE s.hidden=0 AND u.suspended=0 AND NOT EXISTS(SELECT 1 FROM kinnect_core.blocks b WHERE (b.actor=$1 AND b.target=u.id) OR (b.target=$1 AND b.actor=u.id)) AND ($2::text IS NULL OR s.author_id=$2) AND ($3::boolean=false OR EXISTS(SELECT 1 FROM kinnect_core.follows f WHERE f.actor=$1 AND f.target=u.id)) ORDER BY s.created DESC LIMIT 100`,[user.id,url.searchParams.get('user'),url.searchParams.get('feed')==='following'])).rows;
 return json({offline:true,shorts:rows.map(r=>{const{likesBy=[],...data}=r.data;return{...data,video:'/api/shorts/'+r.id+'/video',offline:true,created:Number(r.created),likes:likesBy.length,liked:likesBy.includes(user.id),author:profile({id:r.author_id,username:r.username,name:r.name,role:r.role,suspended:r.suspended,created:r.user_created,profile:r.profile},r.author_id===user.id)};})});
}
