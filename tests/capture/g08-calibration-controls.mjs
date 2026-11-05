import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {createReadStream} from "node:fs";
import {spawn} from "node:child_process";
import {resolve} from "node:path";
import {consumeG08Frames} from "./g08-frame-stream.mjs";
import {measureG08Frame} from "./g08-pixels.mjs";
import {sameG08Pixels} from "./g08-calibration.mjs";
// Independently generated, same-file pointer-overlap controls: frame zero is
// pre-marker; frames 26-29 are either clear or intentionally retained.
const dir=process.argv[2];assert.ok(dir,"Provide the owned control directory");
const results=[];
for(const name of ["pointer","pointer-small","pointer-faint","pointer-full"]){
 const file=resolve(dir,name+".gif"),hash=createHash("sha256");
 for await(const bytes of createReadStream(file))hash.update(bytes);
 const child=spawn(process.env.FFMPEG??"ffmpeg",["-v","error","-threads","1","-i",file,
  "-map","0:v:0","-fps_mode","passthrough","-f","rawvideo","-pix_fmt","rgb24","-"],
  {windowsHide:true,stdio:["ignore","pipe","pipe"]});
 let stderr="";child.stderr.on("data",chunk=>{if(stderr.length<4096)stderr+=chunk.toString().slice(0,4096-stderr.length)});
 const exited=new Promise((resolve,reject)=>{child.once("error",reject);child.once("close",code=>code===0?resolve():reject(Error("Decoder failed "+code+" "+stderr)))});
 void exited.catch(()=>{});
 let baseline,tail=[];
 try{
  const count=await consumeG08Frames(child.stdout,640,450,(frame,index)=>{
   if(index===0||index>=26&&index<=29){
    const measured=measureG08Frame(frame,640,450,{center:{x:480,y:225},radius:24,color:"#0000ff"});
    if(index===0)baseline=measured.marker.roi;
    else tail.push(sameG08Pixels(baseline,measured.marker.roi));
   }
  });
  await exited;assert.equal(count,30);assert.equal(tail.length,4);
  assert.ok(tail.every(same=>same===(name==="pointer")),"Calibration control did not separate "+name);
  results.push({name,sha256:hash.digest("hex"),baselineMatches:tail});
 }finally{if(child.exitCode===null)child.kill();await exited.catch(()=>{})}
}
console.log(JSON.stringify({results}));
