#!/usr/bin/env node
// Compare one fixed synthetic fixture ROI on the same admitted and decoded frames.
import assert from "node:assert/strict";
import { ffmpegPassthrough } from "../capture/ffmpeg-passthrough.mjs";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { redMarkerPixels } from "./red-marker-pixels.mjs";

const [tracePath,roiDir,videoPath,mediaInputPath,outputPath]=process.argv.slice(2);
assert.ok(tracePath && roiDir && videoPath && mediaInputPath && outputPath,"trace, ROI directory, MP4, media input and output required");
const sha=bytes=>createHash("sha256").update(bytes).digest("hex");
const media=JSON.parse(await readFile(mediaInputPath,"utf8"));
const event=media.checks.find(row=>row.name.startsWith("continuous "))?.detail?.event;
assert.ok(event?.trusted && event.hit==="unique");
const videoItem=media.artifacts.find(item=>item.file===videoPath && item.mimeType==="video/mp4");
assert.ok(videoItem);
const scale=videoItem.width/event.viewport.width;
const radius=Math.ceil(24*scale+3);
assert.equal(Math.floor(event.x*scale-radius),70);
assert.equal(Math.floor(event.y*scale-radius),85);
assert.equal(2*radius+1,45);
const traceBytes=await readFile(tracePath);
const trace=traceBytes.toString("utf8").trim().split("\n").map(line=>JSON.parse(line));
const samples=trace.filter(row=>row.phase===0 && row.due===1);
const terminal=trace.filter(row=>row.phase===1);
assert.equal(terminal.length,1);
assert.ok(samples.length>0 && samples.length<=1200);
assert.equal(terminal[0].videoDropped,0);
assert.equal(terminal[0].videoFrames,samples.length);
for(const [index,row] of samples.entries()) {
  assert.equal(row.admittedIndex,index);
  assert.ok(Number.isFinite(row.elapsedMs));
  if(index) assert.ok(row.elapsedMs>samples[index-1].elapsedMs);
}
const run=(command,args,maxBuffer=16777216)=>{
  const result=spawnSync(command,args,{timeout:30000,maxBuffer});
  assert.equal(result.status,0,result.stderr?.toString()??result.error?.message);
  return result.stdout;
};
const pts=run("ffprobe",["-v","error","-select_streams","v:0","-show_entries",
  "frame=best_effort_timestamp_time","-of","csv=p=0",videoPath]).toString().trim().split("\n")
  .map(line=>Number(line.trim().split(",")[0]));
assert.equal(pts.length,samples.length);
const first=samples[0].elapsedMs;
for(const [index,point] of pts.entries()) {
  assert.ok(Number.isFinite(point));
  assert.ok(Math.abs(point-(samples[index].elapsedMs-first)/1000)<0.002,"PTS mismatch");
}
const index=samples.length-1;
assert.equal(samples[index].hasMarker,1);
assert.ok(samples[index].markerAgeMs>=samples[index].markerDurationMs,"source frame precedes expiry");
const source=await readFile(join(roiDir,"sample-"+String(index).padStart(4,"0")+".bgra"));
const size=45*45*4; assert.equal(source.length,size*2);
const rgb=bytes=>{const result=Buffer.alloc(45*45*3);for(let i=0;i<45*45;i++) {
  result[i*3]=bytes[i*4+2]; result[i*3+1]=bytes[i*4+1]; result[i*3+2]=bytes[i*4];
} return result;};
const before=rgb(source.subarray(0,size)),after=rgb(source.subarray(size));
const decoded=run("ffmpeg",["-v","error","-threads","1","-i",videoPath,
  "-vf","format=rgb24,crop=45:45:70:85:exact=1",...ffmpegPassthrough("ffmpeg"),
  "-f","rawvideo","-pix_fmt","rgb24","-"]);
const decodedFrameSize=45*45*3;
assert.equal(decoded.length,decodedFrameSize*samples.length);
const tail=decoded.subarray(decoded.length-decodedFrameSize);
const video=await readFile(videoPath);
assert.equal(sha(video),videoItem.sha256);
const report={traceSHA256:sha(traceBytes),videoSHA256:sha(video),sourceSHA256:sha(source),
  runId:videoItem.runId,artifactId:videoItem.id,documentId:videoItem.documentId,
  crop:{left:70,top:85,width:45,height:45},frameCount:samples.length,
  final:{index,elapsedMs:samples[index].elapsedMs,pts:pts[index],markerAgeMs:samples[index].markerAgeMs,
    markerDurationMs:samples[index].markerDurationMs,before:redMarkerPixels(before,45,45),
    after:redMarkerPixels(after,45,45),decoded:redMarkerPixels(tail,45,45)}};
await writeFile(outputPath,JSON.stringify(report,null,2)+"\n",{flag:"wx"});
