import test from "node:test";
import assert from "node:assert/strict";
import {rgbaFacts,requireFixture,pixelStage} from "./runtime-png-equivalence.mjs";
test("RGBA witness includes alpha and rejects malformed images",()=>{
 const a=rgbaFacts(Buffer.from([1,2,3,255,4,5,6,128]),2,1);
 assert.deepEqual(a.alpha,{min:128,max:255,nonopaque:1});
 assert.notEqual(a.rgbaSHA256,rgbaFacts(Buffer.from([1,2,3,255,4,5,6,255]),2,1).rgbaSHA256);
 assert.throws(()=>rgbaFacts(Buffer.alloc(7),2,1));
});

test("fixture evidence rejects missing colors and noise",()=>{
 assert.throws(()=>requireFixture("static",{pattern:{blue:0,red:0,sampledColors:1}}));
 assert.throws(()=>requireFixture("noisy",{pattern:{blue:0,red:0,sampledColors:1}}));
 assert.throws(()=>requireFixture("layered",{pattern:{blue:501,red:0,sampledColors:1}}));
 requireFixture("layered",{pattern:{blue:501,red:501,sampledColors:1}});
});

test("failure stage retains only allowlisted category",async()=>{
 await assert.rejects(pixelStage("download",()=>{throw Object.assign(new Error("secret"),{code:"CHUNK_OFFSET"})}),e=>e.code==="CHUNK_OFFSET"&&e.pixelStage==="download"&&!e.message.includes("secret"));
 await assert.rejects(pixelStage("decode",()=>{throw Object.assign(new Error("secret"),{code:"secret"})}),e=>e.code==="OTHER"&&e.pixelStage==="decode"&&!e.message.includes("secret"));
});
