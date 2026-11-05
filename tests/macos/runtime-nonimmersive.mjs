import {delay,requireTrue,waitFor} from "./runtime-client.mjs";

// Stop stays available while ordinary chrome remains visible but cannot be operated.
export async function runNonimmersive({client,engine,base,capture,check,load,play}){
 for(const mode of ["no-capture","png-only"]){
  await check("nonimmersive-stop-and-chrome-"+mode,async()=>{
   await load();await client.activateOwnedBrowser();
   const request={...base,actions:[{action:"wait",ms:8000}]};
   if(mode==="png-only")request.capture={...capture,formats:["screenshots"]};
   const pending=client.api("play-script",request);void pending.catch(()=>{});
   const status=await waitFor(async()=>{const value=await client.api("get-script-status");return value.playing&&value.runId?value:null;});
   let stopped=false;
   try{
   const chrome=await waitFor(()=>client.find("browser.action.more"));
   const stop=await waitFor(()=>client.find("browser.recording.stop"));
   const screenshot=await client.screenshot(engine+"-nonimmersive-"+mode+"-running");
   const action=await client.tool("tap_element",{element_id:"browser.action.more",window_id:chrome},true);
   await delay(100);
   requireTrue(!(await client.find("browser.renderer.webkit")),"NONIMMERSIVE_CHROME_OPERATED");
   requireTrue((await client.api("get-script-status")).playing,"NONIMMERSIVE_STOP_NOT_ACTIVE");
   await client.tap("browser.recording.stop",stop);
   const result=await pending;stopped=true;
   requireTrue(!result.success&&result.state==="aborted","NONIMMERSIVE_STOP_FAILED");
   const recovered=await play([{action:"click",target:{role:"button",name:"Submit"}}]);
   requireTrue(recovered.success,"NONIMMERSIVE_STOP_RECOVERY");
   return {chromeVisible:true,chromePressReported:action.success===true,stopVisible:true,aborted:true,recovered:true,screenshot};
   }finally{
    if(!stopped){await client.api("abort-script",{runId:status.runId}).catch(()=>{});await pending.catch(()=>{});}
   }
  },{continueOnFailure:true});
 }
}
