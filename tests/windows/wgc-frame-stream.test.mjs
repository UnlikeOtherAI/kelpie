import test from "node:test";import assert from "node:assert/strict";import {Readable} from "node:stream";
import {consumeWgcFrames,expectedAnalysisSize} from "./wgc-frame-stream.mjs";
function frame(seq,tick=100,overrides={}){const meta=Buffer.from(JSON.stringify({sequence:seq,tick100ns:tick,receiptMs:1,width:2,height:2,sourceWidth:2,sourceHeight:2,sourceStride:8,alphaMode:"straight",...overrides}));const head=Buffer.alloc(8);head.writeUInt32LE(meta.length);head.writeUInt32LE(16,4);return Buffer.concat([head,meta,Buffer.alloc(16,7)]);}
test("parses fragmented actual records in order and bounds",async()=>{const data=Buffer.concat([frame(0),frame(1,101)]),seen=[];const chunks=[];for(let i=0;i<data.length;i+=3)chunks.push(data.subarray(i,i+3));assert.equal(await consumeWgcFrames(Readable.from(chunks),(pixels,meta)=>seen.push([meta.sequence,[...pixels]])),2);assert.deepEqual(seen,[[0,Array(16).fill(7)],[1,Array(16).fill(7)]]);});
test("rejects truncation, bad clocks and unsafe metadata",async()=>{const broken=frame(0);await assert.rejects(consumeWgcFrames(Readable.from([broken.subarray(0,-1)]),()=>{}),/WGC_TRUNCATED/);await assert.rejects(consumeWgcFrames(Readable.from([frame(0),frame(1,100)]),()=>{}),/WGC_CLOCK/);await assert.rejects(consumeWgcFrames(Readable.from([frame(0,100,{alphaMode:"ignore"})]),()=>{}),/WGC_ALPHA_MODE/);});

test("rejects a stream exceeding its capture window",async()=>{await assert.rejects(consumeWgcFrames(Readable.from([frame(0,100),frame(1,260000101)]),()=>{}),/WGC_DURATION_BOUND/);});

test("refuses frame count, source-size, and receipt-clock violations",async()=>{const many=Array.from({length:521},(_,i)=>frame(i,100+i));await assert.rejects(consumeWgcFrames(Readable.from(many),()=>{}),/WGC_FRAME_LIMIT/);await assert.rejects(consumeWgcFrames(Readable.from([frame(0,100,{sourceWidth:4096,sourceHeight:4096,sourceStride:16384})]),()=>{}));await assert.rejects(consumeWgcFrames(Readable.from([frame(0,100,{receiptMs:2}),frame(1,101,{receiptMs:1})]),()=>{}),/WGC_RECEIPT_CLOCK/);});

test("analysis canvas matches even export dimensions and rejects impossible bounds",()=>{
 assert.deepEqual(expectedAnalysisSize(1918,830),{width:640,height:276});
 assert.deepEqual(expectedAnalysisSize(959,415),{width:640,height:276});
 assert.deepEqual(expectedAnalysisSize(639,399),{width:638,height:398});
 assert.throws(()=>expectedAnalysisSize(1,1),/WGC_ANALYSIS_SIZE/);
 assert.throws(()=>expectedAnalysisSize(2,4000),/WGC_ANALYSIS_SIZE/);
});
test("rejects odd and mismatched analysis dimensions",async()=>{
 await assert.rejects(consumeWgcFrames(Readable.from([frame(0,100,{width:1})]),()=>{}),/WGC_ANALYSIS_WIDTH/);
 await assert.rejects(consumeWgcFrames(Readable.from([frame(0,100,{height:1})]),()=>{}),/WGC_ANALYSIS_HEIGHT/);
});
