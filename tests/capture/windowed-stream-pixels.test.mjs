import test from "node:test";
import assert from "node:assert/strict";
import {measureWindowedStreamFrame} from "./windowed-stream-pixels.mjs";

function frame(nonce){
 const width=640,height=400,rgb=new Uint8Array(width*height*3).fill(255);
 function fill(x0,y0,w,h,color){for(let y=y0;y<y0+h;y++)for(let x=x0;x<x0+w;x++)rgb.set(color,(y*width+x)*3);}
 for(let index=0;index<16;index++)if(nonce&(1<<index))fill(10+index*8,10,8,8,[0,0,0]);
 fill(138,10,8,8,[0,0,0]);fill(30,120,30,30,[245,34,51]);
 return {rgb,width,height,viewport:{width,height}};
}
test("extracts a real synthetic dot only with the matching visual nonce",()=>{
 const input=frame(0xa19e);
 assert.deepEqual(measureWindowedStreamFrame(input.rgb,input.width,input.height,input.viewport,0xa19e),
  {x:45,y:135,pixelCount:900});
 assert.throws(()=>measureWindowedStreamFrame(input.rgb,input.width,input.height,input.viewport,0xa19f),/STREAM_NONCE_MISMATCH/);
});
test("refuses missing reference and malformed pixels",()=>{
 const input=frame(7);input.rgb.fill(255,(14*640+142)*3,(14*640+142)*3+3);
 assert.throws(()=>measureWindowedStreamFrame(input.rgb,input.width,input.height,input.viewport,7),/STREAM_NONCE_REFERENCE/);
 assert.throws(()=>measureWindowedStreamFrame(new Uint8Array(2),640,400,input.viewport,7));
});
