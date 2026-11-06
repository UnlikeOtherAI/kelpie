import vm from "node:vm";
import {request} from "node:http";
import test from "node:test";
import assert from "node:assert/strict";
import {listenerState,listenerProbeFailure,startupSignal,navigationSignal,editFocusSignal,processCommandMatches,viewportSignal,workflowVisibilitySignal,serverLifecycleSignal,listenerTransitionSignal,captureCoherenceSignal,captureTimingSignal,pointerTimingSignal,retireeSignal,cefPumpSignal,hostedStreamSignal} from "./runtime-ownership.mjs";
import {startFixture,canary} from "./runtime-fixture.mjs";
import {runIndependentPhase} from "./runtime-orchestration.mjs";
import {cliExitFacts} from "./runtime-diagnostics.mjs";
import {waitForRendererTransition} from "./runtime-renderer-transition.mjs";
import {overlayScene} from "./runtime-overlay-scene.mjs";
test("stream fixture renders its own non-auth nonce as sixteen binary cells",async()=>{
 const fixture=await startFixture();
 try{
  assert.ok(Number.isInteger(fixture.streamNonce)&&fixture.streamNonce>=0&&fixture.streamNonce<=65535);
  const html=await (await fetch(fixture.url+"/stream")).text();
  const marker=html.match(/<div id="stream-marker">(.*?)<\/div>/)?.[1];
  assert.ok(marker);
  const cells=[...marker.matchAll(/<i style="background:(#[0-9a-f]{3})"><\/i>/g)].map(m=>m[1]);
  assert.equal(cells.length,16);
  for(let i=0;i<16;i++)assert.equal(cells[i],fixture.streamNonce&(1<<i)?"#ccc":"#fff");
 }finally{await fixture.close();}
});
test("overlay fixture selects bright damage while standard stream stays red",async()=>{
 const standard=await startFixture(),overlay=await startFixture({overlay:true});
 try{
  const standardHTML=await (await fetch(standard.url+"/stream")).text();
  const overlayHTML=await (await fetch(overlay.url+"/stream")).text();
  assert.ok(standardHTML.includes("background:#f52233;animation:stream"));
  assert.ok(overlayHTML.includes("background:#f8df45;animation:stream"));
 }finally{await standard.close();await overlay.close();}
});
test("overlay scene retains measured centers and relative time without document IDs",()=>{
 const event=(target,x,time)=>({type:"click",target,x,y:20,time,documentId:"private",viewport:{width:900,height:700},
  rect:{left:x-5,right:x+5,top:15,bottom:25}});
 const first=event("first",50,100),second=event("second",550,1600);
 assert.deepEqual(overlayScene([first,second]),{width:900,height:700,first:{x:50,y:20},second:{x:550,y:20},
  firstCenter:{x:50,y:20},secondCenter:{x:550,y:20},clickSeparationMs:1500});
 assert.equal(overlayScene([first,{...second,documentId:"changed"}]),null);
 assert.equal(overlayScene([first,{...second,viewport:{width:800,height:700}}]),null);
 assert.equal(overlayScene([first,{...second,time:99}]),null);
});
test("fixture reflection is synthetic, encoded, and events never contain input values",async()=>{
 const fixture=await startFixture();
 try{
  const response=await fetch(fixture.url+"/secret");const html=await response.text();
  assert.equal(response.status,200);
  for(const variant of [canary,encodeURIComponent(canary),new URLSearchParams({v:canary}).toString().slice(2)])assert.ok(html.includes(variant));
  assert.ok(html.includes("Draft message<textarea"));
  assert.ok(html.includes("event.isTrusted"));
  assert.ok(!html.includes("value:event.target.value"));
  const sent=await fetch(fixture.url+"/events",{method:"POST",body:JSON.stringify({type:"click",target:"submit"})});
  assert.equal(sent.status,202);assert.equal(fixture.events[0].target,"submit");
 }finally{await fixture.close();}
});
test("fixture rejects oversized event bodies without retaining them",async()=>{
 const fixture=await startFixture();
 try{
  const response=await fetch(fixture.url+"/events",{method:"POST",body:"x".repeat(16385)});
  assert.equal(response.status,413);assert.equal(fixture.events.length,0);
 }finally{await fixture.close();}
});

