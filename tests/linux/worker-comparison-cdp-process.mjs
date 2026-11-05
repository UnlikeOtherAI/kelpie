import assert from "node:assert/strict";
import {open} from "node:fs/promises";
import {join} from "node:path";
import {verifyOwnedListener} from "./worker-comparison-listener.mjs";

export function parseDevToolsActivePort(text){
 assert.ok(typeof text==="string"&&text.length<=512,"DEVTOOLS_PORT_INVALID");
 const lines=text.trim().split(/\r?\n/);
 assert.equal(lines.length,2,"DEVTOOLS_PORT_INVALID");
 assert.match(lines[0],/^[0-9]{1,5}$/);
 const port=Number(lines[0]);assert.ok(port>0&&port<=65535,"DEVTOOLS_PORT_INVALID");
 assert.match(lines[1],/^\/devtools\/browser\/[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$/);
 return {port,path:lines[1]};
}
export function extractRendererPids(response,browserPid){
 const processes=response?.result?.processInfo;
 assert.ok(Array.isArray(processes)&&processes.length>0&&processes.length<=256,"DEVTOOLS_PROCESS_LIST");
 const browsers=processes.filter(item=>item?.type==="browser");
 assert.ok(browsers.length===1&&browsers[0].id===browserPid,"DEVTOOLS_BROWSER_MISMATCH");
 const pids=processes.filter(item=>item?.type==="renderer").map(item=>item.id);
 assert.ok(pids.length>0&&pids.length<=256&&pids.every(pid=>Number.isSafeInteger(pid)&&pid>0),"DEVTOOLS_NO_RENDERER");
 assert.equal(new Set(pids).size,pids.length,"DEVTOOLS_DUPLICATE_RENDERER");
 return pids.sort((a,b)=>a-b);
}
async function readPortFile(profile){
 const file=await open(join(profile,"DevToolsActivePort"),"r"),chunks=[];let total=0;
 try{while(true){const buffer=Buffer.alloc(513),{bytesRead}=await file.read(buffer,0,buffer.length,null);
  if(!bytesRead)break;total+=bytesRead;assert.ok(total<=512,"DEVTOOLS_PORT_INVALID");chunks.push(buffer.subarray(0,bytesRead));}
  return Buffer.concat(chunks,total).toString("utf8");
 }finally{await file.close();}
}
export async function queryRendererPids(profile,browserPid,startTicks,{WebSocketClass=globalThis.WebSocket}={}){
 let endpoint;
 for(let n=0;n<100&&!endpoint;n++){
  try{endpoint=parseDevToolsActivePort(await readPortFile(profile));}
  catch{await new Promise(ok=>setTimeout(ok,100));}
 }
 assert.ok(endpoint,"DEVTOOLS_PORT_UNAVAILABLE");
 await verifyOwnedListener(browserPid,endpoint.port,startTicks);
 const socket=new WebSocketClass("ws://127.0.0.1:"+endpoint.port+endpoint.path);
 const result=await performProcessQuery(socket,browserPid);
 await verifyOwnedListener(browserPid,endpoint.port,startTicks);
 return result;
}

export async function performProcessQuery(socket,browserPid){
 return await new Promise((resolve,reject)=>{
  let done=false,messages=0;
  const finish=(error,value)=>{if(done)return;done=true;clearTimeout(timer);try{socket.close();}catch{}error?reject(error):resolve(value);};
  const timer=setTimeout(()=>finish(Error("DEVTOOLS_TIMEOUT")),5000);
  socket.addEventListener("open",()=>{try{socket.send(JSON.stringify({id:1,method:"SystemInfo.getProcessInfo"}));}catch{finish(Error("DEVTOOLS_CONNECTION_FAILED"));}},{once:true});
  socket.addEventListener("error",()=>finish(Error("DEVTOOLS_CONNECTION_FAILED")),{once:true});
  socket.addEventListener("close",()=>finish(Error("DEVTOOLS_CLOSED")),{once:true});
  socket.addEventListener("message",event=>{
   if(++messages>20||typeof event.data!=="string"||event.data.length>65536)return finish(Error("DEVTOOLS_RESPONSE_INVALID"));
   let response;try{response=JSON.parse(event.data);}catch{return finish(Error("DEVTOOLS_RESPONSE_INVALID"));}
   if(!response||typeof response!=="object")return finish(Error("DEVTOOLS_RESPONSE_INVALID"));
   if(response.id!==1)return;
   if(response.error)return finish(Error("DEVTOOLS_PROTOCOL_ERROR"));
   try{finish(null,extractRendererPids(response,browserPid));}catch(error){finish(error);}
  });
 });
}
