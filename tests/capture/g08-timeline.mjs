import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import { scriptPointerPosition, scriptTapPresentation } from "../../packages/shared/dist/index.js";
import { median } from "./g08-pixels.mjs";
import { sameG08Pixels } from "./g08-calibration.mjs";
const rms=values=>Math.sqrt(values.reduce((sum,value)=>sum+value*value,0)/values.length);
const distance=(a,b)=>Math.hypot(a.x-b.x,a.y-b.y);
function demand(value,message){assert.ok(value,message);}
export function evaluateG08(samples,config){
  const {curve,pointerMs,markerMs,color}=config;
  demand(["c","s"].includes(curve)&&/^#[a-f0-9]{6}$/i.test(color),"Invalid G08 configuration");
  demand(Number.isFinite(pointerMs)&&pointerMs>=1000&&pointerMs<=5000,"Invalid pointer duration");
  demand(Number.isFinite(markerMs)&&markerMs>=1500&&markerMs<=5000,"Invalid marker duration");
  const scale=config.scale??{x:1,y:1};
  demand([scale.x,scale.y].every(v=>Number.isFinite(v)&&v>.05&&v<=4)&&Math.abs(scale.x-scale.y)<.01,"Invalid uniform capture scale");
  demand([config.from.x,config.from.y,config.to.x,config.to.y,config.radius].every(Number.isFinite),"Invalid geometry");
  demand(config.radius>=20&&config.radius<=100,"Invalid radius");
  const map=p=>({x:p.x*scale.x,y:p.y*scale.y});
  const from=map(config.from),to=map(config.to),radius=config.radius*scale.x;
  demand(samples.length>=50&&samples.length<=600,"INSUFFICIENT_EVIDENCE frame count");
  demand(samples.every((s,i)=>Number.isFinite(s.timeMs)&&(i===0||s.timeMs>samples[i-1].timeMs)),"Nonmonotonic decoded PTS");
  const dx=to.x-from.x,dy=to.y-from.y,length=Math.hypot(dx,dy);
  demand(length>=120,"INSUFFICIENT_EVIDENCE path span");
  const project=p=>((p.x-from.x)*dx+(p.y-from.y)*dy)/(length*length);
  const pointers=samples.filter(s=>s.pointer);
  demand(pointers.length>=3,"INSUFFICIENT_EVIDENCE calibration pointer");
  const initial=pointers[0];
  const settled=pointers.filter(s=>distance(s.pointer,to)<=10).slice(-8);
  demand(settled.length>=3,"INSUFFICIENT_EVIDENCE endpoint pixels");
  const offset={x:to.x-median(settled.map(s=>s.pointer.x)),y:to.y-median(settled.map(s=>s.pointer.y))};
  demand(Math.hypot(offset.x,offset.y)<=8,"Pointer anchor differs by more than8pixels");
  const corrected=pointers.map(s=>({...s,p:{x:s.pointer.x+offset.x,y:s.pointer.y+offset.y}}));
  const lastStart=corrected.filter(s=>s.timeMs<settled.at(-1).timeMs&&distance(s.p,from)<=2).at(-1);
  demand(lastStart,"INSUFFICIENT_EVIDENCE final motion start");
  const calibrationMarker=samples.find(s=>s.timeMs>=initial.timeMs+pointerMs*.65&&
    s.timeMs<lastStart.timeMs&&s.marker.alpha>.2);
  demand(calibrationMarker,"INSUFFICIENT_EVIDENCE calibration dispatch marker");
  const endpoint=settled.at(-1).pointer;
  const calibration=pointers.filter(s=>s.timeMs<calibrationMarker.timeMs&&
    s.timeMs>=calibrationMarker.timeMs-1000&&s.pointer.x===endpoint.x&&s.pointer.y===endpoint.y&&
    s.marker.alpha<=.03&&Buffer.isBuffer(s.marker.roi));
  demand(calibration.length>=2,"INSUFFICIENT_EVIDENCE pre-dispatch pointer-only baseline");
  const reference=calibration[0].marker.roi;
  demand(calibration.every(s=>sameG08Pixels(reference,s.marker.roi)),
    "INSUFFICIENT_EVIDENCE unstable pre-dispatch baseline");
  const finalSamples=samples.filter(s=>s.timeMs>=lastStart.timeMs);
  const path=corrected.filter(s=>s.timeMs>=lastStart.timeMs)
    .filter(s=>project(s.p)>.025&&project(s.p)<.975);
  demand(path.length>=18,"INSUFFICIENT_EVIDENCE dense motion samples");
  const pointerDark=path.map(s=>s.pointer.dark);
  demand(Math.min(...pointerDark)/Math.max(...pointerDark)>=.5,
    "INSUFFICIENT_EVIDENCE unstable decoded pointer silhouette");
  const span=path.at(-1).timeMs-path[0].timeMs;
  demand(span>pointerMs*.65,"INSUFFICIENT_EVIDENCE motion phase coverage");
  const gaps=path.slice(1).map((s,i)=>s.timeMs-path[i].timeMs);
  demand(Math.max(...gaps)<=pointerMs*.12,"INSUFFICIENT_EVIDENCE motion sample gap");
  const motion={from:config.from,to:config.to,curve};
  let best={error:Infinity};
  // Only a bounded onset fit, not arbitrary per-frame phase fitting.
  for(let start=path[0].timeMs-pointerMs*.4;start<=path[0].timeMs;start+=5){
    const errors=path.map(s=>distance(s.p,map(scriptPointerPosition(motion,(s.timeMs-start)/pointerMs))));
    const error=rms(errors);
    if(error<best.error)best={start,error};
  }
  demand(best.error<=3,"G08_PATH_OR_EASING_MISMATCH");
  const phases=path.map(s=>(s.timeMs-best.start)/pointerMs);
  demand(Math.min(...phases)<.18&&Math.max(...phases)>.82,"INSUFFICIENT_EVIDENCE easing endpoints");
  // Compare the same geometric curve with a linear time parameter.
  const uneased=progress=>{
    let lo=0,hi=1;
    for(let n=0;n<24;n++){const mid=(lo+hi)/2;if(mid*mid*(3-2*mid)<progress)lo=mid;else hi=mid;}
    return map(scriptPointerPosition(motion,(lo+hi)/2));
  };
  const noEaseError=rms(path.map((s,i)=>distance(s.p,uneased(Math.max(0,Math.min(1,phases[i]))))));
  demand(noEaseError>best.error+4,"G08_EASING_NOT_DISTINGUISHABLE");
  const normals=path.map(s=>(dx*(s.p.y-from.y)-dy*(s.p.x-from.x))/length);
  if(curve==="c")demand(Math.max(...normals)>12&&Math.min(...normals)>-5,"G08_C_CURVE_MISSING");
  else demand(Math.max(...normals)>6&&Math.min(...normals)<-6,"G08_S_CURVE_MISSING");
  const baseAlpha=0.7;
  const normalized=finalSamples.map(s=>({...s,marker:{...s.marker,alpha:s.marker.alpha/baseAlpha}}));
  const marker=normalized.filter(s=>s.marker.count>=20&&s.marker.alpha>.12);
  demand(marker.length>=25,"INSUFFICIENT_EVIDENCE marker phases");
  const peakAlpha=Math.max(...marker.map(s=>s.marker.alpha));
  demand(peakAlpha>=.9,"INSUFFICIENT_EVIDENCE marker onset opacity");
  demand(peakAlpha<=1.1,"G08_MARKER_BASE_OPACITY_MISMATCH");
  const fading=marker.filter(s=>s.marker.alpha>.15&&s.marker.alpha<.9);
  demand(fading.length>=12,"G08_FADE_MISSING");
  const markerStart=median(fading.map(s=>s.timeMs-markerMs*(1-s.marker.alpha)));
  const alphaError=rms(fading.map(s=>s.marker.alpha-scriptTapPresentation((s.timeMs-markerStart)/markerMs).alpha));
  demand(alphaError<=.085,"G08_FADE_TIMELINE_MISMATCH");
  const wave=marker.filter(s=>{const t=(s.timeMs-markerStart)/markerMs;return t>=.03&&t<=.75;});
  demand(wave.length>=20,"INSUFFICIENT_EVIDENCE wobble phases");
  demand(wave[0].timeMs<markerStart+markerMs*.15&&wave.at(-1).timeMs>markerStart+markerMs*.65,
    "INSUFFICIENT_EVIDENCE wobble coverage");
  demand(wave.slice(1).every((s,i)=>s.timeMs-wave[i].timeMs<=markerMs*.12),"INSUFFICIENT_EVIDENCE wobble sample gap");
  const predicted=wave.map(s=>radius*scriptTapPresentation((s.timeMs-markerStart)/markerMs).scale);
  const bias=median(wave.map((s,i)=>s.marker.radius-predicted[i]));
  demand(Math.abs(bias)<=1.6,"G08_MARKER_RADIUS_MISMATCH");
  const wobbleError=rms(wave.map((s,i)=>s.marker.radius-predicted[i]-bias));
  const staticRadius=median(wave.map(s=>s.marker.radius));
  const staticError=rms(wave.map(s=>s.marker.radius-staticRadius));
  demand(wobbleError<=1.25&&staticError>=.75&&wobbleError<staticError*.72,"G08_WOBBLE_MISSING_OR_MISMATCH");
  demand(marker.every(s=>distance(s.marker.center,to)<=3),"G08_MARKER_CENTER_MISMATCH");
  const full=marker.filter(s=>s.marker.alpha>.85);
  demand(full.length>=2,"INSUFFICIENT_EVIDENCE configured color");
  const expected=color.match(/[a-f0-9]{2}/gi).map(value=>parseInt(value,16));
  demand(full.some(s=>s.marker.channels.every((v,i)=>Math.abs(v-(255*(1-baseAlpha)+expected[i]*baseAlpha))<=40)),"G08_MARKER_COLOR_MISMATCH");
  const tail=finalSamples.filter(s=>s.timeMs>=markerStart+markerMs+150);
  demand(tail.length>=3,"INSUFFICIENT_EVIDENCE clean end");
  demand(tail.every(s=>s.pointer&&s.pointer.x===endpoint.x&&s.pointer.y===endpoint.y&&Buffer.isBuffer(s.marker.roi)&&sameG08Pixels(reference,s.marker.roi)),
    "INSUFFICIENT_EVIDENCE tail differs from calibrated pointer-only baseline");
  return {passed:true,confidence:"dense decoded pixels with bounded onset fit",baseAlpha,pointerStartMs:best.start,
    pointerRmsPx:best.error,uneasedRmsPx:noEaseError,endpointOffset:offset,motionSamples:path.length,
    maxMotionGapMs:Math.max(...gaps),markerStartMs:markerStart,
    dwellAfterMotionMs:markerStart-(best.start+pointerMs),alphaRms:alphaError,
    radiusBiasPx:bias,wobbleRmsPx:wobbleError,staticRadiusRmsPx:staticError,markerSamples:marker.length,
    calibrationFrames:calibration.length,calibrationStartMs:calibration[0].timeMs,
    baselineRGBSha256:createHash("sha256").update(reference).digest("hex"),finalClearFrames:tail.length};
}
