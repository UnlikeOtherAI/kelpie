#!/usr/bin/env node
// Synthetic codec mechanism only; never attributes previously recorded frames.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { ffmpegPassthrough } from "../capture/ffmpeg-passthrough.mjs";
import { redMarkerPixels } from "./red-marker-pixels.mjs";

const [root,output,baselineRoot]=process.argv.slice(2);assert.ok(root&&output);
const hash=bytes=>createHash("sha256").update(bytes).digest("hex");
const pts=[
 [0,.266393,.498066,.731110,.945517,1.199273,1.399336,1.598874,1.866598,2.067556,2.295128,2.505635,2.721153,2.999615,3.206449],
 [0,.265986,.498659,.732797,.951810,1.199477,1.466689,1.667739,1.933402,2.166241,2.398606,2.599386,2.824673,3.065929,3.264412],
];
const exec=(cmd,args)=>{
 const result=spawnSync(cmd,args,{timeout:30000,maxBuffer:16777216});
 assert.equal(result.status,0,result.stderr?.toString()??result.error?.message);return result.stdout;
};
const pairs=[];
for (const [timing,expected] of pts.entries()) {
 const row={timing:timing?"replay":"original"};
 for (const name of ["clear","history"]) {
  const dir=join(root,row.timing+"-"+name),video=join(dir,"capture.mp4");
  const raw=await readFile(join(dir,"final.bgra"));assert.equal(raw.length,1000*702*4);
  const decoded=exec("ffmpeg",["-v","error","-threads","1","-i",video,
   "-vf","format=rgb24,crop=45:45:70:85:exact=1",...ffmpegPassthrough("ffmpeg"),
   "-f","rawvideo","-pix_fmt","rgb24","-"]);
  const size=45*45*3;assert.equal(decoded.length,size*15);
  const actual=exec("ffprobe",["-v","error","-select_streams","v:0","-show_entries",
   "frame=best_effort_timestamp_time","-of","csv=p=0",video]).toString().trim().split("\n")
   .map(line=>Number(line.trim().split(",")[0]));
  assert.equal(actual.length,15);
  for(const [i,value] of actual.entries())assert.ok(Number.isFinite(value)&&Math.abs(value-expected[i])<0.002);
  const counts=[];for(let i=0;i<15;i++)counts.push(redMarkerPixels(decoded.subarray(i*size,(i+1)*size),45,45));
  const pngSHA256=[];for(let i=0;i<6;i++)pngSHA256.push(hash(await readFile(join(dir,"step-"+i+".png"))));
  const videoBytes=await readFile(video);
  row[name]={rawSHA256:hash(raw),videoSHA256:hash(videoBytes),videoBytes:videoBytes.length,
    gifSHA256:hash(await readFile(join(dir,"capture.gif"))),pngSHA256,pts:actual,frames:counts};
  if (baselineRoot) {
   const baseline=join(baselineRoot,row.timing+"-"+name);
   assert.ok(raw.equals(await readFile(join(baseline,"final.bgra"))),"baseline raw frame differs");
   const baselineVideo=await readFile(join(baseline,"capture.mp4"));
   row[name].baselineVideoBytes=baselineVideo.length;
   row[name].videoByteDelta=videoBytes.length-baselineVideo.length;
   const key=exec("ffprobe",["-v","error","-select_streams","v:0","-show_entries","frame=key_frame",
    "-of","csv=p=0",video]).toString().trim().split("\n").map(line=>Number(line.trim().split(",")[0]));
   assert.equal(key.length,15);assert.equal(key.at(-1),1,"final frame is not a keyframe");
   assert.equal(counts.at(-1).count,0,"forced final frame retains red pixels");
   row[name].finalKeyFrame=true;
  }
 }
 assert.equal(row.clear.rawSHA256,row.history.rawSHA256,"final full raw frames differ");
 assert.ok(row.clear.frames.every(frame=>frame.count===0),"clear control contains red pixels");
 assert.ok(row.history.frames.slice(0,-1).some(frame=>frame.count>0),"history did not visibly stimulate encoder");
 pairs.push(row);
}
await writeFile(output,JSON.stringify({scope:"synthetic-codec-mechanism",pairs},null,2)+"\n",{flag:"wx"});
