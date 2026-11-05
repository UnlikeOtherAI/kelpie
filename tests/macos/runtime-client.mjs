import {execFileSync,spawn} from "node:child_process";
import {writeFile} from "node:fs/promises";
import {createHash} from "node:crypto";
import path from "node:path";
import {listenerState} from "./runtime-ownership.mjs";
import {artifactFacts,errorFacts,toolEnvelopeFacts} from "./runtime-diagnostics.mjs";
import {scriptArtifactSchema,scriptArtifactChunkSchema,scriptStatusV1Schema} from "../../packages/shared/dist/index.js";
export const delay=ms=>new Promise(r=>setTimeout(r,ms));
export class Failure extends Error { constructor(code){super(code);this.code=code;} }
export function requireTrue(ok,code){if(!ok)throw new Failure(code);}
export function listeners(port){
 try{return [...new Set(execFileSync("/usr/sbin/lsof",["-nP","-iTCP:"+port,"-sTCP:LISTEN","-t"],{encoding:"utf8"}).trim().split(/\s+/).filter(Boolean).map(Number))];}
 catch{return [];}
}
export async function waitFor(run,ms=10000){
 const end=Date.now()+ms;let last;
 do{try{const result=await run();if(result)return result;}catch(e){if(e.code==="LISTENER_IDENTITY")throw e;last=e;}await delay(100);}while(Date.now()<end);
 throw last??new Failure("WAIT_TIMEOUT");
}
export class Client {
 constructor(pid,out){this.pid=pid;this.out=out;this.token=null;this.secrets=[];this.readiness=[];this.began=Date.now();this.artifacts=[];this.counter=0;}
 pin(port){requireTrue(listenerState(listeners(port),this.pid)==="owned","LISTENER_IDENTITY");}
 ready(){const states=[28420,8421].map(port=>listenerState(listeners(port),this.pid));
  if(this.readiness.at(-1)?.states.join(",")!==states.join(",")&&this.readiness.length<16)this.readiness.push({elapsedMs:Date.now()-this.began,states});
  requireTrue(!states.includes("foreign"),"LISTENER_IDENTITY");return states.every(state=>state==="owned");}
 async request(route,body={},options={}){
  const port=options.reveal?8421:28420;this.pin(port);
  const headers={"content-type":"application/json",accept:"application/json, text/event-stream"};
  if(!options.reveal&&(options.token??this.token))headers.authorization="Bearer "+(options.token??this.token);
  const response=await fetch("http://127.0.0.1:"+port+route,{method:options.method??"POST",headers,
   body:options.method==="GET"?undefined:JSON.stringify(body),signal:options.signal?AbortSignal.any([options.signal,AbortSignal.timeout(options.timeout??365000)]):AbortSignal.timeout(options.timeout??365000),redirect:"error"});
  const pieces=[];let size=0;for await(const bytes of response.body){size+=bytes.length;if(size>32*1024*1024)throw new Failure("RESPONSE_LIMIT");pieces.push(Buffer.from(bytes));options.onChunk?.(size);}
  let text=Buffer.concat(pieces).toString("utf8");
  this.pin(port);
  if(text.startsWith("event:")||text.startsWith("data:"))text=text.split("\n").filter(x=>x.startsWith("data:")).map(x=>x.slice(5).trim()).at(-1);
  return {status:response.status,value:JSON.parse(text)};
 }
 async api(method,body={},token){
  const response=await this.request("/v1/"+method,body,{token});
  if(method==="get-script-status"&&response.value.success)scriptStatusV1Schema.parse(response.value);
  return response.value;
 }
 async tool(name,args={},reveal=false,options={}){
  this.toolFacts=null;
  const {value}=await this.request("/mcp",{jsonrpc:"2.0",id:++this.counter,method:"tools/call",params:{name,arguments:args}},{...options,reveal});
  this.toolFacts=toolEnvelopeFacts(value);
  requireTrue(!value.error,"MCP_ERROR");
  const result=JSON.parse(value.result.content.find(x=>x.type==="text").text);
  return result.ok===true?result.value:result.ok===false?{success:false,error:result.error}:result;
 }
 async direct(name,args={},generic=false){
  return generic?this.tool("kelpie_extension",{name,arguments:args}):this.tool(name,args);
 }
 async find(id){
  for(const window of await this.windows()){
   const tree=await this.tool("get_view_tree",{window_id:window.id,max_depth:50},true);
   if(JSON.stringify(tree).includes('"'+id+'"'))return window.id;
  }
  return null;
 }
 async tap(id,windowId){const value=await this.tool("tap_element",{element_id:id,...(windowId?{window_id:windowId}:{})},true);requireTrue(value.success,"NATIVE_CONTROL_UNAVAILABLE");}
 async windows(){return (await this.tool("list_windows",{},true)).windows;}
 async screenshot(name){
  const windows=await this.windows();const target=windows.find(w=>w.isKey)??windows[0];
  requireTrue(target,"NO_VISIBLE_WINDOW");
  const image=await this.tool("screenshot",{window_id:target.id,format:"png"},true);
  requireTrue(typeof image.image==="string"&&image.width>100,"NATIVE_SCREENSHOT_UNAVAILABLE");
  const file=path.join(this.out,name+".png");await writeFile(file,Buffer.from(image.image,"base64"));
  return {file,width:image.width,height:image.height,windowId:target.id};
 }
 async pair(name,persistent=false){
  const pending=await this.request("/v1/pair",{clientId:"hosted-"+name,clientName:name});
  requireTrue(pending.status===202&&pending.value.status==="pending","PAIR_REQUEST_FAILED");
  const id=persistent?"pair.dialog.always":"pair.dialog.yes-once";
  const windowId=await waitFor(()=>this.find(id));
  await this.tap(id,windowId);
  const approved=await waitFor(async()=>{
   const result=await this.request("/v1/pair/status?requestId="+encodeURIComponent(pending.value.requestId),{}, {method:"GET"});
   return result.value.status==="approved"?result.value:null;
  });
  requireTrue(typeof approved.token==="string","PAIR_TOKEN_MISSING");
  this.secrets.push(approved.token);return approved.token;
 }
 async download(run,label){
  requireTrue(typeof run.runId==="string","RUN_ID_MISSING");
  const records=[];
  for(const raw of run.artifacts??[]){
   this.artifactFacts=artifactFacts(raw);
   const item=scriptArtifactSchema.parse(raw);const extension={"image/png":"png","image/gif":"gif","video/mp4":"mp4"}[item.mimeType];
   const file=path.join(this.out,label+"-"+this.artifacts.length+"."+extension);let offset=0;const chunks=[];
   requireTrue(item.byteLength<=64*1024*1024,"ARTIFACT_LIMIT");
   while(offset<item.byteLength){
    const rawChunk=await this.api("get-script-artifact",{runId:run.runId,artifactId:item.id,offset,length:262144});
    this.chunkFacts=artifactFacts(rawChunk);
    if(rawChunk?.success===false){
     // Read-only same-owner probes classify transport consistency; the original failure still fails the run.
     const args={runId:run.runId,artifactId:item.id,offset,length:262144};
     this.protocolFacts={http:this.chunkFacts};
     for(const [label,generic] of [["directMCP",false],["genericMCP",true]]){
      try{this.protocolFacts[label]=artifactFacts(await this.direct("kelpie_get_script_artifact",args,generic));}
      catch(error){this.protocolFacts[label]={exception:errorFacts(error)};}
     }
    }
    const chunk=scriptArtifactChunkSchema.parse(rawChunk);
    requireTrue(chunk.runId===run.runId&&chunk.artifactId===item.id&&chunk.offset===offset&&chunk.sha256===item.sha256&&chunk.mimeType===item.mimeType&&chunk.byteLength===item.byteLength,"CHUNK_IDENTITY");
    const bytes=Buffer.from(chunk.data,"base64");requireTrue(bytes.length>0&&chunk.nextOffset===offset+bytes.length,"CHUNK_OFFSET");
    chunks.push(bytes);offset=chunk.nextOffset;requireTrue(chunk.eof===(offset===item.byteLength),"CHUNK_EOF");
   }
   const bytes=Buffer.concat(chunks);
   requireTrue(bytes.length===item.byteLength&&createHash("sha256").update(bytes).digest("hex")===item.sha256,"ARTIFACT_HASH");
   await writeFile(file,bytes,{flag:"wx"});
   const record={runId:run.runId,...item,file};this.artifacts.push(record);records.push(record);
  }
  return records;
 }
}
export function cli(args,timeout=45000){
 const child=spawn("node",["packages/cli/bin/kelpie.js","--device","127.0.0.1:28420","--format","json","--timeout","45000",...args],{stdio:["ignore","pipe","pipe"]});
 let stdout="",stderr="";const timer=setTimeout(()=>child.kill("SIGTERM"),timeout);
 child.stdout.on("data",data=>{stdout+=data;if(stdout.length>8*1024*1024)child.kill("SIGTERM");});
 child.stderr.on("data",data=>{if(stderr.length<65536)stderr+=data;});
 const result=new Promise((resolve,reject)=>{child.once("error",()=>{clearTimeout(timer);reject(new Failure("CLI_SPAWN"));});child.on("exit",code=>{clearTimeout(timer);if(code!==0)return reject(new Failure("CLI_EXIT_"+code));try{resolve(JSON.parse(stdout));}catch{reject(new Failure("CLI_JSON"));}});});
 return {process:child,result};
}

