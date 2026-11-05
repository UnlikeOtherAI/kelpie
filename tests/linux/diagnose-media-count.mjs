// Diagnostic-only: retain the first synthetic artifact whose decoded frame count differs.
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFile, writeFile, copyFile, realpath, stat } from "node:fs/promises";
import { join, resolve, sep } from "node:path";
import { redMarkerPixels } from "./red-marker-pixels.mjs";
const rawDirectory=process.argv[2];
if(!rawDirectory || process.argv[3]!=="--synthetic-fixture") throw Error("DIAGNOSTIC_REQUIRED");
const directory=resolve(rawDirectory);
const report=JSON.parse(await readFile(join(directory,"combined-media-input.json"),"utf8"));
const root=await realpath(directory); let mismatch=null;
for(const item of report.artifacts) {
  if(item.frameCount===undefined) continue;
  const path=await realpath(item.file);
  if(!path.startsWith(root+sep)) throw Error("ARTIFACT_OUTSIDE_DIAGNOSTIC");
  const info=await stat(path); if(!info.isFile() || info.size>16777216) throw Error("DIAGNOSTIC_BYTE_LIMIT");
  const bytes=await readFile(path); const digest=createHash("sha256").update(bytes).digest("hex");
  if(digest!==item.sha256) throw Error("ARTIFACT_HASH_MISMATCH");
  const probe=spawnSync("ffprobe",["-v","error","-select_streams","v:0","-count_frames","-show_frames",
    "-show_entries","frame=best_effort_timestamp_time:stream=nb_read_frames","-of","json",path],{timeout:30000,maxBuffer:1048576});
  if(probe.status!==0) throw Error("FFPROBE_FAILED");
  const parsed=JSON.parse(probe.stdout.toString()), count=Number(parsed.streams[0].nb_read_frames);
  const pts=parsed.frames.map(frame=>Number(frame.best_effort_timestamp_time));
  if(!Number.isSafeInteger(count) || count<0 || pts.length!==count || !pts.every(Number.isFinite)) throw Error("INVALID_PROBE");
  if(count!==item.frameCount) {
    if(!["image/gif","video/mp4"].includes(item.mimeType)) throw Error("INVALID_MEDIA_TYPE");
    const name=item.mimeType==="image/gif"?"count-mismatch.gif":"count-mismatch.mp4";
    await copyFile(path,join(directory,name),1);
    mismatch={id:item.id,sha256:digest,mimeType:item.mimeType,manifestFrames:item.frameCount,decodedFrames:count,pts,byteLength:info.size,file:name};
    break;
  }
}
if(!mismatch) {
  let continuous;
  try { continuous=JSON.parse(await readFile(join(directory,"continuous-media-input.json"),"utf8")); }
  catch(error) { if(error.code!=="ENOENT") throw error; }
  const event=continuous?.checks.find(check=>check.name.startsWith("continuous "))?.detail?.event;
  if(continuous && (!event?.trusted || event.hit!=="unique")) throw Error("INVALID_SYNTHETIC_FIXTURE");
  for(const item of continuous?.artifacts ?? []) {
    if(!["image/gif","video/mp4"].includes(item.mimeType)) continue;
    const path=await realpath(item.file); if(!path.startsWith(root+sep)) throw Error("ARTIFACT_OUTSIDE_DIAGNOSTIC");
    const info=await stat(path); if(!info.isFile() || info.size>16777216) throw Error("DIAGNOSTIC_BYTE_LIMIT");
    const bytes=await readFile(path),digest=createHash("sha256").update(bytes).digest("hex");
    if(digest!==item.sha256) throw Error("ARTIFACT_HASH_MISMATCH");
    const scale=item.width/event.viewport.width,radius=Math.ceil(24*scale+3);
    const left=Math.max(0,Math.floor(event.x*scale-radius)),top=Math.max(0,Math.floor(event.y*scale-radius));
    const width=Math.min(item.width-left,2*radius+1),height=Math.min(item.height-top,2*radius+1);
    if(![left,top,width,height].every(Number.isSafeInteger) || width<=0 || height<=0 || width*height>65536) throw Error("INVALID_CROP");
    const decoded=spawnSync("ffmpeg",["-v","error","-threads","1","-i",path,"-vf",`format=rgb24,crop=${width}:${height}:${left}:${top}:exact=1`,
      "-vsync","0","-f","rawvideo","-pix_fmt","rgb24","-"],{timeout:30000,maxBuffer:16777216});
    if(decoded.status!==0 || decoded.stdout.length%(width*height*3)) throw Error("FRAME_DECODE_FAILED");
    const frameSize=width*height*3,frameCount=decoded.stdout.length/frameSize;
    if(!frameCount) throw Error("FRAME_DECODE_EMPTY");
    const tail=redMarkerPixels(decoded.stdout.subarray((frameCount-1)*frameSize),width,height);
    if(tail.count) {
      const probe=spawnSync("ffprobe",["-v","error","-select_streams","v:0","-show_frames","-show_entries","frame=best_effort_timestamp_time","-of","json",path],{timeout:30000,maxBuffer:1048576});
      if(probe.status!==0) throw Error("FFPROBE_FAILED");
      const pts=JSON.parse(probe.stdout.toString()).frames.map(frame=>Number(frame.best_effort_timestamp_time));
      if(pts.length!==frameCount || !pts.every(Number.isFinite)) throw Error("INVALID_PROBE");
      const name=item.mimeType==="image/gif"?"count-mismatch.gif":"count-mismatch.mp4";
      await copyFile(path,join(directory,name),1);
      mismatch={kind:"marker-tail",id:item.id,sha256:digest,mimeType:item.mimeType,manifestFrames:item.frameCount,decodedFrames:frameCount,pts,byteLength:info.size,file:name,crop:{left,top,width,height},redPixels:tail};
      break;
    }
  }
}
await writeFile(join(directory,"count-mismatch.json"),JSON.stringify({mismatch},null,2)+"\n",{flag:"wx"});
