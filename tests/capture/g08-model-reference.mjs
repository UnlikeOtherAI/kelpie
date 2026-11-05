import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {readFile,stat} from "node:fs/promises";
import {spawn} from "node:child_process";
import {resolve} from "node:path";
import {isDeepStrictEqual} from "node:util";
import {consumeG08Frames} from "./g08-frame-stream.mjs";
import {measureG08Frame} from "./g08-pixels.mjs";

const digest=bytes=>createHash("sha256").update(bytes).digest("hex");
const equal=(a,b)=>isDeepStrictEqual(a,b);
const check=(value,message)=>assert.ok(value,"INSUFFICIENT_EVIDENCE model "+message);
async function bounded(path,max){
  const info=await stat(path);check(info.isFile()&&info.size>0&&info.size<=max,"file bound");
  return readFile(path);
}
async function json(path,max=1000000){const bytes=await bounded(path,max);return {bytes,value:JSON.parse(bytes.toString("utf8"))};}

// This accepts only the private Linux test capture that emitted the backing
// receipt; ordinary native exports and MP4 do not acquire a model reference.
function validateFacts({input,inputSHA256,item,artifact,actualPTS,manifest,backing,evidence,evidenceSHA256}) {
  check(input.runtime==="linux-gtk-cef"||input.runtime==="linux-osr-cef","runtime");
  check(artifact.mimeType==="image/gif"&&artifact.partial===false,"GIF only");
  check(manifest.version===1&&backing.version===1&&backing.confidence==="test-only-backing-observed","receipt version");
  check(input.source===manifest.source&&input.source===backing.source&&input.source===evidence.source,"source identity");
  check(input.binarySHA256===manifest.candidateBinarySHA256&&input.binarySHA256===backing.binarySHA256&&
    input.binarySHA256===evidence.binarySHA256,"binary identity");
  check(evidenceSHA256===manifest.candidateEvidenceSHA256&&evidenceSHA256===backing.candidateEvidenceSHA256,"live evidence identity");
  check(evidence.loaderOverridesAbsent===true&&equal(manifest.mediaObjectSHA256,evidence.mediaObjectSHA256)&&
    manifest.mediaArchiveSHA256===evidence.mediaArchiveSHA256&&manifest.candidateLinkMapSHA256===evidence.candidateLinkMapSHA256,
    "media object identity");
  check(backing.captureReportSHA256===inputSHA256&&backing.gifSHA256===artifact.sha256&&backing.run===item.runId&&
    backing.documentId===artifact.documentId,"capture identity");
  check(artifact.width===640&&artifact.height===450&&item.capture.fps===20&&manifest.encoder.mimeType==="image/gif"&&
    manifest.encoder.palette==="RGB332-floor"&&manifest.encoder.sourcePixelFormat==="BGRA8-opaque","format");
  const core=path=>["/libgif.so","/libcairo.so","/libpixman","/libz.so"].some(name=>path.includes(name));
  const deps=values=>values.filter(value=>core(value.path)).sort((a,b)=>a.path.localeCompare(b.path));
  check(Array.isArray(manifest.generatorDependencies)&&Array.isArray(evidence.dependencies)&&
    deps(manifest.generatorDependencies).length>=4&&equal(deps(manifest.generatorDependencies),deps(evidence.dependencies)),
    "live media dependencies");
  const model=manifest.input,finish=item.scene.finish,view=finish.visualViewport;
  check(model.width===640&&model.height===450&&model.fps===20&&model.frameCount===30&&
    model.viewportWidth===finish.viewport.width&&model.viewportHeight===finish.viewport.height&&equal(model.visualViewport,view)&&
    equal(model.pointer,finish.center),"geometry");
  const roi={left:445,top:190,right:515,bottom:260};
  check(equal(manifest.roi,roi)&&equal(backing.roi,[445,190,71,71]),"ROI");
  const x=(finish.center.x-view.offsetLeft)*view.scale*640/model.viewportWidth;
  const y=(finish.center.y-view.offsetTop)*view.scale*450/model.viewportHeight;
  check(x===480&&y===225,"mapped pointer");
  const white=digest(Buffer.alloc(71*71*4,255));
  check(typeof model.backingBGRA==="string"&&model.backingBGRA.length===26888,"model backing encoding");
  const modelBacking=Buffer.from(model.backingBGRA,"base64");
  check(modelBacking.length===71*71*4&&modelBacking.toString("base64")===model.backingBGRA&&
    modelBacking.every(value=>value===255)&&digest(modelBacking)===white,"model backing");
  check(backing.bgraSHA256===white&&backing.frameCount===actualPTS.length&&
    Array.isArray(backing.frames)&&backing.frames.length===actualPTS.length,"backing count");
  check(backing.frames.every((frame,i)=>frame.sequence===i&&frame.bgraSHA256===white&&
    Number.isFinite(frame.ptsMs)&&Math.abs(frame.ptsMs-actualPTS[i]*1000)<0.1),"backing frame PTS");
  const cases=manifest.cases;
  check(Array.isArray(cases)&&equal(cases.map(c=>c.name),["pointer","small","faint","full","palette-collision"]),"controls");
  const pointer=cases[0];
  check(pointer.marker===null&&Array.isArray(pointer.frames)&&pointer.frames.length===30,"pointer frames");
  const roiHash=pointer.frames[0]?.roiSHA256;
  check(/^[a-f0-9]{64}$/.test(roiHash)&&pointer.frames.every((frame,i)=>frame.index===i&&
    frame.ptsMs===i*50&&frame.roiSHA256===roiHash),"stable pointer");
  for(const [index,control] of cases.slice(1).entries()){
    const marker=control.marker, radius=index===0?4:48, age=[0,650,0,699][index];
    check(marker&&marker.color==="#0000FF"&&marker.radiusCss===radius&&marker.ageMs===age&&
      marker.durationMs===700&&marker.fade===true&&marker.wobble===false&&
      Math.abs(marker.baseAlpha-178/255)<1e-12,"control configuration");
  }
  for(const control of cases.slice(1,4))
    check(Array.isArray(control.frames)&&control.frames.length===30&&control.frames.every((frame,i)=>
      frame.index===i&&frame.ptsMs===i*50&&frame.roiSHA256!==roiHash),"retained marker control");
  check(cases[4].marker&&cases[4].marker.ageMs<cases[4].marker.durationMs&&cases[4].frames.length===30&&
    cases[4].frames.every((frame,i)=>frame.index===i&&frame.ptsMs===i*50&&frame.roiSHA256===roiHash),
    "palette collision control");
  return {pointer,roiHash};
}

