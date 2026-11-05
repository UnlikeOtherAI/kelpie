import test from "node:test";import assert from "node:assert/strict";import {Readable} from "node:stream";
import {evaluateWgcFrames} from "./wgc-g08-evaluate.mjs";
test("empty actual stream is insufficient, regardless of supplied pass claims",async()=>{
 const cfg={curve:"c",color:"#ff0000",pointerMs:2400,markerMs:3000,radius:48,from:{x:1,y:1},to:{x:2,y:1},viewport:{width:640,height:400}};
 const result=await evaluateWgcFrames(Readable.from([]),cfg);assert.equal(result.analysis,null);assert.match(result.oracleError,/INSUFFICIENT/);
});

test("one valid sealed frame remains insufficient",async()=>{const meta=Buffer.from(JSON.stringify({sequence:0,tick100ns:100,receiptMs:1,width:320,height:180,sourceWidth:320,sourceHeight:180,sourceStride:1280,alphaMode:"straight"}));const head=Buffer.alloc(8);head.writeUInt32LE(meta.length);head.writeUInt32LE(320*180*4,4);const pixels=Buffer.alloc(320*180*4);const cfg={curve:"c",color:"#ff0000",pointerMs:2400,markerMs:3000,radius:24,from:{x:64,y:90},to:{x:256,y:90},viewport:{width:320,height:180}};const result=await evaluateWgcFrames(Readable.from([head,meta,pixels]),cfg);assert.equal(result.analysis,null);assert.match(result.oracleError,/INSUFFICIENT/);});

test("350 ms profile retains observations without claiming dense oracle coverage",async()=>{
 const meta=Buffer.from(JSON.stringify({sequence:0,tick100ns:100,receiptMs:1,width:320,height:180,sourceWidth:320,sourceHeight:180,sourceStride:1280,alphaMode:"straight"}));
 const head=Buffer.alloc(8);head.writeUInt32LE(meta.length);head.writeUInt32LE(320*180*4,4);
 const cfg={curve:"c",color:"#ff0000",pointerMs:350,markerMs:3000,radius:24,from:{x:64,y:90},to:{x:256,y:90},viewport:{width:320,height:180}};
 let progress;const result=await evaluateWgcFrames(Readable.from([head,meta,Buffer.alloc(320*180*4)]),cfg,{onProgress:value=>{progress=value;}});assert.equal(progress.frameCount,1);assert.equal(progress.shape,"320:180");
 assert.equal(result.frameCount,1);assert.equal(result.analysis,null);assert.equal(result.oracleError,"FAST_PROFILE_NOT_DENSE");
});

test("preserves observed samples when a later frame is truncated",async()=>{
 const meta=Buffer.from(JSON.stringify({sequence:0,tick100ns:100,receiptMs:1,width:320,height:180,sourceWidth:320,sourceHeight:180,sourceStride:1280,alphaMode:"straight"}));
 const head=Buffer.alloc(8);head.writeUInt32LE(meta.length);head.writeUInt32LE(320*180*4,4);
 const cfg={curve:"c",color:"#ff0000",pointerMs:2400,markerMs:3000,radius:24,from:{x:64,y:90},to:{x:256,y:90},viewport:{width:320,height:180}};
 let progress;await assert.rejects(evaluateWgcFrames(Readable.from([head,meta,Buffer.alloc(320*180*4),Buffer.from([1])]),cfg,{onProgress:value=>{progress=value;}}),/WGC_TRUNCATED/);
 assert.equal(progress.frameCount,1);assert.equal(progress.samples.length,1);
});

test("owned layered BGRA uses calibrated premultiplied analysis while retaining API label",async()=>{
 const meta=Buffer.from(JSON.stringify({sequence:0,tick100ns:100,receiptMs:1,width:320,height:180,sourceWidth:320,sourceHeight:180,sourceStride:1280,alphaMode:"straight"}));
 const head=Buffer.alloc(8);head.writeUInt32LE(meta.length);head.writeUInt32LE(320*180*4,4);
 const pixels=Buffer.alloc(320*180*4);
 for(let y=75;y<106;y++)for(let x=241;x<272;x++){const i=(y*320+x)*4;pixels[i+2]=178;pixels[i+3]=178;}
 const cfg={curve:"c",color:"#ff0000",pointerMs:2400,markerMs:3000,radius:24,from:{x:64,y:90},to:{x:256,y:90},viewport:{width:320,height:180}};
 const result=await evaluateWgcFrames(Readable.from([head,meta,pixels]),cfg);
 assert.equal(result.samples[0].reportedAlphaMode,"straight");
 assert.equal(result.samples[0].analysisAlphaMode,"premultiplied");
 assert.ok(result.samples[0].marker.alpha>0.65);
 pixels[(90*320+256)*4+2]=255;
 await assert.rejects(evaluateWgcFrames(Readable.from([head,meta,pixels]),cfg),/INVALID_PREMULTIPLIED_ALPHA/);
});