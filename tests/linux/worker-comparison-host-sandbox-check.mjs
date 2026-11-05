import assert from "node:assert/strict";
import {readFile,writeFile} from "node:fs/promises";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {join} from "node:path";
import {createHostReader,readHostSnapshot,validateHostSnapshot,hostAuditCategory,summarizeRendererCandidates} from "./worker-comparison-host-sandbox.mjs";
const [dir,unit,nonce]=process.argv.slice(2),exec=promisify(execFile);
assert.ok(dir&&/^kelpie-worker-ab-\d+-\d+-(sandbox|playwright)$/.test(unit??"")&&/^[a-f0-9]{64}$/.test(nonce??""));
const group="/sys/fs/cgroup/system.slice/"+unit+".service";
const identity=JSON.parse(await readFile(join(dir,"browser-identity.json"),"utf8"));
const policy=JSON.parse(await readFile(join(dir,"policy-observed.json"),"utf8"));
const namespace=JSON.parse(await readFile(join(dir,"namespace-verified.json"),"utf8"));
assert.ok(Number.isSafeInteger(identity.pid)&&identity.pid>0&&/^\d+$/.test(identity.startTicks??""));
assert.ok(Array.isArray(identity.rendererPids)&&identity.rendererPids.length>0&&identity.rendererPids.length<=256&&identity.rendererPids.every(pid=>Number.isSafeInteger(pid)&&pid>0)&&new Set(identity.rendererPids).size===identity.rendererPids.length);
assert.equal(identity.unitPid,policy.policy?.pid);assert.equal(identity.unitPid,namespace.pid);
assert.equal(identity.nonce,nonce);assert.equal(namespace.nonce,nonce);
if(unit.endsWith("-playwright")){assert.equal(identity.stage,"isolated-session");assert.match(identity.stageNonce??"",/^[a-f0-9]{64}$/);}
const reader=createHostReader(),delay=ms=>new Promise(ok=>setTimeout(ok,ms));
let category="no-renderer",evidence=null;
let counts={cdpCount:identity.rendererPids.length,hostLabeledCount:null,missingMembership:null,unreadableCmdline:null,omittedLabeled:null};
try{
 const unitPid=async()=>Number((await exec("systemctl",["show",unit,"--value","--property=ExecMainPID"],{timeout:1000,maxBuffer:1024})).stdout.trim());
 assert.equal(await unitPid(),identity.unitPid,"AUDIT_IDENTITY");
 while(reader.within()&&!evidence){
  try{
   const before=await readHostSnapshot(group,reader),after=await readHostSnapshot(group,reader);
   counts=summarizeRendererCandidates({rendererPids:identity.rendererPids,before,after});
   evidence=validateHostSnapshot({unitPid:identity.unitPid,browserPid:identity.pid,startTicks:identity.startTicks,rendererPids:identity.rendererPids,before,after});
  }catch(error){
   category=hostAuditCategory(error);
   if(category!=="no-renderer"&&category!=="process-race")break;
   await delay(100);
  }
 }
 assert.equal(await unitPid(),identity.unitPid,"AUDIT_IDENTITY");
 if(!evidence)throw Error("AUDIT_FAILED");
 await writeFile(join(dir,"host-sandbox-result.json"),JSON.stringify({ok:true,unitPid:identity.unitPid,pid:identity.pid,
  startTicks:identity.startTicks,nonce,stageNonce:identity.stageNonce??null,evidence,counts,...reader.stats()}),{mode:0o600,flag:"wx"});
}catch(error){
 if(String(error?.message??"").includes("AUDIT_IDENTITY"))category="identity";
 await writeFile(join(dir,"host-sandbox-result.json"),JSON.stringify({ok:false,unitPid:identity.unitPid,pid:identity.pid,
  startTicks:identity.startTicks,nonce,stageNonce:identity.stageNonce??null,category,counts,...reader.stats()}),{mode:0o600,flag:"wx"});
 process.exitCode=1;
}
