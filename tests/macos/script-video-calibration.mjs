import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {createReadStream} from "node:fs";
import {readFile,realpath,stat,writeFile} from "node:fs/promises";
import {execFileSync,spawn,spawnSync} from "node:child_process";
import path from "node:path";
import {consumeG08Frames} from "../capture/g08-frame-stream.mjs";
import {ffmpegPassthrough} from "../capture/ffmpeg-passthrough.mjs";
import {validateCalibrationCase,decodedTicksAt600,redExcess,classifyMarkerRegime,markerControls,caseNames} from "./script-video-calibration-check.mjs";
import {intraWriterSource} from "./script-video-intra-source.mjs";

const [inputName,outputName]=process.argv.slice(2);
assert.ok(inputName&&outputName&&process.argv.length===4,"CALIBRATION_ARGUMENTS");
assert.ok((await stat(inputName)).size<=131072,"CALIBRATION_MANIFEST_SIZE");
const inputBytes=await readFile(inputName),input=JSON.parse(inputBytes.toString("utf8")),directory=await realpath(path.dirname(inputName));
const inputSHA256=createHash("sha256").update(inputBytes).digest("hex");
const command=(file,args)=>execFileSync(file,args,{encoding:"utf8",timeout:15000,maxBuffer:1048576}).trim();
const executable=async value=>realpath(value.includes(path.sep)?value:command("/usr/bin/which",[value]));
const hashFile=async file=>{const hash=createHash("sha256");for await(const bytes of createReadStream(file))hash.update(bytes);return hash.digest("hex");};
const swiftc=await executable(command("xcrun",["--find","swiftc"]));
const ffmpegPath=await executable(process.env.FFMPEG??"ffmpeg"),ffprobePath=await executable(process.env.FFPROBE??"ffprobe");
const source=command("git",["rev-parse","HEAD"]);
assert.match(source,/^[a-f0-9]{40}$/);
if(process.env.GITHUB_SHA)assert.equal(source,process.env.GITHUB_SHA,"CALIBRATION_SOURCE_MISMATCH");
const identity={source,node:process.version,architecture:process.arch,
 compiler:{version:command("xcrun",["swiftc","--version"]),sha256:await hashFile(swiftc)},
 sdk:command("xcrun",["--sdk","macosx","--show-sdk-version"]),
 ffmpeg:{version:command(ffmpegPath,["-version"]).split("\n")[0],sha256:await hashFile(ffmpegPath)},
 ffprobe:{version:command(ffprobePath,["-version"]).split("\n")[0],sha256:await hashFile(ffprobePath)}};
