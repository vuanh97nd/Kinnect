import test from 'node:test';
import assert from 'node:assert/strict';
import tls from 'node:tls';
import {createApp} from '../server.js';

test('test apps never open live SMTP; admin reset notifications use the injected sender', async t => {
  const keys = ['SMTP_USER','SMTP_PASS','RESET_NOTIFY_EMAIL'];
  const previous = Object.fromEntries(keys.map(k=>[k,process.env[k]]));
  Object.assign(process.env,{SMTP_USER:'test@example.invalid',SMTP_PASS:'fake-test-secret',RESET_NOTIFY_EMAIL:'admin@example.invalid'});
  t.after(()=>{for(const k of keys)if(previous[k]===undefined)delete process.env[k];else process.env[k]=previous[k];});
  const smtp=t.mock.method(tls,'connect',()=>{throw Error('Live SMTP must not be called');});
  for(const injected of [false,true]) {
    const mail=[];
    const app=createApp(injected?{emailSender:async m=>{mail.push(m);return true;},emailReady:()=>true}:{});
    await new Promise(r=>app.server.listen(0,'127.0.0.1',r));
    const base='http://127.0.0.1:'+app.server.address().port+'/api';
    try {
      const post=(path,data)=>fetch(base+path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
      assert.equal((await post('/password-reset',{username:'mail_isolation',contact:'Test contact'})).status,200);
      const start=await post('/recovery/reset/start',{identifier:'unknown_member'});
      assert.equal(start.status,injected?200:503);
      await new Promise(r=>setImmediate(r));
      assert.equal(smtp.mock.callCount(),0,'A test notification escaped to real SMTP');
      assert.equal(mail.length,injected?1:0);
      if(injected){assert.equal(mail[0].to,'admin@example.invalid');assert.match(mail[0].subject,/quên mật khẩu/);}
    } finally {
      for(const client of app.wss.clients)client.terminate();
      await new Promise(r=>app.wss.close(r));
      app.server.closeAllConnections();await new Promise(r=>app.server.close(r));app.social.close();
    }
  }
});
