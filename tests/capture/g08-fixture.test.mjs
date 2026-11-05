import test from "node:test";
import assert from "node:assert/strict";
import {startG08Fixture,g08Workflow} from "./g08-fixture.mjs";
test("neutral fixture serves blank named controls and bounded facts through actual HTTP",async()=>{
 const fixture=await startG08Fixture();
 try{
  const html=await(await fetch(fixture.url)).text();
  assert.match(html,/aria-label="G08 Start"><\/button>/);
  assert.match(html,/aria-label="G08 Finish"><\/button>/);
  const endpoint=new URL("/events",fixture.url);
  const fact={target:"start",documentId:"synthetic",trusted:true,timeMs:1,center:{x:160,y:240},viewport:{width:640,height:480}};
  assert.equal((await fetch(endpoint,{method:"POST",body:JSON.stringify(fact)})).status,202);
  assert.equal((await(await fetch(endpoint)).json()).events.length,1);
  assert.equal((await fetch(endpoint,{method:"POST",body:"x".repeat(8193)})).status,413);
  assert.equal((await(await fetch(endpoint)).json()).events.length,1);
 }finally{await fixture.close();}
});
test("same bounded production request covers both curves without product eval",()=>{
 for(const curve of ["c","s"]){
  const workflow=g08Workflow("owned",curve);
  assert.equal(workflow.pointer.curve,curve);assert.equal(workflow.capture.maxWidth,640);
  assert.equal(workflow.capture.fps,20);assert.equal(workflow.actions.length,4);
 }
 assert.throws(()=>g08Workflow("owned","line"));
});
