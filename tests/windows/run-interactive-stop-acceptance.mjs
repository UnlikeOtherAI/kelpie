import assert from "node:assert/strict";
import {readFile,writeFile,mkdir} from "node:fs/promises";
import {createHash,randomUUID} from "node:crypto";
import {nativeWindowFixtureExpression} from "./native-window-fixture.mjs";
import {waitForOwnedExit} from "./wait-for-owned-exit.mjs";
import {safeCliFailure} from "./safe-cli-failure.mjs";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {fileURLToPath} from "node:url";
import {observeInFlight,awaitBounded} from "./interactive-stop-lifecycle.mjs";
import {nativeMarkerVerified} from "./native-window-evidence.mjs";
import {finishNativeWindowEvidence} from "./native-window-completion.mjs";
import {dirname,join,resolve,isAbsolute} from "node:path";
import {scriptArtifactSchema,scriptArtifactChunkSchema,scriptStatusV1Schema} from "../../packages/shared/dist/index.js";
const [exe,cli,uia,outputRoot,privateRoot,mode="stop",wgcHelper,markerValidator,identityManifest]=process.argv.slice(2);
assert.ok(mode==="stop"||mode==="capture"||mode==="wgc");
if(!privateRoot||![exe,cli,uia,outputRoot,privateRoot].every(isAbsolute))throw Error("Provide absolute candidate, CLI, UIA client, evidence and private roots");
if(mode==="wgc")assert.ok(wgcHelper&&markerValidator&&identityManifest&&[wgcHelper,markerValidator,identityManifest].every(isAbsolute));
const baseline={source:"9333ff507ec91d06d86e338b1d2d9378daca2ac5",
  exeSha256:"54c8be31e003853947182c9461755bf4e7be5f91a2c64fcfb97ed5da1a32d755",
  dllSha256:"27a474291206310a64e17cce27f6f9c50836af55b997b275d5f31e0fc71bca8c",
  cliSha256:"831dd89b45aa3186efb8978d3da6ff7e9d8ec7f832ca7519bc152c0dc58e71dd"};
