import {execFileSync} from "node:child_process";
import {createHash} from "node:crypto";
import {requireTrue} from "./runtime-client.mjs";
import {scriptPointerPosition} from "../../packages/shared/dist/index.js";
export function inspectMedia(item,{marker=false,preNavigation=false}={}) {
 const meta=JSON.parse(execFileSync("ffprobe",["-v","error","-select_streams","v:0","-show_streams","-show_frames","-of","json",item.file],{maxBuffer:16*1024*1024}));
 const stream=meta.streams[0];requireTrue(stream?.width===item.width&&stream?.height===item.height,"MEDIA_DIMENSIONS");
 const frames=meta.frames??[];requireTrue(frames.length>0,"MEDIA_EMPTY");
 requireTrue(stream.width*stream.height*3*frames.length<=256*1024*1024,"DECODE_LIMIT");
 const rgb=execFileSync("ffmpeg",["-v","error","-threads","1","-filter_threads","1","-i",item.file,"-map","0:v:0","-fps_mode","passthrough","-f","rawvideo","-pix_fmt","rgb24","-"],{maxBuffer:256*1024*1024});
 const stride=stream.width*stream.height*3;requireTrue(rgb.length===stride*frames.length,"MEDIA_FULL_DECODE");
 let previous=-Infinity,marked=0,markedWhite=0,yellowFrames=0;
 const times=frames.map(frame=>{const value=Number(frame.best_effort_timestamp_time??frame.pts_time??0);requireTrue(value>=previous,"MEDIA_TIMESTAMPS");previous=value;return value;});
 for(let start=0;start<rgb.length;start+=stride){let pixels=0,white=0,yellow=0;
  for(let p=start;p<start+stride;p+=3){
   if(rgb[p]>180&&rgb[p+1]<140&&rgb[p+2]<150)pixels++;
   if(rgb[p]>240&&rgb[p+1]>240&&rgb[p+2]>240)white++;
   if(rgb[p]>230&&rgb[p+1]>200&&rgb[p+2]<170)yellow++;
  }
  if(pixels>20){marked++;if(white>stride/3*0.3)markedWhite++;}
  if(yellow>stride/3*0.3)yellowFrames++;
 }
 if(marker)requireTrue(marked>0,"MOVIE_MARKER_MISSING");
 if(preNavigation)requireTrue(markedWhite>0&&yellowFrames>0,"MARKER_DOCUMENT_COHERENCE");
 return {mimeType:item.mimeType,width:stream.width,height:stream.height,decodedFrames:frames.length,timestamps:times,markerFrames:marked,markedPreNavigationFrames:markedWhite,yellowFrames};
}

export function centerPixel(item) {
 const rgb=execFileSync("ffmpeg",["-v","error","-threads","1","-filter_threads","1","-i",item.file,"-frames:v","1","-vf","crop=1:1:iw/2:ih/2,format=rgb24","-f","rawvideo","-"],{maxBuffer:1024});
 requireTrue(rgb.length===3,"PIXEL_DECODE");return [...rgb];
}

