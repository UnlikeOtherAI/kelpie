import assert from "node:assert/strict";
import { mkdtemp, rm, readdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
const executable=process.argv[2];assert.ok(executable);
const directory=await mkdtemp(join(tmpdir(),"kelpie-irregular-mp4-"));
try {
 const produced=spawnSync(executable,[directory],{timeout:30000,maxBuffer:1048576});
 assert.equal(produced.status,0,produced.stderr?.toString());
 const output=JSON.parse(produced.stdout.toString());assert.equal(output.frames,15);
 const probed=spawnSync("ffprobe",["-v","error","-select_streams","v:0","-count_frames","-count_packets","-show_frames","-show_entries","stream=nb_read_frames,nb_read_packets:frame=best_effort_timestamp_time","-of","json",output.file],{timeout:30000,maxBuffer:1048576});
 assert.equal(probed.status,0,probed.stderr?.toString());const result=JSON.parse(probed.stdout.toString());
 assert.equal(Number(result.streams[0].nb_read_packets),15);assert.equal(Number(result.streams[0].nb_read_frames),15);
 assert.equal(result.frames.length,15);
 for(let i=0;i<15;i++)assert.ok(Math.abs(Number(result.frames[i].best_effort_timestamp_time)*1000-output.ptsMs[i])<1);
 const decoded=spawnSync("ffmpeg",["-v","error","-xerror","-threads","1","-i",output.file,"-f","null","-"],{timeout:30000,maxBuffer:1048576});
 assert.equal(decoded.status,0,decoded.stderr?.toString());assert.deepEqual(await readdir(directory),["capture.mp4"]);
} finally {await rm(directory,{recursive:true,force:true});}
