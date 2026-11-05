import assert from "node:assert/strict";
import {readFile,writeFile} from "node:fs/promises";
import {spawnSync} from "node:child_process";
import {resolve} from "node:path";
// Independently decode native artifacts; no app, credentials or desktop input.
const [reportPath,outputPath,markerOption]=process.argv.slice(2);
if(!outputPath)throw Error("Provide downloaded artifact report and fresh output JSON; optional --red-marker");
const report=JSON.parse(await readFile(reportPath,"utf8"));
const ffmpeg=process.env.FFMPEG??"ffmpeg",ffprobe=process.env.FFPROBE??"ffprobe";
const command=(exe,args,maxBuffer=64*1024*1024)=>{
 const result=spawnSync(exe,args,{windowsHide:true,maxBuffer});
 assert.equal(result.status,0,result.stderr?.toString()??result.error?.message);return result.stdout;
};
const artifacts=[];
for(const item of report.artifacts) {
 assert.equal(typeof item.file,"string","Downloader must supply exact verified local file");
 const metadata=JSON.parse(command(ffprobe,["-v","error","-select_streams","v:0","-count_frames","-show_frames",
 "-show_entries","frame=best_effort_timestamp_time:stream=width,height,nb_read_frames,duration:format=duration","-of","json",item.file]));
 const stream=metadata.streams[0],count=Number(stream.nb_read_frames);
 assert.equal(stream.width,item.width);assert.equal(stream.height,item.height);
 if(item.frameCount!==undefined)assert.equal(count,item.frameCount);
 const times=metadata.frames.map(f=>Number(f.best_effort_timestamp_time));
 assert.ok(times.every((t,i)=>Number.isFinite(t)&&(i===0||t>times[i-1])));
 command(ffmpeg,["-v","error","-threads","1","-i",item.file,"-map","0:v:0","-f","null","-"]);
 const entry={id:item.id,runId:item.runId,mimeType:item.mimeType,sha256:item.sha256,decodedFrames:count,timestamps:times};
 if(markerOption==="--red-marker"&&item.mimeType!=="image/png") {
   // Evidence fixtures use white/black/yellow pages and a red marker. Preserve
   // every frame's pixel count, rather than selecting a favorable still.
   const pixels=command(ffmpeg,["-v","error","-threads","1","-i",item.file,"-fps_mode","passthrough","-f","rawvideo","-pix_fmt","rgb24","-"]);
   const size=item.width*item.height*3;
   assert.equal(pixels.length,size*count);
   entry.markerPixels=[];
   for(let frame=0;frame<count;frame++) {
     let red=0;for(let i=frame*size;i<(frame+1)*size;i+=3)
       if(pixels[i]>190&&pixels[i+1]<95&&pixels[i+2]<95)red++;
     entry.markerPixels.push(red);
   }
   assert.ok(entry.markerPixels.some(n=>n>100),"Movie contains no red marker");
 }
 artifacts.push(entry);
}
await writeFile(resolve(outputPath),JSON.stringify({source:report.source,launchId:report.launchId,artifacts},null,2));
console.log(JSON.stringify({allFramesDecoded:true,artifacts:artifacts.length}));
