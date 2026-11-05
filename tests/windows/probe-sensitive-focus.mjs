import assert from "node:assert/strict";
import {readFile,writeFile} from "node:fs/promises";
import {randomUUID,createHash} from "node:crypto";
const [readinessPath,outputPath,expectation="diagnostic"]=process.argv.slice(2);
assert.ok(expectation==="diagnostic"||expectation==="expect-refused");
const r=JSON.parse(await readFile(readinessPath,"utf8")),report={kind:expectation==="diagnostic"?"privacy diagnostic, not acceptance":"privacy regression",source:process.env.KELPIE_CAPTURE_SOURCE,cases:[],viewport:[]};
const api=async(method,body={})=>{
 const response=await fetch("http://127.0.0.1:"+r.port+"/v1/"+method,{method:"POST",
  headers:{authorization:"Bearer "+r.token,"content-type":"application/json"},body:JSON.stringify(body),
  signal:AbortSignal.timeout(15000)});
 return response.json();
};
const metrics="({width:innerWidth,height:innerHeight,clientWidth:document.documentElement.clientWidth,clientHeight:document.documentElement.clientHeight,compatMode:document.compatMode,visual:{width:visualViewport.width,height:visualViewport.height,scale:visualViewport.scale,offsetLeft:visualViewport.offsetLeft,offsetTop:visualViewport.offsetTop}})";
try{
 assert.equal((await api("navigate",{url:"about:blank"})).success,true);
 const tabs=await api("get-tabs"),tabId=tabs.tabs.find(t=>t.active).id;
 report.viewport.push({name:"blank",value:(await api("evaluate",{tabId,expression:metrics})).result});
 for(const mode of ["autocomplete","password-type"]){
  const secret="SyntheticFocus Aa b+! "+randomUUID();
  const uri=encodeURIComponent(secret).replace(/%2B/g,"%2b");
  const form=new URLSearchParams({value:secret}).toString().slice(6).replace(/%2B/g,"%2b");
  const focus=mode==="autocomplete"?"e.autocomplete='current-password'":"e.type='password'";
  const expression="(()=>{document.title="+JSON.stringify(secret+" "+uri+" "+form)+";document.body.innerHTML='<input id=private-field aria-label=Privatefield style=\"position:absolute;left:24px;top:100px;width:200px;height:30px\">';document.body.style.cssText='margin:0;height:1600px';window.__edits=0;const e=document.getElementById('private-field');e.oninput=()=>window.__edits++;e.onfocus=()=>{"+focus+"};return true;})()";
  assert.equal((await api("evaluate",{tabId,expression})).success,true);
  report.viewport.push({name:mode,value:(await api("evaluate",{tabId,expression:metrics})).result});
  const result=await api("play-script",{version:1,tabId,actions:[
    {action:"output",name:"before",source:"title"},
    {action:"fill",target:{label:"Privatefield",exact:true},text:secret}],
    capture:{formats:["screenshots"],fps:15,maxWidth:640,maxBytes:8388608}});
  const encoded=JSON.stringify(result);
  const state=(await api("evaluate",{tabId,expression:"(()=>{const e=document.getElementById('private-field');return {valueMatches:e.value==="+JSON.stringify(secret)+",editEvents:window.__edits,sensitiveAfter:e.type==='password'||/^(current|new)-password$/.test(e.autocomplete),type:e.type,autocomplete:e.autocomplete}})()"})).result;
  const status=await api("get-script-status",{runId:result.runId});
  const recovery=await api("play-script",{version:1,tabId,actions:[{action:"wait",ms:0}]});
  report.cases.push({mode,canarySha256:createHash("sha256").update(secret).digest("hex"),
    success:result.success,errorCode:result.error?.code,runId:result.runId,
    leakedRaw:encoded.includes(secret),leakedUri:encoded.includes(uri),leakedForm:encoded.includes(form),
    masked:typeof result.outputs?.before==="string"&&result.outputs.before.includes("[redacted]"),
    artifactCount:result.artifacts?.length??0,statusArtifactCount:status.artifacts?.length??0,
    state,recoverySuccess:recovery.success,resultSha256:createHash("sha256").update(encoded).digest("hex")});
 }
 if(expectation==="expect-refused")for(const item of report.cases){
  assert.equal(item.success,false);assert.equal(item.leakedRaw,false);assert.equal(item.leakedUri,false);assert.equal(item.leakedForm,false);assert.equal(item.masked,true);
  assert.equal(item.artifactCount,0);assert.equal(item.statusArtifactCount,0);
  assert.equal(item.state.editEvents,0);assert.equal(item.state.valueMatches,false);assert.equal(item.recoverySuccess,true);
  assert.ok(["SENSITIVE_CAPTURE_REFUSED","TARGET_MOVED"].includes(item.errorCode));
 }
}catch(error){report.error=error.message;process.exitCode=1;}
finally{await writeFile(outputPath,JSON.stringify(report,null,2));}
console.log(JSON.stringify(report));