let build=baseline,manifestHash;
if(identityManifest){
  assert.ok(isAbsolute(identityManifest));
  const bytes=await readFile(identityManifest);assert.ok(bytes.length<=16384);
  build=JSON.parse(bytes.toString("utf8"));assert.deepEqual(Object.keys(build).sort(),Object.keys(baseline).sort());
  assert.match(build.source,/^[a-f0-9]{40}$/);
  for(const key of ["exeSha256","dllSha256","cliSha256"])assert.match(build[key],/^[a-f0-9]{64}$/);
  manifestHash=createHash("sha256").update(bytes).digest("hex");
}
const output=resolve(outputRoot),home=resolve(privateRoot),alias="capture-uia-session1-"+build.source.slice(0,8);
const cliHome=join(home,"cli-home"),profile=join(home,"profile");
const execute=promisify(execFile),deadline=new AbortController();
const timer=setTimeout(()=>deadline.abort(),120000);timer.unref();
const report={source:build.source,buildIdentity:build,buildIdentityManifestSha256:manifestHash,checks:[],cleanup:"not-started",invocation:"standard Microsoft UIA InvokePattern; no physical input"};
let launched=false,readiness,pending,running,wgcCaptureDirectory,wgcSceneFile,outputCreated=false;
const child=async(command,args,extra={})=>execute(command,args,{windowsHide:true,timeout:15000,maxBuffer:2097152,...extra});
const publicCli=async args=>{try{return JSON.parse((await child(process.execPath,[cli,...args],{timeout:args[1]==="launch"?30000:20000,env:{...process.env,USERPROFILE:home,KELPIE_HOME:cliHome}})).stdout);}catch(error){error.safeDetails=safeCliFailure(error);throw error;}};
const automation=async args=>JSON.parse((await child(uia,args,{signal:deadline.signal,timeout:10000})).stdout);
const api=async(method,body={},cleanup=false)=>{
 const response=await fetch("http://127.0.0.1:28420/v1/"+method,{method:"POST",
  headers:{authorization:"Bearer "+readiness.token,"content-type":"application/json"},body:JSON.stringify(body),
  signal:cleanup?AbortSignal.timeout(5000):AbortSignal.any([deadline.signal,AbortSignal.timeout(method==="play-script"?60000:10000)])});
 return {status:response.status,value:await response.json()};
};
const save=()=>outputCreated?writeFile(join(output,"report.json"),JSON.stringify(report,null,2)):Promise.resolve();
try {
 await mkdir(output,{recursive:false});outputCreated=true;await mkdir(home,{recursive:false});await mkdir(cliHome);
 const session=await automation(["session"]);assert.equal(session.sessionId,1);
 assert.equal(session.user.toLowerCase(),"maxis\\ondre");report.testSession=session;
 await child(join(process.env.WINDIR,"System32","icacls.exe"),[home,"/inheritance:r","/grant:r","*"+session.userSid+":(OI)(CI)F","*S-1-5-18:(OI)(CI)F"]);
 const hash=async file=>createHash("sha256").update(await readFile(file)).digest("hex");
 const testFile=fileURLToPath(import.meta.url),repo=fileURLToPath(new URL("../../",import.meta.url));
 report.testSourceRevision=(await child("git.exe",["-C",repo,"rev-parse","HEAD"])).stdout.trim();
 assert.match(report.testSourceRevision,/^[a-f0-9]{40}$/);
 report.hashes={exe:await hash(exe),dll:await hash(join(dirname(exe),"kelpie.dll")),cliEntry:await hash(cli),uiaClient:await hash(uia),testAction:await hash(testFile),uiaSource:await hash(join(dirname(testFile),"ScriptStopAutomation.cs"))};
 if(mode==="wgc")report.hashes={...report.hashes,wgcHelper:await hash(wgcHelper),markerValidator:await hash(markerValidator)};
 report.cliSource="e71364364db94a6212f556aa7b5ca9efb09ac003";
 assert.equal(report.hashes.cliEntry,build.cliSha256);
 assert.equal(await hash(exe),build.exeSha256);
 assert.equal(await hash(join(dirname(exe),"kelpie.dll")),build.dllSha256);
 report.phase="cli-register";await publicCli(["browser","register",alias,"--platform","windows","--app-path",exe,"--profile-dir",profile]);
 report.phase="cli-launch";const launchStarted=new Date().toISOString();
 const launch=await publicCli(["browser","launch",alias,"--port","28420"]);assert.equal(launch.success,true);launched=true;
 report.phase="cli-running-store";const store=JSON.parse(await readFile(join(cliHome,"browsers.json"),"utf8"));running=store.running[alias];
 assert.equal(running.port,28420);assert.equal(resolve(running.readinessFile),join(profile,"readiness.json"));
 report.phase="readiness-match";readiness=JSON.parse(await readFile(running.readinessFile,"utf8"));assert.equal(readiness.launchId,running.launchId);
 report.phase="uia-process-pin";const identity=await automation(["pin",String(running.pid),exe,launchStarted]);report.identity={...identity,launchId:readiness.launchId,port:28420};
 report.phase="listener-identity";const sockets=(await child(join(process.env.WINDIR,"System32","netstat.exe"),["-ano","-p","tcp"])).stdout.split(/\r?\n/)
   .map(line=>line.trim().split(/\s+/)).filter(parts=>parts[1]==="127.0.0.1:28420"&&parts[3]==="LISTENING");
 assert.ok(sockets.length>0);assert.ok(sockets.every(parts=>Number(parts[4])===running.pid));
 report.phase="device-info";assert.equal((await api("get-device-info")).value.success,true);
 report.identity={...identity,launchId:readiness.launchId,port:28420};
 report.phase="fixture-navigation";
 assert.equal((await api("navigate",{url:"about:blank"})).value.success,true,"FIXTURE_NAVIGATION_FAILED");
 const tabs=(await api("get-tabs")).value;const tabId=tabs.tabs.find(tab=>tab.active).id;

 if(mode!=="stop"){
   report.phase="fixture-preparation";
   const prepared=(await api("evaluate",{tabId,expression:nativeWindowFixtureExpression(randomUUID())})).value;
   assert.equal(prepared.success,true,"FIXTURE_PREPARATION_FAILED:"+prepared.error?.code);report.scene={...prepared.result,radius:24};
 }
 report.phase="script-start";
 const actions=[{action:"commentary",text:"Stop accessibility acceptance",durationMs:30000}];
 if(mode!=="stop")actions.push({action:"click",target:{role:"button",name:"Capture target",exact:true}});
 actions.push({action:"wait",ms:30000});
 const tapOptions={color:"#FF0000",radius:24,durationMs:5000,wobble:mode!=="wgc",fade:mode!=="wgc"};
 if(mode==="wgc")report.spatialCase={purpose:"native spatial/Stop evidence only; animation has separate exported timeline evidence",tapIndicator:tapOptions};
 pending=observeInFlight(api("play-script",{version:1,tabId,actions,
   ...(mode!=="stop"?{pointer:{enabled:true,curve:"c",durationMs:1200,easing:"ease-in-out"},tapIndicator:tapOptions}:{}),
   capture:{formats:["gif","video","screenshots"],fps:10,maxWidth:640,maxBytes:8388608,maxDurationMs:60000}}));
 let status,provider;
 for(let attempt=0;attempt<50;attempt++){
   status=scriptStatusV1Schema.parse((await api("get-script-status")).value);
   if(status.playing){
     provider=await automation(["inspect",String(running.pid),exe,identity.startTime]);
     if(provider.visibleInvokableButtons===1&&(mode==="stop"||status.actionIndex===2))break;
   }
   await new Promise(done=>setTimeout(done,100));
 }
 assert.equal(status.playing,true);assert.equal(provider?.visibleInvokableButtons,1);
 if(mode!=="wgc")await new Promise(done=>setTimeout(done,700));
 const current=scriptStatusV1Schema.parse((await api("get-script-status")).value);
 assert.equal(current.runId,status.runId);assert.equal(current.playing,true);
 report.beforeInvoke={status:current,provider};await save();
 if(mode==="capture"){
   report.nativeWindowCapture=await automation(["capture",String(running.pid),exe,identity.startTime,join(output,"native-window-capture")]);
   const images=report.nativeWindowCapture.captured;
   report.nativeWindowPixels={stop:images.some(image=>image.className==="KelpieScriptStop"&&image.status==="pixels-captured"),marker:nativeMarkerVerified(images)};
   await save();
 }

 if(mode==="wgc"){
   const refused=(await api("evaluate",{tabId,expression:"true"})).value;
   report.ownershipGate={success:refused.success,errorCode:refused.error?.code};
   assert.equal(refused.success,false);assert.equal(refused.error?.code,"BUSY");
   const windows=provider.ownedWindows.filter(window=>window.className==="KelpieScriptPresentation"&&!window.offscreen);
   assert.equal(windows.length,1);const window=windows[0];assert.equal(window.processId,running.pid);
   const scene={...report.scene,processId:running.pid,startFileTime:identity.startFileTime,windowHandle:window.windowHandle};
   wgcSceneFile=join(output,"native-window-scene.json");await writeFile(wgcSceneFile,JSON.stringify(scene,null,2),{flag:"wx"});
   report.nativeStopCapture=await automation(["capture-stop",String(running.pid),exe,identity.startTime,join(output,"native-stop-window")]);
   wgcCaptureDirectory=join(output,"wgc-native-window");
   report.phase="native-wgc-capture";
   const captureBegan=performance.now();report.captureTiming={requestedAt:new Date().toISOString(),workflowElapsedMs:current.elapsedMs};
   try {
   report.wgc=JSON.parse((await child(wgcHelper,[String(running.pid),exe,identity.startFileTime,window.windowHandle,wgcCaptureDirectory],
     {signal:deadline.signal,timeout:10000})).stdout);
   assert.equal(report.wgc.className,"KelpieScriptPresentation");assert.equal(report.wgc.processId,running.pid);
   assert.equal(report.wgc.windowHandle,window.windowHandle);
   }catch(error){report.wgcFailure={error:error.message,code:error.code??null,signal:error.signal??null,killed:error.killed??false,stderr:String(error.stderr??"").slice(0,8192)};}
   finally{report.captureTiming.completedAt=new Date().toISOString();report.captureTiming.durationMs=performance.now()-captureBegan;}
   await save();
 }
 report.invoked=await automation(["invoke",String(running.pid),exe,identity.startTime]);
 assert.equal(report.invoked.invoked,true);
 let result;
 if(mode==="wgc"){
   report.phase="terminal-evidence";
   try {
   const evidence=await finishNativeWindowEvidence({stopInvoked:report.invoked.invoked,scene:report.scene,
     completion:pending.then(value=>{report.playResult=value.value;return value.value;}),
     readStatus:async runId=>scriptStatusV1Schema.parse((await api("get-script-status",{runId})).value),
     readClick:async()=>(await api("evaluate",{tabId,expression:"window.__nativeCaptureClick"})).value,
     validate:async()=>{
       if(report.wgcFailure)return {className:"KelpieScriptPresentation",status:"capture-failed"};
       return JSON.parse((await child(markerValidator,[join(wgcCaptureDirectory,"metadata.json"),wgcSceneFile],
         {signal:deadline.signal,timeout:10000})).stdout);
     }});

   result=evidence.result;report.scene.click=evidence.event;
   report.nativeWindowCapture={captured:[...report.nativeStopCapture.captured,evidence.validated]};
   report.nativeWindowPixels={stop:report.nativeStopCapture.captured.some(image=>image.className==="KelpieScriptStop"&&image.status==="pixels-captured"),
     marker:nativeMarkerVerified([evidence.validated])};await save();
   }catch(error){
     report.terminalEvidenceFailure={error:error.message};
     result=report.playResult??(await pending).value;
     report.nativeWindowCapture={captured:report.nativeStopCapture?.captured??[]};
     report.nativeWindowPixels={stop:report.nativeWindowCapture.captured.some(image=>image.className==="KelpieScriptStop"&&image.status==="pixels-captured"),marker:false};
   }
 }else result=(await pending).value;
 pending=undefined;report.playResult=result;
 assert.equal(result.success,false);assert.equal(result.aborted,true);
 const terminal=scriptStatusV1Schema.parse((await api("get-script-status",{runId:result.runId})).value);
 assert.equal(terminal.state,"aborted");assert.equal(terminal.runSuccess,false);
 assert.ok(terminal.artifacts.length>0);assert.ok(terminal.artifacts.every(item=>item.partial));report.terminal=terminal;
 report.downloaded=[];
 for(const raw of terminal.artifacts){
  const item=scriptArtifactSchema.parse(raw),parts=[];let offset=0;
  while(offset<item.byteLength){
   const c=scriptArtifactChunkSchema.parse((await api("get-script-artifact",{runId:result.runId,artifactId:item.id,offset,length:262144})).value);
   assert.equal(c.runId,result.runId);assert.equal(c.artifactId,item.id);assert.equal(c.offset,offset);
   const bytes=Buffer.from(c.data,"base64");assert.ok(bytes.length);assert.equal(c.nextOffset,offset+bytes.length);
   parts.push(bytes);offset=c.nextOffset;assert.equal(c.eof,offset===item.byteLength);
  }
  const bytes=Buffer.concat(parts);assert.equal(createHash("sha256").update(bytes).digest("hex"),item.sha256);
  const ext={"image/png":"png","image/gif":"gif","video/mp4":"mp4"}[item.mimeType],file=join(output,item.id+"."+ext);
  await writeFile(file,bytes);report.downloaded.push({runId:result.runId,...item,file});
 }
 const recovery=(await api("play-script",{version:1,tabId,actions:[{action:"wait",ms:0}]})).value;
 assert.equal(recovery.success,true);report.recoveryRunId=recovery.runId;
 report.checks.push({name:"exact owned native Stop InvokePattern aborts capture and recovers",passed:true});
 if(mode!=="stop"){
   const passed=report.nativeWindowPixels.stop&&report.nativeWindowPixels.marker;
   report.checks.push({name:mode==="wgc"?"owned WGC presentation marker and separate native Stop pixels":"owned PrintWindow Stop and marker pixels",passed,...(passed?{}:{error:report.wgcFailure?.error??report.terminalEvidenceFailure?.error??"NATIVE_SPATIAL_VALIDATION_FAILED"})});if(!passed)process.exitCode=1;
 }
} catch(error) {
 report.checks.push({name:"interactive Stop acceptance",passed:false,error:error.safeDetails?"CLI_FAILED":"INTERACTIVE_CHECK_FAILED",stage:report.phase??"setup",code:typeof error.code==="number"?error.code:null,signal:error.signal??null,killed:error.killed??false,kind:error.name??"Error",...error.safeDetails});process.exitCode=1;
} finally {
 if(launched){
   if(pending&&readiness){try{await api("abort-script",{},true);await awaitBounded(pending,5000);}catch(error){report.pendingCleanup=error.message;}}
   try{
     const closed=await publicCli(["browser","stop",alias]);assert.equal(closed.success,true);
     if(report.identity){report.processExit=await waitForOwnedExit({pid:running.pid,executable:exe,startTime:report.identity.startTime});assert.equal(report.processExit.exited,true);}
     report.cleanup="supported-cli-closed";
   }catch(error){report.cleanup="failed";report.checks.push({name:"public cleanup",passed:false,error:error.message,code:error.code??null,signal:error.signal??null,killed:error.killed??false});process.exitCode=1;}
 }
 clearTimeout(timer);await save();
}
console.log(JSON.stringify({passed:report.checks.filter(c=>c.passed).length,failed:report.checks.filter(c=>!c.passed).map(c=>c.error),cleanup:report.cleanup}));
