import assert from "node:assert/strict";
import {readFile,writeFile} from "node:fs/promises";
import {spawnSync} from "node:child_process";
const [downloadPath,nativePath,outPath]=process.argv.slice(2);
if(!outPath)throw Error("Provide downloaded report, native motion report and output JSON");
const downloaded=JSON.parse(await readFile(downloadPath,"utf8"));
const native=JSON.parse(await readFile(nativePath,"utf8"));
const results=[];
for(const check of native.checks.filter(c=>c.passed&&c.detail?.curve)){
 const {curve,scene,runId}=check.detail;
 for(const item of downloaded.artifacts.filter(a=>a.runId===runId&&a.mimeType!=="image/png")){
  const raw=spawnSync(process.env.FFMPEG??"ffmpeg",["-v","error","-threads","1","-i",item.file,"-fps_mode","passthrough","-f","rawvideo","-pix_fmt","rgb24","-"],
    {windowsHide:true,maxBuffer:128*1024*1024});
  assert.equal(raw.status,0,raw.stderr?.toString());
  const size=item.width*item.height*3,count=raw.stdout.length/size;
  assert.equal(count,item.decodedFrames);
  const tracks=[],markers=[],sx=scene.width/item.width,sy=scene.height/item.height;
  for(let frame=0;frame<count;frame++){
   let minX=item.width,minY=item.height,maxX=-1,maxY=-1,black=0,color=0;
   let cminX=item.width,cminY=item.height,cmaxX=-1,cmaxY=-1;
   for(let y=0;y<item.height;y++)for(let x=0;x<item.width;x++){
    const i=frame*size+(y*item.width+x)*3,r=raw.stdout[i],g=raw.stdout[i+1],b=raw.stdout[i+2];
    if(r<170&&g<170&&b<170){black++;minX=Math.min(minX,x);minY=Math.min(minY,y);maxX=Math.max(maxX,x);maxY=Math.max(maxY,y);}
    const colored=curve==="s"?r>190&&g<180&&b<180:b>200&&g>100&&g<230&&r<180;
    if(colored){color++;cminX=Math.min(cminX,x);cminY=Math.min(cminY,y);cmaxX=Math.max(cmaxX,x);cmaxY=Math.max(cmaxY,y);}
   }
   if(black>=3&&maxX-minX<24&&maxY-minY<24)
    tracks.push({frame,time:item.timestamps[frame],x:minX*sx,y:minY*sy,black});
   markers.push({frame,time:item.timestamps[frame],pixels:color,bounds:color?{minX:cminX,minY:cminY,maxX:cmaxX,maxY:cmaxY}:null});
  }
  assert.ok(tracks.length>8,"Too few independently decoded pointer positions");
  const last=tracks.at(-1),offset={x:scene.second.x-last.x,y:scene.second.y-last.y};
  assert.ok(Math.hypot(offset.x,offset.y)<8,"Pointer endpoint not at target");
  const dx=scene.second.x-scene.first.x,dy=scene.second.y-scene.first.y,d2=dx*dx+dy*dy,length=Math.sqrt(d2);
  const path=tracks.map(p=>{const x=p.x+offset.x-scene.first.x,y=p.y+offset.y-scene.first.y;
   return {...p,along:(x*dx+y*dy)/d2,normal:(dx*y-dy*x)/length};}).filter(p=>p.along>.08&&p.along<.92);
  assert.ok(path.length>=5,"Too few motion samples between endpoints");
  const normals=path.map(p=>p.normal),minimum=Math.min(...normals),maximum=Math.max(...normals);
  if(curve==="c"){assert.ok(maximum>15,"C curve appears linear");assert.ok(minimum>-8,"C curve changed sides");}
  else {assert.ok(maximum>8&&minimum< -8,"S curve did not cross its chord");}
  assert.ok(markers.some(p=>p.pixels>20),"Configured marker color absent");
  assert.equal(markers.at(-1).pixels,0,"Marker did not end cleanly");
  results.push({curve,runId,id:item.id,mimeType:item.mimeType,tracks,path,normalRange:{minimum,maximum},endpointOffset:offset,markers});
 }
}
assert.equal(results.length,4,"Both GIF/MP4 curves required");
await writeFile(outPath,JSON.stringify({source:native.source,launchId:native.launchId,results},null,2));
console.log(JSON.stringify(results.map(r=>({curve:r.curve,mimeType:r.mimeType,positions:r.tracks.length,pathPositions:r.path.length,normalRange:r.normalRange,endpointOffset:r.endpointOffset}))));
