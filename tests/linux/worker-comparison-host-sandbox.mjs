import assert from "node:assert/strict";
import {open,readlink,stat} from "node:fs/promises";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {performance} from "node:perf_hooks";
import {parseProcStat} from "./native-resource-snapshot.mjs";
import {parseStatusValue,validateSandboxCollection} from "./worker-comparison-sandbox.mjs";
const exec=promisify(execFile);
const disabled=["--no-sandbox","--disable-setuid-sandbox","--disable-namespace-sandbox","--disable-seccomp-filter-sandbox"];
export function summarizeRendererCandidates({rendererPids,before,after}){
 assert.ok(Array.isArray(rendererPids)&&rendererPids.length>0&&rendererPids.length<=256&&
  rendererPids.every(pid=>Number.isSafeInteger(pid)&&pid>0)&&new Set(rendererPids).size===rendererPids.length,"AUDIT_CDP_RENDERER_MISMATCH");
 const candidates=new Set(rendererPids),labeled=[...before.values()].filter(item=>item.renderer);
 return {cdpCount:rendererPids.length,hostLabeledCount:labeled.length,
  missingMembership:rendererPids.filter(pid=>!before.has(pid)||!after.has(pid)).length,
  unreadableCmdline:rendererPids.filter(pid=>before.has(pid)&&after.has(pid)&&
   (!before.get(pid).cmdlinePresent||!after.get(pid).cmdlinePresent)).length,
  omittedLabeled:labeled.filter(item=>!candidates.has(item.pid)).length};
}
export function validateHostSnapshot({unitPid,browserPid,startTicks,rendererPids,before,after}){
 const counts=summarizeRendererCandidates({rendererPids,before,after});
 assert.equal(counts.missingMembership,0,"AUDIT_CDP_MISSING");
 assert.equal(counts.unreadableCmdline,0,"AUDIT_CDP_CMDLINE");
 assert.equal(counts.omittedLabeled,0,"AUDIT_CDP_OMISSION");
 assert.ok(before.has(unitPid)&&before.has(browserPid),"AUDIT_IDENTITY");
 const browser=before.get(browserPid),unit=before.get(unitPid);
 assert.ok(browser.cmdlinePresent&&after.get(browserPid)?.cmdlinePresent,"AUDIT_CDP_CMDLINE");
 assert.equal(browser.startTicks,startTicks,"AUDIT_RACE");
 assert.equal(browser.ppid,unitPid,"AUDIT_IDENTITY");
 assert.ok(unit.startTicks,"AUDIT_IDENTITY");
 assert.deepEqual([...before.keys()].sort((a,b)=>a-b),[...after.keys()].sort((a,b)=>a-b),"AUDIT_RACE");
 const candidates=new Set(rendererPids);
 for(const [pid,item] of before){
  const next=after.get(pid);
  assert.ok(next&&next.startTicks===item.startTicks&&next.ppid===item.ppid,"AUDIT_RACE");
  if(pid===browserPid||item.renderer||next.renderer||candidates.has(pid)){
   for(const key of ["userNs","pidNs","seccomp","filters","sandboxFlagsSafe","renderer","cmdlinePresent"])
    assert.equal(item[key],next[key],"AUDIT_RACE");
  }
 }
 const renderers=[];
 for(const pid of rendererPids){
  const item=before.get(pid);let parent=item.ppid,descendant=false;const seen=new Set([pid]);
  while(parent&&!seen.has(parent)){if(parent===browserPid){descendant=true;break;}seen.add(parent);parent=before.get(parent)?.ppid??0;}
  renderers.push({...item,owned:true,descendant});
 }
 return validateSandboxCollection({...browser,owned:true},renderers);
}
async function boundedRead(path){
 const file=await open(path,"r"),chunks=[];let total=0;
 try{while(true){const buffer=Buffer.alloc(4096),{bytesRead}=await file.read(buffer,0,buffer.length,null);
  if(!bytesRead)break;total+=bytesRead;assert.ok(total<=65536,"AUDIT_BUDGET");chunks.push(buffer.subarray(0,bytesRead));}
  return Buffer.concat(chunks,total).toString("utf8");
 }finally{await file.close();}
}

