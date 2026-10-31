export class AuthLimits{
 constructor(ctx){this.ctx=ctx;}
 async fetch(){const now=Date.now();const allowed=await this.ctx.storage.transaction(async tx=>{let b=await tx.get('bucket');if(!b||now-b.at>=60000)b={at:now,count:0};b.count++;await tx.put('bucket',b);return b.count<=20;});await this.ctx.storage.setAlarm(now+120000);return Response.json({allowed});}
 async alarm(){await this.ctx.storage.deleteAll();}
}
