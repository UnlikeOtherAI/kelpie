import test from "node:test";
import assert from "node:assert/strict";
import {mkdtemp,readFile,writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {spawnSync} from "node:child_process";
import {fileURLToPath} from "node:url";

const verify=fileURLToPath(new URL("./g08-verify.mjs",import.meta.url));
const single=fileURLToPath(new URL("./g08-verify-single.mjs",import.meta.url));
const event=(target,timeMs,center)=>({target,timeMs,center,documentId:"doc",
  viewport:{width:640,height:400},trusted:true});
const artifact=mimeType=>({id:mimeType,mimeType,partial:false,byteLength:1,
  sha256:"a".repeat(64),timestamps:Array.from({length:50},(_,i)=>i/20),
  file:join(tmpdir(),"g08-nonexistent-artifact"),width:640,height:400});
const oneCase=()=>({curve:"c",scene:{
  calibration:event("finish",1,{x:400,y:200}),
  start:event("start",2,{x:100,y:200}),finish:event("finish",3,{x:400,y:200})},
  artifacts:[artifact("image/gif"),artifact("video/mp4")]});

test("single-case adapter preserves the standard case count and failed artifact checks",async()=>{
  const dir=await mkdtemp(join(tmpdir(),"g08-single-"));
  const input=join(dir,"input.json"),out=join(dir,"result.json"),normal=join(dir,"normal.json");
  await writeFile(input,JSON.stringify({source:"a".repeat(40),binarySHA256:"b".repeat(64),
    runtime:"windows-cef",eventsDropped:0,cases:[oneCase()]}));
  const standard=spawnSync(process.execPath,[verify,input,normal],{encoding:"utf8",timeout:30000});
  assert.notEqual(standard.status,0);
  await assert.rejects(readFile(normal));
  const result=spawnSync(process.execPath,[single,input,out],{encoding:"utf8",timeout:30000});
  assert.notEqual(result.status,0);
  const report=JSON.parse(await readFile(out,"utf8"));
  assert.equal(report.scope,"single-case");
  assert.equal(report.results.length,2);
  assert.deepEqual(report.results.map(item=>item.passed),[false,false]);
  assert.ok(report.results.every(item=>item.curve==="c"));
});

test("single-case adapter rejects an extra curve instead of claiming a pair",async()=>{
  const dir=await mkdtemp(join(tmpdir(),"g08-single-"));
  const input=join(dir,"input.json"),out=join(dir,"result.json");
  const second={...oneCase(),curve:"s"};
  await writeFile(input,JSON.stringify({source:"a".repeat(40),binarySHA256:"b".repeat(64),
    runtime:"windows-cef",eventsDropped:0,cases:[oneCase(),second]}));
  const result=spawnSync(process.execPath,[single,input,out],{encoding:"utf8",timeout:30000});
  assert.notEqual(result.status,0);
  await assert.rejects(readFile(out));
});