test("aborted event POST does not crash or retain a partial event",async()=>{
 const fixture=await startFixture();
 try{
  const pending=request(fixture.url+"/events",{method:"POST",headers:{"content-type":"application/json"}});
  pending.on("error",()=>{});
  pending.write('{"type":');
  await new Promise(resolve=>setTimeout(resolve,30));
  pending.destroy();
  await new Promise(resolve=>setTimeout(resolve,30));
  const response=await fetch(fixture.url+"/events",{method:"POST",body:JSON.stringify({type:"click",target:"submit"})});
  assert.equal(response.status,202);
  assert.deepEqual(fixture.events,[{type:"click",target:"submit"}]);
 }finally{await fixture.close();}
});

test("startup waits only for missing listeners, never foreign or ambiguous owners",()=>{
 assert.equal(listenerState([],123),"missing");
 assert.equal(listenerState([123],123),"owned");
 assert.equal(listenerState([456],123),"foreign");
 assert.equal(listenerState([123,456],123),"foreign");
});

test("startup log classification retains fixed labels without raw diagnostics",()=>{
 assert.equal(startupSignal("[KelpieApp] AppReveal start requested"),"APPREVEAL_START_REQUESTED");
 assert.equal(startupSignal("[AppReveal] Server failed: DNS Error -65570 PolicyDenied"),"APPREVEAL_POLICY_DENIED");
 assert.equal(startupSignal("[AppReveal] Server failed: EADDRINUSE"),"APPREVEAL_ADDRESS_IN_USE");
 assert.equal(startupSignal("[AppReveal] Server failed: PRIVATE_LOG_CANARY"),"APPREVEAL_LISTENER_FAILED");
 assert.equal(startupSignal("page says [AppReveal] Server failed: PRIVATE_LOG_CANARY"),null);
});

test("privacy fixtures use bounded focus transitions and valid inline scripts",async()=>{
 const fixture=await startFixture();
 try{
  for(const route of ["/focus-password","/focus-autocomplete","/focus-url","/focus-delay","/input-autocomplete","/known-url"]){
   const html=await (await fetch(fixture.url+route)).text();
   new vm.Script(html.match(/<script>([\s\S]*)<\/script>/)[1]);
   assert.ok(html.includes('const privacyMode='+JSON.stringify(route)));
   assert.ok(html.includes("performance.now()+5500"));
   assert.ok(html.includes("request.open('POST','/events',false)"));
   assert.ok(!html.includes("value:event.target.value"));
   if(route==="/known-url"){
    assert.ok(html.includes("addEventListener('pointerdown',()=>{if(privacyMode==='/known-url'){send({type:'known-mid-transition'},true);history.replaceState"));
    assert.ok(!html.includes("addEventListener('click',()=>{if(privacyMode==='/known-url')history.replaceState"));
   }
  }
 }finally{await fixture.close();}
});

test("navigation diagnostics retain only exact native fixed labels",()=>{
 assert.equal(navigationSignal("[WorkflowNavigation] failure=BUSY"),"BUSY");
 assert.equal(navigationSignal("[WorkflowNavigation] failure=NAVIGATION_ERROR"),"NAVIGATION_ERROR");
 assert.equal(navigationSignal("[WorkflowNavigation] failure=NAVIGATION_ERROR private-url"),null);
 assert.equal(navigationSignal("page [WorkflowNavigation] failure=TIMEOUT"),null);
});

