import assert from "node:assert/strict";
import {spawn,execFile} from "node:child_process";
import {promisify} from "node:util";
import {createHash} from "node:crypto";
import {mkdir,readFile,writeFile,access,stat} from "node:fs/promises";
import {dirname,join,isAbsolute,resolve} from "node:path";
import {startG08Fixture,g08Workflow} from "../capture/g08-fixture.mjs";
import {applyG08MotionProfile} from "./g08-motion-profile.mjs";
import {scriptArtifactSchema,scriptArtifactChunkSchema} from "../../packages/shared/dist/index.js";
import {evaluateWgcFrames} from "./wgc-g08-evaluate.mjs";
import {verifyWgcProvenance} from "./wgc-g08-provenance.mjs";
import {verifyTimelineSnapshots} from "./wgc-case-files.mjs";
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
let fixture,launched=false,running,readiness,identity,pending,pendingDone=false,helper,helperTimer,helperExit,helperError="",monitorStop=false,monitor;
const save=()=>writeFile(join(outputRoot,"report.json"),JSON.stringify(report,null,2));
const api=async(method,body={})=>{
 const response=await fetch("http://127.0.0.1:28420/v1/"+method,{method:"POST",
  headers:{authorization:"Bearer "+readiness.token,"content-type":"application/json"},body:JSON.stringify(body),
  signal:AbortSignal.timeout(method==="play-script"?60000:10000)});
 assert.ok(response.ok,"HTTP_"+response.status);return response.json();
};
const tabFact=async tabId=>{
 const value=await api("get-tabs"),tab=value.tabs.find(item=>item.id===tabId);
 assert.ok(tab);return {tabId:tab.id,active:tab.active,url:tab.url};
};
async function download(result,item,budget){
 assert.ok(item.byteLength<=budget.remaining,"OUTPUT_BUDGET");const chunks=[];let offset=0;
 while(offset<item.byteLength){
  const c=scriptArtifactChunkSchema.parse(await api("get-script-artifact",{runId:result.runId,artifactId:item.id,offset,length:262144}));
  assert.equal(c.runId,result.runId);assert.equal(c.artifactId,item.id);assert.equal(c.offset,offset);
  const bytes=Buffer.from(c.data,"base64");assert.ok(bytes.length>0);offset+=bytes.length;
  assert.equal(c.nextOffset,offset);assert.equal(c.eof,offset===item.byteLength);chunks.push(bytes);
 }
 const bytes=Buffer.concat(chunks);assert.equal(bytes.length,item.byteLength);assert.equal(createHash("sha256").update(bytes).digest("hex"),item.sha256);
 const file=resolve(outputRoot,item.id+(item.mimeType==="image/gif"?".gif":".mp4"));
 assert.ok(bytes.length<=budget.remaining,"OUTPUT_BUDGET");budget.remaining-=bytes.length;await writeFile(file,bytes,{flag:"wx"});
 report.phase="artifact-probe";const probe=await run(process.env.FFPROBE||"ffprobe",["-v","error","-select_streams","v:0","-show_entries","frame=best_effort_timestamp_time","-of","json",file],120000);
 const timestamps=JSON.parse(probe.stdout).frames.map(frame=>Number(frame.best_effort_timestamp_time));
 assert.ok(timestamps.length>0&&timestamps.every(Number.isFinite));return {...item,runId:result.runId,file,timestamps};
}
try{
 const session=await uiaRun(["session"]);assert.equal(session.sessionId,1);assert.equal(session.user.toLowerCase(),"maxis\\ondre");
 await run(join(process.env.WINDIR,"System32/icacls.exe"),[privateRoot,"/inheritance:r","/grant:r","*"+session.userSid+":(OI)(CI)F","*S-1-5-18:(OI)(CI)F"]);await mkdir(home);
 report.hashes={exe:await hash(exe),dll:await hash(join(dirname(exe),"kelpie.dll")),cli:await hash(cli),uia:await hash(uia),wgc:await hash(wgc)};
 assert.equal(report.hashes.uia,expectedUiaHash);assert.equal(report.hashes.wgc,expectedWgcHash);
 report.phase="revision";const revision=(await run("git.exe",["rev-parse","HEAD"])).stdout.trim();assert.equal(revision,expectedRevision);
 report.phase="tracked-status";assert.equal((await run("git.exe",["status","--porcelain","--untracked-files=no"])).stdout.trim(),"");report.testRevision=revision;
 fixture=await startG08Fixture();report.phase="register";
 assert.equal((await cliRun(["browser","register",alias,"--platform","windows","--app-path",exe,"--profile-dir",profile])).success,true);
 const started=new Date().toISOString();report.phase="launch";
 assert.equal((await cliRun(["browser","launch",alias,"--port","28420"])).success,true);launched=true;
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
 const workflow=applyG08MotionProfile(g08Workflow(tabId,curve),motionProfile);
 pending=observeInFlight(api("play-script",workflow).finally(()=>{pendingDone=true;}));
 let active,window;
 for(let attempt=0;attempt<100&&!pendingDone;attempt++){
  const status=await api("get-script-status");if(status.playing){active=status;
   try{const p=await uiaRun(["presentation",String(running.pid),exe,identity.startTime]);
    window=acceptPresentation(p,identity,running.pid);break;
   }catch(error){if(!presentationNotVisible(error))throw error;}
  }
  await new Promise(done=>setTimeout(done,50));
 }
 assert.ok(active?.playing&&window,"PRESENTATION_UNAVAILABLE");assert.equal(window.className,"KelpieScriptPresentation");
 report.phase="capture";report.active={runId:active.runId,playing:true};report.window=window;await save();
 helper=spawn(wgc,["timeline",String(running.pid),presentationCaptureExecutable(identity),identity.startFileTime,window.windowHandle,join(outputRoot,"native")],{env,windowsHide:true,stdio:["ignore","pipe","pipe"]});
 helper.stderr.on("data",chunk=>{if(helperError.length<8192)helperError+=chunk.toString().slice(0,8192-helperError.length);});
 helperExit=new Promise((done,reject)=>{helper.once("error",reject);helper.once("close",(code,signal)=>done({code,signal}));});void helperExit.catch(()=>{});
 helperTimer=setTimeout(()=>helper.kill(),35000);
 const nativePromise=evaluateWgcFrames(helper.stdout,config);void nativePromise.catch(()=>{});
 const activeSamples=[];monitor=(async()=>{while(!monitorStop&&!pendingDone){
  const status=await api("get-script-status");if(status.playing){assert.equal(status.runId,active.runId);assert.ok(activeSamples.length<100,"STATUS_SAMPLE_BOUND");activeSamples.push({runId:status.runId,playing:true});}
  await new Promise(done=>setTimeout(done,300));
 }return activeSamples.length;})();void monitor.catch(()=>{});
 report.phase="capture-play-wait";const terminal=await pending;monitorStop=true;report.terminalFacts={success:terminal.success===true,runIdPresent:typeof terminal.runId==="string"&&terminal.runId.length>0,actionsExecuted:Number.isInteger(terminal.actionsExecuted)?terminal.actionsExecuted:null,errorCode:typeof terminal.error?.code==="string"&&/^[A-Z][A-Z0-9_]{0,79}$/.test(terminal.error.code)?terminal.error.code:null,captureErrorPresent:terminal.captureError!=null,artifactCount:Array.isArray(terminal.artifacts)?terminal.artifacts.length:null};report.phase="capture-monitor";const statusPolls=await monitor;assert.ok(statusPolls>0,"NO_ACTIVE_STATUS_POLL");
 report.phase="capture-evaluate";let native;
 try{native=await nativePromise;}catch(error){helper.kill();report.helperExit=await helperExit.catch(()=>({code:null,signal:null}));report.helperDiagnostic=safeWgcDiagnostic(helperError);throw error;}
 const exit=await helperExit;clearTimeout(helperTimer);helperTimer=null;report.helperDiagnostic=safeWgcDiagnostic(helperError);report.helperExit=exit;assert.equal(exit.code,0,"WGC_HELPER_FAILED");
 assert.equal(terminal.success,true);assert.equal(terminal.runId,active.runId);
 const after=await tabFact(tabId);const fixtureFacts=await(await fetch(new URL("/events",fixture.url),{signal:AbortSignal.timeout(10000)})).json();
 assert.equal(fixtureFacts.events.length,3);assert.deepEqual(fixtureFacts.events.map(event=>event.target),["finish","start","finish"]);
 assert.deepEqual(fixtureFacts.events[1].center,scene.from);assert.deepEqual(fixtureFacts.events[2].center,scene.to);
 assert.deepEqual(fixtureFacts.events[0].viewport,scene.viewport);
 const summary=JSON.parse(await readFile(join(outputRoot,"native","summary.json"),"utf8"));
 let used=await verifyTimelineSnapshots(summary,join(outputRoot,"native"));
 used+=(await stat(join(outputRoot,"native","summary.json"))).size;assert.ok(used<=67108864);
 const items=(terminal.artifacts??[]).map(item=>scriptArtifactSchema.parse(item));assert.equal(items.length,2);
 const budget={remaining:67108864-used-65536};assert.ok(budget.remaining>=0,"OUTPUT_BUDGET");
 const serialSamples=native.samples.map(sample=>({...sample,marker:{...sample.marker,...(sample.marker.roi?{roi:sample.marker.roi.toString("base64")}:{})}}));
 const nativeEvidence=Buffer.from(JSON.stringify({config,native:{samples:serialSamples,analysis:native.analysis,oracleError:native.oracleError,frameCount:native.frameCount}}));
 assert.ok(nativeEvidence.length<=budget.remaining,"OUTPUT_BUDGET");budget.remaining-=nativeEvidence.length;
 await writeFile(join(outputRoot,"native-observation.json"),nativeEvidence,{flag:"wx"});
 report.phase="artifact-download";const artifacts=[];for(const item of items)artifacts.push(await download(terminal,item,budget));
 const trustedFacts={source:manifest.source,curve,frameCount:native.frameCount,
  identity:{pid:running.pid,sessionId:identity.sessionId,executable:identity.executable,startFileTime:identity.startFileTime,launchId:readiness.launchId,port:28420},
  window,active:{runId:active.runId,playing:true},activeSamples,terminal:{runId:terminal.runId,success:terminal.success,inputGuarantee:terminal.inputGuarantee,totalDurationMs:terminal.totalDurationMs},
  before,after,fixture:{url:fixture.url,pageRequests:fixture.pageRequests,...fixtureFacts},artifacts,summary};
 report.phase="provenance";
 const factEvidence=Buffer.from(JSON.stringify(trustedFacts));assert.ok(factEvidence.length<=budget.remaining,"OUTPUT_BUDGET");
 budget.remaining-=factEvidence.length;await writeFile(join(outputRoot,"facts-observation.json"),factEvidence,{flag:"wx"});
 const provenance=verifyWgcProvenance(trustedFacts);
 const caseData={curve,profile:motionProfile,binarySHA256:manifest.dllSha256,scene:{calibration:fixtureFacts.events[0],start:fixtureFacts.events[1],finish:fixtureFacts.events[2]},artifacts,
  provenance,facts:trustedFacts,config,native:{samples:serialSamples,analysis:native.analysis,oracleError:native.oracleError,frameCount:native.frameCount},summary};
 const bytes=Buffer.from(JSON.stringify(caseData,null,2));assert.ok(bytes.length<=budget.remaining,"OUTPUT_BUDGET");await writeFile(join(outputRoot,"case.json"),bytes,{flag:"wx"});
 report.phase="complete";report.checks.push({name:"owned native and exported G08 case",passed:native.analysis?.passed===true,oracleError:native.oracleError,frameCount:native.frameCount,statusPolls});if(!native.analysis?.passed)process.exitCode=1;
}catch(error){
 if(helperExit&&!report.helperExit){if(helper&&helper.exitCode===null)helper.kill();try{report.helperExit=await awaitBounded(helperExit,2000);}catch{report.helperExit={code:null,signal:null};}report.helperDiagnostic=safeWgcDiagnostic(helperError);}
 const errorKind=["AbortError","TimeoutError","TypeError","AssertionError","Error"].includes(error.name)?error.name:"Other";
 const message=String(error.message??"");const safe=/^(INSUFFICIENT_EVIDENCE|WGC_|G08_|OUTPUT_BUDGET|PRESENTATION_UNAVAILABLE|NO_ACTIVE_STATUS_POLL|HTTP_[0-9]{3})[A-Za-z0-9_ .:-]{0,120}$/.test(message)&&!/[a-f0-9]{24,}/i.test(message)?message:"CASE_FAILED";
 report.checks.push({name:"owned native and exported G08 case",passed:false,stage:report.phase,
  category:error.safeDetails?.category??safe,errorKind,code:typeof error.code==="number"?error.code:null,signal:error.signal??null,killed:error.killed??false});
 process.exitCode=1;
}finally{
 monitorStop=true;if(helperTimer)clearTimeout(helperTimer);if(helper&&helper.exitCode===null)helper.kill();
 if(pending&&readiness&&!pendingDone){try{await api("abort-script",{});}catch{}try{await awaitBounded(pending,5000);}catch{}}
 if(launched){try{assert.equal((await cliRun(["browser","stop",alias])).success,true);
  if(identity){report.processExit=await waitForOwnedExit({pid:running.pid,executable:exe,startTime:identity.startTime});assert.equal(report.processExit.exited,true);}
  let readinessAbsent=false;try{await access(running.readinessFile);}catch{readinessAbsent=true;}
  let store=JSON.parse(await readFile(join(home,"browsers.json"),"utf8"));assert.ok(readinessAbsent&&!store.running[alias]);
  assert.equal((await cliRun(["browser","remove",alias])).success,true);store=JSON.parse(await readFile(join(home,"browsers.json"),"utf8"));assert.ok(!store.running[alias]&&!store.aliases[alias]);report.cleanup="supported-cli-closed-and-removed";
 }catch(error){report.cleanup="failed";report.cleanupFailure=error.safeDetails??{category:"cleanup-failed",code:typeof error.code==="number"?error.code:null,signal:error.signal??null,killed:error.killed===true};process.exitCode=1;}}
 if(fixture)await fixture.close();await save();
}
