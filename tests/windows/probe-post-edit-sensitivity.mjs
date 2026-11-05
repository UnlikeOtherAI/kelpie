import assert from "node:assert/strict";
import {readFile,writeFile} from "node:fs/promises";
import {randomUUID,createHash} from "node:crypto";
import {startCaptureFixture} from "../capture/fixture-server.mjs";
const [readinessPath,outputPath,expectation="diagnostic"]=process.argv.slice(2);
const ready=JSON.parse(await readFile(readinessPath,"utf8"));
const report={source:process.env.KELPIE_CAPTURE_SOURCE,expectation,cases:[]};
const api=async(method,body={})=>(await fetch("http://127.0.0.1:"+ready.port+"/v1/"+method,{
 method:"POST",headers:{authorization:"Bearer "+ready.token,"content-type":"application/json"},
 body:JSON.stringify(body),signal:AbortSignal.timeout(20000)})).json();
const evaluate=async(tabId,expression)=>(await api("evaluate",{tabId,expression})).result;
const fixture=await startCaptureFixture();
try{
 await api("navigate",{url:fixture.url});
 const tabs=await api("get-tabs"),tabId=tabs.tabs.find(t=>t.active).id;
 await api("scroll",{tabId,deltaX:0,deltaY:-100000});
 const top=await evaluate(tabId,"document.querySelector('textarea').getBoundingClientRect().top");
 await api("scroll",{tabId,deltaX:0,deltaY:top-150});
 await evaluate(tabId,`(()=>{window.__metricTrace=[];window.__metric=()=>({layout:{width:innerWidth,height:innerHeight},scroll:{x:scrollX,y:scrollY},visual:{offsetLeft:visualViewport.offsetLeft,offsetTop:visualViewport.offsetTop,width:visualViewport.width,height:visualViewport.height,scale:visualViewport.scale},rect:(()=>{let r=document.querySelector('textarea').getBoundingClientRect();return{x:r.x,y:r.y,width:r.width,height:r.height}})()});window.__metricTrace.push({event:'before',metrics:window.__metric()});for(const name of ['pointerdown','mousedown','focus','input','keydown','keyup'])document.querySelector('textarea').addEventListener(name,()=>window.__metricTrace.push({event:name,metrics:window.__metric()}));for(const name of ['resize','scroll'])visualViewport.addEventListener(name,()=>window.__metricTrace.push({event:'visual-'+name,metrics:window.__metric()}));return true})()`);
 const normal=await api("play-script",{version:1,tabId,actions:[{action:"fill",target:{label:"Draft message",exact:true},text:"METRIC_DIAGNOSTIC"}]});
 report.normal={success:normal.success,error:normal.error?.code,mayHaveCompleted:normal.mayHaveCompleted,
  trace:await evaluate(tabId,"window.__metricTrace.concat([{event:'after',metrics:window.__metric()}])")};
 for(const capturing of [false,true])for(const mode of ["autocomplete","password-type"]){
  await api("navigate",{tabId,url:"about:blank"});
  const literal="SyntheticInput Aa b+! "+randomUUID(),uri=encodeURIComponent(literal).replace(/%2B/g,"%2b"),
   form=new URLSearchParams({value:literal}).toString().slice(6).replace(/%2B/g,"%2b");
  const mutation=mode==="autocomplete"?"e.autocomplete='current-password'":"e.type='password'";
  await evaluate(tabId,"(()=>{document.title="+JSON.stringify(literal+" "+uri+" "+form)+";document.body.innerHTML='<input aria-label=Editfield style=\"position:absolute;left:24px;top:100px;width:200px;height:30px\">';window.__edits=0;const e=document.querySelector('input');e.oninput=()=>{window.__edits++;"+mutation+"};return true})()");
  const script={version:1,tabId,actions:[{action:"output",name:"before",source:"title"},{action:"fill",target:{label:"Editfield",exact:true},text:literal}]};
  if(capturing)script.capture={formats:["screenshots"],fps:15,maxWidth:640,maxBytes:8388608};
  const result=await api("play-script",script),text=JSON.stringify(result);
  const state=await evaluate(tabId,"(()=>{const e=document.querySelector('input');return {edits:window.__edits,sensitive:e.type==='password'||e.autocomplete==='current-password'}})()");
  const recovery=await api("play-script",{version:1,tabId,actions:[{action:"wait",ms:0}]});
  const item={mode,capturing,success:result.success,error:result.error?.code,mayHaveCompleted:result.mayHaveCompleted,
   leakedRaw:text.includes(literal),leakedUri:text.includes(uri),leakedForm:text.includes(form),
   masked:typeof result.outputs?.before==="string"&&result.outputs.before.includes("[redacted]"),
   artifactCount:result.artifacts?.length??0,state,recovery:recovery.success,
   canarySha256:createHash("sha256").update(literal).digest("hex")};
  report.cases.push(item);
  if(expectation==="expect-fixed"){
   assert.equal(item.leakedRaw,false);assert.equal(item.leakedUri,false);assert.equal(item.leakedForm,false);assert.equal(item.masked,true);
   assert.equal(item.state.edits,1);assert.equal(item.state.sensitive,true);assert.equal(item.artifactCount,0);assert.equal(item.recovery,true);
   assert.equal(item.success,!capturing);if(capturing){assert.equal(item.error,"SENSITIVE_CAPTURE_REFUSED");assert.equal(item.mayHaveCompleted,true);}
  }
 }
}catch(error){report.error=error.message;process.exitCode=1;}
finally{await writeFile(outputPath,JSON.stringify(report,null,2));await fixture.close();}
console.log(JSON.stringify(report));
