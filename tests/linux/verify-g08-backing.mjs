// Test-only: bind pre-overlay backing samples to every decoded GIF frame.
import assert from "node:assert/strict";
import { readFile, stat, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";

const [recordPath, gifPath, expectedPath, evidencePath, candidatePath, capturePath, outputPath] = process.argv.slice(2);
assert.ok(outputPath, "Expected records, GIF, expected geometry, live candidate evidence, executable, capture report, new output");
const hash = value => createHash("sha256").update(value).digest("hex");
assert.ok((await stat(recordPath)).size <= 20000000, "Backing evidence too large");
const data = await readFile(recordPath);
const records = data.toString("utf8").trimEnd().split("\n").map(line => JSON.parse(line));
const expected = JSON.parse(await readFile(expectedPath,"utf8"));
const evidenceBytes = await readFile(evidencePath);
const evidence = JSON.parse(evidenceBytes);
const captureBytes = await readFile(capturePath);
const capture = JSON.parse(captureBytes);
assert.equal(capture.source,expected.source);
assert.equal(capture.binarySHA256,expected.binarySHA256);
const matching = capture.cases.filter(item => item.runId === expected.run);
assert.equal(matching.length,1);
assert.equal(matching[0].capture.fps,20);
const artifacts = matching[0].artifacts.filter(item => item.mimeType === "image/gif");
assert.equal(artifacts.length,1);
const gifBytes = await readFile(gifPath);
assert.equal(hash(gifBytes),artifacts[0].sha256);
assert.equal(artifacts[0].documentId,expected.documentId);
assert.equal(artifacts[0].width,640);
assert.equal(artifacts[0].height,450);
assert.equal(expected.frameWidth,640);
assert.equal(expected.frameHeight,450);
assert.equal(evidence.source,expected.source);
assert.equal(evidence.binarySHA256,expected.binarySHA256);
assert.equal(hash(await readFile(candidatePath)),expected.binarySHA256);
assert.ok(Number.isInteger(evidence.pid) && evidence.pid>0);
assert.equal(evidence.loaderOverridesAbsent,true);
assert.equal(hash(await readFile(evidencePath+".maps.txt")),evidence.mapsSHA256);
const build=dirname(resolve(candidatePath));
const archive=join(build,"libkelpie_linux_script_media.a");
const map=await readFile(join(build,"kelpie-linux-link.map"));
assert.equal(hash(map),evidence.candidateLinkMapSHA256);
assert.equal(hash(await readFile(archive)),evidence.mediaArchiveSHA256);
for (const [name,member] of Object.entries({compositor:"script_frame_compositor.cpp.o",
  gif:"script_media_gif.cpp.o",encoder:"script_media_encoder.cpp.o"})) {
  const object=await readFile(join(build,"CMakeFiles/kelpie_linux_script_media.dir/src",member));
  assert.equal(hash(object),evidence.mediaObjectSHA256[name]);
  const extracted=spawnSync("ar",["p",archive,member],{timeout:10000,maxBuffer:20000000});
  assert.equal(extracted.status,0);
  assert.equal(hash(extracted.stdout),evidence.mediaObjectSHA256[name]);
  assert.ok(map.includes(Buffer.from("libkelpie_linux_script_media.a("+member+")")));
}
assert.ok(records.length > 0 && records.length <= 600);
assert.match(expected.binarySHA256,/^[a-f0-9]{64}$/);
assert.match(expected.source,/^[a-f0-9]{40}$/);
const probe=spawnSync("ffprobe",["-v","error","-select_streams","v:0","-show_entries",
  "frame=best_effort_timestamp_time","-of","json",gifPath],{encoding:"utf8",timeout:30000,maxBuffer:1000000});
assert.equal(probe.status,0,probe.stderr);
const frames=JSON.parse(probe.stdout).frames;
assert.equal(frames.length,records.length,"Dropped or unlinked GIF samples");
assert.equal(frames.length,artifacts[0].frameCount);
const first=records[0].elapsedMs;
let previous=-1, previousPts=-1;
for (let i=0;i<records.length;i++) {
  const item=records[i];
  assert.equal(item.pid,evidence.pid);
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
  assert.ok(pts>previousPts,"Duplicate GIF hold or PTS");
  previousPts=pts;
  const bytes=Buffer.from(item.bgraBase64,"base64");
  assert.equal(bytes.length,71*71*4);
  assert.equal(hash(bytes),item.bgraSHA256);
  assert.ok(bytes.every(value=>value===255),"Backing is not opaque white");
}
const receipt={version:1,confidence:"test-only-backing-observed",source:expected.source,
  binarySHA256:expected.binarySHA256,run:expected.run,documentId:expected.documentId,
  observationSHA256:hash(data),candidateEvidenceSHA256:hash(evidenceBytes),captureReportSHA256:hash(captureBytes),gifSHA256:hash(gifBytes),
  frameCount:records.length,roi:[445,190,71,71],bgraSHA256:records[0].bgraSHA256,
  frames:records.map((item,i)=>({sequence:i,elapsedMs:item.elapsedMs,ptsMs:Number(frames[i].best_effort_timestamp_time)*1000,bgraSHA256:item.bgraSHA256}))};
await writeFile(outputPath,JSON.stringify(receipt,null,2)+"\n",{flag:"wx"});
