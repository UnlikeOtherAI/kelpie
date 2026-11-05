import {execFileSync} from "node:child_process";
import {delay,requireTrue} from "./runtime-client.mjs";

// These owned-window screenshots show a noninteractive native overlay after the HTTP response.
function redPixels(image){
 const rgb=execFileSync("ffmpeg",["-v","error","-threads","1","-filter_threads","1","-i",image.file,
  "-frames:v","1","-f","rawvideo","-pix_fmt","rgb24","-"],{maxBuffer:32*1024*1024});
 requireTrue(rgb.length===image.width*image.height*3,"RETIREE_IMAGE_DECODE");
 let count=0;
 for(let i=0;i<rgb.length;i+=3)if(rgb[i]>180&&rgb[i+1]<140&&rgb[i+2]<150)count++;
 return count;
}

export async function runRetiree({client,engine,base,capture,check,load,report}){
 for(const mode of ["no-capture","png-only"]){
  await check("native-marker-retiree-"+mode,async()=>{
   await load("/motion");
   await client.activateOwnedBrowser();
   const baseline=redPixels(await client.screenshot(engine+"-retiree-"+mode+"-before"));
   const request={...base,tapIndicator:{color:"#F54242",radius:65,durationMs:5000,wobble:false,fade:false},
    actions:[{action:"click",target:{role:"button",name:"First"}}]};
   if(mode==="png-only")request.capture={...capture,formats:["screenshots"]};
   const start=Date.now(),result=await client.api("play-script",request),responseMs=Date.now()-start;
   requireTrue(result.success,"RETIREE_WORKFLOW");
   requireTrue(responseMs<3500,"RETIREE_BLOCKED_RESPONSE");
   if(mode==="png-only")requireTrue(result.artifacts?.some(item=>item.mimeType==="image/png"),"RETIREE_PNG_MISSING");
   const visible=redPixels(await client.screenshot(engine+"-retiree-"+mode+"-visible"));
   (report.retireeFacts??=[]).push({engine,mode,responseMs,visibleAtMs:Date.now()-start,baselineRedPixels:baseline,visibleRedPixels:visible});
   requireTrue(visible>baseline+100,"RETIREE_MARKER_NOT_VISIBLE");
   if(mode==="no-capture"){
    const next=await client.api("play-script",{...base,actions:[{action:"wait",ms:0}]});
    requireTrue(next.success,"RETIREE_NEXT_RUN");
   }else{
    await delay(5500);
   }
   const retired=redPixels(await client.screenshot(engine+"-retiree-"+mode+"-retired"));
   requireTrue(retired<visible-100,"RETIREE_MARKER_NOT_RETIRED");
   return {responseMs,baselineRedPixels:baseline,visibleRedPixels:visible,retiredRedPixels:retired,
    retiredBy:mode==="no-capture"?"new-run":"expiry"};
  },{continueOnFailure:true});
 }
}
