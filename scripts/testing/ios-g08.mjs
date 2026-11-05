import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {mkdir,writeFile} from "node:fs/promises";
import {join,resolve} from "node:path";
import assert from "node:assert/strict";
import {startG08Fixture,g08Workflow} from "../../tests/capture/g08-fixture.mjs";
import {iosG08Scene} from "./ios_g08_scene.mjs";
const run=promisify(execFile), [tab,dir,family,binarySHA256,source]=process.argv.slice(2);
assert.match(tab,/^[0-9A-Fa-f-]{36}$/); assert.ok(["iPhone","iPad"].includes(family));
assert.match(binarySHA256,/^[a-f0-9]{64}$/); assert.match(source,/^[a-f0-9]{40}$/);
await mkdir(dir);
let stage="setup";
const record=async (state,error)=>writeFile(join(dir,"stage.json"),JSON.stringify({stage,state,...(error?{error}: {})},null,2));
try {
const cli=async args=>JSON.parse((await run("node",["packages/cli/bin/kelpie.js","--device","127.0.0.1:28429","--format","json","--timeout","120000",...args],{timeout:180000,maxBuffer:4194304})).stdout);
const report={source,binarySHA256,runtime:family==="iPhone"?"ios-iphone-webkit":"ios-ipad-webkit",eventsDropped:0,cases:[]};
for(const curve of ["c","s"]){
 stage=curve+"-fixture"; await record("running");
 const fixture=await startG08Fixture();
 try {
  const folder=resolve(dir,curve); await mkdir(folder);
  const nav=join(folder,"navigate.json");
  await writeFile(nav,JSON.stringify({version:1,tabId:tab,actions:[{action:"navigate",url:fixture.url}]}));
  stage=curve+"-navigation"; await record("running");
  assert.equal((await cli(["script","run",nav])).success,true);
  const recipe=join(folder,"workflow.json"); await writeFile(recipe,JSON.stringify(g08Workflow(tab,curve)));
  stage=curve+"-capture"; await record("running");
  const played=await cli(["script","run",recipe,"--output",join(folder,"downloads")]);
  assert.equal(played.result.success,true);
  stage=curve+"-facts-and-probe"; await record("running");
  const facts=await(await fetch(new URL("/events",fixture.url))).json();
  const scene=iosG08Scene(facts);
  const diagnostics=await cli(["debug-screens"]);
  const evidence=diagnostics.testCaptureEvidence;
  assert.equal(evidence?.runId,played.result.runId);
  assert.ok(evidence?.artifacts);
  const artifacts=[];
  for(const manifest of played.result.artifacts){
   const downloaded=played.downloaded.find(item=>item.id===manifest.id); assert.ok(downloaded);
   const file=resolve(downloaded.file); assert.ok(file.startsWith(folder+"/"));
   const p=JSON.parse((await run("ffprobe",["-v","error","-select_streams","v:0","-show_frames","-show_entries","frame=best_effort_timestamp_time:stream=width,height","-of","json",file],{timeout:30000,maxBuffer:1048576})).stdout);
   const geometry=evidence.artifacts[manifest.id]?.geometry;
   assert.ok(geometry);
   artifacts.push({...manifest,geometry,file,width:p.streams[0].width,height:p.streams[0].height,timestamps:p.frames.map(f=>Number(f.best_effort_timestamp_time))});
  }
  report.cases.push({curve,scene,artifacts});
  await writeFile(join(dir,"input.json"),JSON.stringify(report,null,2));
 } finally { await fixture.close(); }
}
stage="oracle"; await record("running");
await run("node",["tests/capture/g08-verify.mjs",join(dir,"input.json"),join(dir,"oracle.json")],{timeout:300000,maxBuffer:4194304});
await record("passed");
} catch(error) {
 await record("failed",error?.name ?? "Error");
 process.exitCode=1;
}
