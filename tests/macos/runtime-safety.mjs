import {requireTrue,waitFor,delay} from "./runtime-client.mjs";
import {startArtifactProtocolFixture} from "../capture/artifact-protocol-fixture.mjs";
import {inspectMedia} from "./runtime-media.mjs";
export async function runSafety({client,fixture,engine,base,capture,check,play,load}){
 await load();
 await check("clipped-and-scrolled-visible-centers",async()=>{
  const begin=fixture.events.length;
  const partial=await play([{action:"click",target:{role:"button",name:"Partially visible"}}]);
  requireTrue(partial.success,"CLIPPED_TARGET_CLICK");
  const first=await waitFor(()=>fixture.events.slice(begin).find(e=>e.type==="click"&&e.target==="partial"));
  requireTrue(first.hit==="partial"&&Math.abs(first.x-(first.rect.left+first.rect.right)/2)<2&&Math.abs(first.y-(first.rect.top+first.rect.bottom)/2)<2,"CLIPPED_VISIBLE_CENTER");
  const moved=await play([{action:"scroll",deltaY:1400},{action:"click",target:{role:"button",name:"Scrolled target"}}]);
  requireTrue(moved.success,"SCROLLED_TARGET_CLICK");
  const second=await waitFor(()=>fixture.events.slice(begin).find(e=>e.type==="click"&&e.target==="scroll-target"));
  requireTrue(second.scrollY>0&&second.hit==="scroll-target"&&Math.abs(second.y-(second.rect.top+second.rect.bottom)/2)<2,"SCROLLED_VISIBLE_CENTER");
  return {partial:first,scrolled:second};
 });
 await load();
 await check("replaced-hit-child-is-uncertain-without-replay",async()=>{
  const begin=fixture.events.length;
  const value=await play([{action:"click",target:{role:"button",name:"Replace child"}}]);
  await delay(100);
  const events=fixture.events.slice(begin).filter(e=>e.target==="replace");
  requireTrue(!value.success&&value.mayHaveCompleted===true,"DETACHED_HIT_NOT_REFUSED");
  requireTrue(events.filter(e=>e.type==="pointerdown").length===1&&!events.some(e=>e.type==="click"),"UNCERTAIN_ACTION_REPLAY");
  return {code:value.error?.code,mayHaveCompleted:true,pointerDowns:1,clicks:0};
 });
 await load();
 await check("focus-readonly-recheck",async()=>{
  const begin=fixture.events.length;
  const value=await play([{action:"fill",target:{label:"Readonly on focus"},text:"Do not insert"}]);
  await delay(100);requireTrue(!value.success&&!fixture.events.slice(begin).some(e=>e.type==="input"&&e.target==="readonly"),"READONLY_FOCUS_MUTATION");
  return {code:value.error?.code,noInput:true};
 });
 await load();
 await check("failed-predicate-stops-following-mutation",async()=>{
  const results=[];
  for(const action of [
   {action:"assert",target:{role:"button",name:"Disabled"},state:"enabled",timeoutMs:100},
   {action:"wait-ready",state:"complete",selector:"#duplicate-a,#duplicate-b",timeoutMs:100}
  ]){
   const begin=fixture.events.length,value=await play([action,{action:"click",target:{role:"button",name:"Submit"}}]);
   await delay(100);requireTrue(!value.success&&!fixture.events.slice(begin).some(e=>e.type==="click"),"PREDICATE_CONTINUED");
   results.push({action:action.action,code:value.error?.code});
  }
  const hidden=await play([{action:"assert",target:{role:"button",name:"Hidden"},state:"hidden",timeoutMs:100}]);
  requireTrue(hidden.success,"HIDDEN_ASSERTION");return results;
 });
 await check("strict-full-preflight",async()=>{
  const navigate={action:"navigate",url:fixture.url+"/next"},codes=[];
  for(const body of [
   {...base,version:2,actions:[navigate]},
   {...base,unexpected:true,actions:[navigate]},
   {...base,capture:{...capture,maxWidth:1921},actions:[navigate]},
   {...base,actions:[navigate,{action:"evaluate",script:"throw Error()"}]},
   {...base,inputs:{text:{type:"string"}},actions:[navigate,{action:"fill",target:{label:"Draft message"},text:{input:"text"}}]}
  ]){
   const begin=fixture.events.length,value=await client.api("play-script",body);
   await delay(100);requireTrue(!value.success&&!fixture.events.slice(begin).some(e=>e.type==="document"),"STRICT_PREFLIGHT_MUTATED");
   codes.push(value.error?.code);
  }return codes;
 });
 await check("explicit-and-automatic-step-pngs",async()=>{
  const explicit=await play([{action:"screenshot",name:"explicit"}]);
  requireTrue(explicit.success&&explicit.artifacts.length===1&&explicit.artifacts[0].mimeType==="image/png","SCREENSHOT_WITHOUT_CAPTURE");
  const mixed=await client.api("play-script",{...base,capture:{...capture,formats:["gif"]},actions:[
   {action:"click",target:{role:"button",name:"Submit"}},{action:"screenshot"},{action:"wait",ms:200}]});
  requireTrue(mixed.success&&mixed.artifacts.filter(a=>a.mimeType==="image/png").length===1&&mixed.artifacts.some(a=>a.mimeType==="image/png"&&a.actionIndex===1),"EXPLICIT_PNG_GIF_ONLY");
  const artifacts=await client.download(mixed,engine+"-explicit");
  return artifacts.map(a=>inspectMedia(a));
 });
 await check("duration-and-minimum-byte-budget-recover",async()=>{
  const expired=await client.api("play-script",{...base,capture:{...capture,formats:["screenshots"],maxDurationMs:100},actions:[{action:"wait",ms:400}]});
  requireTrue(!expired.success,"SCREENSHOTS_DURATION_NOT_ENFORCED");
  const limited=await client.api("play-script",{...base,capture:{...capture,formats:["gif","video"],maxBytes:1024},actions:[{action:"wait",ms:400}]});
  requireTrue(!limited.success&&(limited.artifacts??[]).every(a=>a.partial)&&(limited.artifacts??[]).reduce((sum,a)=>sum+a.byteLength,0)<=1024,"BYTE_LIMIT_NOT_ENFORCED");
  const recovered=await play([{action:"click",target:{role:"button",name:"Submit"}}]);requireTrue(recovered.success,"LIMIT_RECOVERY");
  return {durationCode:expired.error?.code,byteCode:limited.error?.code,recovered:true};
 });
 await check("malformed-and-interrupted-artifact-transfer",async()=>{
  const large=await startArtifactProtocolFixture();
  try{
  const loaded=await play([{action:"navigate",url:large.url},{action:"wait-ready",state:"complete",selector:"img"},{action:"wait",ms:500}]);requireTrue(loaded.success,"TRANSFER_FIXTURE_READY");
  const fresh=await play([{action:"screenshot"}]);
  const artifact=fresh.artifacts?.find(a=>a.byteLength>262*1024);requireTrue(fresh.success&&artifact,"TRANSFER_MULTICHUNK_ARTIFACT");
  const valid={runId:fresh.runId,artifactId:artifact.id,offset:0,length:262144};
  for(const patch of [{offset:-1},{offset:1.5},{length:0},{length:1048577},{offset:artifact.byteLength+1},{artifactId:"../../private"},{runId:"unknown-run"}]){
   const value=await client.api("get-script-artifact",{...valid,...patch});requireTrue(!value.success&&!value.data,"INVALID_CHUNK_LEAK");
  }
  const controller=new AbortController();let interrupted=false;
  try{await client.request("/v1/get-script-artifact",valid,{signal:controller.signal,onChunk:()=>controller.abort()});}
  catch{interrupted=true;}
  requireTrue(interrupted,"TRANSFER_NOT_INTERRUPTED");client.pin(28420);
  const recovery=await client.api("get-script-artifact",valid);
  requireTrue(recovery.success&&recovery.offset===0&&recovery.sha256===artifact.sha256&&recovery.data.length>0,"TRANSFER_RECOVERY");
  return {malformedCases:7,interrupted:true,recovered:true};
  }finally{await large.close();}
 });
 await load();
 await check("revoked-active-grant-cannot-status-abort-download",async()=>{
  const token=await client.pair("Hosted revocation "+engine);
  const pending=client.request("/v1/play-script",{...base,capture:{...capture,formats:["gif"]},actions:[{action:"wait",ms:8000}]},{token,timeout:12000}).catch(()=>({status:0,value:{success:false}}));
  const running=await waitFor(async()=>{const value=await client.api("get-script-status",{},token);return value.playing&&value.runId?value:null;});
  const revoked=await client.request("/v1/pair",{}, {method:"DELETE",token});requireTrue(revoked.value.success,"GRANT_REVOKE");
  const value=await pending;requireTrue(value.status>0&&!value.value.success,"REVOKED_RUNNING_RESULT");
  for(const method of ["get-script-status","abort-script","get-script-artifact"]){
   const denied=await client.request("/v1/"+method,method==="get-script-artifact"?{runId:running.runId,artifactId:"opaque",offset:0,length:1024}:{runId:running.runId},{token});
   requireTrue([401,403].includes(denied.status)&&!denied.value.data&&!denied.value.outputs&&!denied.value.artifacts,"REVOKED_GRANT_ACCESS");
  }
  const recovery=await play([{action:"click",target:{role:"button",name:"Submit"}}]);requireTrue(recovery.success,"REVOCATION_RECOVERY");
  return {revokedWhileRunning:true,allControlsDenied:true,otherOwnerRecovered:true};
 });
}
