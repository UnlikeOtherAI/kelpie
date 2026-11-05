import test from "node:test";
import assert from "node:assert/strict";
import {Readable} from "node:stream";
import {consumeG08Frames} from "./g08-frame-stream.mjs";
test("RGB decoder stream preserves frames across arbitrary chunk boundaries",async()=>{
 const pixels=Buffer.from(Array.from({length:36},(_,i)=>i)),frames=[];
 const count=await consumeG08Frames(Readable.from([pixels.subarray(0,1),pixels.subarray(1,19),pixels.subarray(19)]),
  2,2,(frame,index)=>frames.push({index,pixels:Buffer.from(frame)}));
 assert.equal(count,3);assert.deepEqual(Buffer.concat(frames.map(f=>f.pixels)),pixels);
});
test("partial frames and oversized dimensions fail closed",async()=>{
 await assert.rejects(()=>consumeG08Frames(Readable.from([Buffer.alloc(11)]),2,2,()=>{}),/Incomplete/);
 await assert.rejects(()=>consumeG08Frames(Readable.from([]),641,2,()=>{}));
});

test("the bounded long fixture admits 800 frames and rejects the next",async()=>{
 assert.equal(await consumeG08Frames(Readable.from([Buffer.alloc(800*12)]),2,2,()=>{}),800);
 await assert.rejects(()=>consumeG08Frames(Readable.from([Buffer.alloc(801*12)]),2,2,()=>{}),/frame limit/);
});