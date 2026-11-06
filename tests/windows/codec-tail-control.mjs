import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {execFile} from "node:child_process";
import {readFile,writeFile} from "node:fs/promises";
import {join,resolve} from "node:path";
import {promisify} from "node:util";

const [directoryArg,binaryArg,source]=process.argv.slice(2);
assert.ok(directoryArg&&binaryArg&&/^[a-f0-9]{40}$/.test(source));
assert.ok(process.env.FFMPEG&&process.env.FFPROBE);
const directory=resolve(directoryArg),binary=resolve(binaryArg),exec=promisify(execFile);
const hash=async file=>createHash("sha256").update(await readFile(file)).digest("hex");
const rawClean=join(directory,"clean.bgra"),rawMarked=join(directory,"marked.bgra");
const clean=await readFile(rawClean),marked=await readFile(rawMarked);
assert.equal(clean.length,640*406*4);assert.equal(marked.length,clean.length);assert.ok(!clean.equals(marked));
const report={source,scope:"synthetic production writer; no browser or live capture",fps:20,framesPerCase:40,
 binarySha256:await hash(binary),ffmpegSha256:await hash(process.env.FFMPEG),ffprobeSha256:await hash(process.env.FFPROBE),
 cleanInputSha256:await hash(rawClean),markerInputSha256:await hash(rawMarked),cases:[]};
report.inputSourceHashes={};
for(const path of ["apps/windows/tests/script_media_tail_control.cpp","apps/windows/src/script_media_encoder.cpp",
 "apps/windows/src/script_media_gif.cpp","apps/windows/src/script_media_video.cpp","apps/windows/src/script_media_png.cpp"])
 report.inputSourceHashes[path]=await hash(path);
function compare(a,b){
 let changedPixels=0,maxChannelDifference=0,sum=0,pixels=0;
 for(let y=161;y<=245;y++)for(let x=438;x<=522;x++){
  const offset=(y*640+x)*3;let changed=false;
  for(let channel=0;channel<3;channel++){
   const delta=Math.abs(a[offset+channel]-b[offset+channel]);sum+=delta;
   maxChannelDifference=Math.max(maxChannelDifference,delta);if(delta)changed=true;
  }
  if(changed)changedPixels++;pixels++;
 }
 return {pixels,changedPixels,maxChannelDifference,meanAbsoluteChannelDifference:sum/(pixels*3)};
}
for(const name of ["clean-only","marker-then-clean"]){
 const item={name,outputs:[]};report.cases.push(item);
 for(const extension of ["gif","mp4"]){
  const file=join(directory,name,"capture."+extension),bytes=await readFile(file);
  assert.ok(bytes.length>0&&bytes.length<=33554432);
  const probe=await exec(process.env.FFPROBE,["-v","error","-select_streams","v:0","-show_frames",
   "-show_entries","frame=best_effort_timestamp_time:stream=width,height","-of","json",file],{timeout:30000,maxBuffer:1048576,windowsHide:true});
  const metadata=JSON.parse(probe.stdout);assert.equal(metadata.streams[0].width,640);assert.equal(metadata.streams[0].height,406);
  const pts=metadata.frames.map(frame=>Number(frame.best_effort_timestamp_time));assert.equal(pts.length,40);
  for(let index=0;index<40;index++)assert.ok(Number.isFinite(pts[index])&&Math.abs(pts[index]-index*.05)<.011);
  const decoded=await exec(process.env.FFMPEG,["-v","error","-threads","1","-filter_threads","1","-i",file,
   "-vf","select=eq(n\\,3)+eq(n\\,15)+eq(n\\,35)","-fps_mode","passthrough","-frames:v","3",
   "-f","rawvideo","-pix_fmt","rgb24","pipe:1"],{encoding:"buffer",timeout:30000,maxBuffer:640*406*3*3+1024,windowsHide:true});
  const size=640*406*3;assert.equal(decoded.stdout.length,size*3);
  const frame=index=>decoded.stdout.subarray(index*size,(index+1)*size);
  item.outputs.push({mimeType:extension,sha256:await hash(file),byteLength:bytes.length,ptsSeconds:[pts[3],pts[15],pts[35]],
   baselineToMiddle:compare(frame(0),frame(1)),baselineToTail:compare(frame(0),frame(2))});
 }
}
await writeFile(join(directory,"analysis.json"),JSON.stringify(report,null,2),{flag:"wx"});
