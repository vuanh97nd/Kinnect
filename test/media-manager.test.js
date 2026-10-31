import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {spawn} from 'node:child_process';
import {DatabaseSync} from 'node:sqlite';
import {randomBytes} from 'node:crypto';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
test('two real Windows-compatible managers select storage, import, pair, sync and persist',async()=>{
 const root=mkdtempSync(join(tmpdir(),'kinnect-manager-')),children=[];
 function start(name,port,sync){const home=join(root,name);mkdirSync(home,{recursive:true});const file=join(home,'settings.json');let cfg;try{cfg=JSON.parse(readFileSync(file,'utf8'));}catch{cfg={root:null,source:null,adminKey:randomBytes(32).toString('hex'),syncKey:randomBytes(32).toString('hex'),peers:[],network:false};writeFileSync(file,JSON.stringify(cfg));}const child=spawn(process.execPath,[resolve('services/windows-server/server.mjs')],{env:{...process.env,KINNECT_MANAGER_HOME:home,KINNECT_MANAGER_PORT:String(port),KINNECT_SYNC_PORT:String(sync)},windowsHide:true,stdio:'ignore'});children.push(child);return{child,port,sync,cfg};}
 async function api(node,path,body,key=node.cfg.adminKey){const r=await fetch('http://127.0.0.1:'+node.port+path,{method:body?'POST':'GET',headers:{'Content-Type':'application/json','X-Admin-Key':key},...(body?{body:JSON.stringify(body)}:{})});return{status:r.status,body:await r.json()};}
 async function ready(node){for(let i=0;i<100;i++){try{if((await api(node,'/status')).status===200)return;}catch{}await sleep(50);}throw Error('Manager did not start');}
 let a=start('a',39428,39429),b=start('b',39528,39529);
 try{
  await Promise.all([ready(a),ready(b)]);assert.equal((await api(a,'/status',undefined,'wrong')).status,401);
  const source=join(root,'source.sqlite'),db=new DatabaseSync(source);db.exec('CREATE TABLE post_media(post_id TEXT PRIMARY KEY,type TEXT,data BLOB)');db.prepare('INSERT INTO post_media VALUES(?,?,?)').run('photo-1','image/jpeg',Buffer.from('image fixture'));db.close();
  for(const [node,name]of [[a,'storeA'],[b,'storeB']])assert.equal((await api(node,'/storage',{path:join(root,name)})).status,200);
  assert.equal((await api(a,'/source',{path:source})).status,200);assert.equal((await api(a,'/network',{enabled:true})).status,200);await api(a,'/toggle',{enabled:true});
  for(let i=0;i<100&&(await api(a,'/status')).body.media.files!==1;i++)await sleep(50);
  assert.equal((await api(a,'/status')).body.media.files,1);
  assert.equal((await api(b,'/peer',{url:'http://127.0.0.1:'+a.sync,key:a.cfg.syncKey})).status,200);await api(b,'/toggle',{enabled:true});
  for(let i=0;i<100&&(await api(b,'/status')).body.media.files!==1;i++)await sleep(50);
  assert.equal((await api(b,'/status')).body.media.files,1);
  assert.equal((await api(b,'/storage',{path:join(root,'wrong-while-active')})).status,400);
  const stopped=new Promise(r=>b.child.once('exit',r));b.child.kill();await stopped;b=start('b',39528,39529);await ready(b);const status=(await api(b,'/status')).body;assert.equal(status.enabled,true);assert.equal(status.media.files,1);assert.equal(status.peers.length,1);assert.equal(status.root,join(root,'storeB'));
 }finally{for(const child of children)if(child.exitCode===null)child.kill();}
});
