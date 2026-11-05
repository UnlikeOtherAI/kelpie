import assert from "node:assert/strict";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {createHash} from "node:crypto";
import {access,mkdir,readFile,writeFile} from "node:fs/promises";
import {join,dirname,isAbsolute} from "node:path";
import {waitForOwnedExit} from "./wait-for-owned-exit.mjs";
import {safeCliFailure} from "./safe-cli-failure.mjs";

const [exe,cli,privateRoot,reportPath,manifestPath]=process.argv.slice(2);
assert.ok([exe,cli,privateRoot,reportPath,manifestPath].every(p=>p&&isAbsolute(p)));
const manifest=JSON.parse(await readFile(manifestPath,"utf8"));
const hash=async p=>createHash("sha256").update(await readFile(p)).digest("hex");
assert.equal(await hash(exe),manifest.exeSha256);assert.equal(await hash(join(dirname(exe),"kelpie.dll")),manifest.dllSha256);
assert.equal(await hash(cli),manifest.cliSha256);await mkdir(privateRoot,{recursive:false});
const exec=promisify(execFile);
const sidCommand="[Security.Principal.WindowsIdentity]::GetCurrent().User.Value";
const sid=(await exec("powershell.exe",["-NoProfile","-NonInteractive","-EncodedCommand",Buffer.from(sidCommand,"utf16le").toString("base64")],{windowsHide:true,timeout:15000})).stdout.trim();
assert.match(sid,/^S-1-[0-9-]+$/);
await exec(join(process.env.WINDIR,"System32/icacls.exe"),[privateRoot,"/inheritance:r","/grant:r","*"+sid+":(OI)(CI)F","*S-1-5-18:(OI)(CI)F"],{windowsHide:true,timeout:15000});
const home=join(privateRoot,"cli-home"),profile=join(privateRoot,"profile");await mkdir(home);
const env={...process.env,USERPROFILE:privateRoot,KELPIE_HOME:home,NODE_OPTIONS:"--max-old-space-size=2048"};
const alias="capture-launch-diagnostic-"+manifest.source.slice(0,8);
const report={source:manifest.source,stage:"register",checks:[],cleanup:"not-started"};
const summarize = error => safeCliFailure(error);
async function run(args,timeout){
 const started=Date.now();
 try{const result=await exec(process.execPath,[cli,...args],{env,windowsHide:true,timeout,maxBuffer:2097152});
  const value=JSON.parse(result.stdout);return {ok:true,elapsedMs:Date.now()-started,value};}
 catch(error){return {ok:false,elapsedMs:Date.now()-started,...summarize(error)};}
}
try{
 let result=await run(["browser","register",alias,"--platform","windows","--app-path",exe,"--profile-dir",profile],30000);
 report.checks.push({stage:"register",...result,value:undefined});assert.ok(result.ok);
 report.stage="launch";result=await run(["browser","launch",alias,"--hidden","--port","28420"],45000);
 report.checks.push({stage:"launch",...result,value:undefined});
 if(result.ok){
  const store=JSON.parse(await readFile(join(home,"browsers.json"),"utf8")),running=store.running[alias];
  assert.ok(running?.pid&&running.readinessFile&&running.launchId);
  const ps="$ErrorActionPreference='Stop';$p=Get-Process -Id "+running.pid+";$s=Get-NetTCPConnection -State Listen -LocalPort 28420;if($s.OwningProcess -ne $p.Id){throw 'Wrong listener'};[pscustomobject]@{pid=$p.Id;path=$p.Path;startTime=$p.StartTime.ToUniversalTime().ToString('o');sessionId=$p.SessionId}|ConvertTo-Json";
  const encoded=Buffer.from(ps,"utf16le").toString("base64");
  const info=JSON.parse((await exec("powershell.exe",["-NoProfile","-NonInteractive","-EncodedCommand",encoded],{env,windowsHide:true,timeout:15000})).stdout);
  assert.equal(info.path.replaceAll("\\","/").toLowerCase(),exe.replaceAll("\\","/").toLowerCase());
  report.identity=info;report.stage="stop";
  const stopped=await run(["browser","stop",alias],30000);
  report.checks.push({stage:"stop",...stopped,value:undefined});
  if(!stopped.ok){
   report.cleanupObservations=[];
   for(const delayMs of [0,5000,10000]){
    if(delayMs)await new Promise(done=>setTimeout(done,5000));
    let readinessPresent=true;try{await access(running.readinessFile);}catch{readinessPresent=false;}
    const probe="$p=Get-Process -Id "+info.pid+" -ErrorAction SilentlyContinue;$s=Get-NetTCPConnection -State Listen -LocalPort 28420 -ErrorAction SilentlyContinue;[pscustomobject]@{processPresent=($null -ne $p);listenerOwned=($null -ne $s -and $s.OwningProcess -eq "+info.pid+")}|ConvertTo-Json";
    const probeEncoded=Buffer.from(probe,"utf16le").toString("base64");
    const observed=JSON.parse((await exec("powershell.exe",["-NoProfile","-NonInteractive","-EncodedCommand",probeEncoded],{env,windowsHide:true,timeout:15000})).stdout);
    report.cleanupObservations.push({delayMs,readinessPresent,...observed});
   }
   report.cleanup="public-stop-failed";process.exitCode=1;
  }else{
  report.processExit=await waitForOwnedExit({pid:info.pid,executable:exe,startTime:info.startTime});
  assert.equal(report.processExit.exited,true);report.cleanup="public-cli-closed";
  }
 }else{
  const stored=JSON.parse(await readFile(join(home,"browsers.json"),"utf8")),pending=stored.running[alias];
  report.pending={present:Boolean(pending?.pendingLaunch),pid:Number.isSafeInteger(pending?.pid)?pending.pid:null};
  report.cleanup="launch-failed";process.exitCode=1;
 }
}catch(error){report.failure={stage:report.stage,...summarize(error)};process.exitCode=1;}
finally{await writeFile(reportPath,JSON.stringify(report,null,2),{flag:"wx"});}
