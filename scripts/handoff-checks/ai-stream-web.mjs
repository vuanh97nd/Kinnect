import {createApp} from '../../server.js';import {chromium} from 'playwright';import assert from 'node:assert/strict';
const app=createApp();await new Promise(r=>app.server.listen(0,'127.0.0.1',r));const baseURL='http://127.0.0.1:'+app.server.address().port,b=await chromium.launch({channel:process.platform==='win32'?'chrome':'chromium'}),c=await b.newContext({baseURL,viewport:{width:390,height:844}}),p=await c.newPage();
try{
 const registration=await c.request.post('/api/register',{data:{username:'stream_web',name:'Kiểm tra',password:'abcdef',agree18:true}});const member=(await registration.json()).user;
 app.social.db.prepare("INSERT INTO users(id,username,password,salt,name,birth_date,created) SELECT 'stream-admin','stream_admin',password,salt,'Admin',birth_date,? FROM users LIMIT 1").run(Date.now());
 app.social.db.prepare('INSERT INTO messages VALUES(?,?,?,?,?)').run('stream-seed','stream-admin',member.id,'Xin chào',Date.now());
 await p.goto('/?s=inbox');await p.locator('[data-do="community-chat"][data-value="stream-admin"]').click();await p.locator('.v2-message-history').waitFor();
 const emit=data=>{let count=0;for(const ws of app.wss.clients)if(ws.userId===member.id){ws.send(JSON.stringify({type:'ai-stream',id:'stream-test',sender:'stream-admin',...data}));count++;}assert.ok(count);};
 emit({body:'Chào '});await p.getByText('Chào ',{exact:true}).waitFor();emit({body:'Chào bạn <script>'});await p.getByText('Chào bạn <script>',{exact:true}).waitFor();assert.equal(await p.locator('[data-ai-stream]').count(),1);assert.equal(await p.locator('[data-ai-stream] script').count(),0);
 // A concurrent normal notification renders history again; partial text must survive.
 for(const ws of app.wss.clients)if(ws.userId===member.id)ws.send(JSON.stringify({type:'notifications-changed'}));await p.waitForTimeout(250);assert.equal(await p.locator('[data-ai-stream]').count(),1);
 app.social.db.prepare('INSERT INTO messages VALUES(?,?,?,?,?)').run('stream-final','stream-admin',member.id,'Chào bạn hoàn chỉnh',Date.now());emit({body:'',done:true});await p.getByText('Chào bạn hoàn chỉnh',{exact:true}).waitFor();assert.equal(await p.locator('[data-ai-stream]').count(),0);console.log('PASS: mobile web streams safely, survives history refresh and shows one completed message');
}finally{await b.close();for(const ws of app.wss.clients)ws.terminate();app.wss.close();app.server.closeAllConnections();await new Promise(r=>app.server.close(r));app.social.close();}
