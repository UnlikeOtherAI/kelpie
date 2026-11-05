import test from "node:test";
import assert from "node:assert/strict";
import {listenerState,startupSignal} from "./runtime-ownership.mjs";
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