export function createHostReader({milliseconds=25000,maxFallbacks=128}={}){
 const end=performance.now()+milliseconds;let fallbacks=0;
 async function get(pid,name,link=false){
  assert.ok(Number.isSafeInteger(pid)&&pid>0,"AUDIT_IDENTITY");
  assert.ok(["stat","status","cmdline","ns/user","ns/pid"].includes(name),"AUDIT_FIELD");
  if(performance.now()>=end)throw Error("AUDIT_BUDGET");
  const path="/proc/"+pid+"/"+name;
  try{return link?await readlink(path):await boundedRead(path);}
  catch(error){
   if(String(error?.message??"").includes("AUDIT_BUDGET"))throw error;
   if(error?.code==="ENOENT"||error?.code==="ESRCH")throw Error("AUDIT_RACE");
   if(error?.code!=="EACCES"&&error?.code!=="EPERM")throw Error("AUDIT_UNREADABLE");
   if(++fallbacks>maxFallbacks)throw Error("AUDIT_BUDGET");
   try{return (await exec("sudo",["-n",link?"readlink":"cat",path],{timeout:1000,maxBuffer:65536})).stdout;}
   catch(error){if(error?.code==="ERR_CHILD_PROCESS_STDIO_MAXBUFFER")throw Error("AUDIT_BUDGET");try{await stat("/proc/"+pid);}catch(check){if(check?.code==="ENOENT")throw Error("AUDIT_RACE");}throw Error("AUDIT_UNREADABLE");}
  }
 }
 return {get,within:()=>performance.now()<end,stats:()=>({fallbackReads:fallbacks})};
}
export async function readHostSnapshot(group,reader){
 let text;
 try{text=await boundedRead(group+"/cgroup.procs");}
 catch(error){if(error?.code==="ENOENT")throw Error("AUDIT_RACE");
  if(String(error?.message??"").includes("AUDIT_BUDGET"))throw error;throw Error("AUDIT_UNREADABLE");}
 const pids=text.trim().split(/\s+/).filter(Boolean).map(Number);
 assert.ok(pids.length>0&&pids.length<=256&&pids.every(x=>Number.isSafeInteger(x)&&x>0),"AUDIT_CGROUP");
 const items=new Map();
 for(const pid of pids){
  const before=parseProcStat(await reader.get(pid,"stat"));assert.ok(before,"AUDIT_RACE");
  const status=await reader.get(pid,"status"),args=(await reader.get(pid,"cmdline")).split("\0").filter(Boolean);
  const userNs=(await reader.get(pid,"ns/user",true)).trim(),pidNs=(await reader.get(pid,"ns/pid",true)).trim();
  const after=parseProcStat(await reader.get(pid,"stat"));
  assert.ok(after&&before.startTicks===after.startTicks&&before.ppid===after.ppid,"AUDIT_RACE");
  items.set(pid,{pid,ppid:before.ppid,startTicks:before.startTicks,userNs,pidNs,
   seccomp:parseStatusValue(status,"Seccomp"),filters:parseStatusValue(status,"Seccomp_filters"),
   sandboxFlagsSafe:!args.some(arg=>disabled.some(flag=>arg===flag||arg.startsWith(flag+"="))),
   cmdlinePresent:args.length>0,renderer:args.includes("--type=renderer")});
 }
 return items;
}
export function hostAuditCategory(error){
 const text=String(error?.message??"");
 if(text.includes("AUDIT_CDP_MISSING"))return "cdp-missing";
 if(text.includes("AUDIT_CDP_CMDLINE"))return "cmdline-unreadable";
 if(text.includes("AUDIT_CDP_OMISSION"))return "cdp-omission";
 if(text.includes("AUDIT_CDP_RENDERER_MISMATCH"))return "cdp-mismatch";
 if(text.includes("AUDIT_UNREADABLE"))return "proc-unreadable";
 if(text.includes("AUDIT_RACE"))return "process-race";
 if(text.includes("AUDIT_BUDGET"))return "budget";
 if(text.includes("SANDBOX_NO_RENDERER"))return "no-renderer";
 if(text.includes("SANDBOX_DISABLED"))return "flags";
 if(text.includes("SANDBOX_SECCOMP")||text.includes("SANDBOX_FILTER"))return "filters";
 if(text.includes("SANDBOX_NAMESPACE"))return "namespace";
 if(text.includes("SANDBOX_OWNERSHIP")||text.includes("AUDIT_IDENTITY")||text.includes("AUDIT_CGROUP"))return "identity";
 return "other";
}

export function validHostSandboxHandoff(result,pid,startTicks,unitPid,nonce,stageNonce){
 const categories=["cdp-missing","cmdline-unreadable","cdp-omission","cdp-mismatch","proc-unreadable","process-race","budget","no-renderer","flags","filters","namespace","identity","other"];
 return result?.pid===pid&&result.startTicks===startTicks&&result.unitPid===unitPid&&result.nonce===nonce&&(stageNonce===undefined||result.stageNonce===stageNonce)&&
  (result.ok===true?result.evidence?.allOwnedRenderers===true&&result.evidence?.ownedRenderer===true&&
   result.evidence?.chromiumFlagsSafe===true&&result.evidence?.rendererSeccomp===2&&
   result.evidence?.additionalSeccompFilter===true&&result.evidence?.rendererNamespaceSeparated===true&&
   Number.isSafeInteger(result.evidence?.rendererCount)&&result.evidence.rendererCount>0:
   result.ok===false&&categories.includes(result.category));
}
