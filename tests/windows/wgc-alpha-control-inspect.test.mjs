import test from "node:test";
import assert from "node:assert/strict";
import {inspectAlphaControl} from "./wgc-alpha-control-inspect.mjs";
test("observed 2x WGC control preserves partial, opaque and clear patch bytes",()=>{
 const width=640,height=320,raw=Buffer.alloc(width*height*4),png=Buffer.alloc(raw.length);
 const blocks=[[0,200,[0,0,178,178]],[200,400,[0,89,0,89]],[400,600,[255,0,0,255]]];
 for(const [left,right,pixel] of blocks)for(let y=0;y<height;y++)for(let x=left;x<right;x++){
  const i=(y*width+x)*4;raw.set(pixel,i);png.set([pixel[2],pixel[1],pixel[0],pixel[3]],i);
 }
 const patches=inspectAlphaControl(raw,png,width,height);
 for(const patch of patches)for(const point of patch.samples)assert.deepEqual(point.rawBgra,patch.inputBgra);
 assert.deepEqual(patches[0].samples[0].whiteStraight,[201,77,77]);
 assert.deepEqual(patches[0].samples[0].whitePremultiplied,[255,77,77]);
 assert.deepEqual(patches[1].samples[0].whitePremultiplied,[166,255,166]);
 assert.deepEqual(patches[2].samples[0].whitePremultiplied,[0,0,255]);
 assert.deepEqual(patches[3].samples[0].whitePremultiplied,[255,255,255]);
});
test("different aspect ratios and invalid buffer sizes fail closed",()=>{
 assert.throws(()=>inspectAlphaControl(Buffer.alloc(1),Buffer.alloc(1),640,300),/CONTROL_ASPECT_CHANGED/);
});
