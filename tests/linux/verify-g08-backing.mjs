// Test-only: bind pre-overlay backing samples to every decoded GIF frame.
import assert from "node:assert/strict";
import { readFile, stat, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";

const [recordPath, gifPath, expectedPath, outputPath] = process.argv.slice(2);
assert.ok(outputPath, "Expected records, GIF, expected identity/geometry, new output");
const hash = value => createHash("sha256").update(value).digest("hex");
assert.ok((await stat(recordPath)).size <= 20000000, "Backing evidence too large");
const data = await readFile(recordPath);
const records = data.toString("utf8").trimEnd().split("\n").map(line => JSON.parse(line));
const expected = JSON.parse(await readFile(expectedPath,"utf8"));
assert.ok(records.length > 0 && records.length <= 600);
assert.match(expected.binarySHA256,/^[a-f0-9]{64}$/);
assert.match(expected.source,/^[a-f0-9]{40}$/);
const probe=spawnSync("ffprobe",["-v","error","-select_streams","v:0","-show_entries",
  "frame=best_effort_timestamp_time","-of","json",gifPath],{encoding:"utf8",timeout:30000,maxBuffer:1000000});
assert.equal(probe.status,0,probe.stderr);
const frames=JSON.parse(probe.stdout).frames;
assert.equal(frames.length,records.length,"Dropped or unlinked GIF samples");
const first=records[0].elapsedMs;
let previous=-1;
for (let i=0;i<records.length;i++) {
  const item=records[i];
  assert.equal(item.sequence,i);
  assert.equal(item.run,expected.run);
  assert.equal(item.documentId,expected.documentId);
  assert.equal(item.frameWidth,expected.frameWidth);
  assert.equal(item.frameHeight,expected.frameHeight);
  assert.equal(item.sourceWidth,expected.sourceWidth);
  assert.equal(item.sourceHeight,expected.sourceHeight);
  assert.equal(item.stride,item.frameWidth*4);
  assert.equal(item.viewportWidth,expected.viewportWidth);
  assert.equal(item.viewportHeight,expected.viewportHeight);
  assert.deepEqual(item.visualViewport,expected.visualViewport);
  assert.deepEqual(item.roi,[445,190,71,71]);
  assert.ok(Number.isFinite(item.elapsedMs) && item.elapsedMs>previous);
  previous=item.elapsedMs;
  const pts=Number(frames[i].best_effort_timestamp_time)*1000;
  assert.ok(Number.isFinite(pts));
  assert.equal(Math.round(pts),Math.round((item.elapsedMs-first)/10)*10,"GIF PTS does not match source sample");
  const bytes=Buffer.from(item.bgraBase64,"base64");
  assert.equal(bytes.length,71*71*4);
  assert.equal(hash(bytes),item.bgraSHA256);
  assert.ok(bytes.every(value=>value===255),"Backing is not opaque white");
}
const receipt={version:1,confidence:"test-only-backing-observed",source:expected.source,
  binarySHA256:expected.binarySHA256,run:expected.run,documentId:expected.documentId,
  observationSHA256:hash(data),gifSHA256:hash(await readFile(gifPath)),
  frameCount:records.length,roi:[445,190,71,71],bgraSHA256:records[0].bgraSHA256,
  frames:records.map((item,i)=>({sequence:i,elapsedMs:item.elapsedMs,ptsMs:Number(frames[i].best_effort_timestamp_time)*1000,bgraSHA256:item.bgraSHA256}))};
await writeFile(outputPath,JSON.stringify(receipt,null,2)+"\n",{flag:"wx"});
