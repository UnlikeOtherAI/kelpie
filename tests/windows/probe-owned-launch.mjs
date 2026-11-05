import assert from "node:assert/strict";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {createHash} from "node:crypto";
import {mkdir,readFile,writeFile} from "node:fs/promises";
import {join,dirname,isAbsolute} from "node:path";
import {waitForOwnedExit} from "./wait-for-owned-exit.mjs";

const [exe,cli,privateRoot,reportPath,manifestPath]=process.argv.slice(2);
assert.ok([exe,cli,privateRoot,reportPath,manifestPath].every(p=>p&&isAbsolute(p)));
const manifest=JSON.parse(await readFile(manifestPath,"utf8"));
const hash=async p=>createHash("sha256").update(await readFile(p)).digest("hex");
assert.equal(await hash(exe),manifest.exeSha256);assert.equal(await hash(join(dirname(exe),"kelpie.dll")),manifest.dllSha256);
assert.equal(await hash(cli),manifest.cliSha256);await mkdir(privateRoot,{recursive:false});
const home=join(privateRoot,"cli-home"),profile=join(privateRoot,"profile");await mkdir(home);
const env={...process.env,USERPROFILE:privateRoot,KELPIE_HOME:home,NODE_OPTIONS:"--max-old-space-size=2048"};
const exec=promisify(execFile),alias="capture-launch-diagnostic-"+manifest.source.slice(0,8);
const report={source:manifest.source,stage:"register",checks:[],cleanup:"not-started"};
function summarize(error){
 let data;try{data=JSON.parse(String(error.stdout??""));}catch{}
 const message=String(data?.error?.message??"");
 const category=message==="Kelpie did not publish a valid local readiness file"?"readiness-timeout":
  /^Kelpie exited before publishing readiness \(exit -?\d+\)$/.test(message)?"exited-before-readiness":
  /^Kelpie failed to start:/.test(message)?"spawn-failed":
  message==="A live browser already owns this profile; attach to its alias or stop it first"?"profile-owned":
  data?.error?"other-cli-error":"no-cli-error-json";
 return {code:typeof error.code==="number"?error.code:null,signal:error.signal??null,killed:error.killed??false,
  cliErrorCode:typeof data?.error?.code==="string"&&/^[A-Z_]+$/.test(data.error.code)?data.error.code:null,category};
}
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
  report.checks.push({stage:"stop",...stopped,value:undefined});assert.ok(stopped.ok);
  report.processExit=await waitForOwnedExit({pid:info.pid,executable:exe,startTime:info.startTime});
  assert.equal(report.processExit.exited,true);report.cleanup="public-cli-closed";
 }else{report.cleanup="launch-failed";process.exitCode=1;}
}catch(error){report.failure={stage:report.stage,...summarize(error)};process.exitCode=1;}
finally{await writeFile(reportPath,JSON.stringify(report,null,2),{flag:"wx"});}
