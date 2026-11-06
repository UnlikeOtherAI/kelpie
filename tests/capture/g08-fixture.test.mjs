import test from "node:test";
import assert from "node:assert/strict";
import {request} from "node:http";
import {setImmediate} from "node:timers";
import {startG08Fixture,g08Workflow,mapG08Scene,hasG08Warmup} from "./g08-fixture.mjs";
test("neutral fixture serves blank named controls and bounded facts through actual HTTP",async()=>{
 const fixture=await startG08Fixture();
 try{
  const html=await(await fetch(fixture.url)).text();
  assert.match(html,/data-kelpie-g08-document-id/);
  assert.equal(fixture.pageRequests,1);
  assert.match(html,/aria-label="G08 Start"><\/button>/);
  assert.match(html,/aria-label="G08 Finish"><\/button>/);
  const endpoint=new URL("/events",fixture.url);
  const fact={target:"start",documentId:"synthetic",trusted:true,timeMs:1,center:{x:160,y:240},viewport:{width:640,height:480}};
  assert.equal((await fetch(endpoint,{method:"POST",body:JSON.stringify(fact)})).status,202);
  assert.equal((await(await fetch(endpoint)).json()).events.length,1);
  assert.equal(fixture.pageRequests,1);
  assert.equal((await fetch(endpoint,{method:"POST",body:"x".repeat(8193)})).status,413);
  assert.equal((await(await fetch(endpoint)).json()).events.length,1);
  assert.equal(fixture.pageRequests,1);
 }finally{await fixture.close();}
});
test("witness fixture binds a nonce path and records listener retirement",async()=>{
 const nonce="a".repeat(32),fixture=await startG08Fixture({witnessNonce:nonce});
 try{
  assert.match(fixture.url,new RegExp("/g08/"+nonce+"$"));assert.equal(fixture.listenerHeld,true);
  assert.equal((await fetch(fixture.url)).status,200);
  assert.equal((await fetch(new URL("/g08",fixture.url))).status,404);
 }finally{await fixture.close();}
 assert.equal(fixture.listenerHeld,false);
 await assert.rejects(startG08Fixture({witnessNonce:"not-a-nonce"}));
 await assert.rejects(startG08Fixture({host:"0.0.0.0",witnessNonce:nonce}));
});
test("same bounded production request covers both curves without product eval",()=>{
 for(const curve of ["c","s"]){
  const workflow=g08Workflow("owned",curve);
  assert.equal(workflow.pointer.curve,curve);assert.equal(workflow.capture.maxWidth,640);
  assert.equal(workflow.capture.fps,20);assert.equal(workflow.capture.maxDurationMs,33000);
  assert.equal(workflow.actions.length,8);
  assert.deepEqual(workflow.actions.filter(a=>a.action==="click").map(a=>a.target.name),["G08 Finish","G08 Finish","G08 Start","G08 Finish"]);
 }
 assert.throws(()=>g08Workflow("owned","line"));
});

test("aborted event POST does not crash or poison the fixture",async()=>{
 const fixture=await startG08Fixture();
 try{
  await new Promise((resolve,reject)=>{
   const req=request(new URL("/events",fixture.url),{method:"POST",headers:{"content-length":"100"}});
   req.on("error",error=>{if(error.code==="ECONNRESET")resolve();else reject(error);});
   req.on("close",resolve);
   req.on("socket",socket=>socket.once("connect",()=>{req.write("{");setImmediate(()=>req.destroy());}));
  });
  const result=await fetch(new URL("/events",fixture.url));
  assert.equal(result.status,200);assert.deepEqual((await result.json()).events,[]);
 }finally{await fixture.close();}
});
test("four observed clicks bind warmup and calibration to one ordered scene",()=>{
 const make=(target,timeMs)=>({target,timeMs,documentId:"doc",trusted:true,
   viewport:{width:640,height:480},center:target==="finish"?{x:480,y:240}:{x:160,y:240}});
 const events=[make("finish",1),make("finish",6000),make("start",12000),make("finish",18000)];
 const scene=mapG08Scene(events);
 assert.equal(hasG08Warmup(scene),true);
 assert.equal(hasG08Warmup({calibration:events[1],start:events[2],finish:events[3]}),false);
 assert.throws(()=>hasG08Warmup({...scene,warmup:null}));
 assert.equal(scene.warmup,events[0]);assert.equal(scene.calibration,events[1]);
 assert.equal(scene.start,events[2]);assert.equal(scene.finish,events[3]);
 for(const mutate of [
  list=>list.splice(0,1),list=>list[1].target="start",list=>list[1].timeMs=1,
  list=>list[1].documentId="other",list=>list[1].center.x++,list=>delete list[0].center
 ]){const invalid=structuredClone(events);mutate(invalid);assert.throws(()=>mapG08Scene(invalid));}
 for(const curve of ["c","s"]){
  const workflow=g08Workflow("owned",curve);
  assert.deepEqual(workflow.actions.filter(x=>x.action==="wait").map(x=>x.ms),[3500,3500,3500,3500]);
  assert.ok(workflow.capture.maxDurationMs<=33000&&workflow.capture.fps*workflow.capture.maxDurationMs/1000<=800);
 }
});
