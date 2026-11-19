import {ALL_TABLES,REPLICA_TABLES,OWNED_TABLES} from './schema.js';
export function consoleSnapshot(db,{owned=false,testCredentials=false,media=true}={}){
 const names=owned?ALL_TABLES:REPLICA_TABLES,schemas=[],tables=[];
 for(const name of names){const master=db.prepare("SELECT sql FROM sqlite_master WHERE type='table' AND name=?").get(name);if(!master)continue;schemas.push({name,sql:master.sql});if(name==='sessions')continue;
  const info=db.prepare('PRAGMA table_info('+name+')').all(),columns=info.map(c=>c.name);let records=db.prepare('SELECT * FROM '+name).all();if(!media&&name==='post_media')continue;
  const rows=[];for(const record of records){let tooLarge=false;const row=columns.map(c=>{let v=record[c];if(name==='users'&&!testCredentials&&['password','salt'].includes(c))v='';if(name==='users'&&v instanceof Uint8Array)return null;if(name==='shorts'&&c==='data')return{__blob:''};if(v instanceof Uint8Array){if(v.byteLength>1024*1024)tooLarge=true;return{__blob:Buffer.from(v).toString('base64')};}return v===undefined?null:v;});if(!tooLarge)rows.push(row);}tables.push({name,columns,rows});
 }
 return{schemas,tables};
}
