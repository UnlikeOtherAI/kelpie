import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { startCaptureFixture } from "../capture/fixture-server.mjs";
const [readinessPath, reportPath] = process.argv.slice(2);
const readiness=JSON.parse(await readFile(readinessPath,"utf8"));
const fixture=await startCaptureFixture(), checks=[];
async function api(method,body={}) {
 const r=await fetch("http://127.0.0.1:"+readiness.port+"/v1/"+method,{method:"POST",
  headers:{authorization:"Bearer "+readiness.token,"content-type":"application/json"},
  body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
 return r.json();
}
const tabs=await api("get-tabs");const tabId=tabs.tabs.find(tab=>tab.active).id;
const call=(method,params={})=>api("browser-control",{version:1,method,tabId,params});
const evaluate=async expression=>(await api("evaluate",{tabId,expression})).result;
async function check(name,action) {try{const detail=await action();checks.push({name,passed:true,detail});}
 catch(error){checks.push({name,passed:false,error:error.message});}}
try {
 await check("fixture navigation",async()=>assert.equal((await api("navigate",{tabId,url:fixture.url})).success,true));
 await check("OBS01 value free all private canaries",async()=>{
  const r=await call("tab.snapshot",{maxChars:16000});assert.equal(r.ok,true);
  assert.ok(!JSON.stringify(r.value).includes("CAPTURE_SECRET_"));return {elements:r.value.elements.length};
 });
 await check("OBS02 scoped deterministic prioritized snapshot",async()=>{
  const params={scope:"#catalogue",maxElements:20,maxChars:4000,prioritize:true};
  const a=await call("tab.snapshot",params),b=await call("tab.snapshot",params);
  assert.equal(a.ok,true);assert.equal(b.ok,true);
  const normalize=r=>r.value.elements.map(({ref,...rest})=>rest);
  assert.deepEqual(normalize(a),normalize(b));
  assert.ok(!JSON.stringify(a.value).includes("Confirm order"));return normalize(a);
 });
 await check("OBS03 bounded snapshot truthful truncation",async()=>{
  const r=await call("tab.snapshot",{maxElements:2,maxChars:256,prioritize:true});
  assert.equal(r.ok,true);assert.ok(r.value.elements.length<=2);assert.equal(r.value.truncated,true);
 });
 await check("EXT01 scalar missing ambiguity provenance",async()=>{
  const r=await call("tab.extract",{scope:"#catalogue",fields:[
   {name:"missing",selector:".absent",source:"text"},{name:"ambiguous",selector:"h3",source:"text"},
   {name:"title",selector:"article:first-of-type h3",source:"text"}],metadata:true,maxChars:8000});
  assert.equal(r.ok,true);assert.equal(r.value.fields[0].status,"missing");assert.equal(r.value.fields[1].status,"ambiguous");
  assert.deepEqual(r.value.fields[2].values,["Green tea"]);assert.equal(r.value.fields[2].provenance.source,"text");
  assert.ok(!JSON.stringify(r.value).includes("CAPTURE_SECRET_"));return r.value;
 });
 await check("EXT02 nested records",async()=>{
  const r=await call("tab.extract",{scope:"#catalogue",fields:[{name:"products",selector:"article",source:"text",multiple:true,
   fields:[{name:"name",selector:"h3",source:"text"},{name:"price",selector:".price",source:"text"},
   {name:"link",selector:"a",source:"href"}]}]});
  assert.equal(r.ok,true);assert.equal(r.value.fields[0].records.length,2);
  assert.deepEqual(r.value.fields[0].records.map(row=>row[0].values[0]),["Green tea","Black tea"]);return r.value;
 });
 await check("EXT03 publisher metadata allowlist",async()=>{
  const r=await call("tab.extract",{fields:[{name:"title",selector:"h1",source:"text"}],metadata:true});
  assert.equal(r.ok,true);assert.ok(r.value.metadata.some(m=>m.key==="description"));
  assert.ok(r.value.metadata.every(m=>m.authority==="publisher-claim"));
  assert.ok(!JSON.stringify(r.value).includes("CAPTURE_SECRET_JSONLD_8137"));return r.value.metadata;
 });
 await check("RDY01 DOM diagnostics honesty",async()=>{
  const r=await call("tab.status");assert.equal(r.ok,true);assert.equal(r.value.documentState,"complete");
  assert.equal(r.value.network.availability,"unavailable");assert.equal(r.value.errors.availability,"unavailable");return r.value;
 });
 await check("RDY02 unique visible immediate predicate",async()=>{
  const ready=await call("tab.ready",{state:"complete",selector:"#unique"});assert.equal(ready.value.ready,true);
  const duplicate=await call("tab.ready",{state:"complete",selector:"button"});assert.equal(duplicate.value.ready,false);
  const missing=await call("tab.ready",{state:"complete",selector:".not-present"});assert.equal(missing.value.ready,false);
 });
 await check("WEB01 actual API probe and failclosed capability",async()=>{
  const probe=await evaluate("({available:!!document.modelContext})");
  const caps=await call("capabilities");
  const discover=await call("tab.webmcp.discover",{origin:fixture.url});
  assert.equal(discover.ok,false);assert.equal(discover.error.code,"UNSUPPORTED");
  return {probe,advertised:caps.value.methods.filter(m=>m.includes("webmcp")),error:discover.error.code};
 });
} finally {
 await writeFile(reportPath,JSON.stringify({source:process.env.KELPIE_CAPTURE_SOURCE,checks,cleanup:"pending"},null,2));
 try{await fixture.close();}
 catch(error){checks.push({name:"fixture cleanup",passed:false,error:error.message});}
 await writeFile(reportPath,JSON.stringify({source:process.env.KELPIE_CAPTURE_SOURCE,checks,cleanup:"completed"},null,2));
}
console.log(JSON.stringify({passed:checks.filter(c=>c.passed).length,failed:checks.filter(c=>!c.passed).map(c=>c.name)}));
if(checks.some(c=>!c.passed))process.exitCode=1;
