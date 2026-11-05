import assert from "node:assert/strict";
import {readFile,writeFile,mkdir} from "node:fs/promises";
import {resolve} from "node:path";
import {startCaptureFixture} from "../capture/fixture-server.mjs";
import {downloadArtifacts} from "./capture-artifact-download.mjs";

const [readinessPath,outputPath]=process.argv.slice(2);
assert.ok(readinessPath&&outputPath);
const readiness=JSON.parse(await readFile(readinessPath,"utf8"));
assert.equal(readiness.controlMode,"loopback");
const expected=process.env.KELPIE_CAPTURE_RECEIPT_FIXTURE_URL;
assert.match(expected??"",/^http:\/\/127\.0\.0\.1:[0-9]{1,5}$/);
const port=Number(new URL(expected).port);
assert.ok(Number.isInteger(port)&&port>0&&port<=65535);
const output=resolve(outputPath);await mkdir(output,{recursive:false});
const fixture=await startCaptureFixture({port});assert.equal(fixture.url,expected);
const checks=[],artifacts=[];
const api=async(method,body={})=>{
 const response=await fetch("http://127.0.0.1:"+readiness.port+"/v1/"+method,{
  method:"POST",headers:{authorization:"Bearer "+readiness.token,"content-type":"application/json"},
  body:JSON.stringify(body),signal:AbortSignal.timeout(60000)});
 return response.json();
};
try{
 const tabs=await api("get-tabs"),tabId=(tabs.tabs??[]).find(tab=>tab.active)?.id;assert.ok(tabId);
 assert.equal((await api("navigate",{tabId,url:fixture.url})).success,true);
 assert.equal((await api("play-script",{version:1,tabId,actions:[{action:"wait-ready",state:"complete"}]})).success,true);
 const result=await api("play-script",{version:1,tabId,actions:[{action:"wait",ms:300},{action:"screenshot",name:"after"}],
  pointer:{enabled:false},capture:{formats:["screenshots"],fps:5,maxWidth:640,maxBytes:8388608,maxDurationMs:20000}});
 assert.equal(result.success,true);assert.equal(result.actionsExecuted,2);
 assert.ok(result.artifacts.some(item=>item.mimeType==="image/png"&&item.actionIndex===1&&item.documentId));
 assert.equal((await api("get-current-url",{tabId})).url,fixture.url+"/next");
 await downloadArtifacts(result,{api,output,artifacts});
 assert.equal((await api("navigate",{tabId,url:fixture.url})).success,true);
 assert.equal((await api("play-script",{version:1,tabId,actions:[{action:"wait-ready",state:"complete"}]})).success,true);
 assert.equal((await api("play-script",{version:1,tabId,actions:[{action:"wait",ms:0}]})).success,true);
 checks.push({name:"receipt checkpoint navigation drops old frame and recovers",passed:true});
}catch(error){
 const code=typeof error?.code==="string"&&/^[A-Z][A-Z0-9_]{0,79}$/.test(error.code)?error.code:null;
 checks.push({name:"receipt checkpoint navigation drops old frame and recovers",passed:false,code});
 process.exitCode=1;
}finally{
 let cleanup="closed";try{await fixture.close();}catch{cleanup="failed";process.exitCode=1;}
 await writeFile(resolve(output,"report.json"),JSON.stringify({checks,artifacts,cleanup},null,2),{flag:"wx"});
}