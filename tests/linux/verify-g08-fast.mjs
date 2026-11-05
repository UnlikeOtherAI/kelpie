// Decode the separate omitted-duration capture and fit only measured pointer pixels.
import assert from "node:assert/strict";
import { ffmpegPassthrough } from "../capture/ffmpeg-passthrough.mjs";
import { readFile, writeFile, stat } from "node:fs/promises";
import { createHash } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { consumeG08Frames } from "../capture/g08-frame-stream.mjs";
import { measureG08Frame } from "../capture/g08-pixels.mjs";
import { validateG08PTS } from "../capture/g08-pts.mjs";
import { fitFastPointer } from "../capture/g08-fast-profile.mjs";

const [inputPath,outputPath]=process.argv.slice(2);
assert.ok(inputPath && outputPath);
const input=JSON.parse(await readFile(inputPath,"utf8"));
assert.equal(input.profile,"default");assert.equal(input.eventsDropped,0);
assert.match(input.source,/^[a-f0-9]{40}$/);assert.match(input.binarySHA256,/^[a-f0-9]{64}$/);
assert.ok(["linux-osr-cef","linux-gtk-cef"].includes(input.runtime));
const output={source:input.source,binarySHA256:input.binarySHA256,runtime:input.runtime,profile:input.profile,results:[]};
for(const item of input.cases){
 assert.ok(["c","s"].includes(item.curve));assert.equal(Object.hasOwn(item.pointer,"durationMs"),false);
 const {start,finish}=item.scene;assert.equal(start.documentId,finish.documentId);
 assert.deepEqual(start.viewport,finish.viewport);assert.ok(start.trusted && finish.trusted);
 for(const artifact of item.artifacts){
  const result={curve:item.curve,mimeType:artifact.mimeType,sha256:artifact.sha256,droppedFrames:artifact.droppedFrames,samples:[]};output.results.push(result);
  try {
   assert.ok(["image/gif","video/mp4"].includes(artifact.mimeType));
   assert.ok(artifact.byteLength>0 && artifact.byteLength<=33554432);
   assert.equal((await stat(artifact.file)).size,artifact.byteLength);
   assert.equal(createHash("sha256").update(await readFile(artifact.file)).digest("hex"),artifact.sha256);
   const probe=spawnSync("ffprobe",["-v","error","-select_streams","v:0","-show_frames","-show_entries","frame=best_effort_timestamp_time:stream=width,height","-of","json",resolve(artifact.file)],{timeout:30000,maxBuffer:1048576});
   assert.equal(probe.status,0);const timestamps=validateG08PTS(JSON.parse(probe.stdout.toString()),artifact);
   const sx=artifact.width/start.viewport.width,sy=artifact.height/start.viewport.height;
   assert.ok(sx>0&&sy>0&&Math.abs(sx-sy)<0.03);
   const marker={center:{x:finish.center.x*sx,y:finish.center.y*sy},radius:48*sx,color:item.curve==="c"?"#ff0000":"#0000ff"};
   const child=spawn("ffmpeg",["-v","error","-threads","1","-filter_threads","1","-i",resolve(artifact.file),"-map","0:v:0",...ffmpegPassthrough("ffmpeg"),"-f","rawvideo","-pix_fmt","rgb24","-"],{stdio:["ignore","pipe","pipe"]});
   let stderr="";child.stderr.on("data",chunk=>{stderr+=chunk.toString().slice(0,Math.max(0,4096-stderr.length));});
   const done=new Promise((yes,no)=>{child.once("error",no);child.once("close",code=>code===0?yes():no(Error("DECODER_FAILED "+stderr)));});void done.catch(()=>{});
   const timer=setTimeout(()=>child.kill(),120000);
   try {
    const count=await consumeG08Frames(child.stdout,artifact.width,artifact.height,(frame,index)=>{
     assert.ok(index<timestamps.length);const measured=measureG08Frame(frame,artifact.width,artifact.height,marker);
     if(measured.pointer)result.samples.push({timeMs:timestamps[index]*1000,x:measured.pointer.x/sx,y:measured.pointer.y/sy});
    });
    await done;assert.equal(count,timestamps.length);
   } finally {clearTimeout(timer);if(child.exitCode===null)child.kill();await done.catch(()=>{});}
   result.fit=fitFastPointer(result.samples,{from:start.center,to:finish.center,curve:item.curve});result.passed=true;
  } catch(error){result.passed=false;result.error=String(error.message).slice(0,1024);}
 }
}
await writeFile(outputPath,JSON.stringify(output,null,2)+"\n",{flag:"wx"});
process.exitCode=output.results.length===4&&output.results.every(item=>item.passed)?0:1;
