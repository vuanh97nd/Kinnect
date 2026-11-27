export function feedSnapshot(db){
 const posts=db.prepare("SELECT p.*,COALESCE(c.category,'community') category,m.type media_type FROM posts p LEFT JOIN post_categories c ON c.post_id=p.id LEFT JOIN post_media m ON m.post_id=p.id WHERE p.id NOT IN(SELECT post_id FROM post_stories) ORDER BY p.created DESC LIMIT 1000").all();
 if(!posts.length)return [];
 const idsJson=JSON.stringify(posts.map(p=>p.id));
 const likes=db.prepare('SELECT post_id,user_id,reaction FROM post_likes WHERE post_id IN (SELECT value FROM json_each(?))').all(idsJson);
 const comments=db.prepare('SELECT post_id,COUNT(*) n FROM post_comments WHERE post_id IN (SELECT value FROM json_each(?)) GROUP BY post_id').all(idsJson);
 const likesByPost=new Map();
 for(const l of likes){let list=likesByPost.get(l.post_id);if(!list){list=[];likesByPost.set(l.post_id,list);}list.push(l);}
 const commentsByPost=new Map(comments.map(c=>[c.post_id,c.n]));
 return posts.map(p=>({...p,reactions:likesByPost.get(p.id)||[],comments:commentsByPost.get(p.id)||0}));
}
export function videoSnapshot(db){
 const rows=db.prepare('SELECT id,user_id,caption,duration,hidden,created FROM shorts ORDER BY created DESC LIMIT 1000').all();
 if(!rows.length)return [];
 const idsJson=JSON.stringify(rows.map(r=>r.id));
 const likes=db.prepare('SELECT short_id,user_id FROM short_likes WHERE short_id IN (SELECT value FROM json_each(?))').all(idsJson);
 const comments=db.prepare('SELECT short_id,COUNT(*) n FROM short_comments WHERE short_id IN (SELECT value FROM json_each(?)) GROUP BY short_id').all(idsJson);
 const likesByShort=new Map();
 for(const l of likes){let list=likesByShort.get(l.short_id);if(!list){list=[];likesByShort.set(l.short_id,list);}list.push(l.user_id);}
 const commentsByShort=new Map(comments.map(c=>[c.short_id,c.n]));
 return rows.map(r=>({...r,likesBy:likesByShort.get(r.id)||[],comments:commentsByShort.get(r.id)||0}));
}
