import test from "node:test";
import assert from "node:assert/strict";
import {execFileSync} from "node:child_process";
import {mkdtemp,rm} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import {inspectCurve} from "./runtime-media.mjs";

// Synthetic H.264 control only: exercise the unchanged global-pixel oracle after encoding.
test("bright animated damage preserves C classifier while dark contamination is rejected",async()=>{
 const directory=await mkdtemp(path.join(os.tmpdir(),"kelpie-overlay-oracle-"));
 try{
  const width=640,height=498,frames=31,scene={width:900,height:700,first:{x:55,y:245},second:{x:555,y:75}};
  const encode=negative=>{
   const raw=Buffer.alloc(width*height*3*frames,255);
   const rect=(frame,x,y,w,h,color)=>{
    for(let row=y;row<y+h;row++)for(let column=x;column<x+w;column++){
     const offset=((frame*height+row)*width+column)*3;
     raw[offset]=color[0];raw[offset+1]=color[1];raw[offset+2]=color[2];
    }
   };
   for(let i=0;i<frames;i++){
    const t=i/(frames-1),x=Math.floor(39+356*t),y=Math.floor(174-121*t+60*4*t*(1-t));
    rect(i,Math.floor(60+380*t),85,21,21,[248,223,69]);
    rect(i,x,y,7,10,[0,0,0]);
    if(i<5)rect(i,60,220,10,10,[34,204,255]);
    if(negative)rect(i,2,300,3,30,[0,0,0]);
   }
   const file=path.join(directory,negative?"negative.mp4":"positive.mp4");
   execFileSync("ffmpeg",["-v","error","-y","-f","rawvideo","-pixel_format","rgb24","-video_size","640x498",
    "-framerate","15","-i","-","-c:v","libx264","-pix_fmt","yuv420p","-crf","23",file],
   {input:raw,maxBuffer:1048576});
   return {file,width,height};
  };
  const result=inspectCurve(encode(false),"c",scene);
  assert.ok(result.pointerSamples>8&&result.maximum>15&&result.endpointError<8);
  assert.throws(()=>inspectCurve(encode(true),"c",scene),error=>error.code==="CURVE_POINTER_SAMPLES");
 }finally{await rm(directory,{recursive:true,force:true});}
});
