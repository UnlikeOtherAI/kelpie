#!/usr/bin/env node
// Pinned Chromium only. No worker, fixture corpus, CLI, or comparative cost.
import assert from "node:assert/strict";
import {spawn} from "node:child_process";
import {createHash,randomBytes} from "node:crypto";
import {createReadStream} from "node:fs";
import {mkdir,readFile,writeFile} from "node:fs/promises";
import {join,resolve} from "node:path";
import {observePrivateBoundary,validatePrivateProbe} from "./worker-comparison-network.mjs";
import {validNamespaceHandoff} from "./worker-comparison-netns.mjs";
import {validHostSandboxHandoff} from "./worker-comparison-host-sandbox.mjs";
import {nativeProcessStartTicks} from "./native-resource-snapshot.mjs";
import {classifySpawnError,createBoundedStderr} from "./worker-comparison-launch-diagnostic.mjs";
import {startSmokeFixture} from "./worker-comparison-smoke-fixture.mjs";
const [binary,expected,output]=process.argv.slice(2);
assert.match(expected??"",/^[a-f0-9]{64}$/);
assert.match(process.env.KELPIE_COMPARISON_ID??"",/^[a-f0-9]{64}$/);
assert.ok(process.getuid()>0&&binary&&output);
const dir=resolve(output),home=join(dir,"home"),executable=resolve(binary);
const hash=createHash("sha256");for await(const bytes of createReadStream(executable))hash.update(bytes);
assert.equal(hash.digest("hex"),expected,"BINARY_HASH_MISMATCH");
await mkdir(home,{mode:0o700});
const observed=await observePrivateBoundary(process.env.KELPIE_AB_CANARY_HOST??"",Number(process.env.KELPIE_AB_CANARY_PORT));
await writeFile(join(dir,"network-observation.json"),JSON.stringify({pid:process.pid,uid:process.getuid(),observed}),{mode:0o600,flag:"wx"});
const networkProbe=validatePrivateProbe(observed.local,observed.nonlocal);
let ready=false;
for(let n=0;n<300&&!ready;n++){
 try{ready=validNamespaceHandoff(JSON.parse(await readFile(join(dir,"namespace-verified.json"),"utf8")),process.pid,process.env.KELPIE_COMPARISON_ID);}catch{/* Independent check pending. */}
 if(!ready)await new Promise(ok=>setTimeout(ok,100));
}
assert.ok(ready,"PRIVATE_NETWORK_NOT_VERIFIED");
const group=(await readFile("/proc/self/cgroup","utf8")).split("\n").find(x=>x.startsWith("0::"))?.slice(3);
assert.ok(group?.startsWith("/"));
const delay=ms=>new Promise(ok=>setTimeout(ok,ms));
const env={PATH:process.env.PATH??"/usr/bin:/bin",HOME:home,LANG:"C.UTF-8"};
let browser,fixture,canaryObserved=false,category="startup",evidence=null,startTicks=null,spawnEvent="not-started",spawnError=null,closePromise;
const stderr=createBoundedStderr();
let preIdentityExit=false,exitObserved=false,exitCode=null,exitSignal=null,cleanup="none";
try{
 fixture=await startSmokeFixture(randomBytes(32).toString("hex"));
 browser=spawn(executable,["--headless=new","--remote-debugging-port=0","--user-data-dir="+join(home,"profile"),"--no-first-run",fixture.origin],{env,stdio:["ignore","ignore","pipe"]});
 browser.stderr.on("data",chunk=>stderr.append(chunk));
 closePromise=new Promise(ok=>browser.once("close",ok));
 browser.once("exit",(code,signal)=>{exitObserved=true;exitCode=code;exitSignal=signal;if(!startTicks&&cleanup==="none")preIdentityExit=true;});
 const spawned=new Promise(ok=>{
  browser.once("spawn",()=>{spawnEvent="spawn";ok();});
  browser.once("error",error=>{spawnEvent="error";spawnError=classifySpawnError(error.code);ok();});
 });
 await Promise.race([spawned,delay(3000)]);
 assert.equal(spawnEvent,"spawn","SMOKE_SPAWN_FAILED");
 category="identity";
 startTicks=await nativeProcessStartTicks(browser.pid);
 assert.ok(startTicks,"SANDBOX_BROWSER_ID");
 category="page-canary-unobserved";
 canaryObserved=await Promise.race([fixture.waitForCanary(15000),closePromise.then(()=>false)]);
 assert.ok(canaryObserved,"PAGE_CANARY_MISSING");
 category="identity";
 assert.equal(await nativeProcessStartTicks(browser.pid),startTicks,"SANDBOX_BROWSER_CHANGED");
 assert.equal(browser.exitCode,null,"SANDBOX_BROWSER_EXITED");
 assert.equal(browser.signalCode,null,"SANDBOX_BROWSER_EXITED");
 await writeFile(join(dir,"browser-identity.json"),JSON.stringify({pid:browser.pid,startTicks,unitPid:process.pid,nonce:process.env.KELPIE_COMPARISON_ID}),{mode:0o600,flag:"wx"});
 category="host-audit-timeout";
 for(let attempt=0;attempt<400&&!evidence;attempt++){
  if(browser.exitCode!==null||browser.signalCode!==null)break;
  try{const result=JSON.parse(await readFile(join(dir,"host-sandbox-result.json"),"utf8"));
   if(validHostSandboxHandoff(result,browser.pid,startTicks,process.pid,process.env.KELPIE_COMPARISON_ID)){
    if(result.ok)evidence=result.evidence;else {category=result.category;break;}
   }
  }catch{/* Host audit is pending. */}
  if(!evidence)await delay(100);
 }
 if(!evidence)throw Error("SMOKE_SANDBOX_NOT_PROVEN");
 await writeFile(join(dir,"report.json"),JSON.stringify({pid:process.pid,uid:process.getuid(),networkProbe,
  binarySHA256:expected,sandboxEvidence:evidence},null,2),{mode:0o600,flag:"wx"});
}catch{
 await writeFile(join(dir,"failure.json"),JSON.stringify({category}),{mode:0o600,flag:"wx"});process.exitCode=1;
}finally{
 if(browser&&browser.exitCode===null&&browser.signalCode===null&&spawnEvent==="spawn"){
  cleanup="term";browser.kill("SIGTERM");await Promise.race([closePromise,delay(1500)]);
  if(browser.exitCode===null&&browser.signalCode===null){cleanup="kill";browser.kill("SIGKILL");await Promise.race([closePromise,delay(1500)]);}
 }else if(closePromise)await Promise.race([closePromise,delay(1500)]);
 if(fixture)await fixture.close();
 const allowedSignals=["SIGABRT","SIGBUS","SIGFPE","SIGILL","SIGKILL","SIGSEGV","SIGSYS","SIGTERM","SIGTRAP"];
 const diagnostic={binarySHA256:expected,spawnEvent:spawnEvent==="not-started"?"timeout":spawnEvent,spawnError,
  pid:Number.isSafeInteger(browser?.pid)?browser.pid:null,startTicks,
  canaryObserved,preIdentityExit,exitObserved,exitCode:Number.isInteger(exitCode)?exitCode:null,
  exitSignal:allowedSignals.includes(exitSignal)?exitSignal:exitSignal?"OTHER":null,cleanup,stderr:stderr.result()};
 await writeFile(join(dir,"process-diagnostic.json"),JSON.stringify(diagnostic,null,2),{mode:0o600,flag:"wx"});
}