test("edit focus diagnostics accept only fixed state flags",()=>{
 assert.deepEqual(editFocusSignal("[WorkflowEditFocus] phase=before key=1 responder=0 doc=0 body=1 target=0"),
  {phase:"before",key:"1",responder:"0",documentFocused:"0",activeBody:"1",targetFocused:"0"});
 assert.equal(editFocusSignal("[WorkflowEditFocus] phase=before key=1 responder=0 doc=0 body=1 target=0 secret"),null);
 assert.equal(editFocusSignal("page [WorkflowEditFocus] phase=before key=1 responder=0 doc=0 body=1 target=0"),null);
});

test("hosted focus requires the exact launched candidate command",()=>{
 const candidate="/work/apps/macos/.build-runtime/Build/Products/Debug/Kelpie.app/Contents/MacOS/Kelpie";
 assert.equal(processCommandMatches(candidate+" --port 28420\n",candidate),true);
 assert.equal(processCommandMatches(candidate+"-other --port 28420",candidate),false);
 assert.equal(processCommandMatches(candidate+" --port 8420",candidate),false);
 assert.equal(processCommandMatches("/other/Kelpie --port 28420",candidate),false);
});

test("viewport diagnostics accept only bounded fixed numeric fields",()=>{
 assert.deepEqual(viewportSignal("[WorkflowViewport] bounds=1 layout=1 visible=0 scale=1 pixel=1 widths=883.00,900.00 heights=700.00,700.00"),
  {boundsSame:true,layoutSame:true,visibleSame:false,scaleSame:true,pixelSame:true,oldWidth:883,newWidth:900,oldHeight:700,newHeight:700});
 assert.equal(viewportSignal("[WorkflowViewport] bounds=1 layout=1 visible=0 scale=1 pixel=1 widths=883.00,900.00 heights=700.00,700.00 secret"),null);
});

test("paced fixture logs only synthetic lengths and bounded fixed transitions",async()=>{
 const fixture=await startFixture();
 try{
  for(const route of ["/paced","/paced-blur","/paced-replace","/paced-sensitive","/paced-final-url","/paced-final-delay"]){
   const html=await (await fetch(fixture.url+route)).text();
   new vm.Script(html.match(/<script>([\s\S]*)<\/script>/)[1]);
   assert.ok(html.includes("pacedMode="+JSON.stringify(route)));
   assert.ok(html.includes("type:'paced-input',target:id,length:value.value.length"));
   assert.ok(!html.includes("value:value.value"));
  }
 }finally{await fixture.close();}
});

test("a renderer failure is retained while an independent phase still runs",async()=>{
 const failures=[],seen=[];
 const childState=()=>({childExitAtFailure:null,childAliveAtFailure:true});
 await runIndependentPhase("webkit",async()=>{seen.push("webkit");throw Object.assign(new Error(),{code:"MOTION_WORKFLOW"});},failures,childState);
 await runIndependentPhase("chromium",async()=>{seen.push("chromium");},failures,childState);
 assert.deepEqual(seen,["webkit","chromium"]);
 assert.deepEqual(failures,[{phase:"webkit",code:"MOTION_WORKFLOW",childExitAtFailure:null,childAliveAtFailure:true}]);
 await runIndependentPhase("inference",async()=>{throw Object.assign(new Error(),{code:"unsafe value"});},failures,childState);
 assert.equal(failures[1].code,"HOSTED_RUNTIME_FAILED");
});

test("CLI exit diagnostics retain fixed codes and structural facts only",()=>{
 const known=cliExitFacts(1,JSON.stringify({error:{code:"UNAUTHORIZED",message:"private-value"}}),"private-stderr");
 assert.deepEqual(known,{exitCode:1,stdoutJson:true,stderrPresent:true,errorCode:"UNAUTHORIZED",actionsExecuted:null,mayHaveCompleted:false});
 const unknown=cliExitFacts(2,JSON.stringify({error:{code:"private-value"}}),"");
 assert.equal(unknown.errorCode,"OTHER");
 assert.ok(!JSON.stringify([known,unknown]).includes("private-value"));
 assert.equal(cliExitFacts(1,"not-json","").stdoutJson,false);
});

