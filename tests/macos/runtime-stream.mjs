import {delay,requireTrue,waitFor} from "./runtime-client.mjs";
import {inspectMedia} from "./runtime-media.mjs";

// The page is a local synthetic moving red square; no user page or pixels are exported.
export async function runHostedStream({client,fixture,engine,base,capture,check,load,report}){
 await check("cef-stream-synthetic-cadence",async()=>{
  await load("/stream");await client.activateOwnedBrowser();
  const begin=report.streamSignals.length;
  const result=await client.api("play-script",{...base,capture:{...capture,formats:["video"],fps:30},
   actions:[{action:"wait",ms:2500}]});
  requireTrue(result.success,"STREAM_CAPTURE");
  await waitFor(()=>report.streamSignals.slice(begin).some(event=>event.event==="complete"||event.event==="discarded"),5000);
  const events=report.streamSignals.slice(begin),samples=events.filter(event=>event.event==="sample"),
   complete=events.find(event=>event.event==="complete");
  requireTrue(events.some(event=>event.event==="started")&&complete&&complete.count===samples.length&&samples.length>=2,"STREAM_EVENTS");
  requireTrue(samples.every((sample,index)=>sample.index===index&&
   (!index||(sample.receiptMs>=samples[index-1].receiptMs&&sample.protocolMs>=samples[index-1].protocolMs))),"STREAM_TIMESTAMPS");
  const xs=samples.map(sample=>sample.x),range=Math.max(...xs)-Math.min(...xs);
  requireTrue(range>5,"STREAM_SYNTHETIC_MOTION");
  const gaps=samples.slice(1).map((sample,index)=>sample.receiptMs-samples[index].receiptMs);
  const artifacts=await client.download(result,engine+"-stream-comparison");
  return {samples:samples.length,receiptSpanMs:samples.at(-1).receiptMs,maxReceiptGapMs:Math.max(...gaps),
   syntheticRangePixels:range,media:artifacts.map(item=>inspectMedia(item))};
 },{continueOnFailure:true});
 await check("cef-stream-document-change-discards",async()=>{
  await load("/stream-nav");await client.activateOwnedBrowser();
  const begin=report.streamSignals.length;
  const pending=client.api("play-script",{...base,capture:{...capture,formats:["video"],fps:30},
   actions:[{action:"wait",ms:2500}]});void pending.catch(()=>{});
  await waitFor(()=>report.streamSignals.slice(begin).some(event=>event.event==="started"));
  fixture.armStreamNavigation();
  const result=await pending;
  await waitFor(()=>report.streamSignals.slice(begin).some(event=>event.event==="discarded"||event.event==="complete"),5000);
  await delay(100);
  const events=report.streamSignals.slice(begin);
  requireTrue(events.some(event=>event.event==="discarded")&&!events.some(event=>event.event==="sample"||event.event==="complete"),
   "STREAM_STALE_OUTPUT");
  return {documentTransitionArmed:true,discarded:true,workflowSuccess:result.success===true};
 },{continueOnFailure:true});
}
