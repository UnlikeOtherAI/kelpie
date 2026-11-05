import assert from "node:assert/strict";
import {readFile,writeFile,mkdir} from "node:fs/promises";
import {resolve} from "node:path";
import {createHash} from "node:crypto";
import {startCaptureFixture} from "../capture/fixture-server.mjs";
import {scriptArtifactSchema,scriptArtifactChunkSchema} from "../../packages/shared/dist/index.js";
const [readinessPath,outputPath,mode="geometry"]=process.argv.slice(2);
const r=JSON.parse(await readFile(readinessPath,"utf8")),output=resolve(outputPath);
await mkdir(output,{recursive:false});
const fixture=await startCaptureFixture(),checks=[],artifacts=[];
const api=async(method,body={})=>{
 const response=await fetch("http://127.0.0.1:"+r.port+"/v1/"+method,{method:"POST",
 headers:{authorization:"Bearer "+r.token,"content-type":"application/json"},body:JSON.stringify(body),signal:AbortSignal.timeout(360000)});
 return response.json();
};
const tabs=await api("get-tabs"),tabId=tabs.tabs.find(t=>t.active).id;
const evaluate=async expression=>{const v=await api("evaluate",{tabId,expression});assert.equal(v.success,true);return v.result;};
const pause=ms=>new Promise(done=>setTimeout(done,ms));
const check=async(name,run)=>{if(process.env.KELPIE_GEOMETRY_CASE_FILTER&&!name.includes(process.env.KELPIE_GEOMETRY_CASE_FILTER))return;try{checks.push({name,passed:true,detail:await run()});}catch(e){checks.push({name,passed:false,error:e.message});}};
const download=async run=>{
 for(const raw of run.artifacts??[]){
  const item=scriptArtifactSchema.parse(raw),chunks=[];let offset=0;
  while(offset<item.byteLength){
   const c=scriptArtifactChunkSchema.parse(await api("get-script-artifact",{runId:run.runId,artifactId:item.id,offset,length:262144}));
   assert.equal(c.runId,run.runId);assert.equal(c.artifactId,item.id);assert.equal(c.offset,offset);
   const bytes=Buffer.from(c.data,"base64");assert.equal(c.nextOffset,offset+bytes.length);assert.ok(bytes.length>0);
   chunks.push(bytes);offset=c.nextOffset;assert.equal(c.eof,offset===item.byteLength);
  }
  const bytes=Buffer.concat(chunks);assert.equal(createHash("sha256").update(bytes).digest("hex"),item.sha256);
  const ext={"image/png":"png","image/gif":"gif","video/mp4":"mp4"}[item.mimeType];
  await writeFile(resolve(output,item.id+"."+ext),bytes);artifacts.push({runId:run.runId,...item});
 }
};
const navigate=async()=>{assert.equal((await api("navigate",{tabId,url:fixture.url})).success,true);assert.equal((await api("play-script",{version:1,tabId,actions:[{action:"wait-ready",state:"complete"}]})).success,true);};
try {
 await navigate();
 await check("actual page viewport facts",async()=>({native:await api("get-viewport"),
  page:await evaluate("({width:innerWidth,height:innerHeight,dpr:devicePixelRatio,scale:visualViewport.scale})")}));
 for(const zoom of [1,1.5])await check("clipped semantic center with page CSS zoom "+zoom,async()=>{
  await navigate();
  const facts=await evaluate("document.documentElement.style.zoom="+zoom+";document.querySelector('#partial').scrollIntoView({block:'center'});({width:innerWidth,height:innerHeight,dpr:devicePixelRatio,visualScale:visualViewport.scale,cssZoom:getComputedStyle(document.documentElement).zoom})");
  const from=fixture.events.length;
  const result=await api("play-script",{version:1,tabId,actions:[{action:"click",target:{role:"button",name:"Partially visible action",exact:true}}],
   capture:{formats:["gif","video","screenshots"],fps:15,maxWidth:640,maxBytes:8388608},
   tapIndicator:{color:"#00AAFF",radius:12,durationMs:400,wobble:false,fade:false}});
  await download(result);assert.equal(result.success,true,JSON.stringify(result.error));
  await evaluate("window.captureFixture.flush().then(()=>true)");
  const event=fixture.events.slice(from).find(e=>e.type==="click"&&e.target==="partial");
  assert.ok(event?.trusted);assert.equal(event.hit,"partial");
  assert.ok(Math.abs(event.x-(event.visible.left+event.visible.right)/2)<=1);
  assert.ok(Math.abs(event.y-(event.visible.top+event.visible.bottom)/2)<=1);
  return {runId:result.runId,facts,event};
 });
 if(mode==="motion")for(const curve of ["c","s"])await check("exported "+curve+" curve marker and no presentation hover",async()=>{
  await navigate();
  const scene=await evaluate("(()=>{const b=document.body;for(const e of [...b.children])e.style.display='none';b.style.cssText='margin:0;background:white;overflow:hidden;height:100vh;min-height:0';const w=innerWidth,h=innerHeight;for(const [id,x,y]of [['unique',w*.2,h*.3],['moving',w*.8,h*.7]]){const e=document.getElementById(id);b.append(e);e.setAttribute('aria-label',e.textContent);e.style.cssText='display:block;position:fixed;left:'+(x-40)+'px;top:'+(y-25)+'px;width:80px;min-width:0;height:50px;min-height:0;margin:0;border:1px solid #ccc;background:white;font-size:0';}const events=document.getElementById('events');b.append(events);events.style.display='none';return {first:{x:w*.2,y:h*.3},second:{x:w*.8,y:h*.7},width:w,height:h,began:performance.now()};})()");
  const from=fixture.events.length;
  const result=await api("play-script",{version:1,tabId,actions:[
   {action:"click",target:{role:"button",name:"Confirm order",exact:true}},
   {action:"click",target:{role:"button",name:"Moving action",exact:true}}],
   capture:{formats:["gif","video","screenshots"],fps:15,maxWidth:640,maxBytes:16777216,maxDurationMs:20000},
   pointer:{enabled:true,curve,durationMs:1500,easing:"ease-in-out"},
   tapIndicator:{color:curve==="c"?"#00AAFF":"#FF0000",radius:curve==="c"?12:30,durationMs:700,wobble:curve==="s",fade:curve==="s"}});
  assert.equal(result.success,true,JSON.stringify(result.error));await download(result);
  await evaluate("window.captureFixture.flush().then(()=>true)");
  const events=fixture.events.slice(from),clicks=events.filter(e=>e.type==="click");assert.equal(clicks.length,2);
  const moves=events.filter(e=>e.type==="pointermove");
  assert.ok(moves.every(e=>e.time-scene.began>=1400),"Presentation sent hover before configured motion elapsed");
  return {runId:result.runId,curve,scene,events,artifacts:result.artifacts};
 });
 await check("extraction attribution across navigation",async()=>{
  await navigate();
  const extract=()=>api("browser-control",{version:1,method:"tab.extract",tabId,params:{fields:[{name:"heading",selector:"h1",source:"text"}],metadata:true}});
  const first=await extract();assert.equal(first.ok,true);
  assert.equal((await api("navigate",{tabId,url:fixture.url+"/next"})).success,true);assert.equal((await api("play-script",{version:1,tabId,actions:[{action:"wait-ready",state:"complete"}]})).success,true);
  const second=await extract();assert.equal(second.ok,true);
  assert.notEqual(first.value.url,second.value.url);assert.deepEqual(first.value.fields[0].values,["Capture acceptance fixture"]);
  assert.deepEqual(second.value.fields[0].values,["Next document"]);
  assert.equal(second.value.fields[0].provenance.source,"text");
  return {first:first.value,second:second.value};
 });

 await check("active script refuses public viewport resize",async()=>{
  const before=await api("get-viewport");
  const pending=api("play-script",{version:1,tabId,actions:[{action:"wait",ms:2000}],
    capture:{formats:["gif","video"],fps:15,maxWidth:640,maxBytes:8388608}});
  pending.catch(()=>{}); // Observe early transport rejection while polling controls.
  let status;for(let i=0;i<50;i++){status=await api("get-script-status");if(status.playing)break;await pause(20);}
  assert.equal(status.playing,true);
  for(const method of ["resize-viewport","reset-viewport"]){
    const refusal=await api(method,{width:900,height:700});
    assert.equal(refusal.success,false);assert.equal(refusal.error.code,"BUSY");
  }
  assert.equal((await api("abort-script",{runId:status.runId})).success,true);
  const result=await pending;await download(result);assert.equal(result.success,false);
  assert.deepEqual(await api("get-viewport"),before);
  return {runId:result.runId,before,reason:"Existing public mutations serialize; no active-capture resize entry point"};
 });
} finally {
 const report={source:process.env.KELPIE_CAPTURE_SOURCE,launchId:r.launchId,mode,checks,artifacts};
 await writeFile(resolve(output,"report.json"),JSON.stringify(report,null,2));
 try{await fixture.close();report.cleanup="closed";}catch(e){report.cleanup="failed";checks.push({name:"cleanup",passed:false,error:e.message});}
 await writeFile(resolve(output,"report.json"),JSON.stringify(report,null,2));
}
console.log(JSON.stringify({passed:checks.filter(c=>c.passed).length,failed:checks.filter(c=>!c.passed).map(c=>({name:c.name,error:c.error}))}));
if(checks.some(c=>!c.passed))process.exitCode=1;