test("visibility diagnostics accept only fixed guard phases and Boolean flags",()=>{
 assert.deepEqual(workflowVisibilitySignal("[WorkflowVisibility] phase=focus visible=1 hidden=0 key=0 sheet=1"),
  {phase:"focus",visible:"1",hidden:"0",key:"0",sheet:"1"});
 assert.equal(workflowVisibilitySignal("[WorkflowVisibility] phase=focus visible=1 hidden=0 key=0 sheet=secret"),null);
 assert.equal(workflowVisibilitySignal("[WorkflowVisibility] phase=private visible=1 hidden=0 key=0 sheet=1"),null);
});

test("listener diagnostics distinguish no match from failed lsof without raw stderr",()=>{
 assert.deepEqual(listenerProbeFailure({status:1,stderr:""}),{outcome:"no-match",cause:"OTHER",stderrPresent:false});
 assert.deepEqual(listenerProbeFailure({status:1,stderr:"private"}),{outcome:"probe-error",cause:"OTHER",stderrPresent:true});
 assert.deepEqual(listenerProbeFailure({code:"EAGAIN"}),{outcome:"probe-error",cause:"EAGAIN",stderrPresent:false});
 assert.ok(!JSON.stringify(listenerProbeFailure({stderr:"private"})).includes("private"));
});

test("server lifecycle diagnostics retain only fixed states and requested/default port classes",()=>{
 assert.deepEqual(serverLifecycleSignal("[HTTPServer] Listening on port 28420"),{state:"listening",port:"requested"});
 assert.deepEqual(serverLifecycleSignal("[HTTPServer] Listening on port 8420"),{state:"listening",port:"default"});
 assert.deepEqual(serverLifecycleSignal("[HTTPServer] Listener failed: private"),{state:"failed"});
 assert.ok(!JSON.stringify(serverLifecycleSignal("[HTTPServer] Listener failed: private")).includes("private"));
 assert.equal(serverLifecycleSignal("[HTTPServer] Listening on port 28420 private"),null);
});

test("listener transition diagnostics retain only fixed labels and bounded error codes",()=>{
 assert.deepEqual(listenerTransitionSignal("[WorkflowListener] event=failed domain=posix code=48"),{event:"failed",domain:"posix",code:48});
 assert.deepEqual(listenerTransitionSignal("[WorkflowRenderer] event=service-update engine=chromium"),{event:"service-update",engine:"chromium"});
 assert.equal(listenerTransitionSignal("[WorkflowListener] event=failed domain=private code=48"),null);
 assert.equal(listenerTransitionSignal("[WorkflowListener] event=failed domain=dns code=1234567890"),null);
});

