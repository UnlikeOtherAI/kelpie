import {canary} from "./runtime-fixture.mjs";
import {delay,requireTrue,waitFor} from "./runtime-client.mjs";
import {inspectMedia,inspectPaced} from "./runtime-media.mjs";

export async function runPaced({client,fixture,engine,base,capture,check,load,play}){
 const target={label:"Draft message"};
 await check("paced-fill-type-media",async()=>{
  await load("/paced");const begin=fixture.events.length;
  const result=await client.api("play-script",{...base,tapIndicator:{color:"#F54242",radius:2,durationMs:100,wobble:false,fade:true},
   capture:{...capture,formats:["gif","video"],fps:10},actions:[
    {action:"output",name:"before",source:"title"},
    {action:"fill",target,text:"A😀e",typingDelayMs:250},
    {action:"type",target,text:"xy",typingDelayMs:250}]});
  requireTrue(result.success,"PACED_MEDIA_WORKFLOW");
  requireTrue(result.outputs?.before?.includes("A😀e"),"PACED_ORDINARY_OUTPUT_REDACTED");
  const inputs=fixture.events.slice(begin).filter(e=>e.type==="paced-input"&&e.target==="entry");
  requireTrue(inputs.length===6&&inputs.map(e=>e.length).join(",")==="0,1,3,4,5,6","PACED_INPUT_SEQUENCE");
  const intervals=[inputs[2].time-inputs[1].time,inputs[3].time-inputs[2].time,inputs[5].time-inputs[4].time];
  requireTrue(intervals.every(value=>value>=190),"PACED_INTERVAL");
  const artifacts=await client.download(result,engine+"-paced"),movies=artifacts.filter(a=>a.mimeType!=="image/png");
  requireTrue(movies.length===2&&movies.some(a=>a.mimeType==="image/gif")&&movies.some(a=>a.mimeType==="video/mp4"),"PACED_MEDIA_FORMATS");
  return {lengths:inputs.map(e=>e.length),intervals,ordinaryOutputPreserved:true,media:movies.map(item=>({decode:inspectMedia(item),text:inspectPaced(item,inputs[1])}))};
 });
 await check("paced-empty-type-screenshot",async()=>{
  await load("/paced");const begin=fixture.events.length;
  const value=await client.api("play-script",{...base,pointer:{enabled:true},capture:{...capture,formats:["screenshots"]},
   actions:[{action:"type",target,text:"",typingDelayMs:250}]});
  const events=fixture.events.slice(begin);
  requireTrue(value.success&&(value.artifacts??[]).some(a=>a.mimeType==="image/png"&&a.actionIndex===0),"PACED_EMPTY_SCREENSHOT");
  requireTrue(!events.some(e=>e.type==="paced-focus"||e.type==="paced-input"),"PACED_EMPTY_FOCUSED_OR_WROTE");
  return {screenshot:true,noFocusOrInput:true};
 });
 await check("paced-empty-type-ineligible",async()=>{
  await load("/paced");
  for(const ineligible of [{role:"button",name:"Submit"},{label:"Static readonly"}]){
   const begin=fixture.events.length;
   const value=await play([{action:"type",target:ineligible,text:"",typingDelayMs:250}]);
   requireTrue(!value.success&&value.error?.code==="TARGET_NOT_EDITABLE","PACED_EMPTY_INELIGIBLE");
   requireTrue(!fixture.events.slice(begin).some(e=>e.type==="paced-focus"||e.type==="paced-input"),"PACED_EMPTY_INELIGIBLE_FOCUSED");
  }
  return {buttonRefused:true,readonlyRefused:true,noFocusOrInput:true};
 });
 for(const route of ["/paced-blur","/paced-replace"])await check("paced-fence-"+route.slice(7),async()=>{
  await load(route);const begin=fixture.events.length;
  const value=await client.api("play-script",{...base,capture:{...capture,formats:["screenshots"]},
   actions:[{action:"type",target,text:"ABC",typingDelayMs:250}]});
  const inputs=fixture.events.slice(begin).filter(e=>e.type==="paced-input"&&e.target==="entry");
  requireTrue(!value.success&&value.mayHaveCompleted===true&&inputs.length===1,"PACED_FENCE_OR_REPLAY");
  const artifacts=value.artifacts??[];
  if(route==="/paced-blur")requireTrue(artifacts.length===0,"PACED_UNKNOWN_FOCUS_MEDIA_RETAINED");
  else requireTrue(artifacts.some(a=>a.partial),"PACED_FENCE_PARTIAL");
  return {code:value.error?.code,inputs:inputs.length,discardedUnknownFocus:route==="/paced-blur",partialRetained:route==="/paced-replace"};
 });
 for(const recording of [true,false])await check("paced-late-sensitive-"+(recording?"capture":"no-capture"),async()=>{
  await load("/paced-sensitive");const begin=fixture.events.length;
  const value=await client.api("play-script",{...base,...(recording?{capture:{...capture,formats:["screenshots"]}}:{}),actions:[
   {action:"output",name:"before",source:"title"},
   {action:"type",target:{label:"Focus privacy"},text:canary,typingDelayMs:20}]});
  const inputs=fixture.events.slice(begin).filter(e=>e.type==="paced-input"&&e.target==="focus-privacy");
  const serialized=JSON.stringify(value);
  for(const variant of [canary,encodeURIComponent(canary),new URLSearchParams({v:canary}).toString().slice(2)])
   requireTrue(!serialized.includes(variant),"PACED_SENSITIVE_LEAK");
  requireTrue(value.outputs?.before?.includes("[redacted]"),"PACED_SENSITIVE_NOT_SCRUBBED");
  if(recording)requireTrue(!value.success&&inputs.length===1&&(value.artifacts??[]).length===0,"PACED_SENSITIVE_CAPTURE");
  else requireTrue(value.success&&inputs.length===Array.from(canary).length,"PACED_SENSITIVE_NO_CAPTURE");
  return {recording,code:value.error?.code??null,inputs:inputs.length,scrubbed:true,artifactsDiscarded:recording};
 });
 await check("paced-final-ack-navigation",async()=>{
  await load("/paced-final-url");const begin=fixture.events.length;
  const value=await client.api("play-script",{...base,actions:[
   {action:"type",target,text:"Z",typingDelayMs:20},{action:"output",name:"after",source:"url"}]});
  const inputs=fixture.events.slice(begin).filter(e=>e.type==="paced-input"&&e.target==="entry");
  requireTrue(value.success&&inputs.length===1&&value.outputs?.after?.endsWith("/paced-final-url-changed"),"PACED_FINAL_ACK_NAVIGATION");
  return {acknowledged:true,inputs:inputs.length,navigationObserved:true};
 });
 for(const recording of [true,false])await check("paced-final-lost-ack-"+(recording?"capture":"no-capture"),async()=>{
  await load("/paced-final-delay");const begin=fixture.events.length,started=Date.now();
  const value=await client.api("play-script",{...base,...(recording?{capture:{...capture,formats:["screenshots"]}}:{}),actions:[
   {action:"output",name:"before",source:"title"},{action:"type",target,text:"X",typingDelayMs:20}]});
  const inputs=fixture.events.slice(begin).filter(e=>e.type==="paced-input"&&e.target==="entry");
  requireTrue(!value.success&&value.error?.code==="TIMEOUT"&&value.mayHaveCompleted===true&&inputs.length===1&&Date.now()-started>=5300,"PACED_FINAL_LOST_ACK");
  requireTrue(value.outputs?.before?.includes("[redacted]"),"PACED_FINAL_LOST_ACK_NOT_SCRUBBED");
  if(recording)requireTrue((value.artifacts??[]).length===0,"PACED_FINAL_LOST_ACK_MEDIA_RETAINED");
  return {recording,code:value.error.code,inputs:inputs.length,scrubbed:true,discarded:recording};
 });
 await check("paced-abort-partial-recovery",async()=>{
  await load("/paced");const begin=fixture.events.length;
  const pending=client.api("play-script",{...base,capture:{...capture,formats:["gif"],fps:10},
   actions:[{action:"type",target,text:"abcdef",typingDelayMs:500}]});
  void pending.catch(()=>{});
  await waitFor(()=>fixture.events.slice(begin).filter(e=>e.type==="paced-input"&&e.target==="entry").length>=2);
  const status=await client.api("get-script-status");
  requireTrue(status.playing&&status.runId,"PACED_ACTIVE_STATUS");
  const aborted=await client.api("abort-script",{runId:status.runId});requireTrue(aborted.success,"PACED_ABORT_REQUEST");
  const result=await pending;
  const count=fixture.events.slice(begin).filter(e=>e.type==="paced-input"&&e.target==="entry").length;
  requireTrue(!result.success&&result.state==="aborted"&&result.mayHaveCompleted===true&&count>=2&&count<6,"PACED_ABORT_STATE");
  const artifacts=await client.download(result,engine+"-paced-abort");
  requireTrue(artifacts.some(a=>a.mimeType==="image/gif"&&a.partial),"PACED_ABORT_PARTIAL");
  const decoded=artifacts.map(a=>inspectMedia(a));
  await delay(200);
  requireTrue(fixture.events.slice(begin).filter(e=>e.type==="paced-input"&&e.target==="entry").length===count,"PACED_ABORT_LATE_INPUT");
  const recovery=await play([{action:"click",target:{role:"button",name:"Submit"}}]);
  requireTrue(recovery.success,"PACED_ABORT_RECOVERY");
  return {inputs:count,decoded,recovered:true};
 });
 await check("paced-full-preflight",async()=>{
  await load("/paced");const begin=fixture.events.length;
  const value=await client.api("play-script",{...base,actions:[{action:"click",target:{role:"button",name:"Submit"}},
   {action:"type",target,text:"x".repeat(1001),typingDelayMs:1}]});
  await delay(100);
  requireTrue(!value.success&&value.error?.code==="INVALID_PACED_TYPING"&&!fixture.events.slice(begin).some(e=>e.type==="click"),"PACED_PREFLIGHT");
  return {code:value.error.code,noPriorMutation:true};
 });
}