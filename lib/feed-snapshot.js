export function feedSnapshot(db){
 const posts=db.prepare("SELECT p.*,COALESCE(c.category,'community') category,m.type media_type FROM posts p LEFT JOIN post_categories c ON c.post_id=p.id LEFT JOIN post_media m ON m.post_id=p.id WHERE p.id NOT IN(SELECT post_id FROM post_stories) ORDER BY p.created DESC LIMIT 1000").all();
 const likes=db.prepare('SELECT post_id,user_id,reaction FROM post_likes').all();
 const comments=db.prepare('SELECT post_id,COUNT(*) n FROM post_comments GROUP BY post_id').all();
 return posts.map(p=>({...p,reactions:likes.filter(l=>l.post_id===p.id),comments:comments.find(c=>c.post_id===p.id)?.n||0}));
}
export function videoSnapshot(db){
 const rows=db.prepare('SELECT id,user_id,caption,duration,hidden,created FROM shorts ORDER BY created DESC LIMIT 1000').all();
 const likes=db.prepare('SELECT short_id,user_id FROM short_likes').all(),comments=db.prepare('SELECT short_id,COUNT(*) n FROM short_comments GROUP BY short_id').all();
 return rows.map(r=>({...r,likesBy:likes.filter(l=>l.short_id===r.id).map(l=>l.user_id),comments:comments.find(c=>c.short_id===r.id)?.n||0}));
}
