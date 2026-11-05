import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";

// Select an output passthrough option from the actual executable's advertised
// capabilities. FFmpeg 4.4 supports vsync; FFmpeg 9 removed it.
export function selectFfmpegPassthrough(help) {
 assert.equal(typeof help,"string");
 if(/^\s*-fps_mode(?:\[|\s)/m.test(help))return ["-fps_mode","passthrough"];
 if(/^\s*-vsync(?:\[|\s)/m.test(help))return ["-vsync","0"];
 throw Error("FFMPEG_PASSTHROUGH_UNAVAILABLE");
}
const cache=new Map();
export function ffmpegPassthrough(executable) {
 assert.ok(typeof executable==="string"&&executable.length>0);
 if(!cache.has(executable)){
  const probe=spawnSync(executable,["-hide_banner","-h","full"],
   {encoding:"utf8",windowsHide:true,timeout:15000,maxBuffer:8388608});
  assert.equal(probe.status,0,"FFMPEG_CAPABILITY_PROBE_FAILED");
  cache.set(executable,selectFfmpegPassthrough((probe.stdout??"")+"\n"+(probe.stderr??"")));
 }
 return [...cache.get(executable)];
}
