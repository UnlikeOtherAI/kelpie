import {uptime} from "node:os";
import assert from "node:assert/strict";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {createHash} from "node:crypto";
import {mkdir,readFile,writeFile,access} from "node:fs/promises";
import {dirname,join,isAbsolute} from "node:path";
import {startG08Fixture} from "../capture/g08-fixture.mjs";
import {scriptArtifactSchema,scriptArtifactChunkSchema,scriptV1Schema} from "../../packages/shared/dist/index.js";
import {acceptPresentation,presentationNotVisible,presentationCaptureExecutable,safeUiaFailure} from "./wgc-presentation-identity.mjs";
import {safeCliFailure} from "./safe-cli-failure.mjs";
import {safeWgcDiagnostic} from "./wgc-safe-diagnostic.mjs";
import {waitForOwnedExit} from "./wait-for-owned-exit.mjs";
import {observeInFlight,awaitBounded} from "./interactive-stop-lifecycle.mjs";

const [exe,cli,uia,wgc,privateRoot,outputRoot,manifestPath,curve,expectedUiaHash,expectedWgcHash,expectedRevision,motionProfile="dense"]=process.argv.slice(2);
assert.ok([exe,cli,uia,wgc,privateRoot,outputRoot,manifestPath].every(p=>p&&isAbsolute(p)));
assert.ok(["c","s"].includes(curve));assert.ok(["dense","fast","default"].includes(motionProfile));
assert.match(expectedUiaHash??"",/^[a-f0-9]{64}$/);assert.match(expectedWgcHash??"",/^[a-f0-9]{64}$/);assert.match(expectedRevision??"",/^[a-f0-9]{40}$/);
const exec=promisify(execFile),manifest=JSON.parse(await readFile(manifestPath,"utf8"));
assert.match(manifest.source??"",/^[a-f0-9]{40}$/);
const hash=async p=>createHash("sha256").update(await readFile(p)).digest("hex");
assert.equal(await hash(exe),manifest.exeSha256);assert.equal(await hash(join(dirname(exe),"kelpie.dll")),manifest.dllSha256);
assert.equal(await hash(cli),manifest.cliSha256);
await mkdir(privateRoot,{recursive:false});await mkdir(outputRoot,{recursive:false});
const home=join(privateRoot,"cli-home"),profile=join(privateRoot,"profile");
const env={...process.env,USERPROFILE:privateRoot,KELPIE_HOME:home,NODE_OPTIONS:"--max-old-space-size=2048"};
const run=async(command,args,timeout=15000)=>exec(command,args,{env,windowsHide:true,timeout,maxBuffer:2097152});
const cliRun=async args=>{try{return JSON.parse((await run(process.execPath,[cli,...args],args[1]==="launch"?30000:20000)).stdout);}catch(error){error.safeDetails=safeCliFailure(error);throw error;}};
const uiaRun=async args=>{try{return JSON.parse((await run(uia,args,10000)).stdout);}catch(error){error.safeDetails=safeUiaFailure(error);throw error;}};
const alias="capture-g08-native-"+manifest.source.slice(0,8)+"-"+curve;
const report={source:manifest.source,curve,profile:motionProfile,phase:"session",checks:[],cleanup:"not-started"};
let fixture,registered=false,launched=false,running,readiness,identity,pending,pendingDone=false,capturePromise;
const save=()=>writeFile(join(outputRoot,"report.json"),JSON.stringify(report,null,2));
const api=async(method,body={})=>{
 const response=await fetch("http://127.0.0.1:28420/v1/"+method,{method:"POST",
  headers:{authorization:"Bearer "+readiness.token,"content-type":"application/json"},body:JSON.stringify(body),
  signal:AbortSignal.timeout(method==="play-script"?60000:10000)});
 const value=await response.json();if(method==="play-script")report.playHttpStatus=response.status;else assert.ok(response.ok,"HTTP_"+response.status);return value;
};
const tabFact=async tabId=>{
 const value=await api("get-tabs"),tab=value.tabs.find(item=>item.id===tabId);
 assert.ok(tab);return {tabId:tab.id,active:tab.active,url:tab.url};
};
try{
 const session=await uiaRun(["session"]);assert.equal(session.sessionId,1);assert.equal(session.user.toLowerCase(),"maxis\\ondre");
 await run(join(process.env.WINDIR,"System32/icacls.exe"),[privateRoot,"/inheritance:r","/grant:r","*"+session.userSid+":(OI)(CI)F","*S-1-5-18:(OI)(CI)F"]);await mkdir(home);
 report.hashes={exe:await hash(exe),dll:await hash(join(dirname(exe),"kelpie.dll")),cli:await hash(cli),uia:await hash(uia),wgc:await hash(wgc)};
 assert.equal(report.hashes.uia,expectedUiaHash);assert.equal(report.hashes.wgc,expectedWgcHash);
 report.phase="revision";const revision=(await run("git.exe",["rev-parse","HEAD"])).stdout.trim();assert.equal(revision,expectedRevision);
 report.phase="tracked-status";assert.equal((await run("git.exe",["status","--porcelain","--untracked-files=no"])).stdout.trim(),"");report.testRevision=revision;
 fixture=await startG08Fixture();report.phase="register";
 assert.equal((await cliRun(["browser","register",alias,"--platform","windows","--app-path",exe,"--profile-dir",profile])).success,true);registered=true;
 const started=new Date().toISOString();report.phase="launch";
 const observer=process.env.KELPIE_STARTUP_OBSERVER,observerHash=process.env.KELPIE_STARTUP_OBSERVER_SHA256;
 assert.ok(observer&&isAbsolute(observer));assert.match(observerHash??"",/^[a-f0-9]{64}$/);assert.equal(await hash(observer),observerHash);
 const completion=join(outputRoot,"startup.done"),observationPath=join(outputRoot,"startup-observation.json");
 let launchDone=false,observation;const launch=cliRun(["browser","launch",alias,"--port","28420"]).finally(()=>{launchDone=true;});void launch.catch(()=>{});
 for(let attempt=0;attempt<90&&!launchDone;attempt++){
  try{const current=JSON.parse(await readFile(join(home,"browsers.json"),"utf8")).running[alias];
   if(Number.isSafeInteger(current?.pid)&&current.pid>0){
    observation=run(observer,[String(current.pid),exe,"28420",join(profile,"readiness.json"),completion,observationPath],55000);void observation.catch(()=>{});break;
   }
  }catch{}
  await new Promise(done=>setTimeout(done,250));
 }
 try{assert.equal((await launch).success,true);launched=true;}finally{
 if(capturePromise){try{await awaitBounded(capturePromise,12000);}catch{}}
  await writeFile(completion,"done",{flag:"wx"});
  if(observation){try{await observation;report.startupObservation=JSON.parse(await readFile(observationPath,"utf8"));}
   catch{report.startupObservation={status:"observer-failed"};}}
  else report.startupObservation={status:"pending-pid-not-observed"};
 }
 report.phase="readiness";const store=JSON.parse(await readFile(join(home,"browsers.json"),"utf8"));running=store.running[alias];assert.ok(running?.pid&&running.port===28420);
 readiness=JSON.parse(await readFile(running.readinessFile,"utf8"));assert.equal(readiness.launchId,running.launchId);
 report.phase="pin";identity=await uiaRun(["pin",String(running.pid),exe,started]);
 assert.equal(identity.processId,running.pid);assert.equal(identity.sessionId,1);
 report.phase="socket";const sockets=(await run(join(process.env.WINDIR,"System32/netstat.exe"),["-ano","-p","tcp"])).stdout.split(/\r?\n/).map(line=>line.trim().split(/\s+/)).filter(parts=>parts[1]==="127.0.0.1:28420"&&parts[3]==="LISTENING");
 assert.ok(sockets.length>0&&sockets.every(parts=>Number(parts[4])===running.pid));
 report.phase="device-info";assert.equal((await api("get-device-info")).success,true);
 report.phase="tabs";const tabs=await api("get-tabs"),tabId=tabs.tabs.find(tab=>tab.active)?.id;assert.ok(tabId);
 report.phase="navigate";assert.equal((await api("navigate",{tabId,url:fixture.url})).success,true);
 report.phase="fixture-ready";assert.equal((await api("play-script",{version:1,tabId,actions:[{action:"wait-ready",state:"complete"}]})).success,true);
 report.phase="geometry";const before=await tabFact(tabId);assert.equal(before.url,fixture.url);assert.equal(before.active,true);
 const facts=(await api("evaluate",{tabId,expression:"(()=>{const a=document.querySelector('#start').getBoundingClientRect(),b=document.querySelector('#finish').getBoundingClientRect();return {from:{x:a.x+a.width/2,y:a.y+a.height/2},to:{x:b.x+b.width/2,y:b.y+b.height/2},viewport:{width:innerWidth,height:innerHeight}}})()"}));
 assert.equal(facts.success,true);const scene=facts.result;
 const config={...scene,curve,pointerMs:motionProfile==="dense"?2400:350,markerMs:3000,radius:48,color:curve==="c"?"#ff0000":"#0000ff"};
 report.phase="play";
 const workflow={version:1,tabId,pointer:{enabled:false},tapIndicator:{color:"#ff0000",radius:48,durationMs:5000,wobble:false,fade:true},
  capture:{formats:["screenshots"],fps:15,maxWidth:640,maxDurationMs:30000,maxBytes:16777216},
  actions:[{action:"click",target:{role:"button",name:"G08 Finish",exact:true}},
   {action:"wait",ms:3000},{action:"click",target:{role:"button",name:"G08 Finish",exact:true}}]};
 scriptV1Schema.parse(workflow);
 pending=observeInFlight(api("play-script",workflow).finally(()=>{pendingDone=true;}));
 let active,window;
 for(let attempt=0;attempt<150&&!pendingDone;attempt++){
  const status=await api("get-script-status");if(status.playing){active=status;
   try{window=acceptPresentation(await uiaRun(["presentation",String(running.pid),exe,identity.startTime]),identity,running.pid);break;}
   catch(error){if(!presentationNotVisible(error))throw error;}
  }
  await new Promise(done=>setTimeout(done,50));
 }
 assert.ok(active?.playing&&window,"PRESENTATION_UNAVAILABLE");report.window=window;report.active={runId:active.runId,playing:true};report.viewport=scene.viewport;
 report.phase="terminal";const terminal=await pending;
 const responseTickUpper=Math.ceil(uptime())*1000+1000;
 report.terminal={success:terminal.success===true,runId:terminal.runId,actionsExecuted:terminal.actionsExecuted,
  totalDurationMs:terminal.totalDurationMs,artifactCount:terminal.artifacts?.length,responseTickUpper};
 assert.equal(terminal.success,true);assert.equal(terminal.runId,active.runId);assert.equal(terminal.actionsExecuted,3);
 assert.ok(terminal.totalDurationMs<7000,"PNG_RUN_WAITED_FOR_MARKER");
 // A fresh capture session starts only after the HTTP response, avoiding any
 // ambiguity about old frames queued before the response.
 report.phase="post-response-capture";report.captureStartedTick=Math.floor(uptime()*1000);
 capturePromise=run(wgc,[String(running.pid),presentationCaptureExecutable(identity),identity.startFileTime,window.windowHandle,join(outputRoot,"post-response")],10000);
 void capturePromise.then(()=>{report.captureEndedTick=Math.floor(uptime()*1000);},
  error=>{report.captureEndedTick=Math.floor(uptime()*1000);report.captureFailure=safeWgcDiagnostic(String(error.stderr??""));});
 const stopPromise=uiaRun(["inspect",String(running.pid),exe,identity.startTime]).catch(()=>null);
 const fixtureFacts=await(await fetch(new URL("/events",fixture.url),{signal:AbortSignal.timeout(5000)})).json();
 assert.equal(fixtureFacts.dropped,0);assert.equal(fixtureFacts.events.length,2);
 assert.ok(fixtureFacts.events.every(event=>event.target==="finish"&&event.trusted===true));
 report.fixture={trustedClicks:fixtureFacts.events.length,pageRequests:fixture.pageRequests};
 const items=(terminal.artifacts??[]).map(item=>scriptArtifactSchema.parse(item));
 assert.ok(items.some(item=>item.mimeType==="image/png" && item.actionIndex===2),"PNG_ARTIFACT_MISSING");
 const png=items.find(item=>item.mimeType==="image/png" && item.actionIndex===2),chunks=[];let offset=0;
 assert.ok(png.byteLength<=16777216,"OUTPUT_BUDGET");
 while(offset<png.byteLength){
  const chunk=scriptArtifactChunkSchema.parse(await api("get-script-artifact",{runId:terminal.runId,artifactId:png.id,offset,length:262144}));
  assert.equal(chunk.runId,terminal.runId);assert.equal(chunk.artifactId,png.id);assert.equal(chunk.offset,offset);const bytes=Buffer.from(chunk.data,"base64");assert.ok(bytes.length>0);
  chunks.push(bytes);offset+=bytes.length;assert.equal(chunk.nextOffset,offset);assert.equal(chunk.eof,offset===png.byteLength);
 }
 const pngBytes=Buffer.concat(chunks);assert.equal(createHash("sha256").update(pngBytes).digest("hex"),png.sha256);
 await writeFile(join(outputRoot,"terminal.png"),pngBytes,{flag:"wx"});
 const stopState=await stopPromise;
 report.stopState={visibleInvokableButtons:stopState?.visibleInvokableButtons??null};
 assert.equal(stopState?.visibleInvokableButtons,0);
 const captured=JSON.parse((await capturePromise).stdout);
 assert.equal(captured.processId,running.pid);assert.equal(captured.className,"KelpieScriptPresentation");
 assert.equal(captured.windowHandle,window.windowHandle);
 const pixels=await readFile(join(outputRoot,"post-response","frame.bgra"));
 assert.equal(pixels.length,captured.width*captured.height*4);
 assert.equal(createHash("sha256").update(pixels).digest("hex"),captured.raw.sha256);
 const sx=captured.width/scene.viewport.width,sy=captured.height/scene.viewport.height;
 const cx=scene.to.x*sx,cy=scene.to.y*sy,r=48*Math.max(sx,sy)*1.5;
 let redPixels=0,maxAlpha=0;
 for(let y=Math.max(0,Math.floor(cy-r));y<Math.min(captured.height,Math.ceil(cy+r));y++)
  for(let x=Math.max(0,Math.floor(cx-r));x<Math.min(captured.width,Math.ceil(cx+r));x++){
   const i=(y*captured.width+x)*4;if(pixels[i+2]>20&&pixels[i+2]>pixels[i+1]*2&&pixels[i+3]>20){redPixels++;maxAlpha=Math.max(maxAlpha,pixels[i+3]);}
  }
 report.native={width:captured.width,height:captured.height,redPixels,maxAlpha,rawSha256:captured.raw.sha256,pngSha256:captured.png.sha256};
 report.checks.push({name:"post-response owned marker",passed:redPixels>0,redPixels});
 assert.ok(redPixels>0,"POST_RESPONSE_MARKER_NOT_OBSERVED");
 report.phase="complete";
}catch(error){
 if(fixture){try{
  const partial=await(await fetch(new URL("/events",fixture.url),{signal:AbortSignal.timeout(3000)})).json();
  const bytes=Buffer.from(JSON.stringify(partial));if(bytes.length<=16384)await writeFile(join(outputRoot,"partial-fixture-events.json"),bytes,{flag:"wx"});
 }catch{}}
 const location=String(error.stack??"").match(/(?:wgc-frame-stream|wgc-g08-evaluate|wgc-g08-rgb|g08-pixels|g08-retention).mjs:\d+/)?.[0]??null;
 const errorKind=["AbortError","TimeoutError","TypeError","AssertionError","Error"].includes(error.name)?error.name:"Other";
 const message=String(error.message??"");const safe=/^(INSUFFICIENT_EVIDENCE|INVALID_PREMULTIPLIED_ALPHA|WGC_|G08_|FAST_|OUTPUT_BUDGET|PRESENTATION_UNAVAILABLE|NO_ACTIVE_STATUS_POLL|HTTP_[0-9]{3})[A-Za-z0-9_ .:-]{0,120}$/.test(message)&&!/[a-f0-9]{24,}/i.test(message)?message:"CASE_FAILED";
 report.checks.push({name:"post-response owned marker",passed:false,stage:report.phase,
  category:error.safeDetails?.category??safe,errorKind,location,code:typeof error.code==="number"?error.code:null,signal:error.signal??null,killed:error.killed??false});
 process.exitCode=1;
}finally{
 if(capturePromise){try{await awaitBounded(capturePromise,12000);}catch{}}
 if(pending&&readiness&&!pendingDone){try{await api("abort-script",{});}catch{}try{await awaitBounded(pending,5000);}catch{}}
 if(launched){try{assert.equal((await cliRun(["browser","stop",alias])).success,true);
  if(identity){report.processExit=await waitForOwnedExit({pid:running.pid,executable:exe,startTime:identity.startTime});assert.equal(report.processExit.exited,true);}
  let readinessAbsent=false;try{await access(running.readinessFile);}catch{readinessAbsent=true;}
  let store=JSON.parse(await readFile(join(home,"browsers.json"),"utf8"));assert.ok(readinessAbsent&&!store.running[alias]);
  assert.equal((await cliRun(["browser","remove",alias])).success,true);store=JSON.parse(await readFile(join(home,"browsers.json"),"utf8"));assert.ok(!store.running[alias]&&!store.aliases[alias]);report.cleanup="supported-cli-closed-and-removed";
 }catch(error){report.cleanup="failed";report.cleanupFailure=error.safeDetails??{category:"cleanup-failed",code:typeof error.code==="number"?error.code:null,signal:error.signal??null,killed:error.killed===true};process.exitCode=1;}}
 if(registered&&!launched){try{
  assert.equal((await cliRun(["browser","remove",alias])).success,true);
  const store=JSON.parse(await readFile(join(home,"browsers.json"),"utf8"));assert.ok(!store.running[alias]&&!store.aliases[alias]);report.cleanup="registered-alias-removed";
 }catch(error){report.cleanup="failed";report.cleanupFailure=error.safeDetails??{category:"cleanup-failed",code:typeof error.code==="number"?error.code:null,signal:error.signal??null,killed:error.killed===true};process.exitCode=1;}}
 if(fixture)await fixture.close();await save();
}
