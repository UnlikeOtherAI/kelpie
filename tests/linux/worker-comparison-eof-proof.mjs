#!/usr/bin/env node
// Public EOF probe. Runs only inside the independently verified private unit.
import assert from "node:assert/strict";
import {spawn,execFile} from "node:child_process";
import {createHash} from "node:crypto";
import {createReadStream} from "node:fs";
import {mkdir,readFile,writeFile,unlink} from "node:fs/promises";
import {createServer as fixtureServer} from "node:http";
import {createConnection,createServer} from "node:net";
import {createRequire} from "node:module";
import {join,resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {promisify} from "node:util";
import {startEofRelay,verifyEngineCdp} from "./worker-comparison-eof-relay.mjs";
import {observePrivateBoundary,validatePrivateProbe} from "./worker-comparison-network.mjs";
import {validNamespaceHandoff} from "./worker-comparison-netns.mjs";

import {verifyOwnedListener} from "./worker-comparison-listener.mjs";
import {nativeProcessStartTicks} from "./native-resource-snapshot.mjs";
const require=createRequire(new URL("../../packages/cli/package.json",import.meta.url));
const {Client}=require("@modelcontextprotocol/sdk/client/index.js");
const {StdioClientTransport,getDefaultEnvironment}=require("@modelcontextprotocol/sdk/client/stdio.js");
const root=fileURLToPath(new URL("../..",import.meta.url));
const [file,expected,output]=process.argv.slice(2),dir=resolve(output),binary=resolve(file);
assert.equal(expected,"ae7d01d261efb9e480e18ce3424533332883863bcf70b12a4321b5733f37e19e");
assert.match(process.env.KELPIE_TEST_REVISION??"",/^[a-f0-9]{40}$/);
assert.match(process.env.KELPIE_COMPARISON_ID??"",/^[a-f0-9]{64}$/);
assert.ok(typeof process.getuid==="function"&&process.getuid()>0);
const git=promisify(execFile);
assert.equal((await git("git",["rev-parse","HEAD"],{cwd:root,timeout:5000})).stdout.trim(),process.env.KELPIE_TEST_REVISION);
assert.equal((await git("git",["status","--porcelain","--untracked-files=no"],{cwd:root,timeout:5000})).stdout.trim(),"");
async function hashFile(file){const digest=createHash("sha256");for await(const chunk of createReadStream(file))digest.update(chunk);return digest.digest("hex");}
assert.equal(await hashFile(binary),expected);
const group=(await readFile("/proc/self/cgroup","utf8")).split("\n").find(x=>x.startsWith("0::"))?.slice(3);
assert.ok(group?.startsWith("/"));
const [memory,cpu,tasks]=await Promise.all(["memory.max","cpu.max","pids.max"].map(x=>readFile("/sys/fs/cgroup"+group+"/"+x,"utf8").then(s=>s.trim())));
assert.equal(memory,"2147483648");assert.equal(tasks,"256");
const [quota,period]=cpu.split(/\s+/).map(Number);assert.equal(quota,period);
const observed=await observePrivateBoundary(process.env.KELPIE_AB_CANARY_HOST??"",Number(process.env.KELPIE_AB_CANARY_PORT));
await writeFile(join(dir,"network-observation.json"),JSON.stringify({pid:process.pid,uid:process.getuid(),observed}),{mode:0o600,flag:"wx"});
const networkProbe=validatePrivateProbe(observed.local,observed.nonlocal);
const delay=ms=>new Promise(ok=>setTimeout(ok,ms));
let verified=false;
for(let i=0;i<300&&!verified;i++){
 try{verified=validNamespaceHandoff(JSON.parse(await readFile(join(dir,"namespace-verified.json"),"utf8")),process.pid,process.env.KELPIE_COMPARISON_ID);}catch{}
 if(!verified)await delay(100);
}
assert.ok(verified,"PRIVATE_NETWORK_NOT_VERIFIED");
const timed=async(p,ms)=>{let id;try{return await Promise.race([p,new Promise((_,bad)=>{id=setTimeout(()=>bad(Error("TIMEOUT")),ms);})]);}finally{clearTimeout(id);}};
function exited(child){if(child.exitCode!==null||child.signalCode!==null)return Promise.resolve({code:child.exitCode,signal:child.signalCode});
 return new Promise(ok=>child.once("exit",(code,signal)=>ok({code,signal})));}
const report={version:1,pid:process.pid,uid:process.getuid(),networkProbe,source:process.env.KELPIE_TEST_REVISION,
 engineSHA256:expected,boundary:{memoryMax:memory,cpuMax:cpu,tasksMax:tasks},stage:"setup",outcome:"insufficient",
 cli:{eofSent:false,signals:[],exit:null},engine:{sameIdentity:false,usable:false,termSent:false,exit:null},
 fixture:{created:false,disposed:false}};
const home=join(dir,"home");await mkdir(home,{recursive:true,mode:0o700});
const fixture=fixtureServer((req,res)=>{res.writeHead(200,{"content-type":"text/html"});res.end("<!doctype html><title>EOF fixture</title>");});
let engine,engineExit,child,relay,config,failed=false;
try{
 report.stage="fixture";await new Promise(ok=>fixture.listen(0,"127.0.0.1",ok));
 const origin="http://127.0.0.1:"+fixture.address().port,url=origin+"/eof-"+process.env.KELPIE_COMPARISON_ID;
 const reserve=createServer();await new Promise(ok=>reserve.listen(0,"127.0.0.1",ok));const port=reserve.address().port;
 await new Promise(ok=>reserve.close(ok));
 const env={PATH:process.env.PATH??"/usr/bin:/bin",LANG:"C.UTF-8",HOME:home,KELPIE_HOME:join(home,"kelpie"),LIGHTPANDA_DISABLE_TELEMETRY:"true",LIGHTPANDA_DISABLE_CORE_DUMP:"1"};
 report.stage="engine-start";
 engine=spawn(binary,["serve","--host","127.0.0.1","--port",String(port),"--log-level","error"],{env,stdio:"ignore"});
 engine.on("error",()=>{});engineExit=exited(engine);
 const ticks=await nativeProcessStartTicks(engine.pid);assert.ok(ticks);
 let ready=false;
 for(let i=0;i<150&&!ready;i++){
  assert.equal(engine.exitCode,null);assert.equal(engine.signalCode,null);
  ready=await new Promise(ok=>{const s=createConnection({host:"127.0.0.1",port});
   s.setTimeout(100);s.once("connect",()=>{s.destroy();ok(true);});s.once("error",()=>ok(false));s.once("timeout",()=>{s.destroy();ok(false);});});
  if(!ready)await delay(30);
 }
 assert.ok(ready);await verifyOwnedListener(engine.pid,port,ticks);
 report.engine.pid=engine.pid;report.engine.startTicks=ticks;
 relay=await startEofRelay({port,pid:engine.pid,startTicks:ticks});
 const endpoint=relay.endpoint;config=join(dir,"..","..","worker-ab-assets","eof-operator.json");
 await writeFile(config,JSON.stringify({version:1,backend:"lightpanda",endpointEnv:"KELPIE_AB_ENDPOINT",allowedOrigins:[origin],
  networkBoundary:"operator-enforced",maxSessions:1,maxTabs:1,maxTtlMs:60000,
  verifiedLightpandaMethods:["tabs.list","tabs.close","tab.goto","tab.url","tab.title","tab.back","tab.forward","tab.reload","tab.snapshot","tab.extract","tab.status","tab.ready"]}),{mode:0o600,flag:"wx"});
 report.cliBundleSHA256=await hashFile(join(root,"packages/cli/dist/index.js"));
 report.sharedBundleSHA256=await hashFile(join(root,"packages/shared/dist/browser-control/managed-session.js"));
 report.stage="client-connect";
 const transport=new StdioClientTransport({command:process.execPath,args:[join(root,"packages/cli/bin/kelpie.js"),"worker","mcp","--config",config],cwd:root,
  env:{...getDefaultEnvironment(),HOME:home,KELPIE_HOME:env.KELPIE_HOME,KELPIE_AB_ENDPOINT:endpoint},stderr:"pipe"});
 transport.stderr?.resume();
 const client=new Client({name:"kelpie-eof-proof",version:"1.0.0"},{capabilities:{}});
 await timed(client.connect(transport),10000);
 child=transport._process;assert.ok(child&&child.pid===transport.pid&&child.stdin);
 const childExit=exited(child),originalKill=child.kill.bind(child);
 child.kill=signal=>{report.cli.signals.push(String(signal??"SIGTERM"));return originalKill(signal);};
 report.cli.pid=child.pid;report.cli.startTicks=await nativeProcessStartTicks(child.pid);assert.ok(report.cli.startTicks);
 const call=async(name,args)=>{const result=await timed(client.callTool({name,arguments:args}),5000);
  const text=result.content.find(x=>x.type==="text")?.text;assert.equal(typeof text,"string");return JSON.parse(text);};
 report.stage="session";
 const created=await call("kelpie_worker_session",{request:{action:"create",options:{isolation:"isolated",ttlMs:60000}}});
 assert.equal(created.ok,true);const session=created.value;assert.equal(session.ownedTabIds.length,1);
 const moved=await call("kelpie_browser_control",{sessionId:session.sessionId,request:{version:1,method:"tab.goto",params:{url},tabId:session.ownedTabIds[0]}});
 assert.equal(moved.ok,true);
 report.stage="witness-ready";assert.equal(relay.result().stage,"dispose");report.fixture.created=true;
 report.stage="stdin-eof";assert.equal(await nativeProcessStartTicks(child.pid),report.cli.startTicks);
 child.stdin.end();report.cli.eofSent=true;assert.equal(relay.markEof(),true);report.cli.exit=await timed(childExit,2000);
 assert.equal(report.cli.exit.code,0);assert.equal(report.cli.exit.signal,null);assert.deepEqual(report.cli.signals,[]);
 report.stage="post-eof";
 assert.equal(engine.exitCode,null);assert.equal(engine.signalCode,null);
 assert.equal(await nativeProcessStartTicks(engine.pid),ticks);await verifyOwnedListener(engine.pid,port,ticks);
 report.engine.sameIdentity=true;
 const witness=relay.result();report.fixture.witness=witness;
 assert.equal(witness.ok,true);
 await verifyEngineCdp({port,pid:engine.pid,startTicks:ticks});
 report.fixture.disposed=true;report.engine.usable=true;report.stage="complete";
}catch(error){
 failed=true;const message=error?.message;
 report.outcome=["CONTEXT_ID_UNAVAILABLE","FIXTURE_TARGET_NOT_UNIQUE","CDP_VERSION_INVALID","CDP_UNSUPPORTED","CDP_CONNECTION_FAILED","CDP_CLOSED","CDP_INVALID","TIMEOUT"].includes(message)?message:"PROOF_FAILED";
}finally{
 if(engine&&engine.exitCode===null&&engine.signalCode===null){
  report.engine.termSent=true;report.engine.termAccepted=engine.kill("SIGTERM");
  try{report.engine.exit=await timed(engineExit,1500);}catch{failed=true;report.engine.termTimeout=true;}
 }else if(engine){failed=true;report.engine.exit=await engineExit;report.engine.unexpectedExit=true;}
 if(engine&&(!report.engine.termAccepted||!report.engine.exit||
   !((report.engine.exit.code===0&&report.engine.exit.signal===null)||report.engine.exit.signal==="SIGTERM")))failed=true;
 if(relay){report.fixture.witness=relay.result();await relay.close();}
 if(config){try{await unlink(config);report.configRetired=true;}catch(error){if(error?.code!=="ENOENT"){report.configRetired=false;failed=true;}}}
 fixture.closeAllConnections?.();if(fixture.listening)await new Promise(ok=>fixture.close(ok));
 if(!failed)report.outcome="passed";
 await writeFile(join(dir,"report.json"),JSON.stringify(report,null,2),{mode:0o600,flag:"wx"});
 if(failed)process.exit(1);
}
