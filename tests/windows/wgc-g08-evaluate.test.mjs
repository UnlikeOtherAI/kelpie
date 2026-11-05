import test from "node:test";import assert from "node:assert/strict";import {Readable} from "node:stream";
import {evaluateWgcFrames} from "./wgc-g08-evaluate.mjs";
test("empty actual stream is insufficient, regardless of supplied pass claims",async()=>{
 const cfg={curve:"c",color:"#ff0000",pointerMs:2400,markerMs:3000,radius:48,from:{x:1,y:1},to:{x:2,y:1},viewport:{width:640,height:400}};
 await assert.rejects(evaluateWgcFrames(Readable.from([]),cfg),/Invalid uniform capture scale|INSUFFICIENT/);
});

test("one valid sealed frame remains insufficient",async()=>{const meta=Buffer.from(JSON.stringify({sequence:0,tick100ns:100,receiptMs:1,width:320,height:180,sourceWidth:320,sourceHeight:180,sourceStride:1280,alphaMode:"straight"}));const head=Buffer.alloc(8);head.writeUInt32LE(meta.length);head.writeUInt32LE(320*180*4,4);const pixels=Buffer.alloc(320*180*4);const cfg={curve:"c",color:"#ff0000",pointerMs:2400,markerMs:3000,radius:24,from:{x:64,y:90},to:{x:256,y:90},viewport:{width:320,height:180}};await assert.rejects(evaluateWgcFrames(Readable.from([head,meta,pixels]),cfg),/INSUFFICIENT/);});
