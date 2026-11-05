import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {mkdir,readFile,writeFile} from "node:fs/promises";
import {resolve} from "node:path";
import {startG08Fixture,g08Workflow,mapG08Scene} from "../capture/g08-fixture.mjs";
import {scriptArtifactSchema,scriptArtifactChunkSchema} from "../../packages/shared/dist/index.js";
const [readinessFile,outputPath,identityFile]=process.argv.slice(2);
assert.ok(readinessFile&&outputPath&&identityFile);
const readiness=JSON.parse(await readFile(readinessFile,"utf8"));
const identity=JSON.parse(await readFile(identityFile,"utf8"));
const output=resolve(outputPath);await mkdir(output,{recursive:false});
const exec=promisify(execFile),cases=[];
const api=async(method,body={})=>{
 const response=await fetch("http://127.0.0.1:"+readiness.port+"/v1/"+method,{method:"POST",
  headers:{authorization:"Bearer "+readiness.token,"content-type":"application/json"},
  body:JSON.stringify(body),signal:AbortSignal.timeout(120000)});
 assert.ok(response.ok,"HTTP "+response.status);return response.json();
};
async function download(run,item){
 const chunks=[];let offset=0;
 while(offset<item.byteLength){
  const chunk=scriptArtifactChunkSchema.parse(await api("get-script-artifact",{runId:run.runId,artifactId:item.id,offset,length:262144}));
  assert.equal(chunk.runId,run.runId);assert.equal(chunk.artifactId,item.id);assert.equal(chunk.offset,offset);
  const bytes=Buffer.from(chunk.data,"base64");assert.ok(bytes.length>0);offset+=bytes.length;
  assert.equal(chunk.nextOffset,offset);assert.equal(chunk.eof,offset===item.byteLength);chunks.push(bytes);
 }
 const bytes=Buffer.concat(chunks);assert.equal(bytes.length,item.byteLength);
 assert.equal(createHash("sha256").update(bytes).digest("hex"),item.sha256);
 const file=resolve(output,item.id+(item.mimeType==="image/gif"?".gif":".mp4"));
 await writeFile(file,bytes,{flag:"wx"});
 const probe=await exec(process.env.FFPROBE||"ffprobe",["-v","error","-select_streams","v:0","-show_entries","frame=best_effort_timestamp_time","-of","json",file],{timeout:120000,maxBuffer:8388608});
 const timestamps=JSON.parse(probe.stdout).frames.map(frame=>Number(frame.best_effort_timestamp_time));
 assert.ok(timestamps.length>0&&timestamps.every(Number.isFinite));return {...item,file,timestamps};
}
let fixture;
try{
 const tabs=await api("get-tabs"),tabId=tabs.tabs.find(tab=>tab.active)?.id;assert.ok(tabId);
 for(const curve of ["c","s"]){
  fixture=await startG08Fixture();
  assert.equal((await api("navigate",{tabId,url:fixture.url})).success,true);
  assert.equal((await api("play-script",{version:1,tabId,actions:[{action:"wait-ready",state:"complete"}]})).success,true);
  const run=await api("play-script",g08Workflow(tabId,curve));assert.equal(run.success,true,JSON.stringify(run.error));
  const eventResponse=await fetch(new URL("/events",fixture.url),{signal:AbortSignal.timeout(10000)});
  assert.ok(eventResponse.ok);const {events,dropped}=await eventResponse.json();
  await writeFile(resolve(output,curve+"-events.json"),JSON.stringify({events,dropped},null,2),{flag:"wx"});
  assert.equal(dropped,0);const scene=mapG08Scene(events);
  assert.ok(events.every(event=>event.trusted));

  const items=(run.artifacts??[]).map(item=>scriptArtifactSchema.parse(item));
  assert.deepEqual(items.map(item=>item.mimeType).sort(),["image/gif","video/mp4"]);
  const artifacts=[];for(const item of items)artifacts.push(await download(run,item));
  cases.push({curve,scene,artifacts});
  await fixture.close();fixture=null;
 }
 await writeFile(resolve(output,"oracle-input.json"),JSON.stringify({source:identity.source,binarySHA256:identity.hashes.dllSha256,runtime:"windows-cef",eventsDropped:0,cases},null,2),{flag:"wx"});
}finally{if(fixture)await fixture.close();}
