import {execFileSync} from "node:child_process";
import {createHash} from "node:crypto";
import {copyFile,readFile,stat} from "node:fs/promises";
import path from "node:path";
import {requireTrue,waitFor} from "./runtime-client.mjs";
import {inspectMedia} from "./runtime-media.mjs";
import {overlayScene} from "./runtime-overlay-scene.mjs";

// No CSS or scripted page animation: only the workflow's ordinary click input can damage the page.
export async function runHostedStatic({client,fixture,engine,base,capture,check,load,report}){
 await check("cef-static-overlay-observation",async()=>{
  const begin=fixture.events.length;await load("/stream-static");await client.activateOwnedBrowser();
  const signalStart=report.streamSignals.length;
  const result=await client.api("play-script",{...base,pointer:{enabled:true,curve:"c",durationMs:1200,easing:"ease-in-out"},
   tapIndicator:{color:"#22CCFF",radius:12,durationMs:700,wobble:false,fade:false},
   capture:{...capture,formats:["video"],fps:30},actions:[
    {action:"wait",ms:1500},{action:"click",target:{role:"button",name:"First"}},{action:"wait",ms:300},
    {action:"click",target:{role:"button",name:"Second"}},{action:"wait",ms:300}]});
  requireTrue(result.success&&/^[0-9a-f-]{36}$/i.test(result.runId),"STATIC_WORKFLOW");
  await waitFor(()=>report.streamSignals.slice(signalStart).some(e=>e.event==="complete"||e.event==="discarded"),5000);
  const events=fixture.events.slice(begin),document=events.find(e=>e.type==="document"&&e.path==="/stream-static"),
   first=events.find(e=>e.type==="click"&&e.target==="first"),second=events.find(e=>e.type==="click"&&e.target==="second"),
   scene=overlayScene(events),signals=report.streamSignals.slice(signalStart),probe=signals.find(e=>e.event==="probe"),
   complete=signals.find(e=>e.event==="complete"),sparse=signals.find(e=>e.event==="sparse");
  requireTrue(document?.fixtureStatic===true&&first?.fixtureStatic===true&&second?.fixtureStatic===true&&scene,"STATIC_FIXTURE");
  requireTrue(probe&&complete&&!signals.some(e=>e.event==="discarded"),"STATIC_STREAM_AUDIT");
  const samples=signals.filter(e=>e.event==="sample");
  requireTrue(complete.count===samples.length,"STATIC_STREAM_COUNT");
  const evidence={condition:"static-fixture",fixtureStaticAtDocumentAndClicks:true,scene,
   rawEvents:{received:probe.received,consumed:probe.consumed,decoded:probe.decode,dropped:probe.drop},
   actualStreamReceiptsMs:samples.map(e=>e.receiptMs),sparse:sparse?{accepted:sparse.accepted}:null};
  report.staticOverlayFacts=evidence;
  const snapshot=await client.download(result,engine+"-static-snapshot");
  requireTrue(snapshot.length===1&&snapshot[0].mimeType==="video/mp4","STATIC_SNAPSHOT");
  evidence.snapshotMedia=inspectMedia(snapshot[0]);
  const file=path.join(client.overlayDir,`overlay-${result.runId}.mp4`);
  let exists=true;try{await stat(file)}catch(error){if(error.code!=="ENOENT")throw error;exists=false}
  if(sparse){requireTrue(!exists&&sparse.accepted<2,"STATIC_PLACEHOLDER");evidence.streamMedia=null;}
  else{
   requireTrue(exists,"STATIC_STREAM_MISSING");const data=await readFile(file);
   const meta=JSON.parse(execFileSync("ffprobe",["-v","error","-select_streams","v:0","-show_streams","-of","json",file],{maxBuffer:1048576}));
   const stream=meta.streams[0];requireTrue(stream?.width>0&&stream?.height>0,"STATIC_STREAM_DIMENSIONS");
   const saved=path.join(client.out,engine+"-static-stream.mp4");await copyFile(file,saved);
   evidence.streamMedia={file:saved,sha256:createHash("sha256").update(data).digest("hex"),
    ...inspectMedia({file,mimeType:"video/mp4",width:stream.width,height:stream.height})};
  }
  return evidence;
 },{continueOnFailure:true});
}
