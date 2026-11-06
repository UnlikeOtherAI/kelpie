// Test-only, single-connection CDP relay. Payloads and identifiers stay in memory.
import assert from "node:assert/strict";
import {createServer} from "node:http";
import {createRequire} from "node:module";
import {verifyOwnedListener} from "./worker-comparison-listener.mjs";
import {createEofWitness} from "./worker-comparison-eof-witness.mjs";
const require=createRequire(new URL("../../packages/cli/package.json",import.meta.url));
const {ws:WebSocket,wsServer:WebSocketServer}=require("playwright-core/lib/utilsBundle");

export async function startEofRelay({port,pid,startTicks,verifyListener=verifyOwnedListener}){
 const witness=createEofWitness(),server=createServer(),wss=new WebSocketServer({noServer:true,maxPayload:1048576});
 let used=false,downstream,upstream,bytes=0,closed=false;
 const fail=reason=>{witness.fail(reason);downstream?.terminate();upstream?.terminate();};
 const checkUrl=value=>{
  const url=new URL(value);
  assert.ok(url.protocol==="ws:"&&url.hostname==="127.0.0.1"&&url.port===String(port)&&url.pathname==="/"&&!url.search&&!url.hash&&!url.username&&!url.password);
 };
 server.on("request",async(req,res)=>{
  if(req.method!=="GET"||!["/json/version","/json/version/"].includes(req.url)){res.writeHead(404).end();return;}
  try{
   await verifyListener(pid,port,startTicks);
   const response=await fetch("http://127.0.0.1:"+port+"/json/version",{signal:AbortSignal.timeout(3000)});
   assert.equal(response.status,200);const reader=response.body.getReader(),chunks=[];let size=0;
   while(true){const part=await reader.read();if(part.done)break;size+=part.value.length;
    if(size>8192){await reader.cancel();throw Error("VERSION_LIMIT");}chunks.push(Buffer.from(part.value));}
   const version=JSON.parse(Buffer.concat(chunks,size).toString("utf8"));checkUrl(version.webSocketDebuggerUrl);
   await verifyListener(pid,port,startTicks);
   version.webSocketDebuggerUrl="ws://127.0.0.1:"+server.address().port+"/";
   res.writeHead(200,{"content-type":"application/json"}).end(JSON.stringify(version));
  }catch{witness.fail("VERSION_FAILED");if(!res.destroyed)res.writeHead(502).end();}
 });
 server.on("upgrade",async(req,socket,head)=>{
  if(used||req.url!=="/"){socket.destroy();witness.fail("UPGRADE_INVALID");return;}used=true;
  try{
   await verifyListener(pid,port,startTicks);
   upstream=new WebSocket("ws://127.0.0.1:"+port+"/",{maxPayload:1048576,handshakeTimeout:3000,perMessageDeflate:false});
   upstream.on("error",()=>fail("UPSTREAM_FAILED"));
   await new Promise((ok,bad)=>{upstream.once("open",ok);upstream.once("error",bad);});
   await verifyListener(pid,port,startTicks);
   wss.handleUpgrade(req,socket,head,ws=>{
    downstream=ws;
    const forward=(from,to,direction)=>(data,binary)=>{
     if(binary||closed||!to||to.readyState!==WebSocket.OPEN){fail("FRAME_INVALID");return;}
     bytes+=data.length;
     if(bytes>16777216||to.bufferedAmount>2097152){fail("FRAME_LIMIT");return;}
     let value;try{value=JSON.parse(data.toString("utf8"));}catch{fail("FRAME_INVALID");return;}
     if(!value||typeof value!=="object"||Array.isArray(value)){fail("FRAME_INVALID");return;}
     if(direction==="request")witness.request(value);else witness.response(value);
     if(witness.result().category!=="incomplete"&&witness.result().category!=="complete"){fail("WITNESS_INVALID");return;}
     to.send(data,{binary:false},error=>{if(error)fail("FORWARD_FAILED");});
    };
    downstream.on("message",forward(downstream,upstream,"request"));
    upstream.on("message",forward(upstream,downstream,"response"));
    downstream.on("error",()=>fail("DOWNSTREAM_FAILED"));
    downstream.on("close",()=>{if(!witness.result().ok)witness.fail("TRUNCATED");upstream?.close();});
    upstream.on("close",()=>{if(!witness.result().ok)witness.fail("TRUNCATED");downstream?.close();});
   });
  }catch{socket.destroy();fail("UPSTREAM_FAILED");}
 });
 await new Promise(ok=>server.listen(0,"127.0.0.1",ok));
 return {
  endpoint:"http://127.0.0.1:"+server.address().port,
  markEof:()=>witness.markEof(),result:()=>witness.result(),
  close:async()=>{closed=true;downstream?.terminate();upstream?.terminate();wss.close();server.closeAllConnections?.();
   if(server.listening)await new Promise(ok=>server.close(ok));},
 };
}

export async function verifyEngineCdp({port,pid,startTicks,verifyListener=verifyOwnedListener}){
 await verifyListener(pid,port,startTicks);
 const socket=new WebSocket("ws://127.0.0.1:"+port+"/",{maxPayload:8192,handshakeTimeout:3000,perMessageDeflate:false});
 try{
  await new Promise((ok,bad)=>{
   const timer=setTimeout(()=>bad(Error("HEALTH_TIMEOUT")),3000);
   const finish=(error)=>{clearTimeout(timer);error?bad(error):ok();};
   socket.once("open",()=>socket.send(JSON.stringify({id:1,method:"Browser.getVersion"})));
   socket.once("error",()=>finish(Error("HEALTH_FAILED")));
   socket.once("close",()=>finish(Error("HEALTH_FAILED")));
   socket.on("message",(data,binary)=>{
    if(binary||data.length>8192){finish(Error("HEALTH_INVALID"));return;}
    let value;try{value=JSON.parse(data.toString("utf8"));}catch{finish(Error("HEALTH_INVALID"));return;}
    if(value.id!==1)return;
    if(value.error||typeof value.result?.protocolVersion!=="string"){finish(Error("HEALTH_INVALID"));return;}
    finish();
   });
  });
 }finally{socket.terminate();}
 await verifyListener(pid,port,startTicks);
}