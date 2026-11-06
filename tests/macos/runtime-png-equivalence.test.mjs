import test from "node:test";
import assert from "node:assert/strict";
import {rgbaFacts} from "./runtime-png-equivalence.mjs";
test("RGBA witness includes alpha and rejects malformed images",()=>{
 const a=rgbaFacts(Buffer.from([1,2,3,255,4,5,6,128]),2,1);
 assert.deepEqual(a.alpha,{min:128,max:255,nonopaque:1});
 assert.notEqual(a.rgbaSHA256,rgbaFacts(Buffer.from([1,2,3,255,4,5,6,255]),2,1).rgbaSHA256);
 assert.throws(()=>rgbaFacts(Buffer.alloc(7),2,1));
});
