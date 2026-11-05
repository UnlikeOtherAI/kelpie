import assert from "node:assert/strict";
import {readFile,writeFile,mkdir} from "node:fs/promises";
import {join,resolve} from "node:path";
import {startArtifactProtocolFixture} from "../capture/artifact-protocol-fixture.mjs";
import {verifyArtifactProtocols} from "../capture/artifact-protocol.mjs";
const [readinessFile,identityFile,outputPath]=process.argv.slice(2);
if(!outputPath)throw Error("Provide private readiness, pinned identity and fresh evidence root");
const json=async file=>{
  const bytes=await readFile(file);
  return JSON.parse((bytes[0]===255&&bytes[1]===254?bytes.toString("utf16le"):bytes.toString("utf8")).replace(/^\uFEFF/,""));
};
const readiness=await json(readinessFile),identity=await json(identityFile);
assert.equal(readiness.controlMode,"loopback");assert.equal(readiness.port,28420);
assert.equal(identity.port,readiness.port);assert.equal(identity.launchId,readiness.launchId);
const output=resolve(outputPath);await mkdir(output,{recursive:false});
const fixture=await startArtifactProtocolFixture();
const report={identity,protocols:[],checks:[],cleanup:"not-started"};
let rpcId=0;
async function transport(path,body,signal=AbortSignal.timeout(30000)){
  const response=await fetch("http://127.0.0.1:"+readiness.port+path,{
    method:"POST",headers:{authorization:"Bearer "+readiness.token,"content-type":"application/json",
    accept:"application/json, text/event-stream"},body:JSON.stringify(body),signal});
  assert.equal(response.status,200);
  return response.json();
}
const http=(method,body,options={})=>transport("/v1/"+method,body,options.signal);
const mcp=(name,args,options={})=>transport("/mcp",{jsonrpc:"2.0",id:++rpcId,method:"tools/call",
  params:{name,arguments:args}},options.signal);
try{
  assert.equal((await http("get-device-info",{})).success,true);
  const tabs=await http("get-tabs",{}),tabId=tabs.tabs.find(tab=>tab.active).id;
  const run=await http("play-script",{version:1,tabId,actions:[
    {action:"navigate",url:fixture.url},{action:"wait-ready",state:"complete"},
    {action:"screenshot",name:"large-native-protocol"}],
    capture:{formats:["screenshots"],maxWidth:1920,maxBytes:16777216}});
  assert.equal(run.success,true);
  const geometry=await http("evaluate",{tabId,expression:"({width:innerWidth,height:innerHeight,imageReady:document.images[0].complete&&document.images[0].naturalWidth===512})"});
  report.geometry=geometry.result;assert.equal(report.geometry.imageReady,true);
  assert.ok(report.geometry.width>=512&&report.geometry.height>=512);
  const artifact=run.artifacts.filter(item=>item.mimeType==="image/png").at(-1);
  const verified=await verifyArtifactProtocols({runId:run.runId,artifact,http,mcp});
  await writeFile(join(output,artifact.id+".png"),verified.bytes);
  report.runId=run.runId;report.artifact=artifact;report.protocols=verified.report;
  report.checks.push({name:"large native PNG identical across HTTP/direct MCP/generic MCP chunks",passed:true});
}catch(error){
  report.checks.push({name:"artifact protocol acceptance",passed:false,error:error.message});process.exitCode=1;
}finally{
  await writeFile(join(output,"report.json"),JSON.stringify(report,null,2));
  try{await fixture.close();report.cleanup="closed";}
  catch(error){report.cleanup="failed";report.checks.push({name:"fixture cleanup",passed:false,error:error.message});process.exitCode=1;}
  await writeFile(join(output,"report.json"),JSON.stringify(report,null,2));
}
console.log(JSON.stringify({passed:report.checks.filter(item=>item.passed).length,failed:report.checks.filter(item=>!item.passed),cleanup:report.cleanup}));
