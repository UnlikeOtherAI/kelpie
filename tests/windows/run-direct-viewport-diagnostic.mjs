import assert from "node:assert/strict";
import {spawn,execFile} from "node:child_process";
import {promisify} from "node:util";
import {createHash} from "node:crypto";
import {readFile,writeFile,mkdir,access} from "node:fs/promises";
import {dirname,join,isAbsolute} from "node:path";
import {fileURLToPath} from "node:url";
import {parseViewportDiagnostic} from "./viewport-diagnostic-sanitizer.mjs";
import {parseCaptureStage} from "./capture-stage-diagnostics.mjs";
import {captureDiagnosticStep} from "./capture-diagnostic-step.mjs";
import {downloadArtifacts} from "./capture-artifact-download.mjs";
import {startG08Fixture,g08Workflow,mapG08Scene} from "../capture/g08-fixture.mjs";

const [exe,privateRoot,evidenceRoot,manifestFile]=process.argv.slice(2);
assert.ok([exe,privateRoot,evidenceRoot,manifestFile].every(p=>p&&isAbsolute(p)));
const manifest=JSON.parse(await readFile(manifestFile,"utf8"));
const hash=async p=>createHash("sha256").update(await readFile(p)).digest("hex");
assert.equal(await hash(exe),manifest.exeSha256);
assert.equal(await hash(join(dirname(exe),"kelpie.dll")),manifest.dllSha256);
await mkdir(privateRoot,{recursive:false});await mkdir(evidenceRoot,{recursive:false});
const profile=join(privateRoot,"profile"),readinessPath=join(profile,"readiness.json");
const stageTiming=process.env.KELPIE_DIRECT_STAGE_G08==="1";
const startupOnly=process.env.KELPIE_DIRECT_STARTUP_ONLY==="1";
assert.ok(!(stageTiming&&startupOnly));
const env={...process.env,USERPROFILE:privateRoot,KELPIE_HOME:join(privateRoot,"cli-home"),KELPIE_CAPTURE_VIEWPORT_DIAGNOSTICS:"1",...(stageTiming?{KELPIE_CAPTURE_STAGE_DIAGNOSTICS:"1"}:{})};
const exec=promisify(execFile),report={source:manifest.source,stage:"launch",diagnostics:[],cleanup:"not-started"};
let pending="",child,closed,readiness,fixture,api;
if(stageTiming||startupOnly)report.steps=[];
if(stageTiming)report.captureStages=[];
function acceptLine(line){const value=parseViewportDiagnostic(line);if(value&&report.diagnostics.length<16)report.diagnostics.push(value);
 if(stageTiming){const stage=parseCaptureStage(line);if(stage&&report.captureStages.length<801)report.captureStages.push(stage);}}
