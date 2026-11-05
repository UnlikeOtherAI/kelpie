import vm from "node:vm";
import {request} from "node:http";
import test from "node:test";
import assert from "node:assert/strict";
import {listenerState,listenerProbeFailure,startupSignal,navigationSignal,editFocusSignal,processCommandMatches,viewportSignal,workflowVisibilitySignal} from "./runtime-ownership.mjs";
import {startFixture,canary} from "./runtime-fixture.mjs";
import {runIndependentPhase} from "./runtime-orchestration.mjs";
import {cliExitFacts} from "./runtime-diagnostics.mjs";
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