export function validateG08ModelFacts(context) {
  try{return validateFacts(context);}
  catch(error){
    if(String(error?.message).includes("INSUFFICIENT_EVIDENCE"))throw error;
    throw Error("INSUFFICIENT_EVIDENCE model malformed receipt");
  }
}

export function validateG08ObservedRows(records,context,evidence,backing) {
  check(records.length===context.actualPTS.length,"observation count");
  const white=digest(Buffer.alloc(71*71*4,255));
  for(let i=0;i<records.length;i++){
    const row=records[i],raw=Buffer.from(row.bgraBase64,"base64");
    check(row.pid===evidence.pid&&row.run===context.item.runId&&row.documentId===context.artifact.documentId&&
      row.sequence===i&&row.frameWidth===640&&row.frameHeight===450&&row.stride===2560&&
      row.sourceWidth===1280&&row.sourceHeight===900&&
      row.viewportWidth===context.item.scene.finish.viewport.width&&row.viewportHeight===context.item.scene.finish.viewport.height&&
      equal(row.visualViewport,context.item.scene.finish.visualViewport)&&equal(row.roi,[445,190,71,71]),"observed geometry");
    check(raw.length===71*71*4&&raw.every(value=>value===255)&&digest(raw)===white&&row.bgraSHA256===white,
      "observed white backing");
    check(Number.isFinite(row.elapsedMs)&&row.elapsedMs===backing.frames[i].elapsedMs&&(i===0||row.elapsedMs>records[i-1].elapsedMs)&&
      Math.round((row.elapsedMs-records[0].elapsedMs)/10)*10===Math.round(context.actualPTS[i]*1000),"observed PTS");
  }
}

export async function loadG08ModelReference(paths,context) {
  const [modelFile,backingFile,evidenceFile]=await Promise.all([
    json(paths.manifest,2000000),json(paths.backing,2000000),json(paths.evidence,2000000)]);
  const {roiHash}=validateG08ModelFacts({...context,manifest:modelFile.value,backing:backingFile.value,
    evidence:evidenceFile.value,evidenceSHA256:digest(evidenceFile.bytes)});
  const observed=await bounded(paths.observations,20000000);
  check(digest(observed)===backingFile.value.observationSHA256,"observation hash");
  const records=observed.toString("utf8").trimEnd().split("\n").map(line=>JSON.parse(line));
  validateG08ObservedRows(records,context,evidenceFile.value,backingFile.value);
  const files=await Promise.all(modelFile.value.cases.map(async item=>{
    const bytes=await bounded(item.file,33554432);
    check(bytes.length===item.byteLength&&digest(bytes)===item.sha256,"control file hash");
    return item;
  }));
  const child=spawn(process.env.FFMPEG??"ffmpeg",["-v","error","-threads","1","-filter_threads","1",
    "-i",resolve(files[0].file),"-map","0:v:0","-fps_mode","passthrough","-f","rawvideo","-pix_fmt","rgb24","-"],
    {windowsHide:true,stdio:["ignore","pipe","pipe"]});
  let stderr="";child.stderr.on("data",chunk=>{if(stderr.length<4096)stderr+=chunk.toString().slice(0,4096-stderr.length);});
  const exited=new Promise((ok,bad)=>{child.once("error",bad);child.once("close",code=>code===0?ok():bad(Error("model decoder "+stderr)));});
  void exited.catch(()=>{});
  const timer=setTimeout(()=>child.kill(),120000);let reference;
  try{
    const count=await consumeG08Frames(child.stdout,640,450,(frame,index)=>{
      check(index<30,"model decoder frames");
      const measured=measureG08Frame(frame,640,450,{center:{x:480,y:225},radius:24,color:"#0000ff"});
      check(digest(measured.marker.roi)===roiHash,"decoded reference hash");
      if(!reference) reference=measured.marker.roi;
    });
    await exited;check(count===30,"model frame count");
  }finally{clearTimeout(timer);if(child.exitCode===null)child.kill();await exited.catch(()=>{});}
  return {reference,manifestSHA256:digest(modelFile.bytes),backingSHA256:digest(backingFile.bytes),referenceSHA256:roiHash};
}
