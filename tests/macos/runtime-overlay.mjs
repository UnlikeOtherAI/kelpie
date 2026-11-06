import {execFileSync} from "node:child_process";
import {createHash} from "node:crypto";
import {copyFile,readFile,readdir} from "node:fs/promises";
import path from "node:path";
import {delay,requireTrue,waitFor} from "./runtime-client.mjs";
import {inspectCurve,inspectMedia} from "./runtime-media.mjs";
import {overlayScene} from "./runtime-overlay-scene.mjs";

// Animated page damage drives these diagnostic frames; this is not static-page evidence.
export async function runHostedOverlay({client,fixture,engine,base,capture,check,load,report}){
 await check("cef-animated-overlay-c",async()=>{
  await load("/stream");await client.activateOwnedBrowser();const begin=fixture.events.length;
  const result=await client.api("play-script",{...base,pointer:{enabled:true,curve:"c",durationMs:1200,easing:"ease-in-out"},
   tapIndicator:{color:"#22CCFF",radius:12,durationMs:700,wobble:false,fade:false},
   capture:{...capture,formats:["video"],fps:30},actions:[
    {action:"click",target:{role:"button",name:"First"}},{action:"wait",ms:300},
    {action:"click",target:{role:"button",name:"Second"}},{action:"wait",ms:300}]});
  requireTrue(result.success&&/^[0-9a-f-]{36}$/i.test(result.runId),"OVERLAY_WORKFLOW");
  const scene=overlayScene(fixture.events.slice(begin));
  requireTrue(scene,"OVERLAY_EVENTS");
  const evidence={condition:"animated-fixture",scene};
  report.overlayFacts=evidence;
  const file=path.join(client.overlayDir,`overlay-${result.runId}.mp4`),data=await readFile(file);
  const meta=JSON.parse(execFileSync("ffprobe",["-v","error","-select_streams","v:0","-show_streams","-of","json",file],{maxBuffer:1048576}));
  const stream=meta.streams[0];requireTrue(stream?.width>0&&stream?.height>0,"OVERLAY_DIMENSIONS");
  const artifact={file,mimeType:"video/mp4",width:stream.width,height:stream.height};
  const saved=path.join(client.out,engine+"-animated-overlay-c.mp4");await copyFile(file,saved);
  evidence.file=saved;
  evidence.sha256=createHash("sha256").update(data).digest("hex");
  evidence.media=inspectMedia(artifact);
  const snapshot=await client.download(result,engine+"-overlay-snapshot");
  requireTrue(snapshot.length===1&&snapshot[0].mimeType==="video/mp4","OVERLAY_SNAPSHOT");
  evidence.snapshotMedia=inspectMedia(snapshot[0]);
  return {...evidence,motion:inspectCurve(artifact,"c",scene)};
 },{continueOnFailure:true});
 await check("cef-overlay-document-change-discards",async()=>{
  await load("/stream-nav");await client.activateOwnedBrowser();const before=new Set(await readdir(client.overlayDir));
  const begin=report.streamSignals.length;
  const pending=client.api("play-script",{...base,capture:{...capture,formats:["video"],fps:30},actions:[{action:"wait",ms:2500}]});
  void pending.catch(()=>{});await waitFor(()=>report.streamSignals.slice(begin).some(event=>event.event==="started"));
  fixture.armStreamNavigation();const result=await pending;
  await waitFor(()=>report.streamSignals.slice(begin).some(event=>event.event==="discarded"||event.event==="complete"),5000);
  await delay(100);const events=report.streamSignals.slice(begin),after=await readdir(client.overlayDir);
  requireTrue(events.some(e=>e.event==="discarded")&&!events.some(e=>e.event==="sample"||e.event==="complete")&&
   after.every(name=>before.has(name)),"OVERLAY_STALE_OUTPUT");
  return {condition:"animated-fixture",documentTransitionArmed:true,discarded:true,workflowSuccess:result.success===true};
 },{continueOnFailure:true});
}