export function inspectCurve(item,curve,scene){
 const rgb=execFileSync("ffmpeg",["-v","error","-threads","1","-filter_threads","1","-i",item.file,"-map","0:v:0","-fps_mode","passthrough","-f","rawvideo","-pix_fmt","rgb24","-"],{maxBuffer:256*1024*1024});
 const stride=item.width*item.height*3,tracks=[],colors=[];
 for(let start=0;start<rgb.length;start+=stride){let minX=item.width,minY=item.height,maxX=-1,maxY=-1,count=0,colored=0;
  for(let y=0;y<item.height;y++)for(let x=0;x<item.width;x++){
   const p=start+(y*item.width+x)*3;
   if(curve==="s"?rgb[p]>190&&rgb[p+1]<180&&rgb[p+2]<180:rgb[p+2]>200&&rgb[p+1]>100&&rgb[p+1]<230&&rgb[p]<180)colored++;
   if(rgb[p]<170&&rgb[p+1]<170&&rgb[p+2]<170){count++;minX=Math.min(minX,x);minY=Math.min(minY,y);maxX=Math.max(maxX,x);maxY=Math.max(maxY,y);}
  }
  colors.push(colored);
  if(count>=3&&maxX-minX<24&&maxY-minY<24)tracks.push({x:minX*scene.width/item.width,y:minY*scene.height/item.height});
 }
 requireTrue(tracks.length>8,"CURVE_POINTER_SAMPLES");
 requireTrue(colors.some(c=>c>20)&&colors.at(-1)===0,"CONFIGURED_MARKER_COLOR_AND_END");
 const last=tracks.at(-1),offset={x:scene.second.x-last.x,y:scene.second.y-last.y};
 requireTrue(Math.hypot(offset.x,offset.y)<8,"CURVE_ENDPOINT");
 const dx=scene.second.x-scene.first.x,dy=scene.second.y-scene.first.y,d2=dx*dx+dy*dy;
 const normals=tracks.flatMap(p=>{const x=p.x+offset.x-scene.first.x,y=p.y+offset.y-scene.first.y,along=(x*dx+y*dy)/d2;
  return along>.08&&along<.92?[(dx*y-dy*x)/Math.sqrt(d2)]:[];});
 requireTrue(normals.length>=5,"CURVE_INTERMEDIATE_SAMPLES");
 const minimum=Math.min(...normals),maximum=Math.max(...normals);
 requireTrue(curve==="s"?minimum< -8&&maximum>8:minimum> -8&&maximum>15,"CURVE_GEOMETRY");
 return {curve,pointerSamples:tracks.length,minimum,maximum,endpointError:Math.hypot(offset.x,offset.y)};
}

// Hash only a small top-left text region, away from the centered tap marker.
export function inspectPaced(item,event){
 const rect=event.rect,viewport=event.viewport;
 requireTrue(rect&&viewport&&rect.width>50&&rect.height>25,"PACED_TEXT_REGION");
 const rgb=execFileSync("ffmpeg",["-v","error","-threads","1","-filter_threads","1","-i",item.file,
  "-map","0:v:0","-fps_mode","passthrough","-f","rawvideo","-pix_fmt","rgb24","-"],{maxBuffer:256*1024*1024});
 const stride=item.width*item.height*3;
 requireTrue(rgb.length%stride===0&&rgb.length/stride>=4,"PACED_MEDIA_FRAMES");
 const sx=item.width/viewport.width,sy=item.height/viewport.height;
 const left=Math.max(0,Math.floor((rect.left+5)*sx)),right=Math.min(item.width,Math.ceil((rect.left+45)*sx));
 const top=Math.max(0,Math.floor((rect.top+4)*sy)),bottom=Math.min(item.height,Math.ceil((rect.top+25)*sy));
 requireTrue(right>left&&bottom>top,"PACED_TEXT_REGION");
 const variants=new Set();
 for(let start=0;start<rgb.length;start+=stride){
  const digest=createHash("sha256");
  for(let y=top;y<bottom;y++)digest.update(rgb.subarray(start+(y*item.width+left)*3,start+(y*item.width+right)*3));
  variants.add(digest.digest("hex"));
 }
 requireTrue(variants.size>=3,"PACED_TEXT_FRAMES");
 return {decodedFrames:rgb.length/stride,distinctTextRegions:variants.size};
}

export function inspectEdgeMarker(item,event){
 const rgb=execFileSync("ffmpeg",["-v","error","-threads","1","-filter_threads","1","-i",item.file,"-frames:v","1","-f","rawvideo","-pix_fmt","rgb24","-"],{maxBuffer:16*1024*1024});
 requireTrue(rgb.length===item.width*item.height*3,"EDGE_IMAGE_DECODE");
 let count=0,sumX=0,sumY=0;
 for(let y=0;y<item.height;y++)for(let x=0;x<item.width;x++){
  const i=(y*item.width+x)*3;
  if(rgb[i]>180&&rgb[i+1]<150&&rgb[i+2]<160){count++;sumX+=x;sumY+=y;}
 }
 requireTrue(count>20,"EDGE_MARKER_MISSING");
 const actual={x:sumX/count,y:sumY/count},expected={x:event.x*item.width/event.viewport.width,y:event.y*item.height/event.viewport.height};
 const error=Math.hypot(actual.x-expected.x,actual.y-expected.y);
 requireTrue(error<4,"EDGE_MARKER_ALIGNMENT");
 return {actual,expected,error,clientWidth:event.viewport.clientWidth,innerWidth:event.viewport.width};
}

