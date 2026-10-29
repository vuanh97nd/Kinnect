import {test,expect} from '@playwright/test';
test('long mobile history keeps message content inside each bubble',async({browser})=>{
 const a=await browser.newContext({viewport:{width:390,height:844}}),b=await browser.newContext();
 try{
 const stamp=Date.now();await a.request.post('/api/register',{data:{username:'overflowa'+stamp,name:'Sender',password:'abcdef',agree18:true}});
 const response=await b.request.post('/api/register',{data:{username:'overflowb'+stamp,name:'Receiver',password:'abcdef',agree18:true}});const user=(await response.json()).user;
 for(let i=0;i<24;i++)await a.request.post('/api/users/'+user.id+'/messages',{data:{body:i%2?'Hi':'A longer message that wraps onto multiple lines to verify content height '+i}});
 const p=await a.newPage();await p.goto('/?chat='+user.id);await expect(p.locator('.bubble')).toHaveCount(24);
 const geometry=()=>p.locator('.dm-log').evaluate(log=>({overflow:log.scrollHeight>log.clientHeight,valid:[...log.querySelectorAll('.bubble')].every(b=>{const rect=b.getBoundingClientRect();return [...b.children].filter(c=>c.getClientRects().length).every(c=>c.getBoundingClientRect().bottom<=rect.bottom+1);})}));
 expect(await geometry()).toEqual({overflow:true,valid:true});
 await p.setViewportSize({width:390,height:460});expect(await geometry()).toEqual({overflow:true,valid:true});
 await expect(p.getByRole('textbox',{name:'Tin nhắn riêng',exact:true})).toHaveAttribute('autocomplete','off');
 }finally{await a.close();await b.close();}
});
