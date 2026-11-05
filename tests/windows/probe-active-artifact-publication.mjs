import assert from "node:assert/strict";
import {readFile,writeFile} from "node:fs/promises";
import {randomUUID,createHash} from "node:crypto";
import {startCaptureFixture} from "../capture/fixture-server.mjs";
const [readinessPath,outputPath]=process.argv.slice(2),r=JSON.parse(await readFile(readinessPath,"utf8"));
const report={source:process.env.KELPIE_CAPTURE_SOURCE,protocols:[],checks:[],foreignGrant:"not claimed: unknown-run isolation and invalid bearer are separate from a second valid grant"};
let rpcId=0,pending,currentRun,settled=false;
const fixture=await startCaptureFixture();
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function request(path,body){
 const response=await fetch("http://127.0.0.1:"+r.port+path,{method:"POST",
  headers:{authorization:"Bearer "+r.token,"content-type":"application/json",accept:"application/json, text/event-stream"},
  body:JSON.stringify(body),signal:AbortSignal.timeout(30000)});
 return response.json();
}
const api=(method,body={})=>request("/v1/"+method,body);
async function call(protocol,method,body={}){
 if(protocol==="http")return api(method,body);
 const name="kelpie_"+method.replaceAll("-","_"),params=protocol==="mcp-direct"?{name,arguments:body}:
  {name:"kelpie_extension",arguments:{name,arguments:body}};
 const raw=await request("/mcp",{jsonrpc:"2.0",id:++rpcId,method:"tools/call",params});
 if(raw.error)return {success:false,error:{code:"JSON_RPC_"+raw.error.code}};
 const wrapped=JSON.parse(raw.result.content[0].text);
 return wrapped.ok?wrapped.value:{success:false,error:wrapped.error};
}
function chunk(response,run,artifact){
 assert.equal(response.success,true);assert.equal(response.runId,run);assert.equal(response.artifactId,artifact.id);
 assert.equal(response.sha256,artifact.sha256);assert.ok(Buffer.from(response.data,"base64").length>0);
}
try{
 await api("navigate",{url:fixture.url});
 const tabs=await api("get-tabs"),tabId=tabs.tabs.find(t=>t.active).id;
 const previous=await api("play-script",{version:1,tabId,actions:[{action:"screenshot"}],capture:{formats:["screenshots"],maxWidth:640}});
 assert.equal(previous.success,true);assert.ok(previous.artifacts.length>0);
 const ordinary=await api("play-script",{version:1,tabId,actions:[{action:"wait",ms:100},{action:"click",target:{role:"button",name:"Covered action",exact:true}}],
  capture:{formats:["gif","video"],fps:10,maxWidth:640}});
 assert.equal(ordinary.success,false);assert.equal(ordinary.error?.code,"TARGET_OBSCURED");
 assert.ok(ordinary.artifacts.length>0);assert.ok(ordinary.artifacts.every(a=>a.partial));
 report.checks.push({name:"known nonsensitive ordinary failure retains partials",passed:true,runId:ordinary.runId,count:ordinary.artifacts.length});
 const literal="SyntheticPublication Aa b+! "+randomUUID(),uri=encodeURIComponent(literal).replace(/%2B/g,"%2b"),
  form=new URLSearchParams({value:literal}).toString().slice(6).replace(/%2B/g,"%2b");
 assert.equal((await api("evaluate",{tabId,expression:"(()=>{document.title="+JSON.stringify(literal+" "+uri+" "+form)+";document.body.innerHTML='<input type=password aria-label=Privatefield style=\"position:absolute;left:24px;top:100px;width:200px;height:30px\">';return true})()"})).success,true);
 pending=api("play-script",{version:1,tabId,actions:[{action:"output",name:"before",source:"title"},
  {action:"screenshot"},{action:"wait",ms:5000},{action:"fill",target:{label:"Privatefield",exact:true},text:literal}],
  capture:{formats:["screenshots"],fps:15,maxWidth:640,maxBytes:8388608}});
 pending.then(()=>{settled=true;},()=>{settled=true;}); // Observe immediately; preserve the original promise.
 for(let i=0;i<100;i++){
  const status=await api("get-script-status");
  if(status.playing&&status.actionIndex>=2){currentRun=status.runId;break;}
  await sleep(50);
 }
 assert.ok(currentRun,"Current run never reached its owned publication hold");
 for(const protocol of ["http","mcp-direct","mcp-generic"]){
  const status=await call(protocol,"get-script-status",{runId:currentRun});
  assert.equal(status.success,true);assert.equal(status.playing,true);assert.deepEqual(status.artifacts,[]);
  const hidden=await call(protocol,"get-script-artifact",{runId:currentRun,artifactId:"pending-artifact",offset:0,length:1});
  assert.equal(hidden.error?.code,"ARTIFACT_NOT_READY");assert.equal(hidden.data,undefined);
  const malformed=await call(protocol,"get-script-artifact",{runId:currentRun,artifactId:"pending-artifact",length:0});
  assert.equal(malformed.error?.code,protocol==="http"?"INVALID_PARAMS":"JSON_RPC_-32602");
  const unknown=await call(protocol,"get-script-artifact",{runId:"unknown-run-"+randomUUID(),artifactId:"unknown-artifact",length:1});
  assert.equal(unknown.error?.code,"ARTIFACT_NOT_FOUND");assert.equal(unknown.data,undefined);
  const old=await call(protocol,"get-script-artifact",{runId:previous.runId,artifactId:previous.artifacts[0].id,length:1024});
  const partial=await call(protocol,"get-script-artifact",{runId:ordinary.runId,artifactId:ordinary.artifacts[0].id,length:1024});
  chunk(old,previous.runId,previous.artifacts[0]);chunk(partial,ordinary.runId,ordinary.artifacts[0]);
  report.protocols.push({protocol,currentHidden:true,ownerCode:hidden.error.code,malformedCode:malformed.error.code,
   unknownRunCode:unknown.error.code,previousSafeReadable:true,previousPartialReadable:true});
 }
 const result=await pending,status=await api("get-script-status",{runId:currentRun}),text=JSON.stringify({result,status});
 assert.equal(result.success,false);assert.equal(result.error?.code,"SENSITIVE_CAPTURE_REFUSED");
 assert.deepEqual(result.artifacts,[]);assert.deepEqual(status.artifacts,[]);assert.equal(status.outputs,undefined);
 assert.ok(result.outputs.before.includes("[redacted]"));assert.ok(!text.includes(literal)&&!text.includes(uri)&&!text.includes(form));
 report.terminal={runId:currentRun,code:result.error.code,artifactCount:0,statusArtifactCount:0,masked:true,leaked:false,
  canarySha256:createHash("sha256").update(literal).digest("hex")};
 const preserved=await api("get-script-artifact",{runId:ordinary.runId,artifactId:ordinary.artifacts[0].id,length:1024});
 chunk(preserved,ordinary.runId,ordinary.artifacts[0]);
 const recovery=await api("play-script",{version:1,tabId,actions:[{action:"navigate",url:fixture.url},
  {action:"wait-ready",state:"complete"},{action:"click",target:{role:"button",name:"Confirm order",exact:true}}]});
 assert.equal(recovery.success,true);report.recovery=true;
}catch(error){report.error=error.message;process.exitCode=1;}
finally{
 if(pending&&!settled){try{await api("abort-script",currentRun?{runId:currentRun}:{});await pending;}catch{}}
 await writeFile(outputPath,JSON.stringify(report,null,2));await fixture.close();
}
console.log(JSON.stringify(report));
