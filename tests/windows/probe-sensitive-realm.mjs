import assert from "node:assert/strict";
import {readFile,writeFile} from "node:fs/promises";
import {randomUUID,createHash} from "node:crypto";
import {startCaptureFixture} from "../capture/fixture-server.mjs";
const [readinessPath,outputPath]=process.argv.slice(2),r=JSON.parse(await readFile(readinessPath,"utf8"));
const report={source:process.env.KELPIE_CAPTURE_SOURCE,cases:[]};
const api=async(method,body={})=>(await fetch("http://127.0.0.1:"+r.port+"/v1/"+method,{
 method:"POST",headers:{authorization:"Bearer "+r.token,"content-type":"application/json"},
 body:JSON.stringify(body),signal:AbortSignal.timeout(30000)})).json();
const fixture=await startCaptureFixture();
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
try{
 await api("navigate",{url:fixture.url});
 const tabs=await api("get-tabs"),tabId=tabs.tabs.find(t=>t.active).id;
 for(const phase of ["focus","input"])for(const capturing of [false,true]){
  await api("navigate",{tabId,url:fixture.url});
  const literal="SyntheticRealm Aa b+! "+randomUUID(),uri=encodeURIComponent(literal).replace(/%2B/g,"%2b"),
   form=new URLSearchParams({value:literal}).toString().slice(6).replace(/%2B/g,"%2b");
  const setup="(()=>{document.title="+JSON.stringify(literal+" "+uri+" "+form)+";document.body.innerHTML='<input aria-label=Realmfield style=\"position:absolute;left:24px;top:100px;width:200px;height:30px\">';sessionStorage.setItem('realmPhase','none');sessionStorage.setItem('realmEdits','0');const e=document.querySelector('input');e.oninput=()=>sessionStorage.setItem('realmEdits',String(Number(sessionStorage.getItem('realmEdits'))+1));e.addEventListener("+JSON.stringify(phase)+",()=>{e.autocomplete='current-password';sessionStorage.setItem('realmPhase',"+JSON.stringify(phase)+");location.href="+JSON.stringify(fixture.url+"/next")+"},{once:true});return true})()";
  assert.equal((await api("evaluate",{tabId,expression:setup})).success,true);
  const script={version:1,tabId,actions:[{action:"output",name:"before",source:"title"},{action:"fill",target:{label:"Realmfield",exact:true},text:literal}]};
  if(capturing)script.capture={formats:["screenshots"],fps:15,maxWidth:640,maxBytes:8388608};
  const result=await api("play-script",script),status=await api("get-script-status",{runId:result.runId});
  let state,polls=0;
  for(;polls<100;polls++){
   const response=await api("evaluate",{tabId,expression:"({phase:sessionStorage.getItem('realmPhase'),edits:Number(sessionStorage.getItem('realmEdits')),url:location.href})"});
   if(response.success&&response.result?.url===fixture.url+"/next"){state=response.result;break;}
   await sleep(50);
  }
  const text=JSON.stringify({result,status});
  const item={phase,capturing,runId:result.runId,success:result.success,error:result.error?.code,
   mayHaveCompleted:result.mayHaveCompleted,leakedRaw:text.includes(literal),leakedUri:text.includes(uri),leakedForm:text.includes(form),
   masked:typeof result.outputs?.before==="string"&&result.outputs.before.includes("[redacted]"),artifactCount:result.artifacts?.length??0,
   statusArtifacts:status.artifacts?.length??0,statusState:status.state,state,polls,
   canarySha256:createHash("sha256").update(literal).digest("hex")};
  report.cases.push(item);
  assert.equal(item.leakedRaw,false);assert.equal(item.leakedUri,false);assert.equal(item.leakedForm,false);
  assert.equal(item.masked,true);assert.equal(item.artifactCount,0);assert.equal(item.statusArtifacts,0);
  assert.ok(state,"Navigation did not retire into the expected new document");assert.equal(state.phase,phase);
  if(capturing)assert.equal(result.success,false);
  if(!result.success){assert.equal(result.mayHaveCompleted,true);assert.equal(status.runError?.code,result.error?.code);}
  const recovery=await api("play-script",{version:1,tabId,actions:[{action:"navigate",url:fixture.url},
   {action:"wait-ready",state:"complete"},{action:"click",target:{role:"button",name:"Confirm order",exact:true}}]});
  item.recovery=recovery.success;assert.equal(recovery.success,true,JSON.stringify(recovery.error));
 }
}catch(error){report.error=error.message;process.exitCode=1;}
finally{await writeFile(outputPath,JSON.stringify(report,null,2));await fixture.close();}
console.log(JSON.stringify(report));
