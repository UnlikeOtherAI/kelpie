import assert from "node:assert/strict";
import {readFile,readlink} from "node:fs/promises";
import {parseProcStat} from "./native-resource-snapshot.mjs";

export function validateSandboxFacts(browser,renderer){
 assert.ok(browser.owned&&renderer.owned&&renderer.descendant,"SANDBOX_OWNERSHIP");
 assert.ok(browser.sandboxFlagsSafe&&renderer.sandboxFlagsSafe,"SANDBOX_DISABLED");
 assert.equal(renderer.seccomp,2,"SANDBOX_SECCOMP");
 assert.ok(Number.isSafeInteger(browser.filters)&&Number.isSafeInteger(renderer.filters)&&renderer.filters>browser.filters,"SANDBOX_FILTER_NOT_PROVEN");
 for(const item of [browser,renderer]){assert.match(item.userNs??"",/^user:\[\d+\]$/);assert.match(item.pidNs??"",/^pid:\[\d+\]$/);}
 assert.ok(renderer.userNs!==browser.userNs||renderer.pidNs!==browser.pidNs,"SANDBOX_NAMESPACE_NOT_PROVEN");
 return {ownedRenderer:true,chromiumFlagsSafe:true,rendererSeccomp:2,additionalSeccompFilter:true,rendererNamespaceSeparated:true};
}
export function parseStatusValue(status,key){
 const line=status.split("\n").find(x=>x.startsWith(key+":"));
 const match=line?.slice(key.length+1).match(/^\s*(\d+)\s*$/);
 return match?Number(match[1]):null;
}
async function facts(pid){
 const root="/proc/"+pid;
 const before=parseProcStat(await readFile(root+"/stat","utf8"));assert.ok(before);
 const status=await readFile(root+"/status","utf8");
 const args=(await readFile(root+"/cmdline","utf8")).split("\0").filter(Boolean);
 const userNs=await readlink(root+"/ns/user"),pidNs=await readlink(root+"/ns/pid");
 const after=parseProcStat(await readFile(root+"/stat","utf8"));
 assert.ok(after&&before.startTicks===after.startTicks&&before.ppid===after.ppid,"SANDBOX_PROCESS_CHANGED");
 const value=key=>parseStatusValue(status,key);
 const forbidden=["--no-sandbox","--disable-setuid-sandbox","--disable-namespace-sandbox","--disable-seccomp-filter-sandbox"];
 return {pid,ppid:before.ppid,startTicks:before.startTicks,userNs,pidNs,seccomp:value("Seccomp"),filters:value("Seccomp_filters"),
  sandboxFlagsSafe:!args.some(arg=>forbidden.some(flag=>arg===flag||arg.startsWith(flag+"="))),
  renderer:args.includes("--type=renderer")};
}
export async function inspectOwnedChromiumSandbox(cgroup,browserPid,startTicks){
 assert.ok(/^\/sys\/fs\/cgroup\/[a-zA-Z0-9/_.@:-]+$/.test(cgroup),"SANDBOX_CGROUP");
 assert.ok(Number.isSafeInteger(browserPid)&&browserPid>0&&/^\d+$/.test(startTicks),"SANDBOX_BROWSER_ID");
 const pids=(await readFile(cgroup+"/cgroup.procs","utf8")).trim().split(/\s+/).filter(Boolean).map(Number);
 assert.ok(pids.length<=256&&pids.includes(browserPid),"SANDBOX_CGROUP_PROCESSES");
 const table=new Map();
 for(const pid of pids){try{const item=await facts(pid);table.set(pid,item);}catch{/* Missing observations never establish proof. */}}
 const browser=table.get(browserPid);assert.ok(browser&&browser.startTicks===startTicks,"SANDBOX_BROWSER_CHANGED");
 for(const renderer of table.values()){
  if(!renderer.renderer)continue;
  let parent=renderer.ppid,descendant=false;
  const seen=new Set([renderer.pid]);
  while(parent&&!seen.has(parent)){if(parent===browserPid){descendant=true;break;}seen.add(parent);parent=table.get(parent)?.ppid??0;}
  try{return validateSandboxFacts({...browser,owned:true},{...renderer,owned:true,descendant});}catch{/* Inspect other owned renderers. */}
 }
 throw Error("SANDBOX_RENDERER_NOT_PROVEN");
}
