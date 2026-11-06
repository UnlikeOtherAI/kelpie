import {test} from "node:test";
import assert from "node:assert/strict";
import {createServer} from "node:http";
import {createRequire} from "node:module";
import {startEofRelay,verifyEngineCdp} from "./worker-comparison-eof-relay.mjs";
const require=createRequire(new URL("../../packages/cli/package.json",import.meta.url));
const {ws:WebSocket,wsServer:WebSocketServer}=require("playwright-core/lib/utilsBundle");
async function setup(){
 const server=createServer((req,res)=>res.end(JSON.stringify({webSocketDebuggerUrl:"ws://127.0.0.1:"+server.address().port+"/"})));
 const wss=new WebSocketServer({server});let replyMode="ok";
 wss.on("connection",socket=>socket.on("message",data=>{
  const req=JSON.parse(data.toString()),result=req.method==="Target.createBrowserContext"?{browserContextId:"ctx"}:
   req.method==="Target.createTarget"?{targetId:"target"}:
   req.method==="Browser.getVersion"?{protocolVersion:"1.3"}:{};
  if(replyMode==="close"){socket.terminate();return;}
  socket.send(JSON.stringify(replyMode==="error"?{id:req.id,error:{code:-1}}:{id:req.id,result}));
 }));
 await new Promise(ok=>server.listen(0,"127.0.0.1",ok));
 const checks=[];const relay=await startEofRelay({port:server.address().port,pid:1,startTicks:"1",
  verifyListener:async(...args)=>checks.push(args)});
 const response=await fetch(relay.endpoint+"/json/version"),version=await response.json();
 const client=new WebSocket(version.webSocketDebuggerUrl);
 await new Promise((ok,bad)=>{client.once("open",ok);client.once("error",bad);});
 const send=req=>new Promise((ok,bad)=>{client.once("message",data=>ok(JSON.parse(data.toString())));client.once("error",bad);client.send(JSON.stringify(req));});
 const prepare=async()=>{
  await send({id:1,method:"Target.createBrowserContext"});
  await send({id:2,method:"Target.createTarget",params:{browserContextId:"ctx"}});
 };
 return {relay,client,checks,send,prepare,port:server.address().port,setMode:x=>{replyMode=x;},close:async()=>{
  client.terminate();await relay.close();wss.close();server.closeAllConnections?.();await new Promise(ok=>server.close(ok));}};
}
test("relay preserves a real matching disposal exchange and verifies upstream identity",async()=>{
 const t=await setup();try{await t.prepare();assert.equal(t.relay.markEof(),true);
  const response=await t.send({id:3,method:"Target.disposeBrowserContext",params:{browserContextId:"ctx"}});
  assert.deepEqual(response.result,{});assert.equal(t.relay.result().ok,true);assert.ok(t.checks.length>=3);
  await verifyEngineCdp({port:t.port,pid:1,startTicks:"1",verifyListener:async()=>{}});
 }finally{await t.close();}
});
test("relay rejects disposal errors and records incomplete upstream closure",async()=>{
 let t=await setup();try{await t.prepare();t.relay.markEof();t.setMode("error");
  await new Promise(ok=>{t.client.once("close",ok);t.client.send(JSON.stringify({id:3,method:"Target.disposeBrowserContext",params:{browserContextId:"ctx"}}));});
  assert.equal(t.relay.result().ok,false);
 }finally{await t.close();}
 t=await setup();try{await t.prepare();t.relay.markEof();t.setMode("close");
  await new Promise(ok=>{t.client.once("close",ok);t.client.send(JSON.stringify({id:3,method:"Target.disposeBrowserContext",params:{browserContextId:"ctx"}}));});
  assert.equal(t.relay.result().ok,false);
 }finally{await t.close();}
});
