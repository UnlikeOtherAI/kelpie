// Test-only CEF release-context probe. All network, input and profiles are private.
import assert from "node:assert/strict";
import {createServer} from "node:http";
import {createServer as createNetServer} from "node:net";
import {mkdtemp,writeFile} from "node:fs/promises";
import {randomBytes,createHash} from "node:crypto";
import {spawn} from "node:child_process";
import {resolve} from "node:path";
import {resolveScriptTarget} from "../../packages/shared/dist/index.js";

const [binaryArg, outputArg] = process.argv.slice(2);
assert.ok(binaryArg && outputArg, "Provide probe binary and fresh receipt path");
const nonce=randomBytes(16).toString("hex"), key="__kelpie_release_proof_"+nonce;
const sentinel="__kelpie_release_nonce_"+nonce;
const html=`<!doctype html><style>button,input{position:absolute;left:80px;top:80px;width:100px;height:50px}
input{top:180px}</style><button id="go">Go</button><input id="edit" type="text">
<script>document.querySelector('#go').onclick=()=>{document.body.dataset.before='set';
document.querySelector('#edit').type='password';location.href='/done';document.body.dataset.after='set'}</script>`;
let doneRequests=0;
const server=createServer((request,response)=>{
  if(request.url==="/done"){doneRequests++;response.writeHead(200,{"content-type":"text/html"});response.end("<title>done</title>");return;}
  response.writeHead(200,{"content-type":"text/html"});response.end(html);
});
await new Promise(ok=>server.listen(0,"127.0.0.1",ok));
const url="http://127.0.0.1:"+server.address().port+"/";
const probePort=await new Promise((ok,bad)=>{const socket=createNetServer();socket.once("error",bad);
  socket.listen(0,"127.0.0.1",()=>{const p=socket.address().port;socket.close(()=>ok(p));});});
const runtime=await mkdtemp("/tmp/kelpie-cef-release-");
const env={...process.env,KELPIE_RELEASE_PROOF_NONCE:nonce,KELPIE_RELEASE_PROOF_URL:url,
  KELPIE_RELEASE_PROOF_PORT:String(probePort),XDG_RUNTIME_DIR:runtime};
