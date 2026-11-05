import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, writeFile, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve, delimiter } from "node:path";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
const script=resolve("tests/linux/diagnose-media-count.mjs");
test("retains only first mismatched bounded synthetic file",{skip:process.platform==="win32"},async()=>{
 const root=await mkdtemp(join(tmpdir(),"kelpie-count-test-"));
 try {
  const bin=join(root,"bin"),output=join(root,"capture");await mkdir(bin);await mkdir(output);
  await writeFile(join(bin,"ffprobe"),"#!/bin/sh\nprintf '%s' '{\"streams\":[{\"nb_read_frames\":\"2\"}],\"frames\":[{\"best_effort_timestamp_time\":\"0\"},{\"best_effort_timestamp_time\":\"0.1\"}]}'\n",{mode:0o700});
  const bytes=Buffer.from("synthetic"),file=join(output,"fixture.gif");await writeFile(file,bytes);
  const item={id:"fixture",file,mimeType:"image/gif",frameCount:3,sha256:createHash("sha256").update(bytes).digest("hex")};
  await writeFile(join(output,"combined-media-input.json"),JSON.stringify({artifacts:[item]}));
  const result=spawnSync(process.execPath,[script,output],{env:{...process.env,KELPIE_LINUX_RESOURCE_DIAGNOSTIC:"1",PATH:bin+delimiter+process.env.PATH}});
  assert.equal(result.status,0,result.stderr.toString());
  const receipt=JSON.parse(await readFile(join(output,"count-mismatch.json")));assert.equal(receipt.mismatch.manifestFrames,3);
  assert.equal(receipt.mismatch.decodedFrames,2);assert.deepEqual(receipt.mismatch.pts,[0,0.1]);
  assert.deepEqual(await readFile(join(output,"count-mismatch.gif")),bytes);
 } finally { await rm(root,{recursive:true,force:true}); }
});

test("rejects a missing directory before resolving paths",()=>{
 const result=spawnSync(process.execPath,[script],{env:{...process.env,KELPIE_LINUX_RESOURCE_DIAGNOSTIC:"1"}});
 assert.notEqual(result.status,0);assert.match(result.stderr.toString(),/DIAGNOSTIC_REQUIRED/);
});
