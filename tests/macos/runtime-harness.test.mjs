import vm from "node:vm";
import test from "node:test";
import assert from "node:assert/strict";
import {listenerState,startupSignal,navigationSignal,editFocusSignal} from "./runtime-ownership.mjs";
import {startFixture,canary} from "./runtime-fixture.mjs";
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
