/** Snapshot only block edges between current room members, never profile blobs. */
export function liveRoomBlocks(social,room){
 const ids=new Set([...room.members.values()].map(p=>p.userId)),blocked=new Map();
 const rows=social.db.prepare('SELECT actor,target FROM blocks WHERE actor IN (SELECT value FROM json_each(?))').all(JSON.stringify([...ids]));
 for(const {actor,target} of rows){if(!ids.has(target))continue;if(!blocked.has(actor))blocked.set(actor,new Set());if(!blocked.has(target))blocked.set(target,new Set());blocked.get(actor).add(target);blocked.get(target).add(actor);}
 return {ids,blocked,has:(a,b)=>blocked.get(a)?.has(b)===true};
}
