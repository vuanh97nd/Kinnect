module.exports=class{onTestEnd(test,result){console.log(result.status+': '+test.title);for(const e of result.errors)console.log(e.message);}onEnd(result){console.log('SUITE '+result.status);}};
