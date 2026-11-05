import assert from "node:assert/strict";
import {spawn,execFile} from "node:child_process";
import {promisify} from "node:util";
import {createHash} from "node:crypto";
import {readFile,writeFile,mkdir,access} from "node:fs/promises";
import {dirname,join,isAbsolute} from "node:path";
import {fileURLToPath} from "node:url";
import {parseViewportDiagnostic} from "./viewport-diagnostic-sanitizer.mjs";
import {parsePresentationTiming} from "./presentation-timing-sanitizer.mjs";
import {startG08Fixture,g08Workflow,mapG08Scene} from "../capture/g08-fixture.mjs";

const [exe,privateRoot,evidenceRoot,manifestFile]=process.argv.slice(2);
assert.ok([exe,privateRoot,evidenceRoot,manifestFile].every(p=>p&&isAbsolute(p)));
const manifest=JSON.parse(await readFile(manifestFile,"utf8"));
const hash=async p=>createHash("sha256").update(await readFile(p)).digest("hex");
assert.equal(await hash(exe),manifest.exeSha256);
assert.equal(await hash(join(dirname(exe),"kelpie.dll")),manifest.dllSha256);
await mkdir(privateRoot,{recursive:false});await mkdir(evidenceRoot,{recursive:false});
const profile=join(privateRoot,"profile"),readinessPath=join(profile,"readiness.json");
const timing=process.env.KELPIE_DIRECT_TIMING_G08==="1";
const env={...process.env,USERPROFILE:privateRoot,KELPIE_HOME:join(privateRoot,"cli-home"),KELPIE_CAPTURE_VIEWPORT_DIAGNOSTICS:"1",...(timing?{KELPIE_PRESENTATION_TIMING_DIAGNOSTICS:"1"}:{})};
const exec=promisify(execFile),report={source:manifest.source,stage:"launch",diagnostics:[],cleanup:"not-started"};
let pending="",child,closed,readiness,fixture;
if(timing) report.presentationTiming=[];
function acceptLine(line){const value=parseViewportDiagnostic(line);if(value&&report.diagnostics.length<16)report.diagnostics.push(value);
 if(timing){const fact=parsePresentationTiming(line);if(fact&&report.presentationTiming.length<1602)report.presentationTiming.push(fact);}}
try{
 const sidCode="[Security.Principal.WindowsIdentity]::GetCurrent().User.Value";
 const sid=(await exec("powershell.exe",["-NoProfile","-NonInteractive","-EncodedCommand",Buffer.from(sidCode,"utf16le").toString("base64")],{windowsHide:true,timeout:15000})).stdout.trim();
 assert.match(sid,/^S-1-[0-9-]+$/);await exec(join(process.env.WINDIR,"System32/icacls.exe"),[privateRoot,"/inheritance:r","/grant:r","*"+sid+":(OI)(CI)F","*S-1-5-18:(OI)(CI)F"],{windowsHide:true,timeout:15000});
 const started=Date.now();child=spawn(exe,["--port","28420","--profile-dir",profile],{env,windowsHide:true,stdio:["ignore","ignore","pipe"]});
 closed=new Promise((resolve,reject)=>{child.once("error",reject);child.once("close",(code,signal)=>resolve({code,signal}));});void closed.catch(()=>{});
 child.stderr.on("data",chunk=>{pending=(pending+chunk.toString()).slice(-32768);const lines=pending.split(String.fromCharCode(10));pending=lines.pop();for(const line of lines)acceptLine(line.trimEnd());});
 while(Date.now()-started<20000){
  if(child.exitCode!==null)throw new Error("OWNED_PROCESS_EXITED");
  try{readiness=JSON.parse(await readFile(readinessPath,"utf8"));break;}catch{}
  await new Promise(resolve=>setTimeout(resolve,250));
 }
 assert.ok(readiness&&readiness.controlMode==="loopback"&&readiness.port===28420&&typeof readiness.token==="string","READINESS_MISSING");
 const ps="$p=Get-Process -Id "+child.pid+";$s=Get-NetTCPConnection -State Listen -LocalPort 28420;if($s.OwningProcess -ne $p.Id){throw 'Wrong listener'};[pscustomobject]@{pid=$p.Id;path=$p.Path;session=$p.SessionId;start=$p.StartTime.ToUniversalTime().ToString('o')}|ConvertTo-Json";
 const info=JSON.parse((await exec("powershell.exe",["-NoProfile","-NonInteractive","-EncodedCommand",Buffer.from(ps,"utf16le").toString("base64")],{env,windowsHide:true,timeout:15000})).stdout);
 assert.equal(info.path.replaceAll(String.fromCharCode(92),"/").toLowerCase(),exe.replaceAll(String.fromCharCode(92),"/").toLowerCase());assert.ok(Date.parse(info.start)>=started-1000);report.identity=info;
 const api=async(method,body={})=>(await fetch("http://127.0.0.1:28420/v1/"+method,{method:"POST",headers:{authorization:"Bearer "+readiness.token,"content-type":"application/json"},body:JSON.stringify(body),signal:AbortSignal.timeout(method==="play-script"?60000:10000)})).json();
 const device=await api("get-device-info");assert.equal(device.success,true);assert.equal(device.version,"0.1.16");
 report.stage="corpus";
 const tests=dirname(fileURLToPath(import.meta.url));
 if(timing){
  fixture=await startG08Fixture();
  const tabs=await api("get-tabs"),tabId=tabs.tabs.find(tab=>tab.active)?.id;assert.ok(tabId);
  assert.equal((await api("navigate",{tabId,url:fixture.url})).success,true);
  assert.equal((await api("play-script",{version:1,tabId,actions:[{action:"wait-ready",state:"complete"}]})).success,true);
  const result=await api("play-script",g08Workflow(tabId,"c"));
  const observed=await (await fetch(new URL("/events",fixture.url))).json();
  report.workflow={success:result.success===true,actionCount:Array.isArray(result.actions)?result.actions.length:null,
    eventCount:observed.events.length,dropped:observed.dropped};
  if(result.success===true){mapG08Scene(observed.events);assert.equal(observed.dropped,0);
   assert.ok(observed.events.every(event=>event.trusted===true));}
  report.casePassed=result.success===true;
 }else try{
  await exec(process.execPath,[join(tests,"run-script-capture-acceptance.mjs"),readinessPath,join(evidenceRoot,"native")],
    {env:{...env,KELPIE_CAPTURE_SOURCE:manifest.source,KELPIE_CAPTURE_CASE_FILTER:"continuous GIF MP4 marker PNG semantic"},windowsHide:true,timeout:180000,maxBuffer:2097152});
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
}finally{
 if(fixture) await fixture.close();
 if(child&&child.exitCode===null){child.kill();try{report.forcedExit=await Promise.race([closed,new Promise((_,reject)=>setTimeout(()=>reject(new Error("EXIT_TIMEOUT")),2000))]);}catch{report.forcedExit={timedOut:true};}}
 await writeFile(join(evidenceRoot,"diagnostic.json"),JSON.stringify(report,null,2),{flag:"wx"});
}
if(!report.casePassed)process.exitCode=1;
