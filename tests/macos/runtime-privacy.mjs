import {canary} from "./runtime-fixture.mjs";
import {requireTrue} from "./runtime-client.mjs";

export async function runPrivacy({client,fixture,base,capture,check,load}) {
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
}
