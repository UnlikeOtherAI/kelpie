import {writeFile} from "node:fs/promises";
import path from "node:path";
import {startArtifactProtocolFixture} from "../capture/artifact-protocol-fixture.mjs";
import {verifyArtifactProtocols} from "../capture/artifact-protocol.mjs";
import {runPrivacy} from "./runtime-privacy.mjs";
import {runSafety} from "./runtime-safety.mjs";
import {runG08} from "./runtime-g08.mjs";
import {runPaced} from "./runtime-paced.mjs";
import {runRetiree} from "./runtime-retiree.mjs";
import {errorFacts,playFacts} from "./runtime-diagnostics.mjs";
import {canary} from "./runtime-fixture.mjs";
import {Failure,delay,requireTrue,waitFor,probeListeners} from "./runtime-client.mjs";
import {waitForRendererTransition} from "./runtime-renderer-transition.mjs";
import {inspectMedia,centerPixel,inspectCurve,inspectEdgeMarker,inspectDefaultMotion} from "./runtime-media.mjs";
async function runDefaultMotion({client,fixture,engine,base,capture,check,load}) {
 for(const [label,formats] of [["combined",["gif","video"]],["video-only",["video"]]])
 await check(label==="combined"?"default-350ms-pointer-motion":"default-350ms-pointer-motion-video-only",async()=>{
  await load("/motion");const begin=fixture.events.length;
  const result=await client.api("play-script",{...base,pointer:{enabled:true},
   tapIndicator:{color:"#F54242",radius:2,durationMs:100,wobble:false,fade:true},
   capture:{...capture,formats,fps:30},actions:[
    {action:"click",target:{role:"button",name:"First"}},{action:"wait",ms:800},
    {action:"click",target:{role:"button",name:"Second"}},{action:"wait",ms:400}]});
  requireTrue(result.success,"DEFAULT_MOTION_WORKFLOW");
  const events=fixture.events.slice(begin),first=events.find(e=>e.type==="click"&&e.target==="first"),
   second=events.find(e=>e.type==="click"&&e.target==="second");
  requireTrue(first&&second,"DEFAULT_MOTION_EVENTS");
  const scene={width:second.viewport.width,height:second.viewport.height,first:{x:first.x,y:first.y},second:{x:second.x,y:second.y}};
  const artifacts=await client.download(result,engine+"-default-motion-"+label);
  requireTrue(artifacts.length===formats.length&&artifacts.every(item=>
   formats.includes(item.mimeType==="video/mp4"?"video":item.mimeType==="image/gif"?"gif":"unknown")),"DEFAULT_MOTION_FORMATS");
  return {formats,media:artifacts.map(item=>({decode:inspectMedia(item),motion:inspectDefaultMotion(item,scene)}))};
 },{continueOnFailure:true});
}
async function runEdge({client,fixture,engine,base,capture,check,load,continueOnFailure=false}) {
 await check("scrollbar-right-edge-marker",async()=>{
  await load("/edge");const begin=fixture.events.length;
  const result=await client.api("play-script",{...base,tapIndicator:{color:"#F54242",radius:18,durationMs:700,wobble:false,fade:false},
   capture:{...capture,formats:["screenshots"]},actions:[{action:"click",target:{role:"button",name:"Edge"}}]});
  requireTrue(result.success,"EDGE_WORKFLOW");
  const event=await waitFor(()=>fixture.events.slice(begin).find(e=>e.type==="click"&&e.target==="edge"));
  const artifacts=await client.download(result,engine+"-edge");
  const image=artifacts.find(a=>a.mimeType==="image/png");requireTrue(image,"EDGE_SCREENSHOT");
  return inspectEdgeMarker(image,event);
 },{continueOnFailure});
}
const capture={formats:["gif","video","screenshots"],fps:5,maxWidth:640,maxBytes:33554432,maxDurationMs:20000};
export async function runEngine(client,fixture,engine,report,scope="full") {
 let authorityRun,foreignToken,semanticStage="not-started",semanticPlay=null;
 const checks=[];report.engines.push({engine,checks});
 async function check(name,run,{continueOnFailure=false}={}){try{const detail=await run();checks.push({name,passed:true,detail});}
 catch(error){
  const diagnostic=name==="semantic-label-export"?{stage:semanticStage,...errorFacts(error),
   tool:client.toolFacts??null,play:semanticPlay,artifact:client.artifactFacts??null,chunk:client.chunkFacts??null,protocols:client.protocolFacts??null}:undefined;
  checks.push({name,passed:false,code:error.code??"CHECK_FAILED",...(diagnostic?{diagnostic}:{})});
  if(!continueOnFailure){
   const first=checks.find(item=>!item.passed);
   if(first?.name!==name)throw new Failure(first.code);
   throw error;
  }}}
 await check("native-renderer-control",async()=>{
  client.nativeControlStage="engine-before";
  const before=await client.api("get-renderer");
  client.lastEngine=["webkit","chromium"].includes(before.engine)?before.engine:"unknown";
  const focus=await client.focusOwnedBrowser();
  client.nativeControlStage="more-find";
  const more=await client.find("browser.action.more");requireTrue(more,"NATIVE_MORE_MISSING");
  client.nativeControlStage="more-tap";await client.tap("browser.action.more",more);
  client.nativeControlStage="engine-find";const id="browser.renderer."+engine,window=await waitFor(()=>client.find(id));
  client.nativeControlStage="engine-tap";await client.tap(id,window);
  client.nativeControlStage="engine-confirm";
  await waitForRendererTransition({pid:client.pid,probe:()=>probeListeners(28420),
   verifyReveal:()=>client.verifyOwnedReveal(),
   readEngine:async()=>(await client.request("/v1/get-renderer",{}, {timeout:3000})).value,
   noteFailure:probe=>client.noteListenerFailure(28420,probe),lastFailure:()=>client.listenerFailure,
   recordEngine:actual=>{client.lastEngine=actual;},delay,now:Date.now},engine);
  client.nativeControlStage=null;
  const resized=await client.api("resize-viewport",{width:900,height:700});
  requireTrue(resized.success,"NATIVE_VIEWPORT_RESIZE");
  return {...await client.screenshot(engine+"-renderer"),focus};
 });
 const tabs=await client.api("get-tabs");
 const entries=Array.isArray(tabs)?tabs:tabs.tabs;
 const tabId=engine==="chromium"?"chromium":(entries.find(t=>t.active||t.isActive)??entries[0]).id;
 const base={version:1,tabId,defaultWaitBetweenActions:0,tapIndicator:{color:"#F54242",radius:25,durationMs:700,wobble:true,fade:true}};
 const play=actions=>client.api("play-script",{...base,actions});
 async function load(route="/"){const begin=fixture.events.length;const result=await play([{action:"navigate",url:fixture.url+route},{action:"wait-ready",state:"complete",timeoutMs:10000}]);if(!result.success){
  const allowed=new Set(["UNAUTHORIZED","INVALID_SCRIPT","BUSY","RECORDING_IN_PROGRESS","TAB_NOT_FOUND","TAB_NOT_ACTIVE","TAB_NOT_VISIBLE","TAB_CHANGED","RENDERER_CHANGED","SCRIPT_RENDERER_UNSUPPORTED","NAVIGATION_FAILED","TIMEOUT","WEBVIEW_ERROR","DOCUMENT_CHANGED","OBSERVATION_FAILED","CAPTURE_VIEWPORT_UNSTABLE","SCRIPT_ABORTED"]);
  const code=allowed.has(result.error?.code)?result.error.code:"UNCLASSIFIED";
  (report.fixtureNavigationFailures??=[]).push({engine,code,hasRunId:typeof result.runId==="string",mayHaveCompleted:result.mayHaveCompleted===true});
 }requireTrue(result.success,"FIXTURE_NAVIGATION");await waitFor(()=>fixture.events.slice(begin).find(e=>e.type==="document"&&e.path===route));}
 await check("strict-capability",async()=>{
  const direct=await client.api("get-script-status");
  const generic=await client.direct("kelpie_get_script_status",{},true);
  requireTrue(direct.supportedVersions?.includes(1)&&generic.supportedVersions?.includes(1),"STRICT_CAPABILITY_MISSING");
  return {direct:true,generic:true};
 });
 await check("public-navigation-from-start-page",async()=>{
  const result=await client.api("navigate",{tabId,url:fixture.url+"/"});
  requireTrue(result.success,"PUBLIC_NAVIGATION");
  await waitFor(()=>fixture.events.find(e=>e.type==="document"&&e.path==="/"));
  return {success:true};
 });
 await load();
 if(scope==="cef-timing"){
  requireTrue(engine==="chromium","FOCUSED_RENDERER");
  await runRetiree({client,engine,base,capture,check,load});
  await runEdge({client,fixture,engine,base,capture,check,load,continueOnFailure:true});
  await runDefaultMotion({client,fixture,engine,base,capture,check,load});
  const failed=checks.find(item=>!item.passed);
  if(failed)throw new Failure(failed.code);
  return;
 }
 await check("semantic-label-export",async()=>{
  const begin=fixture.events.length;
  semanticStage="direct-play";
  const result=await client.direct("kelpie_play_script",{...base,capture,actions:[
   {action:"fill",target:{label:"Draft message"},text:"Synthetic written"},
   {action:"type",target:{label:"Draft message"},text:" more"},
   {action:"click",target:{role:"button",name:"Submit"}},
   {action:"output",name:"title",source:"title"},
   {action:"extract",name:"catalogue",params:{scope:"#catalogue",fields:[{name:"tea",selector:"h3",source:"text",multiple:true}],metadata:true}}]});
  semanticPlay=playFacts(result);
  semanticStage="validate-output";
  if(!result.success){
   const codes=new Set(["INPUT_UNCERTAIN","INPUT_INTERRUPTED","SENSITIVE_CAPTURE_REFUSED","DOCUMENT_CHANGED",
    "AUTHORIZATION_REVOKED","CAPTURE_DOCUMENT_CHANGED","CAPTURE_VIEWPORT_CHANGED","CAPTURE_FAILED",
    "CAPTURE_DURATION_LIMIT","CAPTURE_ADMISSION_FAILED","TAB_CHANGED","TAB_NOT_VISIBLE","RENDERER_CHANGED",
    "TARGET_FAILED","TARGET_MOVED","TARGET_NOT_FOUND","TARGET_NOT_EDITABLE","TARGET_NOT_INTERACTABLE",
    "TIMEOUT","WEBVIEW_ERROR","WORKFLOW_FAILED","COMMAND_FAILED","BUSY","UNAUTHORIZED"]);
   const classify=code=>codes.has(code)?code:"OTHER";
   const evidence={engine,mcpCode:classify(result.error?.code)};
   report.semanticFailure=evidence;
   try{
    const status=await client.api("get-script-status");
    evidence.status={success:status.success===true,state:["idle","running","finalizing","completed","failed","aborted"].includes(status.state)?status.state:"OTHER",
     hasRunId:typeof status.runId==="string",runSuccess:status.runSuccess===true?true:status.runSuccess===false?false:null,
     runError:classify(status.runError?.code),mayHaveCompleted:status.mayHaveCompleted===true,
     artifactCount:Array.isArray(status.artifacts)?status.artifacts.length:null};
   }catch(error){evidence.statusException=errorFacts(error);}
   const events=fixture.events.slice(begin);
   evidence.entryInputObserved=events.some(event=>event.type==="input"&&event.target==="entry");
   evidence.submitClickObserved=events.some(event=>event.type==="click"&&event.target==="submit");
  }
  requireTrue(result.success,"SEMANTIC_WORKFLOW");
  const field=result.outputs?.catalogue?.fields?.[0];
  requireTrue(field?.status==="ok"&&field.values.join("|")==="Green tea|Black tea"&&field.provenance.selector==="h3","STRUCTURED_EXTRACTION_PROVENANCE");
  semanticStage="fixture-event";
  const event=await waitFor(()=>fixture.events.slice(begin).find(e=>e.type==="click"&&e.target==="submit"));
  requireTrue(event.hit==="submit"&&!event.trusted&&Math.abs(event.x-(event.rect.left+event.rect.right)/2)<2&&Math.abs(event.y-(event.rect.top+event.rect.bottom)/2)<2,"SEMANTIC_CENTER");
  authorityRun=result;
  semanticStage="artifact-download";
  const artifacts=await client.download(result,engine+"-main");
  requireTrue(new Set(artifacts.map(a=>a.mimeType)).size===3,"ALL_FORMATS");
  semanticStage="media-decode";
  return {runId:result.runId,artifacts:artifacts.map(a=>({...a,decode:inspectMedia(a,{marker:a.mimeType!=="image/png"})})),event};
 });
 await runRetiree({client,engine,base,capture,check,load});
 await runPaced({client,fixture,engine,base,capture,check,load,play});
 await load();
 await check("observation-and-readiness-public-entry",async()=>{
  const results={};
  for(const [method,params] of [["tab.status",{}],["tab.ready",{state:"complete",selector:"#submit"}],["tab.snapshot",{}]]){
   const value=await client.api("browser-control",{version:1,method,tabId,params});
   requireTrue(value.ok,"CANONICAL_OBSERVATION");results[method]={ok:true};
   if(method==="tab.ready")requireTrue(value.value.ready,"READINESS_PREDICATE");
  }return results;
 });
 await check("generic-mcp-play-and-owner-fence",async()=>{
  const value=await client.direct("kelpie_play_script",{...base,actions:[{action:"click",target:{selector:"#submit"}}]},true);
  requireTrue(value.success,"GENERIC_MCP_PLAY");
  const foreign=await client.pair("Hosted foreign owner");foreignToken=foreign;
  const status=await client.api("get-script-status",{runId:value.runId},foreign);
  const abort=await client.api("abort-script",{runId:value.runId},foreign);
  const chunk=await client.api("get-script-artifact",{runId:authorityRun.runId,artifactId:authorityRun.artifacts[0].id,offset:0,length:1024},foreign);
  requireTrue(!status.success&&!abort.success&&!status.artifacts&&!status.outputs&&!chunk.success&&!chunk.data,"FOREIGN_OWNER_ACCESS");
  return {genericPlay:true,foreignStatusDenied:true,foreignAbortDenied:true,foreignArtifactDenied:true};
 });
 await check("three-protocol-multichunk-artifact",async()=>{
  const large=await startArtifactProtocolFixture();
  try{
   const navigated=await play([{action:"navigate",url:large.url},{action:"wait-ready",state:"complete",selector:"img"},{action:"wait",ms:500}]);
   requireTrue(navigated.success,"ARTIFACT_FIXTURE_READY");
   const status=await client.api("browser-control",{version:1,method:"tab.status",tabId,params:{}});
   requireTrue(status.ok&&status.value.viewport.width>=512&&status.value.viewport.height>=512,"ARTIFACT_FIXTURE_VIEWPORT");
   const value=await client.api("play-script",{...base,capture:{...capture,formats:["screenshots"],maxWidth:1280},actions:[{action:"screenshot"}]});
   requireTrue(value.success,"ARTIFACT_FIXTURE_CAPTURE");
   const artifact=value.artifacts.find(a=>a.mimeType==="image/png"&&a.byteLength>262*1024);
   requireTrue(artifact,"ARTIFACT_MULTICHUNK_SIZE");
   const verified=await verifyArtifactProtocols({runId:value.runId,artifact,
    http:async(method,body,options)=>(await client.request("/v1/"+method,body,options)).value,
    mcp:(name,args,options)=>client.tool(name,args,false,options)});
   const file=path.join(client.out,engine+"-three-protocol.png");await writeFile(file,verified.bytes,{flag:"wx"});
   return {...verified.report,fixtureSha256:large.fixtureSha256,decoded:inspectMedia({...artifact,file})};
  }finally{await large.close();}
 });
 await load();
 await check("ambiguity-obscured-disabled",async()=>{
  const results=[];
  for(const name of ["Duplicate","Covered","Disabled"]){
   const begin=fixture.events.length;
   const value=await play([{action:"click",target:{role:"button",name}}]);
   requireTrue(!value.success&&!fixture.events.slice(begin).some(e=>e.type==="click"),"UNSAFE_TARGET_MUTATED");
   results.push({name,code:value.error?.code});
  }return results;
 });
 await check("session-full-preflight",async()=>{
  const begin=fixture.events.length;
  const value=await client.api("play-script",{...base,sessionId:"unknown-owned-session",actions:[
   {action:"navigate",url:fixture.url+"/next"},{action:"click",target:{selector:"#submit"}}]});
  requireTrue(!value.success&&value.error?.code==="SESSION_UNSUPPORTED","SESSION_REFUSAL");
  await delay(200);requireTrue(!fixture.events.slice(begin).some(e=>e.type==="document"),"SESSION_EARLY_MUTATION");
  return {code:value.error.code};
 });
 await check("inferred-secret-refusal-scrubs-prior-output",async()=>{
  await load("/secret");const begin=fixture.events.length;
  const value=await client.api("play-script",{...base,capture:{...capture,formats:["screenshots"]},actions:[
   {action:"output",name:"before",source:"title"},
   {action:"fill",target:{label:"Account password"},text:canary}]});
  requireTrue(!value.success&&value.error?.code==="SENSITIVE_CAPTURE_REFUSED","SENSITIVE_REFUSAL");
  const status=await client.api("get-script-status",{runId:value.runId});
  const serialized=JSON.stringify({value,status});
  for(const variant of [canary,encodeURIComponent(canary),new URLSearchParams({v:canary}).toString().slice(2)])
   requireTrue(!serialized.includes(variant),"SENSITIVE_OUTPUT_LEAK");
  requireTrue(value.outputs?.before?.includes("[redacted]")&&(value.artifacts??[]).length===0,"SENSITIVE_OUTPUT_DISCARD");
  requireTrue(!fixture.events.slice(begin).some(e=>e.target==="password"&&e.type==="input"),"SENSITIVE_INPUT_OCCURRED");
  requireTrue(!("outputs" in status),"STATUS_OUTPUT_LEAK");
  return {code:value.error.code,priorOutputScrubbed:true,noInput:true,artifactsDiscarded:true};
 });
 await runPrivacy({client,fixture,base,capture,check,load,authorityRun,foreignToken});
 await check("gif-native-stop-early",async()=>{
  await load();
  const pending=client.api("play-script",{...base,capture:{...capture,formats:["gif"]},actions:[{action:"wait",ms:8000}]});
  void pending.catch(()=>{});
  const status=await waitFor(async()=>{const value=await client.api("get-script-status");return value.playing&&value.runId?value:null;});
  const window=await waitFor(()=>client.find("browser.recording.stop"));
  await client.tap("browser.recording.stop",window);
  const result=await pending;requireTrue(!result.success&&result.state==="aborted","NATIVE_EARLY_STOP_FAILED");
  const artifacts=await client.download(result,engine+"-early-abort");
  requireTrue(artifacts.every(a=>a.partial),"NATIVE_EARLY_STOP_NONPARTIAL");
  const decoded=artifacts.map(a=>inspectMedia(a));
  const recovery=await play([{action:"click",target:{role:"button",name:"Submit"}}]);
  requireTrue(recovery.success,"EARLY_ABORT_RECOVERY_FAILED");
  return {observedActionIndex:status.actionIndex,partialCount:artifacts.length,decoded,recovered:true};
 });
 await check("gif-native-stop-partial-recovery",async()=>{
  await load();const begin=fixture.events.length;
  const pending=client.api("play-script",{...base,capture:{...capture,formats:["gif"]},actions:[
   {action:"click",target:{role:"button",name:"Submit"}},{action:"wait",ms:8000}]});
  void pending.catch(()=>{});
  // Action 1 starts only after capture.start and the clicked marker's critical frame are admitted.
  const status=await waitFor(async()=>{const value=await client.api("get-script-status");
   return value.playing&&value.runId&&value.actionIndex>=1?value:null;});
  const window=await waitFor(()=>client.find("browser.recording.stop"));
  await client.screenshot(engine+"-native-stop");await client.tap("browser.recording.stop",window);
  const result=await pending;
  const facts={engine,actionIndex:status.actionIndex,clickObserved:fixture.events.slice(begin).some(e=>e.type==="click"&&e.target==="submit"),
   state:["aborted","failed","completed"].includes(result.state)?result.state:"OTHER",play:playFacts(result)};
  (report.stopFacts??=[]).push(facts);
  requireTrue(!result.success&&result.state==="aborted","NATIVE_STOP_FAILED");
  const artifacts=await client.download(result,engine+"-abort");
  facts.downloaded=artifacts.map(a=>({mimeType:a.mimeType,partial:a.partial,byteLength:a.byteLength,sha256:a.sha256}));
  requireTrue(artifacts.some(a=>a.mimeType==="image/gif"&&a.partial),"ABORT_GIF_PREFIX_MISSING");
  const decoded=artifacts.map(a=>inspectMedia(a));
  const recovery=await play([{action:"click",target:{role:"button",name:"Submit"}}]);
  requireTrue(recovery.success,"ABORT_RECOVERY_FAILED");
  return {runId:status.runId,decoded,recovered:true};
 });
 await check("scrolled-current-surface-pixels",async()=>{
  await load("/bands");const begin=fixture.events.length;
  const value=await client.api("play-script",{...base,capture:{...capture,formats:["screenshots"]},actions:[
   {action:"scroll",deltaY:1200},{action:"wait",ms:250},{action:"screenshot",name:"scrolled"}]});
  requireTrue(value.success,"SCROLLED_CAPTURE");
  const event=await waitFor(()=>fixture.events.slice(begin).filter(e=>e.type==="scroll").at(-1));
  const artifacts=await client.download(value,engine+"-scrolled"),item=artifacts.at(-1);
  const sourceY=event.visual.pageY+event.visual.height/2;
  const expected=[[255,0,0],[0,255,0],[0,0,255],[255,0,255]][Math.floor(sourceY/1000)%4];
  const actual=centerPixel(item);
  requireTrue(actual.every((v,i)=>Math.abs(v-expected[i])<20),"SCROLLED_SOURCE_DESTINATION_PIXEL");
  return {sourceY,expected,actual,viewport:event.viewport,visual:event.visual,artifact:item};
 });
 await runEdge({client,fixture,engine,base,capture,check,load});
 for(const formats of [["gif","video"],["gif","video","screenshots"]])await check("low-fps-navigation-marker-"+formats.length,async()=>{
  await load();
  const begin=fixture.events.length;
  const result=await client.api("play-script",{...base,capture:{...capture,formats,fps:1},actions:[
   {action:"click",target:{role:"link",name:"Next document"}},{action:"wait",ms:1200}]});
  if(!result.success){
   const codes=new Set(["AUTHORIZATION_REVOKED","BUSY","CAPTURE_ADMISSION_FAILED","CAPTURE_AFTER_ACTION_FAILED",
    "CAPTURE_BYTE_LIMIT","CAPTURE_DOCUMENT_CHANGED","CAPTURE_DOCUMENT_UNAVAILABLE","CAPTURE_DURATION_LIMIT",
    "CAPTURE_FAILED","CAPTURE_STOPPED","CAPTURE_VIEWPORT_CHANGED","CAPTURE_VIEWPORT_UNAVAILABLE",
    "CAPTURE_VIEWPORT_UNSTABLE","DOCUMENT_CHANGED","INPUT_INTERRUPTED","INPUT_UNCERTAIN","INVALID_PARAM",
    "INVALID_SCRIPT","INVALID_TARGET","NAVIGATION_FAILED","OBSERVATION_FAILED","OUTPUT_BUDGET_EXCEEDED",
    "OUTPUT_REDACTION_FAILED","RECORDING_IN_PROGRESS","RENDERER_CHANGED","SCRIPT_ABORTED","SCRIPT_UNAVAILABLE",
    "SENSITIVE_CAPTURE_REFUSED","STALE_TARGET","TAB_CHANGED","TAB_NOT_ACTIVE","TAB_NOT_FOUND","TAB_NOT_VISIBLE",
    "TARGET_FAILED","TARGET_MOVED","TARGET_NOT_FOUND","TARGET_NOT_INTERACTABLE","TARGET_OBSCURED",
    "TARGET_OUTSIDE_VIEWPORT","TARGET_QUERY_LIMIT","TIMEOUT","UNAUTHORIZED","VIEWPORT_CHANGED","WEBVIEW_ERROR",
    "WORKFLOW_FAILED"]);
   const events=fixture.events.slice(begin);
   const initial=fixture.events.slice(0,begin).filter(e=>e.type==="document"&&e.path==="/").at(-1);
   const next=events.find(e=>e.type==="document"&&e.path==="/next");
   const number=value=>typeof value==="number"&&Number.isFinite(value)&&value>=0&&value<=100000?value:null;
   const geometry=event=>event?{innerWidth:number(event.viewport?.width),innerHeight:number(event.viewport?.height),
    clientWidth:number(event.viewport?.clientWidth),clientHeight:number(event.viewport?.clientHeight),
    pixelRatio:number(event.viewport?.pixelRatio),visualWidth:number(event.visual?.width),
    visualHeight:number(event.visual?.height),visualScale:number(event.visual?.scale)}:null;
   const failure={engine,formats:formats.length,initialGeometry:geometry(initial),nextGeometry:geometry(next),code:codes.has(result.error?.code)?result.error.code:"OTHER",
    mayHaveCompleted:result.mayHaveCompleted===true,actionsExecuted:Number.isInteger(result.actionsExecuted)?result.actionsExecuted:null,
    clickObserved:events.some(e=>e.type==="click"&&e.target==="next"),
    nextDocumentObserved:events.some(e=>e.type==="document"&&e.path==="/next"),play:playFacts(result)};
   (report.lowFpsFailures??=[]).push(failure);
   try{
    const artifacts=await client.download(result,engine+"-lowfps-failure");
    failure.downloaded=artifacts.map(a=>({mimeType:a.mimeType,partial:a.partial,byteLength:a.byteLength,sha256:a.sha256}));
    failure.decode=artifacts.filter(a=>a.mimeType!=="image/png").map(a=>inspectMedia(a));
   }catch(error){failure.downloadError=errorFacts(error);}
  }
  requireTrue(result.success,"LOW_FPS_NAVIGATION");
  const artifacts=await client.download(result,engine+"-lowfps"),movies=artifacts.filter(a=>a.mimeType!=="image/png");
  requireTrue(movies.length===2,"LOW_FPS_FORMATS");
  return movies.map(a=>inspectMedia(a,{marker:true,preNavigation:true}));
 });
 await runDefaultMotion({client,fixture,engine,base,capture,check,load});
 for(const curve of ["s","c"])await check("movie-pointer-curve-"+curve,async()=>{
  await load("/motion");const begin=fixture.events.length;
  const result=await client.api("play-script",{...base,pointer:{enabled:true,curve,durationMs:2000,easing:"ease-in-out"},
   tapIndicator:{color:curve==="s"?"#F54242":"#22CCFF",radius:curve==="s"?30:12,durationMs:700,wobble:curve==="s",fade:curve==="s"},
   capture:{...capture,formats:["gif","video"],fps:15},actions:[{action:"click",target:{role:"button",name:"First"}},
    {action:"wait",ms:800},{action:"click",target:{role:"button",name:"Second"}},{action:"wait",ms:800}]});
  if(!result.success){
   const allowed=new Set(["AUTHORIZATION_REVOKED","BUSY","CAPTURE_ADMISSION_FAILED","CAPTURE_AFTER_ACTION_FAILED",
    "CAPTURE_ARTIFACT_FAILED","CAPTURE_BYTE_LIMIT","CAPTURE_DOCUMENT_CHANGED","CAPTURE_DURATION_LIMIT",
    "CAPTURE_FAILED","CAPTURE_FINALIZATION_LIMIT","CAPTURE_STOPPED","CAPTURE_VIEWPORT_CHANGED",
    "CAPTURE_VIEWPORT_UNAVAILABLE","DOCUMENT_CHANGED","INPUT_INTERRUPTED","INPUT_UNCERTAIN","INVALID_PARAM",
    "INVALID_SCRIPT","INVALID_TARGET","RECORDING_IN_PROGRESS","RENDERER_CHANGED","SCRIPT_ABORTED",
    "SENSITIVE_CAPTURE_REFUSED","STALE_TARGET","TAB_CHANGED","TAB_NOT_ACTIVE","TAB_NOT_VISIBLE",
    "TARGET_FAILED","TARGET_MOVED","TARGET_NOT_FOUND","TARGET_NOT_INTERACTABLE","TARGET_OBSCURED",
    "TARGET_OUTSIDE_VIEWPORT","TIMEOUT","UNAUTHORIZED","VIEWPORT_CHANGED","WEBVIEW_ERROR","WORKFLOW_FAILED"]);
   const events=fixture.events.slice(begin);
   const failure={engine,curve,code:allowed.has(result.error?.code)?result.error.code:"OTHER",
    mayHaveCompleted:result.mayHaveCompleted===true,actionsExecuted:Number.isInteger(result.actionsExecuted)?result.actionsExecuted:null,
    firstClicks:events.filter(e=>e.type==="click"&&e.target==="first").length,
    secondClicks:events.filter(e=>e.type==="click"&&e.target==="second").length,play:playFacts(result)};
   (report.motionFailures??=[]).push(failure);
   try{
    const artifacts=await client.download(result,engine+"-motion-failure");
    failure.downloaded=artifacts.map(a=>({mimeType:a.mimeType,partial:a.partial,byteLength:a.byteLength,sha256:a.sha256}));
    failure.decode=artifacts.filter(a=>a.mimeType!=="image/png").map(a=>inspectMedia(a));
   }catch(error){failure.downloadError=errorFacts(error);}
  }
  requireTrue(result.success,"MOTION_WORKFLOW");
  const events=fixture.events.slice(begin),first=events.find(e=>e.type==="click"&&e.target==="first"),second=events.find(e=>e.type==="click"&&e.target==="second");
  requireTrue(first&&second,"MOTION_TARGET_EVENTS");
  const scene={width:second.viewport.width,height:second.viewport.height,first:{x:first.x,y:first.y},second:{x:second.x,y:second.y}};
  const artifacts=await client.download(result,engine+"-curve-"+curve);
  return {curve,scene,runId:result.runId,decoded:artifacts.map(a=>({decode:inspectMedia(a),motion:inspectCurve(a,curve,scene)}))};
 },{continueOnFailure:true});
 await check("dense-animation",()=>runG08(client,tabId,engine,report),{continueOnFailure:true});
 await runSafety({client,fixture,engine,base,capture,check,play,load});
 report.gaps.push({engine,capability:"native-pinch",reason:"No supported native pinch input exists in audited public/app-owned interfaces; not substituted with stage scaling or OS input."});
 const failed=checks.find(item=>!item.passed);
 if(failed)throw new Failure(failed.code);
}
