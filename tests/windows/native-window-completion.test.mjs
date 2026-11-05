import test from "node:test";
import assert from "node:assert/strict";
import {finishNativeWindowEvidence} from "./native-window-completion.mjs";
const scene={documentId:"fixture",target:{x:230,y:180},viewport:{dpr:2,visualScale:1}};
const event={trusted:true,documentId:"fixture",x:230,y:180,dpr:2,visualScale:1};
test("legacy click read and validator wait for Stop and terminal completion",async()=>{
 const calls=[];let resolve;const completion=new Promise(done=>{resolve=done;});
 const pending=finishNativeWindowEvidence({stopInvoked:true,completion,scene,
  readStatus:async()=>{calls.push("terminal-status");return {runId:"run",playing:false};},
  readClick:async()=>{calls.push("legacy-read");return {success:true,result:event};},
  validate:async()=>{calls.push("spatial-validation");return {verified:true};}});
 await Promise.resolve();assert.deepEqual(calls,[]);
 resolve({runId:"run",success:false,aborted:true});await pending;
 assert.deepEqual(calls,["terminal-status","legacy-read","spatial-validation"]);
});
test("active status refuses without probing a BUSY legacy route",async()=>{
 let read=false;
 await assert.rejects(finishNativeWindowEvidence({stopInvoked:true,completion:Promise.resolve({runId:"run"}),scene,
  readStatus:async()=>({runId:"run",playing:true}),readClick:async()=>{read=true;},validate:async()=>{}}),/terminal/);
 assert.equal(read,false);
});
test("no validation when post-terminal legacy read is refused",async()=>{
 let validated=false;
 await assert.rejects(finishNativeWindowEvidence({stopInvoked:true,completion:Promise.resolve({runId:"run"}),scene,
  readStatus:async()=>({runId:"run",playing:false}),readClick:async()=>({success:false,error:{code:"BUSY"}}),
  validate:async()=>{validated=true;}}),/POST_TERMINAL_CLICK_READ:BUSY/);
 assert.equal(validated,false);
});

test("no completion reads before native Stop invocation",async()=>{
 let read=false;
 await assert.rejects(finishNativeWindowEvidence({stopInvoked:false,completion:Promise.resolve({runId:"run"}),scene,
  readStatus:async()=>{read=true;},readClick:async()=>{},validate:async()=>{}}),/Native Stop/);
 assert.equal(read,false);
});