try{
 const sidCode="[Security.Principal.WindowsIdentity]::GetCurrent().User.Value";
 const sid=(await exec("powershell.exe",["-NoProfile","-NonInteractive","-EncodedCommand",Buffer.from(sidCode,"utf16le").toString("base64")],{windowsHide:true,timeout:15000})).stdout.trim();
 assert.match(sid,/^S-1-[0-9-]+$/);await exec(join(process.env.WINDIR,"System32/icacls.exe"),[privateRoot,"/inheritance:r","/grant:r","*"+sid+":(OI)(CI)F","*S-1-5-18:(OI)(CI)F"],{windowsHide:true,timeout:15000});
 const started=Date.now();child=spawn(exe,["--port","28420","--profile-dir",profile],{env,windowsHide:true,stdio:["ignore","ignore","pipe"]});
 closed=new Promise((resolve,reject)=>{child.once("error",reject);child.once("close",(code,signal)=>resolve({code,signal}));});void closed.catch(()=>{});
 child.stderr.on("data",chunk=>{pending+=chunk.toString();const lines=pending.split(String.fromCharCode(10));pending=lines.pop().slice(-32768);for(const line of lines)acceptLine(line.trimEnd());});
 while(Date.now()-started<20000){
  if(child.exitCode!==null)throw new Error("OWNED_PROCESS_EXITED");
  try{readiness=JSON.parse(await readFile(readinessPath,"utf8"));break;}catch{}
  await new Promise(resolve=>setTimeout(resolve,250));
 }
 assert.ok(readiness&&readiness.controlMode==="loopback"&&readiness.port===28420&&typeof readiness.token==="string","READINESS_MISSING");
 const ps="$p=Get-Process -Id "+child.pid+";$s=Get-NetTCPConnection -State Listen -LocalPort 28420;if($s.OwningProcess -ne $p.Id){throw 'Wrong listener'};[pscustomobject]@{pid=$p.Id;path=$p.Path;session=$p.SessionId;start=$p.StartTime.ToUniversalTime().ToString('o')}|ConvertTo-Json";
 const info=JSON.parse((await exec("powershell.exe",["-NoProfile","-NonInteractive","-EncodedCommand",Buffer.from(ps,"utf16le").toString("base64")],{env,windowsHide:true,timeout:15000})).stdout);
 assert.equal(info.path.replaceAll(String.fromCharCode(92),"/").toLowerCase(),exe.replaceAll(String.fromCharCode(92),"/").toLowerCase());assert.ok(Date.parse(info.start)>=started-1000);report.identity=info;
 api=async(method,body={})=>(await fetch("http://127.0.0.1:28420/v1/"+method,{method:"POST",headers:{authorization:"Bearer "+readiness.token,"content-type":"application/json"},body:JSON.stringify(body),signal:AbortSignal.timeout(method==="play-script"?60000:10000)})).json();
 const device=await api("get-device-info");assert.equal(device.success,true);assert.equal(device.version,"0.1.16");
 report.stage="corpus";
 const tests=dirname(fileURLToPath(import.meta.url));
 if(stageTiming||startupOnly){
  const step=(name,fn)=>captureDiagnosticStep(report,name,fn);
  fixture=await step("fixture-start",()=>startG08Fixture());
  const tabId=await step("tabs",async()=>{const tabs=await api("get-tabs"),id=tabs.tabs.find(tab=>tab.active)?.id;assert.ok(id);return id;});
  await step("navigate",async()=>assert.equal((await api("navigate",{tabId,url:fixture.url})).success,true));
  await step("ready",async()=>assert.equal((await api("play-script",{version:1,tabId,actions:[{action:"wait-ready",state:"complete"}]})).success,true));
  if(startupOnly)report.casePassed=true;
  else{
   const result=await step("workflow",()=>api("play-script",g08Workflow(tabId,"c")));
   const observed=await step("events",async()=>(await fetch(new URL("/events",fixture.url),{signal:AbortSignal.timeout(3000)})).json());
   report.workflow={success:result.success===true,actionsExecuted:Number.isSafeInteger(result.actionsExecuted)?result.actionsExecuted:null,
     errorCode:/^[A-Z_]{1,64}$/.test(result.error?.code??"")?result.error.code:null,eventCount:observed.events.length,dropped:observed.dropped};
   if(result.success===true){
    mapG08Scene(observed.events);assert.equal(observed.dropped,0);assert.ok(observed.events.every(event=>event.trusted===true));
    const artifacts=[];await step("artifact-download",()=>downloadArtifacts(result,{api,output:evidenceRoot,artifacts}));
    report.artifacts=artifacts.map(({id,mimeType,byteLength,sha256,frameCount,droppedFrames})=>({id,mimeType,byteLength,sha256,frameCount,droppedFrames}));
   }
   report.casePassed=result.success===true;
  } }else try{
  const filters=process.env.KELPIE_CAPTURE_CASE_FILTERS
    ? JSON.parse(process.env.KELPIE_CAPTURE_CASE_FILTERS)
    : ["continuous GIF MP4 marker PNG semantic"];
  assert.ok(Array.isArray(filters)&&filters.length>0&&filters.length<=6);
  assert.ok(filters.every(filter=>typeof filter==="string"&&/^[A-Za-z0-9 ,_-]{1,100}$/.test(filter)));
  report.caseFilters=filters;
  for(const [index,filter] of filters.entries()){
   const output=filters.length===1?join(evidenceRoot,"native"):join(evidenceRoot,"native-"+index);
   await exec(process.execPath,[join(tests,"run-script-capture-acceptance.mjs"),readinessPath,output],
     {env:{...env,KELPIE_CAPTURE_SOURCE:manifest.source,KELPIE_CAPTURE_CASE_FILTER:filter},windowsHide:true,timeout:180000,maxBuffer:2097152});
   const caseReport=JSON.parse(await readFile(join(output,"report.json"),"utf8"));
   assert.ok(Array.isArray(caseReport.checks)&&caseReport.checks.length>0 && caseReport.checks.every(check=>check.passed===true));
   assert.equal(caseReport.cleanup,"closed");
  }
  report.casePassed=true;
 }catch(error){report.casePassed=false;report.caseExit=typeof error.code==="number"?error.code:null;}
 report.stage="close";
 const response=await api("close-browser");assert.equal(response.success,true);
 report.processExit=await Promise.race([closed,new Promise((_,reject)=>setTimeout(()=>reject(new Error("CLOSE_TIMEOUT")),12000))]);
 let present=true;try{await access(readinessPath);}catch{present=false;}report.readinessAbsent=!present;
 assert.ok(report.readinessAbsent);report.cleanup="public-close-exited";
}catch(error){
 report.failure={stage:report.stage,kind:["AssertionError","Error","TypeError","AbortError","TimeoutError"].includes(error.name)?error.name:"Other"};
 process.exitCode=1;
 if(api&&child&&child.exitCode===null){
  try{
   const close=await api("close-browser");assert.equal(close.success,true);
   report.recoveryExit=await Promise.race([closed,new Promise((_,reject)=>setTimeout(()=>reject(new Error("CLOSE_TIMEOUT")),12000))]);
   let present=true;try{await access(readinessPath);}catch{present=false;}
   report.recoveryReadinessAbsent=!present;report.cleanup="public-close-after-failure";
  }catch{report.cleanup="public-close-after-failure-unconfirmed";}
 }
}finally{
 if(fixture) await fixture.close();
 if(child&&child.exitCode===null){child.kill();try{report.forcedExit=await Promise.race([closed,new Promise((_,reject)=>setTimeout(()=>reject(new Error("EXIT_TIMEOUT")),2000))]);}catch{report.forcedExit={timedOut:true};}}
 await writeFile(join(evidenceRoot,"diagnostic.json"),JSON.stringify(report,null,2),{flag:"wx"});
}
if(!report.casePassed)process.exitCode=1;
