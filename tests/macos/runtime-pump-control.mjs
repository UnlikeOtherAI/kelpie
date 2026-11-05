import {delay,requireTrue,waitFor} from "./runtime-client.mjs";

// Controls run on both pump modes, even if a timing oracle is insufficient.
export async function runPumpControls({client,fixture,base,capture,check,load,play}){
 await check("pump-native-stop-recovery",async()=>{
  await load();
  const pending=client.api("play-script",{...base,capture:{...capture,formats:["gif"]},actions:[{action:"wait",ms:8000}]});
  void pending.catch(()=>{});
  await waitFor(async()=>{const value=await client.api("get-script-status");return value.playing&&value.runId?value:null;});
  const window=await waitFor(()=>client.find("browser.recording.stop"));
  await client.tap("browser.recording.stop",window);
  const result=await pending;
  requireTrue(!result.success&&result.state==="aborted","PUMP_STOP_FAILED");
  const recovery=await play([{action:"click",target:{role:"button",name:"Submit"}}]);
  requireTrue(recovery.success,"PUMP_STOP_RECOVERY");
  return {aborted:true,recovered:true};
 },{continueOnFailure:true});
 await check("pump-callback-retirement",async()=>{
  await load("/paced-final-delay");const begin=fixture.events.length,started=Date.now();
  const result=await play([{action:"type",target:{label:"Draft message"},text:"X",typingDelayMs:20}]);
  const inputs=()=>fixture.events.slice(begin).filter(e=>e.type==="paced-input"&&e.target==="entry").length;
  requireTrue(!result.success&&result.error?.code==="TIMEOUT"&&result.mayHaveCompleted===true&&
   inputs()===1&&Date.now()-started>=5300,"PUMP_CALLBACK_RETIREMENT");
  await delay(200);requireTrue(inputs()===1,"PUMP_CALLBACK_REPLAYED");
  const recovery=await play([{action:"click",target:{role:"button",name:"Submit"}}]);
  requireTrue(recovery.success,"PUMP_CALLBACK_RECOVERY");
  return {timeout:true,inputs:1,retired:true,recovered:true};
 },{continueOnFailure:true});
}
