import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const script=fileURLToPath(new URL("./verify-admitted-marker.mjs",import.meta.url));
test("admission comparator refuses drops and a mismatched fixture crop",async()=>{
 const dir=await mkdtemp(join(tmpdir(),"kelpie-admitted-test-"));
 try {
  const trace=join(dir,"trace.jsonl"),media=join(dir,"media.json"),video=join(dir,"movie.mp4");
  const input={checks:[{name:"continuous fixture",detail:{event:{trusted:true,hit:"unique",x:119,y:137,viewport:{width:1280}}}}],
    artifacts:[{file:video,mimeType:"video/mp4",width:1000}]};
  await writeFile(media,JSON.stringify(input));
  await writeFile(trace,JSON.stringify({phase:0,due:1,admittedIndex:0,elapsedMs:1})+"\n"+
    JSON.stringify({phase:1,videoDropped:1,videoFrames:1})+"\n");
  const args=[script,trace,dir,video,media,join(dir,"out.json")];
  const dropped=spawnSync(process.execPath,args,{encoding:"utf8"});assert.notEqual(dropped.status,0);
  assert.match(dropped.stderr,/1 !== 0/);
  input.checks[0].detail.event.x=999;await writeFile(media,JSON.stringify(input));
  const wrong=spawnSync(process.execPath,args,{encoding:"utf8"});assert.notEqual(wrong.status,0);
  assert.match(wrong.stderr,/AssertionError/);
 } finally {await rm(dir,{recursive:true,force:true});}
});
