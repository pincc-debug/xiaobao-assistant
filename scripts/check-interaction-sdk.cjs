// Exercises the shipped official SDK against mocked native transports; never contacts a live room.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const socketCalls = [];
const httpCalls = [];
const ctx = {console:{log(){},warn(){},error(){},info(){},debug(){}},setTimeout,clearTimeout,setInterval,clearInterval,URL,TextEncoder,TextDecoder,Blob,FormData,navigator:{userAgent:'AssistantSDKTest'},location:{href:'https://localhost/'}};
ctx.window=ctx;ctx.self=ctx;
ctx.document={location:{host:'localhost',href:'https://localhost/'},createElement:()=>({setAttribute(){},style:{},firstChild:{host:'api.polyv.net'},host:'api.polyv.net'}),cookie:'',addEventListener(){}};
ctx.webkit={messageHandlers:{platform:{async postMessage(m){
 if(m.kind==='socket') {
  const p=JSON.parse(m.raw);socketCalls.push(p);
  if(p.EVENT==='GET_SIGN_IN_INFO')return {code:200,data:{}};
  if(p.EVENT==='GET_SIGN_IN_STATUS_FOR_LARGE')return {code:200,data:{signNum:7}};
  return {code:200,data:{},status:'success'};
 }
 if(m.kind==='authorization')return {appId:'test',channelId:'1',channelToken:'test',timestamp:Date.now(),expireTime:Date.now()+60000};
 if(m.kind==='http'){
  httpCalls.push(m);
  if(m.url.includes('/admin/getQuestionState'))return {status:200,text:JSON.stringify({code:200,status:'success',data:{content:{questionId:'q1',name:'题目',type:'R',answer:'A',itemType:0},singleResult:[2,1],total:3}})};
  return {status:200,text:JSON.stringify({code:200,status:'success',data:[]})};
 }
}}}};
vm.createContext(ctx);
vm.runInContext(fs.readFileSync('Sources/Assistant/Resources/interaction-bridge.js','utf8'),ctx);
vm.runInContext(fs.readFileSync('Sources/Assistant/Resources/polyv-il-0.7.0.js','utf8'),ctx);
(async()=>{
 ctx.configure({channelId:'1',roomId:'1',sessionId:'session',socketId:'socket'});
 await ctx.invoke('Notice','publishNotice',['测试公告']);
 assert.equal(socketCalls.at(-1).EVENT,'BULLETIN');assert.equal(socketCalls.at(-1).content,'测试公告');
 await ctx.invoke('CheckIn','start',[{duration:60,tips:'请签到'}]);
 assert.equal(socketCalls.at(-1).EVENT,'SIGN_IN');assert.equal(socketCalls.at(-1).data.limitTime,60);
 assert.equal(socketCalls.at(-1).data.sessionId,'session');
 assert.equal(await ctx.invoke('CheckIn','getCheckInNum',[]),7);
 assert.equal(socketCalls.at(-1).EVENT,'GET_SIGN_IN_STATUS_FOR_LARGE');
 const liveAnswer = await ctx.invoke('AnswerCard','getOngoingStatus',[]);
 assert.equal(liveAnswer.question.questionId,'q1');
 assert.equal(liveAnswer.statistics.total,3);
 assert.deepEqual(Array.from(liveAnswer.statistics.options,x=>x.count),[2,1]);
 await ctx.invoke('Notice','unpublishNotice',[]);assert.equal(socketCalls.at(-1).EVENT,'REMOVE_BULLETIN');
 await ctx.invoke('CheckIn','stop',[]);assert.equal(socketCalls.at(-1).EVENT,'STOP_SIGN_IN');
 await ctx.invoke('PushCard','getList',[]);assert.ok(httpCalls.length>0);
 await ctx.invoke('AnswerCard','start',[{question:{questionId:'',name:'题目',type:'R',answer:'A',options:['甲','乙'],isQuickQuestion:false},setting:{duration:0,defaultLimitTimeAnswer:false}}]);
 const manual = new URLSearchParams(httpCalls.at(-1).body);
 assert.equal(manual.has('duration'),false);
 assert.equal(manual.has('autoSendResult'),false);
 console.log('Official SDK bridge: notice/check-in/manual answer card/socket/HTTP transport passed');
 process.exit(0);
})().catch(e=>{console.error(e);process.exit(1)});
