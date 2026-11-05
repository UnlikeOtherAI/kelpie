// Diagnostic-only: retain the first synthetic artifact whose decoded frame count differs.
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFile, writeFile, copyFile, realpath, stat } from "node:fs/promises";
import { join, resolve, sep } from "node:path";
const rawDirectory=process.argv[2];
if(!rawDirectory || process.env.KELPIE_LINUX_RESOURCE_DIAGNOSTIC!=="1") throw Error("DIAGNOSTIC_REQUIRED");
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
await writeFile(join(directory,"count-mismatch.json"),JSON.stringify({mismatch},null,2)+"\n",{flag:"wx"});
