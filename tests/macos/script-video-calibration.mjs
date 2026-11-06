import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {createReadStream} from "node:fs";
import {readFile,realpath,stat,writeFile} from "node:fs/promises";
import {spawn,spawnSync} from "node:child_process";
import path from "node:path";
import {consumeG08Frames} from "../capture/g08-frame-stream.mjs";
import {ffmpegPassthrough} from "../capture/ffmpeg-passthrough.mjs";
import {validateCalibrationCase} from "./script-video-calibration-check.mjs";

const [inputName,outputName]=process.argv.slice(2);
assert.ok(inputName&&outputName&&process.argv.length===4,"CALIBRATION_ARGUMENTS");
assert.ok((await stat(inputName)).size<=32768,"CALIBRATION_MANIFEST_SIZE");
const input=JSON.parse(await readFile(inputName,"utf8")),directory=await realpath(path.dirname(inputName));
assert.equal(input.version,1);assert.equal(input.width,640);assert.equal(input.height,496);
assert.deepEqual(input.roi,[432,200,97,97]);assert.equal(input.timeBase,"1/600");
assert.ok(Array.isArray(input.cases)&&input.cases.length===2,"CALIBRATION_CASES");
assert.deepEqual(input.cases.map(item=>item.name),["stable","varying"]);
const results=[];let totalBytes=0;
for(const item of input.cases){
 assert.equal(item.file,item.name+".mp4","CALIBRATION_FILENAME");
 const file=await realpath(path.join(directory,item.file));
 assert.equal(path.dirname(file),directory,"CALIBRATION_PATH");
 const info=await stat(file);assert.ok(Number.isSafeInteger(item.size)&&item.size>0&&item.size===info.size,"CALIBRATION_SIZE");
 totalBytes+=info.size;assert.ok(totalBytes<=8*1024*1024,"CALIBRATION_BYTE_LIMIT");
 const digest=createHash("sha256");for await(const bytes of createReadStream(file))digest.update(bytes);
 const artifactSHA256=digest.digest("hex");
 const ffprobe=process.env.FFPROBE??"ffprobe";
 const probe=spawnSync(ffprobe,["-v","error","-select_streams","v:0","-show_frames","-show_entries",
  "frame=best_effort_timestamp:stream=width,height,time_base","-of","json",file],
 {windowsHide:true,maxBuffer:1048576,timeout:30000});
 assert.equal(probe.status,0,"CALIBRATION_PROBE");
 const metadata=JSON.parse(probe.stdout.toString());assert.equal(metadata.streams?.length,1);
 const stream=metadata.streams[0];assert.equal(stream.width,640);assert.equal(stream.height,496);assert.equal(stream.time_base,"1/600");
 const frames=metadata.frames??[];assert.ok(frames.length<=40,"CALIBRATION_FRAME_LIMIT");
 const decodedTicks=frames.map(frame=>{const value=Number(frame.best_effort_timestamp);assert.ok(Number.isSafeInteger(value));return value;});
 const ffmpeg=process.env.FFMPEG??"ffmpeg";
 const child=spawn(ffmpeg,["-v","error","-threads","1","-filter_threads","1","-i",file,"-map","0:v:0",
  ...ffmpegPassthrough(ffmpeg),"-f","rawvideo","-pix_fmt","rgb24","-"],{windowsHide:true,stdio:["ignore","pipe","pipe"]});
 let stderr="";child.stderr.on("data",bytes=>{if(stderr.length<4096)stderr+=bytes.toString().slice(0,4096-stderr.length);});
 const exited=new Promise((resolve,reject)=>{child.once("error",reject);child.once("close",code=>code===0?resolve():reject(Error("CALIBRATION_DECODER "+stderr)));});
 void exited.catch(()=>{});const timer=setTimeout(()=>child.kill(),30000),decodedHashes=[];
 try{
  const count=await consumeG08Frames(child.stdout,640,496,(frame,index)=>{
   assert.ok(index<40,"CALIBRATION_FRAME_LIMIT");const hash=createHash("sha256");
   for(let y=200;y<297;y++)hash.update(frame.subarray((y*640+432)*3,(y*640+529)*3));
   decodedHashes.push(hash.digest("hex"));
  });
  await exited;assert.equal(count,frames.length,"CALIBRATION_DECODE_COUNT");
 }finally{clearTimeout(timer);if(child.exitCode===null)child.kill();await exited.catch(()=>{});}
 results.push({...validateCalibrationCase(item,decodedTicks,decodedHashes),artifactSHA256,bytes:info.size});
}
const output={version:1,scope:"synthetic-identical-source-writer-calibration",width:640,height:496,
 roi:[432,200,97,97],timeBase:"1/600",results};
await writeFile(outputName,JSON.stringify(output,null,2)+"\n",{flag:"wx"});
console.log(JSON.stringify(results.map(({name,accepted,sourceUnique,decodedUnique,observation})=>({name,accepted,sourceUnique,decodedUnique,observation}))));