export async function cliMCP(){
 const child=spawn("node",["packages/cli/bin/kelpie.js","--device","127.0.0.1:28420","mcp"],{stdio:["pipe","pipe","pipe"]});
 let text="",sequence=0;const pending=new Map();
 child.stdout.setEncoding("utf8");child.stdout.on("data",value=>{
  text+=value;if(text.length>1048576){child.kill("SIGTERM");return;}
  let line;while((line=text.indexOf("\n"))>=0){const raw=text.slice(0,line);text=text.slice(line+1);
   try{const result=JSON.parse(raw);pending.get(result.id)?.(result);pending.delete(result.id);}catch{child.kill("SIGTERM");}}
 });
 child.stderr.resume();
 const call=(method,params)=>new Promise((resolve,reject)=>{const id=++sequence;
  const timer=setTimeout(()=>{pending.delete(id);reject(new Failure("CLI_MCP_TIMEOUT"));},20000);
  pending.set(id,value=>{clearTimeout(timer);value.error?reject(new Failure("CLI_MCP_ERROR")):resolve(value.result);});
  child.stdin.write(JSON.stringify({jsonrpc:"2.0",id,method,params})+"\n");
 });
 try{
  await new Promise((resolve,reject)=>{child.once("spawn",resolve);child.once("error",()=>reject(new Failure("CLI_MCP_SPAWN")));});
  await call("initialize",{protocolVersion:"2024-11-05",capabilities:{},clientInfo:{name:"hosted-native-acceptance",version:"1"}});
  child.stdin.write(JSON.stringify({jsonrpc:"2.0",method:"notifications/initialized"})+"\n");
  const tools=await call("tools/list",{});requireTrue(tools.tools.some(t=>t.name==="kelpie_extension"),"CLI_MCP_TOOL_MISSING");
  await call("tools/call",{name:"kelpie_extension_tools",arguments:{names:["kelpie_get_script_status"]}});
  const result=await call("tools/call",{name:"kelpie_extension",arguments:{name:"kelpie_get_script_status",arguments:{}}});
  const value=JSON.parse(result.content.find(v=>v.type==="text").text);
  requireTrue(JSON.stringify(value).includes("supportedVersions"),"CLI_MCP_NATIVE_STATUS");
  return {tool:"kelpie_get_script_status",nativeStatus:true};
 }finally{child.stdin.end();child.kill("SIGTERM");}
}
