import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {createReadStream} from "node:fs";
import {lstat} from "node:fs/promises";
import {resolve} from "node:path";
export async function verifyTimelineSnapshots(summary,root){
 assert.ok(Array.isArray(summary.snapshots)&&summary.snapshots.length<=3);
 assert.ok(Number.isInteger(summary.width)&&summary.width>0&&summary.width<=4096);
 assert.ok(Number.isInteger(summary.height)&&summary.height>0&&summary.height<=4096&&summary.width*summary.height<=2097152);
 let used=0,lastTick=-1;
 for(let index=0;index<summary.snapshots.length;index++){
  const snapshot=summary.snapshots[index];
  assert.ok(Number.isSafeInteger(snapshot.tick100ns)&&snapshot.tick100ns>lastTick,"WGC_SNAPSHOT_CLOCK");lastTick=snapshot.tick100ns;
  for(const [kind,file] of [["bgra",snapshot.raw],["png",snapshot.png]]){
   assert.ok(file&&typeof file.path==="string");assert.equal(resolve(file.path),resolve(root,"sample-"+index+"."+kind),"WGC_SNAPSHOT_PATH");
   assert.ok(Number.isSafeInteger(file.byteLength)&&file.byteLength>0&&file.byteLength<=67108864);
   assert.match(file.sha256,/^[a-f0-9]{64}$/);if(kind==="bgra")assert.equal(file.byteLength,summary.width*summary.height*4);
   const info=await lstat(file.path);assert.ok(info.isFile()&&!info.isSymbolicLink());assert.equal(info.size,file.byteLength);
   const digest=createHash("sha256");for await(const chunk of createReadStream(file.path))digest.update(chunk);
   assert.equal(digest.digest("hex"),file.sha256);used+=info.size;assert.ok(used<=67108864,"WGC_OUTPUT_BOUND");
  }
 }
 return used;
}
