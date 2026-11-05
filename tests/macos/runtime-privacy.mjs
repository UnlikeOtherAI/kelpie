import {canary} from "./runtime-fixture.mjs";
import {requireTrue,waitFor} from "./runtime-client.mjs";

export async function runPrivacy({client,fixture,base,capture,check,load,authorityRun,foreignToken}) {
 const variants=[canary,encodeURIComponent(canary),new URLSearchParams({v:canary}).toString().slice(2)];
 for(const route of ["/focus-password","/focus-autocomplete","/focus-url","/focus-delay","/input-autocomplete"]){
  for(const recording of route==="/focus-delay"||route==="/input-autocomplete"?[true,false]:[true]){
   await check("late-sensitive-"+route.slice(1)+(recording?"-capture":"-no-capture"),async()=>{
    await load(route);const begin=fixture.events.length;
    const started=Date.now();
    const value=await client.api("play-script",{...base,...(recording?{capture:{...capture,formats:["screenshots"]}}:{}),actions:[
     {action:"output",name:"before",source:"title"},
     {action:"fill",target:{label:"Focus privacy"},text:canary}]});
    const elapsedMs=Date.now()-started;
    const status=await client.api("get-script-status",{runId:value.runId});
    const serialized=JSON.stringify({value,status});
    for(const variant of variants)requireTrue(!serialized.includes(variant),"LATE_SENSITIVE_OUTPUT_LEAK");
    requireTrue(value.outputs?.before?.includes("[redacted]"),"LATE_SENSITIVE_OUTPUT_NOT_SCRUBBED");
    requireTrue(!("outputs" in status),"LATE_STATUS_OUTPUT_LEAK");
    const inputs=fixture.events.slice(begin).filter(e=>e.type==="input"&&e.target==="focus-privacy").length;
    if(recording){
     requireTrue(!value.success&&(value.artifacts??[]).length===0,"LATE_SENSITIVE_CAPTURE_RETAINED");
     if(route!=="/input-autocomplete")requireTrue(inputs===0,"SENSITIVE_FOCUS_INPUT_OCCURRED");
    }
    if(route==="/focus-delay")requireTrue(!value.success&&elapsedMs>=5300,"LATE_CALLBACK_NOT_RETIRED");
    return {recording,code:value.error?.code??null,elapsedMs,inputs,priorOutputScrubbed:true,artifactsDiscarded:recording};
   });
  }
 }
 await check("known-nonsensitive-navigation-retains-partial",async()=>{
  await load("/known-url");
  const value=await client.api("play-script",{...base,capture:{...capture,formats:["screenshots"]},actions:[
   {action:"output",name:"before",source:"title"},{action:"click",target:{role:"button",name:"Submit"}}]});
  requireTrue(!value.success,"KNOWN_NAVIGATION_GUARD_MISSING");
  requireTrue(value.outputs?.before?.includes(canary),"KNOWN_NONSENSITIVE_OUTPUT_OVERSCRUBBED");
  requireTrue((value.artifacts??[]).some(a=>a.partial),"KNOWN_NONSENSITIVE_PARTIAL_DISCARDED");
  const recovery=await client.api("play-script",{...base,actions:[{action:"wait",ms:1}]});
  requireTrue(recovery.success,"KNOWN_GUARD_RECOVERY_FAILED");
  return {code:value.error?.code,partialRetained:true,ordinaryOutputPreserved:true,recovered:true};
 });
 await check("late-sensitive-cancel-active-artifact-fence",async()=>{
  await load("/focus-delay");const begin=fixture.events.length;
  const pending=client.api("play-script",{...base,capture:{...capture,formats:["screenshots"]},actions:[
   {action:"output",name:"before",source:"title"},{action:"fill",target:{label:"Focus privacy"},text:canary}]});
  // Observe completion immediately, including transport failure, without leaving an unhandled rejection.
  const settled=pending.then(value=>({value}),()=>({transportFailed:true}));
  await waitFor(()=>fixture.events.slice(begin).some(e=>e.type==="focus-privacy"));
  const active=await client.api("get-script-status");requireTrue(active.playing&&active.runId,"ACTIVE_RUN_MISSING");
  const abort=await client.api("abort-script",{runId:active.runId});requireTrue(abort.success,"ACTIVE_ABORT_FAILED");
  const finalizing=await waitFor(async()=>{const status=await client.api("get-script-status",{runId:active.runId});return status.state==="finalizing"?status:null;});
  requireTrue((finalizing.artifacts??[]).length===0,"ACTIVE_STATUS_MEDIA_EXPOSED");
  const request={runId:active.runId,artifactId:"pending-artifact",offset:0,length:1024};
  for(const read of [()=>client.api("get-script-artifact",request),()=>client.direct("kelpie_get_script_artifact",request),()=>client.direct("kelpie_get_script_artifact",request,true)]){
   const value=await read();requireTrue(!value.success&&value.error?.code==="ARTIFACT_NOT_READY"&&!value.data,"ACTIVE_MEDIA_EXPOSED");
  }
  const foreign=await client.api("get-script-artifact",request,foreignToken);
  requireTrue(!foreign.success&&foreign.error?.code==="ARTIFACT_NOT_FOUND","FOREIGN_ACTIVE_MEDIA_DISCLOSED");
  const old=await client.api("get-script-artifact",{runId:authorityRun.runId,artifactId:authorityRun.artifacts[0].id,offset:0,length:1024});
  requireTrue(old.success&&typeof old.data==="string","PRIOR_SAFE_MEDIA_BLOCKED");
  const result=await settled;requireTrue(!result.transportFailed,"CANCEL_TRANSPORT_FAILED");
  const value=result.value,serialized=JSON.stringify(value);
  requireTrue(!value.success&&(value.artifacts??[]).length===0,"CANCEL_PRIVACY_MEDIA_RETAINED");
  for(const variant of variants)requireTrue(!serialized.includes(variant),"CANCEL_PRIOR_OUTPUT_LEAK");
  requireTrue(!fixture.events.slice(begin).some(e=>e.type==="input"&&e.target==="focus-privacy"),"CANCEL_SENSITIVE_INPUT");
  return {code:value.error?.code,activeProtocolsWithheld:3,foreignDenied:true,priorSafeReadable:true,lateResultRetired:true};
 });

}
