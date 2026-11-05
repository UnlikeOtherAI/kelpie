import assert from "node:assert/strict";
import {waitForOwnedExit} from "./wait-for-owned-exit.mjs";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {readFile,writeFile,mkdir,access} from "node:fs/promises";
import {createHash} from "node:crypto";
import {dirname,join,isAbsolute} from "node:path";
import {fileURLToPath} from "node:url";
const [exe,cli,privateRoot,evidenceRoot,manifestFile,mode="full"]=process.argv.slice(2);
assert.ok([exe,cli,privateRoot,evidenceRoot,manifestFile].every(value=>value&&isAbsolute(value)));
assert.ok(mode==="motion"||mode==="g08"||mode==="alias-only"||mode==="edit-diagnostic"||mode==="edit-regression"||mode==="full"||mode==="fixture"||(mode==="privacy-focus"||mode==="privacy-regression"));
const execute=promisify(execFile),tests=dirname(fileURLToPath(import.meta.url));
const manifest=JSON.parse(await readFile(manifestFile,"utf8"));
for(const key of ["exeSha256","dllSha256","cliSha256"])assert.match(manifest[key],/^[a-f0-9]{64}$/);
assert.match(manifest.source,/^[a-f0-9]{40}$/);
const hash=async path=>createHash("sha256").update(await readFile(path)).digest("hex");
assert.equal(await hash(exe),manifest.exeSha256);
assert.equal(await hash(join(dirname(exe),"kelpie.dll")),manifest.dllSha256);
assert.equal(await hash(cli),manifest.cliSha256);
await mkdir(privateRoot,{recursive:false});await mkdir(evidenceRoot,{recursive:false});
const cliHome=join(privateRoot,"cli-home"),profile=join(privateRoot,"profile"),alias="capture-api-"+manifest.source.slice(0,8);
await mkdir(cliHome);
const env={...process.env,USERPROFILE:privateRoot,KELPIE_HOME:cliHome,NODE_OPTIONS:"--max-old-space-size=2048"};
const run=(command,args,timeout=30000)=>execute(command,args,{env,windowsHide:true,timeout,maxBuffer:2097152});
const publicCli=async args=>JSON.parse((await run(process.execPath,[cli,...args],args[1]==="launch"?30000:20000)).stdout);
const ps=async code=>{
 const encoded=Buffer.from(code,"utf16le").toString("base64");
 return JSON.parse((await run(join(process.env.WINDIR,"System32/WindowsPowerShell/v1.0/powershell.exe"),
  ["-NoProfile","-NonInteractive","-OutputFormat","Text","-EncodedCommand",encoded])).stdout.replace(/^\uFEFF/,""));
};
let launched=false,readinessFile,running;
const report={nativeSource:manifest.source,manifest,checks:[],cleanup:"not-started"};
async function childCase(name,file,args,extraEnv={}){
 try{
  const result=await execute(process.execPath,[join(tests,file),...args],
   {env:{...env,...extraEnv},windowsHide:true,timeout:600000,maxBuffer:2097152});
  report.checks.push({name,passed:true,summary:result.stdout.trim()});
 }catch(error){
  report.checks.push({name,passed:false,exitCode:error.code,summary:String(error.stdout??"").slice(0,8192)});
  process.exitCode=1;
 }
}
try{
 const preflight=await ps("$ErrorActionPreference='Stop';$o=Get-CimInstance Win32_OperatingSystem;$free=$o.FreePhysicalMemory/1MB;if($free -lt 10){throw 'Below10GiB'};if(Get-NetTCPConnection -LocalPort 28420 -State Listen -ErrorAction SilentlyContinue){throw 'Port occupied'};[pscustomobject]@{sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;freeGiB=[math]::Round($free,2)}|ConvertTo-Json");
 await run(join(process.env.WINDIR,"System32/icacls.exe"),[privateRoot,"/inheritance:r","/grant:r",
  "*"+preflight.sid+":(OI)(CI)F","*S-1-5-18:(OI)(CI)F"]);
 report.freeGiB=preflight.freeGiB;
 await publicCli(["browser","register",alias,"--platform","windows","--app-path",exe,"--profile-dir",profile]);
 const started=new Date().toISOString();
 launched=true;assert.equal((await publicCli(["browser","launch",alias,"--hidden","--port","28420"])).success,true);
 const store=JSON.parse(await readFile(join(cliHome,"browsers.json"),"utf8"));running=store.running[alias];
 assert.equal(running.port,28420);readinessFile=running.readinessFile;
 const readiness=JSON.parse(await readFile(readinessFile,"utf8"));
 assert.equal(readiness.launchId,running.launchId);
 const pinned=await ps("$ErrorActionPreference='Stop';$p=Get-Process -Id "+running.pid+";$s=Get-NetTCPConnection -State Listen -LocalPort 28420;if($s.OwningProcess -ne $p.Id){throw 'Wrong listener'};[pscustomobject]@{pid=$p.Id;path=$p.Path;startTime=$p.StartTime.ToUniversalTime().ToString('o');sessionId=$p.SessionId}|ConvertTo-Json");
 assert.equal(pinned.path.replaceAll("\\","/").toLowerCase(),exe.replaceAll("\\","/").toLowerCase());
 assert.ok(Date.parse(pinned.startTime)>=Date.parse(started)-1000);
 report.identity={...pinned,source:manifest.source,launchId:readiness.launchId,port:28420,hashes:manifest};
 const nativeInfo=await (await fetch("http://127.0.0.1:28420/v1/get-device-info",{method:"POST",headers:{authorization:"Bearer "+readiness.token,"content-type":"application/json"},body:"{}",signal:AbortSignal.timeout(10000)})).json();
 const cmakeSource=(await run("git",["show",manifest.source+":apps/windows/CMakeLists.txt"])).stdout;
 const expectedVersion=/project\(kelpie_windows VERSION ([0-9.]+)/.exec(cmakeSource)?.[1];
 assert.ok(expectedVersion);assert.equal(nativeInfo.version,expectedVersion);report.nativeVersion=nativeInfo.version;
 const identityFile=join(evidenceRoot,"identity.json");await writeFile(identityFile,JSON.stringify(report.identity,null,2));
 if(mode==="motion"){
  await childCase("native clipped geometry and motion media","run-geometry-media-acceptance.mjs",[readinessFile,join(evidenceRoot,"geometry"),"motion"],{KELPIE_CAPTURE_SOURCE:manifest.source});
 }else if(mode==="g08"){
  await childCase("shared G08 fixture through Windows HTTP", "run-g08-acceptance.mjs", [readinessFile,join(evidenceRoot,"g08"),identityFile]);
 }else if(mode==="alias-only"){
  await childCase("public alias CLI and stdio MCP","run-alias-cli-acceptance.mjs",[cli,alias,cliHome,readinessFile,join(evidenceRoot,"alias")],{KELPIE_CAPTURE_SOURCE:manifest.source});
 }else if(mode==="edit-diagnostic" || mode==="edit-regression"){
  await childCase("post-edit privacy and focus viewport diagnostic","probe-post-edit-sensitivity.mjs",[readinessFile,join(evidenceRoot,"post-edit.json"),mode==="edit-regression"?"expect-fixed":"diagnostic"],{KELPIE_CAPTURE_SOURCE:manifest.source});
 }else if(mode==="privacy-focus" || mode==="privacy-regression"){
  await childCase("late sensitivity focus diagnostic","probe-sensitive-focus.mjs",[readinessFile,join(evidenceRoot,"privacy-focus.json"),mode==="privacy-regression"?"expect-refused":"diagnostic"],{KELPIE_CAPTURE_SOURCE:manifest.source});
 }else if(mode==="fixture"){
  await childCase("native fixture preparation diagnosis","probe-script-fixture.mjs",[readinessFile,join(evidenceRoot,"fixture.json")]);
 }else{
 await childCase("native full script capture corpus","run-script-capture-acceptance.mjs",
  [readinessFile,join(evidenceRoot,"native")],{KELPIE_CAPTURE_SOURCE:manifest.source});
 await childCase("canonical observations/extraction/readiness","run-observation-acceptance.mjs",
  [readinessFile,join(evidenceRoot,"observations.json")],{KELPIE_CAPTURE_SOURCE:manifest.source});
 await childCase("public alias CLI and stdio MCP","run-alias-cli-acceptance.mjs",
  [cli,alias,cliHome,readinessFile,join(evidenceRoot,"alias")],{KELPIE_CAPTURE_SOURCE:manifest.source});
 await childCase("three artifact protocols","run-artifact-protocol-acceptance.mjs",
  [readinessFile,identityFile,join(evidenceRoot,"protocols")]);
 for(const [name,file,output,expectation] of [
  ["focus privacy regression","probe-sensitive-focus.mjs","privacy-focus.json","expect-refused"],
  ["post-input privacy and viewport regression","probe-post-edit-sensitivity.mjs","post-edit.json","expect-fixed"],
  ["realm retirement privacy","probe-sensitive-realm.mjs","realm.json"],
  ["active artifact publication across three protocols","probe-active-artifact-publication.mjs","publication.json"]
 ])await childCase(name,file,[readinessFile,join(evidenceRoot,output),...(expectation?[expectation]:[])],{KELPIE_CAPTURE_SOURCE:manifest.source});
 }
}catch(error){
 report.checks.push({name:"owned API flow",passed:false,error:error.message,code:error.code??null,signal:error.signal??null,killed:error.killed??false});process.exitCode=1;
}finally{
 await writeFile(join(evidenceRoot,"flow-report.json"),JSON.stringify(report,null,2));
 if(launched){
  try{assert.equal((await publicCli(["browser","stop",alias])).success,true);
   if(report.identity){report.processExit=await waitForOwnedExit({pid:running.pid,executable:exe,startTime:report.identity.startTime});assert.equal(report.processExit.exited,true);}
   report.cleanup="public-cli-closed";}
  catch(error){report.cleanup="failed";report.checks.push({name:"public close",passed:false,error:error.message,code:error.code??null,signal:error.signal??null,killed:error.killed??false});process.exitCode=1;}
 }
 if(running){
  const finalStore=JSON.parse(await readFile(join(cliHome,"browsers.json"),"utf8"));
  try{await access(readinessFile);report.readinessAbsent=false;}catch{report.readinessAbsent=true;}
  report.aliasRunningAbsent=!finalStore.running[alias];
  const cleanup=await ps("$p=Get-Process -Id "+running.pid+" -ErrorAction SilentlyContinue;$s=Get-NetTCPConnection -State Listen -LocalPort 28420 -ErrorAction SilentlyContinue;[pscustomobject]@{processAbsent=($null -eq $p);socketAbsent=($null -eq $s)}|ConvertTo-Json");
  report.cleanupProof=cleanup;
  if(!Object.values(cleanup).every(Boolean)||!report.readinessAbsent||!report.aliasRunningAbsent)process.exitCode=1;
 }
 await writeFile(join(evidenceRoot,"flow-report.json"),JSON.stringify(report,null,2));
}
console.log(JSON.stringify({checks:report.checks,cleanup:report.cleanup}));