const profile=process.env.KELPIE_CALIBRATION_PROFILE??"default";
assert.ok(["default","all-intra"].includes(profile),"CALIBRATION_PROFILE");
const writerPath="apps/macos/Kelpie/Handlers/ScriptVideoWriter.swift",writerSource=await readFile(writerPath);
identity.writerSourceSHA256=createHash("sha256").update(writerSource).digest("hex");
if(process.env.KELPIE_CALIBRATION_BINARY)identity.calibrationBinarySHA256=await hashFile(await realpath(process.env.KELPIE_CALIBRATION_BINARY));
if(process.env.KELPIE_CALIBRATION_TIME){
 const timing=await readFile(process.env.KELPIE_CALIBRATION_TIME,"utf8");assert.ok(timing.length<=8192,"CALIBRATION_TIMING_SIZE");
 const match=/^\s*([0-9.]+)\s+real\s+([0-9.]+)\s+user\s+([0-9.]+)\s+sys/m.exec(timing);
 const rss=/^\s*(\d+)\s+maximum resident set size/m.exec(timing);
 assert.ok(match&&rss,"CALIBRATION_TIMING_FORMAT");
 const [elapsedSeconds,userSeconds,systemSeconds]=match.slice(1).map(Number),maxResidentBytes=Number(rss[1]);
 assert.ok([elapsedSeconds,userSeconds,systemSeconds,maxResidentBytes].every(Number.isFinite)&&elapsedSeconds>0&&
  userSeconds>=0&&systemSeconds>=0&&maxResidentBytes>0,"CALIBRATION_TIMING_VALUES");
 identity.process={elapsedSeconds,userSeconds,systemSeconds,maxResidentBytes};
}
if(profile==="all-intra"){
 assert.ok(process.env.KELPIE_INTRA_SOURCE&&process.env.KELPIE_INTRA_RECEIPT,"INTRA_PROVENANCE_MISSING");
 const transformed=await readFile(process.env.KELPIE_INTRA_SOURCE),receipt=JSON.parse(await readFile(process.env.KELPIE_INTRA_RECEIPT,"utf8"));
 const expected=Buffer.from(intraWriterSource(writerSource.toString("utf8")));
 assert.ok(transformed.equals(expected),"INTRA_SOURCE_MISMATCH");
 assert.equal(receipt.version,1);assert.equal(receipt.source,"apps/macos/Kelpie/Handlers/ScriptVideoWriter.swift");
 assert.equal(receipt.insertion,"AVVideoMaxKeyFrameIntervalKey: 1");
 assert.equal(receipt.sourceSHA256,identity.writerSourceSHA256);
 assert.equal(receipt.transformedSHA256,createHash("sha256").update(transformed).digest("hex"));
 identity.intraTransform=receipt;
}
assert.equal(input.version,2);assert.equal(input.width,640);assert.equal(input.height,496);
assert.deepEqual(input.roi,[432,200,97,97]);assert.equal(input.timeBase,"1/600");
assert.ok(Array.isArray(input.cases)&&input.cases.length===caseNames.length,"CALIBRATION_CASES");
assert.deepEqual(input.cases.map(item=>item.name),caseNames);
assert.match(input.cleanROIHash,/^[a-f0-9]{64}$/);assert.match(input.varyingROIHash,/^[a-f0-9]{64}$/);
assert.notEqual(input.cleanROIHash,input.varyingROIHash);
assert.match(input.cleanImageHash,/^[a-f0-9]{64}$/);assert.match(input.varyingImageHash,/^[a-f0-9]{64}$/);
assert.notEqual(input.cleanImageHash,input.varyingImageHash);
assert.ok(Array.isArray(input.markerControls)&&input.markerControls.length===markerControls.length);
const sourceHashes={clean:input.cleanROIHash,varying:input.varyingROIHash};
const imageHashes={clean:input.cleanImageHash,varying:input.varyingImageHash};
for(let i=0;i<markerControls.length;i++){
 const expected=markerControls[i],actual=input.markerControls[i];
 assert.equal(actual.name,expected.name);assert.equal(actual.radiusPx,expected.radiusPx);assert.equal(actual.alpha,expected.alpha);
 assert.equal(actual.color,expected.color);assert.equal(actual.anchor,expected.anchor);
 assert.match(actual.sourceROIHash,/^[a-f0-9]{64}$/);assert.notEqual(actual.sourceROIHash,input.cleanROIHash);
 sourceHashes[actual.name]=actual.sourceROIHash;
 assert.match(actual.sourceImageHash,/^[a-f0-9]{64}$/);assert.notEqual(actual.sourceImageHash,input.cleanImageHash);
 imageHashes[actual.name]=actual.sourceImageHash;
}
const results=[];let totalBytes=0;
for(const item of input.cases){
 assert.equal(item.file,item.name+".mp4","CALIBRATION_FILENAME");
 const file=await realpath(path.join(directory,item.file));
 assert.equal(path.dirname(file),directory,"CALIBRATION_PATH");
 const info=await stat(file);assert.ok(Number.isSafeInteger(item.size)&&item.size>0&&item.size===info.size,"CALIBRATION_SIZE");
 totalBytes+=info.size;assert.ok(totalBytes<=8*1024*1024,"CALIBRATION_BYTE_LIMIT");
 const digest=createHash("sha256");for await(const bytes of createReadStream(file))digest.update(bytes);
 const artifactSHA256=digest.digest("hex");
 const probe=spawnSync(ffprobePath,["-v","error","-select_streams","v:0","-show_frames","-show_entries",
  "frame=best_effort_timestamp,key_frame,pict_type:stream=width,height,time_base","-of","json",file],
 {windowsHide:true,maxBuffer:1048576,timeout:30000});
 assert.equal(probe.status,0,"CALIBRATION_PROBE");
 const metadata=JSON.parse(probe.stdout.toString());assert.equal(metadata.streams?.length,1);
 const stream=metadata.streams[0];assert.equal(stream.width,640);assert.equal(stream.height,496);
 const frames=metadata.frames??[];assert.ok(frames.length<=40,"CALIBRATION_FRAME_LIMIT");
 const trackPTS=frames.map(frame=>Number(frame.best_effort_timestamp));
 const frameTypes=frames.map(frame=>({key:Number(frame.key_frame),type:frame.pict_type}));
 assert.ok(frameTypes.every(frame=>[0,1].includes(frame.key)&&["I","P","B"].includes(frame.type)),"CALIBRATION_FRAME_TYPES");
 const decodedTicks=decodedTicksAt600(trackPTS,stream.time_base);
 const child=spawn(ffmpegPath,["-v","error","-threads","1","-filter_threads","1","-i",file,"-map","0:v:0",
  ...ffmpegPassthrough(ffmpegPath),"-f","rawvideo","-pix_fmt","rgb24","-"],{windowsHide:true,stdio:["ignore","pipe","pipe"]});
 let stderr="";child.stderr.on("data",bytes=>{if(stderr.length<4096)stderr+=bytes.toString().slice(0,4096-stderr.length);});
 const exited=new Promise((resolve,reject)=>{child.once("error",reject);child.once("close",code=>code===0?resolve():reject(Error("CALIBRATION_DECODER "+stderr)));});
 void exited.catch(()=>{});const timer=setTimeout(()=>child.kill(),30000),decodedHashes=[],scores=[];
 try{
  const count=await consumeG08Frames(child.stdout,640,496,(frame,index)=>{
   assert.ok(index<40,"CALIBRATION_FRAME_LIMIT");const roi=Buffer.allocUnsafe(97*97*3);
   for(let y=200;y<297;y++)frame.copy(roi,(y-200)*97*3,(y*640+432)*3,(y*640+529)*3);
   decodedHashes.push(createHash("sha256").update(roi).digest("hex"));scores.push(redExcess(roi));
  });
  await exited;assert.equal(count,frames.length,"CALIBRATION_DECODE_COUNT");
 }finally{clearTimeout(timer);if(child.exitCode===null)child.kill();await exited.catch(()=>{});}
 results.push({...validateCalibrationCase(item,decodedTicks,decodedHashes,sourceHashes,imageHashes),scores,trackTimeBase:stream.time_base,trackPTS,frameTypes,artifactSHA256,bytes:info.size});
}
const training=results.find(result=>result.name==="stable").scores;
const holdout=results.find(result=>result.name==="holdout").scores;
const regimes=markerControls.map(control=>{
 const result=results.find(value=>value.name===control.name);
 const marker=result.scores.filter((_,index)=>result.sourceKinds[index]==="alternate");
 const tail=result.scores.filter((_,index)=>result.sourceKinds[index]==="clean");
 return {...control,...classifyMarkerRegime(training,holdout,marker,tail)};
});
const output={version:2,scope:"synthetic-encoded-visible-marker-calibration",profile,inputSHA256,identity,width:640,height:496,
 roi:[432,200,97,97],writerTimeBase:"1/600",metric:"sum-max-zero-red-minus-max-green-blue",regimes,results};
const outputBytes=Buffer.from(JSON.stringify(output,null,2)+"\n");
assert.ok(outputBytes.length<=131072,"CALIBRATION_OUTPUT_LIMIT");
await writeFile(outputName,outputBytes,{flag:"wx"});
console.log(JSON.stringify({cases:results.map(({name,accepted,sourceUnique,decodedUnique,observation})=>({name,accepted,sourceUnique,decodedUnique,observation})),regimes}));
