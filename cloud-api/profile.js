const parse=(value,fallback)=>{if(value===null||value===undefined)return fallback;if(typeof value!=='string')return value;try{return JSON.parse(value);}catch{return fallback;}};
export function profile(row,own=false){
 const p=row.profile||{},visibility=parse(p.profile_visibility,{}),visible=key=>own||visibility[key]!==false;
 const out={id:row.id,username:row.username,name:row.name,bio:visible('bio')?p.bio||'':'',age:visible('age')?p.age??null:null,city:visible('city')?p.city||'':'',lookingFor:visible('lookingFor')?p.looking_for||'':'',interests:visible('interests')?parse(p.interests,[]):[],joinedAt:Number(row.created),isNew:Date.now()-Number(row.created)<7*86400000,avatar:p.avatar?'/api/users/'+row.id+'/avatar':null,cover:p.cover?'/api/users/'+row.id+'/cover':null,activityShared:!!p.show_activity,isActive:false,lastActiveAt:p.show_activity?p.last_active||null:null,storeStyle:'',storeMembership:''};
 for(const [key,column]of [['gender','gender'],['orientation','orientation'],['communityRole','community_role'],['relationshipRole','relationship_role'],['pronouns','pronouns']])out[key]=(own||p.identity_public)&&visible(key)?p[column]||'':'';
 const details=parse(p.profile_details,{});for(const [key,value]of Object.entries(details))if(visible(key)&&!Object.hasOwn(out,key)&&!['role','password','salt','suspended','profile','token'].includes(key))out[key]=value;
 if(own)Object.assign(out,{role:row.role,suspended:row.suspended,discoverable:!!p.discoverable,dmMode:p.dm_mode||'everyone',identityPublic:!!p.identity_public,showActivity:!!p.show_activity,showDistance:!!p.show_distance,profileVisibility:visibility,profileDetails:details,profileDob:p.profile_dob||''});
 return out;
}
