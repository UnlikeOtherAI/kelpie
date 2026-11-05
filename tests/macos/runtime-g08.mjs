import {execFileSync,spawnSync} from "node:child_process";
import {writeFile} from "node:fs/promises";
import path from "node:path";
import {startG08Fixture,g08Workflow} from "../capture/g08-fixture.mjs";
import {delay,requireTrue,waitFor} from "./runtime-client.mjs";

export async function runG08(client,tabId,engine,report){
 const cases=[];
 for(const curve of ["c","s"]){
  const fixture=await startG08Fixture();
  try{
   const navigation=await client.api("navigate",{tabId,url:fixture.url});
   requireTrue(navigation.success,"G08_NAVIGATION");
   const pending=client.api("play-script",g08Workflow(tabId,curve));
   void pending.catch(()=>{});
   await waitFor(()=>fixture.events[1]?.target==="start",20000);
   await delay(500);
   const first=await client.screenshot(engine+"-g08-"+curve+"-start");
   await waitFor(()=>fixture.events[2]?.target==="finish",15000);
   await delay(500);
   const last=await client.screenshot(engine+"-g08-"+curve+"-finish");
   const result=await pending;
   requireTrue(result.success,"G08_WORKFLOW");
   const facts=await (await fetch(fixture.url.replace("/g08","/events"))).json();
   requireTrue(facts.dropped===0&&facts.events.length===3&&facts.events[0].target==="finish"&&facts.events[1].target==="start"&&facts.events[2].target==="finish","G08_FACTS");
   const artifacts=await client.download(result,engine+"-g08-"+curve);
   for(const artifact of artifacts){
    const probe=JSON.parse(execFileSync("ffprobe",["-v","error","-select_streams","v:0","-show_frames","-show_entries","frame=best_effort_timestamp_time","-of","json",artifact.file],{maxBuffer:1048576}));
    artifact.timestamps=probe.frames.map(frame=>Number(frame.best_effort_timestamp_time));
   }
   cases.push({curve,scene:{calibration:facts.events[0],start:facts.events[1],finish:facts.events[2]},artifacts,nativeScreenshots:[first,last]});
  }finally{await fixture.close();}
 }
 const input={source:report.source,binarySHA256:report.executableHash,runtime:engine==="webkit"?"macos-webkit":"macos-cef",eventsDropped:0,cases};
 const inputPath=path.join(client.out,engine+"-g08-input.json"),outputPath=path.join(client.out,engine+"-g08-analysis.json");
 await writeFile(inputPath,JSON.stringify(input,null,2),{flag:"wx"});
 const verification=spawnSync(process.execPath,["tests/capture/g08-verify.mjs",inputPath,outputPath],{encoding:"utf8",timeout:300000,maxBuffer:1048576});
 requireTrue(verification.status===0,"G08_PIXEL_ORACLE");
 return {input:inputPath,analysis:outputPath,nativeScreenshots:cases.flatMap(item=>item.nativeScreenshots)};
}