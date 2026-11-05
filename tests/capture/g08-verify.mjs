import assert from "node:assert/strict";
import {readFile,writeFile,stat} from "node:fs/promises";
import {createReadStream} from "node:fs";
import {createHash} from "node:crypto";
import {spawn,spawnSync} from "node:child_process";
import {resolve} from "node:path";
import {consumeG08Frames} from "./g08-frame-stream.mjs";
import {measureG08Frame} from "./g08-pixels.mjs";
import {evaluateG08} from "./g08-timeline.mjs";
import {validateG08PTS} from "./g08-pts.mjs";
const [inputPath,outputPath]=process.argv.slice(2);
assert.ok(outputPath,"Provide owned joined artifact/decoder input and fresh output path");
assert.ok((await stat(inputPath)).size<=524288,"Input report exceeds bound");
const input=JSON.parse(await readFile(inputPath,"utf8"));
assert.match(input.source,/^[a-f0-9]{40}$/);
assert.match(input.binarySHA256,/^[a-f0-9]{64}$/);
const runtimes=["windows-cef","linux-gtk-cef","linux-osr-cef","macos-webkit","macos-cef",
  "ios-iphone-webkit","ios-ipad-webkit","android-phone-chromium","android-tablet-chromium"];
assert.ok(runtimes.includes(input.runtime),"Choose an exact native renderer/runtime profile");
assert.equal(input.eventsDropped,0,"Dropped fixture facts invalidate scene evidence");
assert.equal(input.cases.length,2);
const output={version:1,source:input.source,binarySHA256:input.binarySHA256,runtime:input.runtime,results:[]};
const seen=new Set();
for(const item of input.cases){
  assert.ok(["c","s"].includes(item.curve)&&!seen.has(item.curve));seen.add(item.curve);
  const {start,finish}=item.scene;
  assert.equal(start.target,"start");assert.equal(finish.target,"finish");
  assert.equal(start.documentId,finish.documentId);
  assert.deepEqual(start.viewport,finish.viewport);
  assert.ok(Number.isFinite(start.timeMs)&&Number.isFinite(finish.timeMs)&&finish.timeMs>start.timeMs);
  assert.equal(typeof start.trusted,"boolean");assert.equal(typeof finish.trusted,"boolean");
  assert.equal(item.artifacts.length,2);
  const formats=new Set();
  for(const artifact of item.artifacts){
    const entry={curve:item.curve,id:artifact.id,mimeType:artifact.mimeType,sha256:artifact.sha256,
      droppedFrames:artifact.droppedFrames??null,requestedFPS:20,documentId:start.documentId,samples:[]};
    output.results.push(entry);
    try{
      assert.ok(["image/gif","video/mp4"].includes(artifact.mimeType)&&!formats.has(artifact.mimeType));
      formats.add(artifact.mimeType);
      assert.equal(artifact.partial,false);
      assert.ok(Number.isInteger(artifact.byteLength)&&artifact.byteLength>0&&artifact.byteLength<=33554432);
      assert.ok(Array.isArray(artifact.timestamps)&&artifact.timestamps.length>=50&&artifact.timestamps.length<=600);
      assert.ok((await stat(artifact.file)).size===artifact.byteLength);
      const digest=createHash("sha256");
      for await(const bytes of createReadStream(artifact.file))digest.update(bytes);
      assert.equal(digest.digest("hex"),artifact.sha256);
      const probe=spawnSync(process.env.FFPROBE??"ffprobe",["-v","error","-select_streams","v:0",
        "-show_frames","-show_entries","frame=best_effort_timestamp_time:stream=width,height",
        "-of","json",resolve(artifact.file)],{windowsHide:true,maxBuffer:1048576,timeout:30000});
      assert.equal(probe.status,0,"PTS probe failed");
      const metadata=JSON.parse(probe.stdout.toString());
      const actualPTS=validateG08PTS(metadata,artifact);
      const config={from:start.center,to:finish.center,curve:item.curve,pointerMs:2400,markerMs:3000,radius:48,
        color:item.curve==="c"?"#ff0000":"#0000ff",
        scale:{x:artifact.width/start.viewport.width,y:artifact.height/start.viewport.height}};
      const marker={center:{x:finish.center.x*config.scale.x,y:finish.center.y*config.scale.y},
        radius:48*config.scale.x,color:config.color};
      const child=spawn(process.env.FFMPEG??"ffmpeg",["-v","error","-threads","1","-filter_threads","1",
        "-i",resolve(artifact.file),"-fps_mode","passthrough","-f","rawvideo","-pix_fmt","rgb24","-"],
        {windowsHide:true,stdio:["ignore","pipe","pipe"]});
      const timeout=setTimeout(()=>child.kill(),120000);
      let stderr="";child.stderr.on("data",chunk=>{if(stderr.length<4096)stderr+=chunk.toString().slice(0,4096-stderr.length);});
      const exited=new Promise((resolve,reject)=>{child.once("error",reject);child.once("close",code=>code===0?resolve():reject(Error("Decoder failed "+code+" "+stderr)));});
      void exited.catch(()=>{}); // A stream assertion can fail before the process-close await.
      try{
        const count=await consumeG08Frames(child.stdout,artifact.width,artifact.height,(frame,index)=>{
          assert.ok(index<artifact.timestamps.length,"Decoder exceeded recorded PTS");
          entry.samples.push({timeMs:actualPTS[index]*1000,
            ...measureG08Frame(frame,artifact.width,artifact.height,marker)});
        });
        await exited;assert.equal(count,artifact.timestamps.length);
      }finally{clearTimeout(timeout);if(child.exitCode===null)child.kill();await exited.catch(()=>{});}
      entry.analysis=evaluateG08(entry.samples,config);entry.passed=true;
    }catch(error){
      entry.passed=false;entry.error=String(error.message).slice(0,1024);
      entry.confidence=entry.error.includes("INSUFFICIENT_EVIDENCE")?"insufficient":"failed";
    }
  }
}
await writeFile(outputPath,JSON.stringify(output,null,2),{flag:"wx"});
process.exitCode=output.results.every(entry=>entry.passed)?0:1;
console.log(JSON.stringify(output.results.map(({curve,mimeType,passed,confidence,error,analysis})=>({curve,mimeType,passed,confidence,error,analysis}))));