test("renderer confirmation waits only for a clean missing API under owned reveal",async()=>{
 const owned={owners:[7],outcome:"success",stderrPresent:false},missing={owners:[],outcome:"no-match",stderrPresent:false};
 let time=0,verifications=0,reads=0,confirmed=null;const sequence=[missing,owned];
 const deps={pid:7,probe:()=>sequence.shift()??owned,verifyReveal:async()=>{verifications++;},
  readEngine:async()=>{reads++;return {engine:"chromium"};},noteFailure:()=>{},lastFailure:()=>null,
  recordEngine:engine=>{confirmed=engine;},delay:async ms=>{time+=ms;},now:()=>time};
 await waitForRendererTransition(deps,"chromium",1000);
 assert.equal(verifications,1);assert.equal(reads,1);assert.equal(confirmed,"chromium");
});
test("renderer confirmation rejects foreign owners, failed probes, and unverified reveal",async()=>{
 for(const bad of [{owners:[8],outcome:"success",stderrPresent:false},{owners:[],outcome:"probe-error",stderrPresent:true}]){
  let recorded=0,reads=0;const deps={pid:7,probe:()=>bad,verifyReveal:async()=>{},readEngine:async()=>{reads++;},
   noteFailure:()=>{recorded++;},lastFailure:()=>null,recordEngine:()=>{},delay:async()=>{},now:()=>0};
  await assert.rejects(waitForRendererTransition(deps,"chromium",1000),error=>error.code==="LISTENER_IDENTITY");
  assert.equal(recorded,1);assert.equal(reads,0);
 }
 const missing={owners:[],outcome:"no-match",stderrPresent:false};let reads=0;
 const deps={pid:7,probe:()=>missing,verifyReveal:async()=>{throw new Error("UNVERIFIED_REVEAL");},
  readEngine:async()=>{reads++;},noteFailure:()=>{},lastFailure:()=>null,recordEngine:()=>{},delay:async()=>{},now:()=>0};
 await assert.rejects(waitForRendererTransition(deps,"chromium",1000),/UNVERIFIED_REVEAL/);assert.equal(reads,0);
});
test("renderer confirmation never retries an observed foreign or failed pin",async()=>{
 const owned={owners:[7],outcome:"success",stderrPresent:false};let probes=0;
 const deps={pid:7,probe:()=>{probes++;return owned;},verifyReveal:async()=>{},
  readEngine:async()=>{throw Object.assign(new Error("foreign"),{code:"LISTENER_IDENTITY"});},
  noteFailure:()=>{},lastFailure:()=>({port:"api",state:"foreign",probeOutcome:"success"}),
  recordEngine:()=>{},delay:async()=>{},now:()=>0};
 await assert.rejects(waitForRendererTransition(deps,"chromium",1000),error=>error.code==="LISTENER_IDENTITY");
 assert.equal(probes,1);
});

test("only a clean listener loss during a read-only confirmation is retried",async()=>{
 const owned={owners:[7],outcome:"success",stderrPresent:false},missing={owners:[],outcome:"no-match",stderrPresent:false};
 const sequence=[owned,missing,owned];let time=0,reads=0,verified=0;
 const deps={pid:7,probe:()=>sequence.shift()??owned,verifyReveal:async()=>{verified++;},
  readEngine:async()=>{if(++reads===1)throw new Error("connection lost");return {engine:"chromium"};},
  noteFailure:()=>{},lastFailure:()=>null,recordEngine:()=>{},delay:async ms=>{time+=ms;},now:()=>time};
 await waitForRendererTransition(deps,"chromium",1000);
 assert.equal(reads,2);assert.equal(verified,1);
});

test("capture coherence diagnostics accept only fixed sample and change labels",()=>{
 assert.deepEqual(captureCoherenceSignal("[WorkflowCaptureCoherence] sample=movie change=document"),{sample:"movie",change:"document"});
 assert.equal(captureCoherenceSignal("[WorkflowCaptureCoherence] sample=private change=document"),null);
 assert.equal(captureCoherenceSignal("[WorkflowCaptureCoherence] sample=movie change=private"),null);
});

test("timing diagnostics accept only bounded numeric fixed labels",()=>{
 assert.deepEqual(captureTimingSignal("[WorkflowCaptureTiming] sample=movie engine=chromium ms=1,2,3,4,5"),
  {sample:"movie",engine:"chromium",stagesMs:[1,2,3,4,5]});
 assert.equal(captureTimingSignal("[WorkflowCaptureTiming] sample=movie engine=chromium ms=1,2,private,4,5"),null);
 assert.deepEqual(captureTimingSignal("[WorkflowCaptureTiming] sample=movie engine=chromium model=coherent ms=10,20,30"),
  {sample:"movie",engine:"chromium",model:"coherent",stagesMs:[10,20,30]});
 assert.deepEqual(pointerTimingSignal("[WorkflowPointerTiming] engine=chromium elapsed=350 updates=20 updateGap=20 draws=18 drawGap=24 complete=1"),
  {engine:"chromium",elapsedMs:350,updates:20,maxUpdateGapMs:20,draws:18,maxDrawGapMs:24,completed:true});
 assert.equal(pointerTimingSignal("[WorkflowPointerTiming] engine=private elapsed=350 updates=20 updateGap=20 draws=18 drawGap=24 complete=1"),null);
});