// Fit one real decoded pointer path to the omitted-duration default and the prior 500 ms timing.
export function inspectDefaultMotion(item,scene){
 const meta=JSON.parse(execFileSync("ffprobe",["-v","error","-select_streams","v:0","-show_frames","-show_entries",
  "frame=best_effort_timestamp_time","-of","json",item.file],{maxBuffer:16*1024*1024}));
 const frames=meta.frames??[];
 const rgb=execFileSync("ffmpeg",["-v","error","-threads","1","-filter_threads","1","-i",item.file,
  "-map","0:v:0","-fps_mode","passthrough","-f","rawvideo","-pix_fmt","rgb24","-"],{maxBuffer:256*1024*1024});
 const stride=item.width*item.height*3;requireTrue(rgb.length===stride*frames.length,"DEFAULT_MOTION_DECODE");
 const tracks=[];
 for(let index=0;index<frames.length;index++){
  let minX=item.width,minY=item.height,maxX=-1,maxY=-1,count=0;
  for(let y=0;y<item.height;y++)for(let x=0;x<item.width;x++){
   const offset=index*stride+(y*item.width+x)*3;
   if(rgb[offset]<170&&rgb[offset+1]<170&&rgb[offset+2]<170){count++;minX=Math.min(minX,x);minY=Math.min(minY,y);maxX=Math.max(maxX,x);maxY=Math.max(maxY,y);}
  }
  const time=Number(frames[index].best_effort_timestamp_time)*1000;
  if(count>=3&&maxX-minX<24&&maxY-minY<24&&Number.isFinite(time))
   tracks.push({time,x:minX*scene.width/item.width,y:minY*scene.height/item.height});
 }
 const distance=(a,b)=>Math.hypot(a.x-b.x,a.y-b.y);
 const endpoint=tracks.filter(point=>distance(point,scene.second)<8).at(-1);
 requireTrue(endpoint,"DEFAULT_MOTION_ENDPOINT");
 const offset={x:scene.second.x-endpoint.x,y:scene.second.y-endpoint.y};
 const corrected=tracks.map(point=>({...point,x:point.x+offset.x,y:point.y+offset.y}));
 const start=corrected.filter(point=>point.time<endpoint.time&&distance(point,scene.first)<4).at(-1);
 requireTrue(start,"DEFAULT_MOTION_START");
 const end=corrected.find(point=>point.time>start.time&&distance(point,scene.second)<4);
 requireTrue(end,"DEFAULT_MOTION_END");
 const path=corrected.filter(point=>point.time>start.time&&point.time<end.time);
 requireTrue(path.length>=4,"DEFAULT_MOTION_INSUFFICIENT_FRAMES");
 const dx=scene.second.x-scene.first.x,dy=scene.second.y-scene.first.y,length2=dx*dx+dy*dy;
 const progress=point=>((point.x-scene.first.x)*dx+(point.y-scene.first.y)*dy)/length2;
 requireTrue(Math.min(...path.map(progress))<.35&&Math.max(...path.map(progress))>.65,"DEFAULT_MOTION_INSUFFICIENT_COVERAGE");
 const samples=[start,...path,end],motion={from:scene.first,to:scene.second,curve:"s"};
 function fit(duration){
  let best=Infinity,bestOnset=null;
  for(let onset=start.time;onset<=path[0].time;onset+=2){
   const errors=samples.map(point=>distance(point,scriptPointerPosition(motion,(point.time-onset)/duration)));
   const rms=Math.sqrt(errors.reduce((sum,error)=>sum+error*error,0)/errors.length);
   if(rms<best){best=rms;bestOnset=onset;}
  }
  return {rms:best,onset:bestOnset};
 }
 const current=fit(350),previous=fit(500);
 requireTrue(current.rms<9&&previous.rms>current.rms+6,"DEFAULT_MOTION_DURATION");
 return {samples:path.length,durationMs:350,fit350Px:current.rms,fit500Px:previous.rms,
  observedSpanMs:end.time-start.time,endpointErrorPx:distance(endpoint,scene.second)};
}