for(const name of ["DISPLAY","WAYLAND_DISPLAY","XAUTHORITY","DBUS_SESSION_BUS_ADDRESS","AT_SPI_BUS_ADDRESS","GNOME_SETUP_DISPLAY"])delete env[name];
const child=spawn(resolve(binaryArg),[],{env,stdio:["ignore","pipe","pipe"]});
let stdout="",stderr="";
child.stdout.on("data",x=>{if(stdout.length<65536)stdout+=x.toString().slice(0,65536-stdout.length)});
child.stderr.on("data",x=>{if(stderr.length<131072)stderr+=x.toString().slice(0,131072-stderr.length)});
const exited=new Promise(ok=>{child.once("error",error=>ok({error:error.message}));child.once("exit",(code,signal)=>ok({code,signal}));});
let socket,closeResult,driverError,token,mainContext,decoyContext,clickAck=false;
const timeout=ms=>new Promise(ok=>setTimeout(ok,ms));
async function until(fn,ms=20000){const end=Date.now()+ms;while(Date.now()<end){const x=await fn().catch(()=>null);if(x)return x;await timeout(100);}throw Error("probe deadline");}
try{
  const target=await until(async()=>{const r=await fetch("http://127.0.0.1:"+probePort+"/json/list",{signal:AbortSignal.timeout(1000)});
    return (await r.json()).find(x=>x.type==="page"&&x.url.startsWith(url));});
  socket=new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((ok,bad)=>{socket.addEventListener("open",ok,{once:true});socket.addEventListener("error",bad,{once:true});});
  let next=0;const pending=new Map();
  socket.addEventListener("message",event=>{const msg=JSON.parse(event.data);if(msg.id&&pending.has(msg.id)){const [ok,bad,timer]=pending.get(msg.id);
    clearTimeout(timer);pending.delete(msg.id);msg.error?bad(Error(JSON.stringify(msg.error))):ok(msg.result);}});
  const call=(method,params={})=>new Promise((ok,bad)=>{const id=++next;const timer=setTimeout(()=>{pending.delete(id);bad(Error(method+" deadline"));},5000);pending.set(id,[ok,bad,timer]);socket.send(JSON.stringify({id,method,params}));});
  const tree=await call("Page.getFrameTree");
  const frameId=tree.frameTree.frame.id;
  mainContext=(await call("Page.createIsolatedWorld",{frameId,worldName:"kelpie-proof"})).executionContextId;
  decoyContext=(await call("Page.createIsolatedWorld",{frameId,worldName:"kelpie-decoy"})).executionContextId;
  const targetRequest={selector:"#edit"};
  const expression="("+resolveScriptTarget.toString()+")("+JSON.stringify(targetRequest)+","+JSON.stringify(key)+
    ",undefined,false,undefined,false,{refuseSensitive:true})";
  const prepared=await call("Runtime.evaluate",{contextId:mainContext,expression,returnByValue:true});
  assert.equal(prepared.result.value?.ok,true,JSON.stringify(prepared));
  token=prepared.result.value.token;assert.equal(typeof token,"string");
  const setSentinel=await call("Runtime.evaluate",{contextId:mainContext,
    expression:"globalThis["+JSON.stringify(sentinel)+"]="+JSON.stringify(nonce),returnByValue:true});
  assert.equal(setSentinel.result.value,nonce);
  await call("Runtime.evaluate",{contextId:decoyContext,
    expression:"globalThis["+JSON.stringify(sentinel)+"]='wrong-nonce'",returnByValue:true});
  await call("Input.dispatchMouseEvent",{type:"mousePressed",x:120,y:100,button:"left",clickCount:1});
  await call("Input.dispatchMouseEvent",{type:"mouseReleased",x:120,y:100,button:"left",clickCount:1});
  clickAck=true;
  await until(async()=>doneRequests>0,10000);
  await timeout(1500);
  await call("Page.close").catch(()=>{});
  closeResult=await Promise.race([exited,timeout(5000).then(()=>null)]);
  if(!closeResult){child.kill("SIGTERM");closeResult=await Promise.race([exited,timeout(3000).then(()=>({timeout:true}))]);}
}catch(error){driverError=error.message;if(socket?.readyState===WebSocket.OPEN)socket.close();child.kill("SIGTERM");closeResult=await exited;}
finally{server.close();}
const records=stderr.split("\n").filter(line=>line.startsWith("KELPIE_RELEASE_PROOF ")).flatMap(line=>{
  try{return [JSON.parse(line.slice("KELPIE_RELEASE_PROOF ".length))]}catch{return []}});
const matches=records.filter(record=>record.observation?.nonceMatch===true);
const unique=matches.length===1;
const matched=unique?matches[0]:null;
const passed=Boolean(!driverError&&clickAck&&doneRequests===1&&closeResult?.code===0&&unique&&
  matched.mainFrame&&matched.evalOK&&matched.observation.before==="set"&&matched.observation.after==="set"&&
  matched.classificationEvalOK&&matched.classification?.ok===true&&matched.classification.sensitive===true&&
  matched.classification.sensitivityKnown===true);
const receipt={version:1,source:process.env.KELPIE_CAPTURE_SOURCE,
  binarySHA256:createHash("sha256").update(await (await import("node:fs/promises")).readFile(resolve(binaryArg))).digest("hex"),
  targetURL:url,privateWorldCreated:Number.isInteger(mainContext),decoyWorldCreated:Number.isInteger(decoyContext),
  originalTokenPresent:typeof token==="string",clickAck,doneRequests,closeResult,driverError,records,
  passed,confidence:passed?"single isolated-world release observation":"insufficient"};
await writeFile(resolve(outputArg),JSON.stringify(receipt,null,2),{flag:"wx"});
console.log(JSON.stringify({passed,driverError,clickAck,doneRequests,closeResult,callbacks:records.length,matchingCallbacks:matches.length}));
if(!passed)process.exitCode=1;
