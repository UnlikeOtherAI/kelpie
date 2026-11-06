import {test} from "node:test";
import assert from "node:assert/strict";
import {createEofWitness} from "./worker-comparison-eof-witness.mjs";
function ready(){const w=createEofWitness();
 w.request({id:1,method:"Target.createBrowserContext"});w.response({id:1,result:{browserContextId:"ctx"}});
 w.request({id:2,method:"Target.createTarget",params:{browserContextId:"ctx"}});w.response({id:2,result:{targetId:"target"}});return w;}
function dispose(w,context="ctx"){w.request({id:3,method:"Target.disposeBrowserContext",params:{browserContextId:context}});}
test("only the matching post-EOF successful disposal completes the witness",()=>{
 const w=ready();assert.equal(w.markEof(),true);dispose(w);w.response({id:3,result:{}});assert.equal(w.result().ok,true);
});
test("missing or mismatched response, error and wrong context fail closed",()=>{
 let w=ready();w.markEof();dispose(w);w.response({id:4,result:{}});assert.equal(w.result().ok,false);
 w=ready();w.markEof();dispose(w);w.response({id:3,error:{code:-1}});assert.equal(w.result().ok,false);
 w=ready();w.markEof();dispose(w,"other");assert.equal(w.result().ok,false);
});
test("early disposal, incomplete creation, and truncated relay cannot pass",()=>{
 let w=ready();dispose(w);assert.equal(w.markEof(),false);
 w=createEofWitness();w.request({id:1,method:"Target.createBrowserContext"});assert.equal(w.markEof(),false);
 w=ready();w.markEof();dispose(w);w.fail("TRUNCATED");w.response({id:3,result:{}});assert.equal(w.result().ok,false);
});
test("unrelated replies cannot satisfy pending request",()=>{
 const w=ready();w.markEof();dispose(w);w.response({id:999,result:{}});assert.equal(w.result().ok,false);
});