test("retiree diagnostics accept only fixed safe labels",()=>{
 assert.deepEqual(retireeSignal("[WorkflowRetiree] event=retire reason=geometry"),{event:"retire",reason:"geometry"});
 assert.deepEqual(retireeSignal("[WorkflowRetiree] event=start reason=none"),{event:"start",reason:"none"});
 assert.equal(retireeSignal("[WorkflowRetiree] event=retire reason=https://private"),null);
 assert.equal(retireeSignal("[WorkflowRetiree] event=retire reason=geometry extra"),null);
});

test("pump experiment signal accepts only fixed modes",()=>{
 assert.equal(cefPumpSignal("[WorkflowCEFPump] mode=scheduled"),"scheduled");
 assert.equal(cefPumpSignal("[WorkflowCEFPump] mode=legacy"),"legacy");
 assert.equal(cefPumpSignal("[WorkflowCEFPump] mode=private"),null);
});

test("hosted stream parser accepts only bounded synthetic numeric events",()=>{
 assert.deepEqual(hostedStreamSignal("[WorkflowHostedStream] event=started"),{event:"started"});
 assert.deepEqual(hostedStreamSignal("[WorkflowHostedStream] event=fence stop=1 failure=4 stale=2"),{event:"fence",stop:1,failure:4,stale:2});
 assert.equal(hostedStreamSignal("[WorkflowHostedStream] event=fence stop=11 failure=0 stale=0"),null);
 assert.deepEqual(hostedStreamSignal("[WorkflowHostedStream] event=refusal reason=viewport"),{event:"refusal",reason:"viewport"});
 assert.equal(hostedStreamSignal("[WorkflowHostedStream] event=refusal reason=private"),null);
 assert.deepEqual(hostedStreamSignal("[WorkflowHostedStream] event=refusal reason=overlay"),{event:"refusal",reason:"overlay"});
 const facts="[WorkflowHostedStream] event=probe received=4 consumed=3 malformed=0 metadata=1 rejected=0 drop=2 decode=1 stop=0 ackfail=0 decodefail=0 overflow=1 detached=0 identity=0 protocol=0 stopped=1";
 assert.deepEqual(hostedStreamSignal(facts),{event:"probe",received:4,consumed:3,malformed:0,metadata:1,rejected:0,drop:2,decode:1,stop:0,ackfail:0,decodefail:0,overflow:1,detached:0,identity:0,protocol:0,stopped:1});
 assert.equal(hostedStreamSignal(facts.replace("metadata=1","metadata=64")),null);
 assert.deepEqual(hostedStreamSignal("[WorkflowHostedStream] event=sample index=1 receipt=50 protocol=48 x=300 y=120"),
  {event:"sample",index:1,receiptMs:50,protocolMs:48,x:300,y:120});
 assert.deepEqual(hostedStreamSignal("[WorkflowHostedStream] event=sample index=255 receipt=10000 protocol=9999 x=300 y=120"),
  {event:"sample",index:255,receiptMs:10000,protocolMs:9999,x:300,y:120});
 assert.deepEqual(hostedStreamSignal("[WorkflowHostedStream] event=complete count=256"),{event:"complete",count:256});
 assert.equal(hostedStreamSignal("[WorkflowHostedStream] event=sample index=256 receipt=50 protocol=48 x=300 y=120"),null);
 assert.equal(hostedStreamSignal("[WorkflowHostedStream] event=sample index=1 receipt=50 protocol=48 x=secret y=120"),null);
});
