#!/usr/bin/env node
// Pinned Chromium only. No worker, fixture corpus, CLI, or comparative cost.
import assert from "node:assert/strict";
import {spawn} from "node:child_process";
import {createHash} from "node:crypto";
import {createReadStream} from "node:fs";
import {mkdir,readFile,writeFile} from "node:fs/promises";
import {join,resolve} from "node:path";
import {observePrivateBoundary,validatePrivateProbe} from "./worker-comparison-network.mjs";
import {validNamespaceHandoff} from "./worker-comparison-netns.mjs";
import {inspectOwnedChromiumSandbox,sandboxFailureCategory} from "./worker-comparison-sandbox.mjs";
import {nativeProcessStartTicks} from "./native-resource-snapshot.mjs";
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
const cgroup="/sys/fs/cgroup"+group,delay=ms=>new Promise(ok=>setTimeout(ok,ms));
const env={PATH:process.env.PATH??"/usr/bin:/bin",HOME:home,LANG:"C.UTF-8"};
let browser,category="startup",evidence=null;
try{
 browser=spawn(executable,["--headless=new","--remote-debugging-port=0","--user-data-dir="+join(home,"profile"),"--no-first-run","about:blank"],{env,stdio:"ignore"});
 browser.on("error",()=>{});
 category="identity";
 const startTicks=await nativeProcessStartTicks(browser.pid);
 assert.ok(startTicks,"SANDBOX_BROWSER_ID");
 for(let attempt=0;attempt<80&&!evidence;attempt++){
  if(browser.exitCode!==null||browser.signalCode!==null)break;
  try{evidence=await inspectOwnedChromiumSandbox(cgroup,browser.pid,startTicks);}
  catch(error){const next=sandboxFailureCategory(error);if(next!=="no-renderer"||category==="startup")category=next;await delay(100);}
 }
 if(!evidence)throw Error("SMOKE_SANDBOX_NOT_PROVEN");
 await writeFile(join(dir,"report.json"),JSON.stringify({pid:process.pid,uid:process.getuid(),networkProbe,
  binarySHA256:expected,sandboxEvidence:evidence},null,2),{mode:0o600,flag:"wx"});
}catch{
 await writeFile(join(dir,"failure.json"),JSON.stringify({category}),{mode:0o600,flag:"wx"});process.exitCode=1;
}finally{
 if(browser&&browser.exitCode===null&&browser.signalCode===null){
  const exited=new Promise(ok=>browser.once("exit",ok));browser.kill("SIGTERM");
  await Promise.race([exited,delay(1500)]);if(browser.exitCode===null&&browser.signalCode===null){browser.kill("SIGKILL");await Promise.race([exited,delay(1500)]);}
 }
}
