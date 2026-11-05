import test from "node:test";
import assert from "node:assert/strict";
import { scriptPointerPosition,scriptTapPresentation } from "../../packages/shared/dist/index.js";
import { measureG08Frame } from "./g08-pixels.mjs";
import { evaluateG08 } from "./g08-timeline.mjs";
const width=320,height=180;
const base={from:{x:64,y:90},to:{x:256,y:90},pointerMs:2400,markerMs:3000,radius:24,color:"#ff0000"};
const inverse=t=>{let lo=0,hi=1;for(let n=0;n<24;n++){const m=(lo+hi)/2;if(m*m*(3-2*m)<t)lo=m;else hi=m;}return(lo+hi)/2;};
function render(config,mode){
  const samples=[],scale=config.scale??{x:1,y:1};
  const center={x:config.to.x*scale.x,y:config.to.y*scale.y};
  for(let timeMs=0;timeMs<=9100;timeMs+=50){
    const bytes=Buffer.alloc(width*height*3,255);
    const phase=Math.max(0,Math.min(1,(timeMs-2900)/config.pointerMs));
    let p=scriptPointerPosition(mode==="wrongcurve"?{...config,curve:"s"}:config,mode==="noease"?inverse(phase):phase);
    if(timeMs<2500){
      if(["movingCalibration","noStableCalibration"].includes(mode)){
        const initial={x:config.to.x-80,y:config.to.y-60};
        p=scriptPointerPosition({from:initial,to:config.to,curve:config.curve},
          timeMs/(mode==="movingCalibration"?1700:2000));
      }else p=config.to;
    }
    if(mode==="straight"&&timeMs>=2500)p={x:config.from.x+(config.to.x-config.from.x)*phase,y:config.from.y};
    p={x:p.x*scale.x,y:p.y*scale.y};
    const progress=timeMs>=2000&&timeMs<2150?.1:(timeMs-5500)/(mode==="wrongduration"?config.markerMs*.65:config.markerMs);
    if(progress>=0&&(progress<1||mode==="stuck")){
      const tap=scriptTapPresentation(progress,mode!=="nowobble",true);
      const alpha=(["stuck","nofade"].includes(mode)?1:tap.alpha)*(mode==="opaque"?1:mode==="wrongopacity"?.85:(config.baseAlpha??0.7)),radius=config.radius*scale.x*tap.scale;
      const channels=(mode==="wrongcolor"?"#0000ff":config.color).match(/[a-f0-9]{2}/gi).map(value=>parseInt(value,16));
      for(let y=0;y<height;y++)for(let x=0;x<width;x++)if(Math.hypot(x-center.x,y-center.y)<=radius){
        const i=(y*width+x)*3;for(let c=0;c<3;c++)bytes[i+c]=Math.round(255*(1-alpha)+channels[c]*alpha);
      }
    }
    for(let y=Math.floor(p.y);y<Math.floor(p.y)+10;y++)for(let x=Math.floor(p.x);x<Math.floor(p.x)+6;x++){
      const i=(y*width+x)*3;bytes[i]=bytes[i+1]=bytes[i+2]=0;
    }
    if(mode?.startsWith("overlap")){
      const anchor={x:Math.floor(p.x),y:Math.floor(p.y)};
      for(let y=anchor.y+2;y<anchor.y+5;y++)for(let x=anchor.x+3;x<anchor.x+6;x++){
        const i=(y*width+x)*3;bytes[i]=bytes[i+1]=72;bytes[i+2]=96;
      }
      if(timeMs>=8700&&mode!=="overlapClean"){
        const r=mode==="overlapSmall"?2:config.radius*scale.x;
        for(let y=0;y<height;y++)for(let x=0;x<width;x++)if(Math.hypot(x-center.x,y-center.y)<=r){
          const i=(y*width+x)*3;
          if(bytes[i]>200){bytes[i]=bytes[i+1]=220;bytes[i+2]=255;}
        }
      }
    }
    if(mode==="palette"||mode?.startsWith("overlap"))for(let i=0;i<bytes.length;i++)bytes[i]=Math.round((bytes[i]>>(i%3===2?6:5))*255/(i%3===2?3:7));
    samples.push({timeMs,...measureG08Frame(bytes,width,height,{center,radius:config.radius*scale.x,color:config.color})});
  }
  return samples;
}
for(const curve of ["c","s"])for(const palette of [false,true])for(const baseAlpha of [178/255,179/255]){
  test("decoded pixel oracle accepts canonical "+curve+" path/ease/wobble/fade palette="+palette+" alpha="+baseAlpha,()=>{
    const config={...base,curve,baseAlpha,color:curve==="s"?"#0000ff":"#ff0000"};const result=evaluateG08(render(config,palette?"palette":undefined),config);
    assert.equal(result.passed,true);assert.ok(result.motionSamples>=18);
  });
}
for(const mode of ["straight","noease","nowobble","nofade","stuck","wrongduration","opaque","wrongopacity","wrongcurve","wrongcolor"]){
  test("pixel negative rejects "+mode,()=>{
    const config={...base,curve:"c"};
    assert.throws(()=>evaluateG08(render(config,mode),config),/G08_|INSUFFICIENT/);
  });
}
test("unstable pointer silhouette is insufficient rather than a curve failure",()=>{
  const config={...base,curve:"s"},samples=render(config);
  for(let i=0;i<samples.length;i++)if(samples[i].pointer&&i%2)samples[i].pointer.dark=5;
  assert.throws(()=>evaluateG08(samples,config),/INSUFFICIENT_EVIDENCE unstable decoded pointer silhouette/);
});
test("sparse samples are insufficient rather than a timeline pass",()=>{
  const config={...base,curve:"s"};
  assert.throws(()=>evaluateG08(render(config).filter((_,i)=>i%8===0),config),/INSUFFICIENT/);
});

for(const curve of ["c","s"])test("CSS curve amplitude is projected after model evaluation "+curve,()=>{
 const config={...base,curve,from:{x:64,y:180},to:{x:576,y:180},radius:48,scale:{x:.5,y:.5}};
 assert.equal(evaluateG08(render(config),config).passed,true);
});

test("pointer palette baseline accepts clear tail but rejects small and faint overlapping markers",()=>{
  const config={...base,curve:"s",color:"#0000ff"};
  assert.equal(evaluateG08(render(config,"overlapClean"),config).passed,true);
  for(const mode of ["overlapSmall","overlapFaint"]){
    const samples=render(config,mode);
    assert.equal(samples[0].marker.roi.equals(samples.at(-1).marker.roi),false);
    assert.throws(()=>evaluateG08(samples,config),/INSUFFICIENT_EVIDENCE tail differs|G08_FADE_TIMELINE_MISMATCH/);
  }
});

test("calibration requires an observed later dispatch marker and stable pre-dispatch pixels",()=>{
  const config={...base,curve:"c"};
  const missing=render(config);for(const sample of missing)if(sample.timeMs>=2000&&sample.timeMs<2150)sample.marker.alpha=0;
  assert.throws(()=>evaluateG08(missing,config),/INSUFFICIENT_EVIDENCE calibration dispatch marker/);
  const unstable=render(config);const candidate=unstable.find(sample=>sample.timeMs===1900);candidate.marker.roi=Buffer.from(candidate.marker.roi);candidate.marker.roi[0]^=1;
  assert.throws(()=>evaluateG08(unstable,config),/INSUFFICIENT_EVIDENCE unstable pre-dispatch baseline/);
});

test("calibration allows an initial pointer movement but requires same-position pre-marker frames",()=>{
  const config={...base,curve:"c"};
  assert.equal(evaluateG08(render(config,"movingCalibration"),config).passed,true);
  assert.throws(()=>evaluateG08(render(config,"noStableCalibration"),config),
    /INSUFFICIENT_EVIDENCE pre-dispatch pointer-only baseline/);
});

test("validated model reference substitutes only exact tail pixels",()=>{
  const config={...base,curve:"s",color:"#0000ff"};
  const clean=render(config,"overlapClean");
  const reference=Buffer.from(clean[0].marker.roi);
  const unstable=render(config,"overlapClean");
  const candidate=unstable.find(sample=>sample.timeMs===1900);
  candidate.marker.roi=Buffer.from(candidate.marker.roi);candidate.marker.roi[0]^=1;
  assert.throws(()=>evaluateG08(unstable,config),/unstable pre-dispatch baseline/);
  const result=evaluateG08(unstable,config,reference);
  assert.match(result.confidence,/ENCODED-VISIBLE only/);
  assert.equal(result.referenceKind,"production-model-gif");
  for(const mode of ["overlapSmall","overlapFaint","stuck"]){
    assert.throws(()=>evaluateG08(render(config,mode),config,reference),/INSUFFICIENT|G08_/);
  }
  const noMarker=render(config,"overlapClean");
  for(const sample of noMarker)if(sample.timeMs>=2000&&sample.timeMs<2150)sample.marker.alpha=0;
  assert.throws(()=>evaluateG08(noMarker,config,reference),/calibration dispatch marker/);
  assert.throws(()=>evaluateG08(clean,config,Buffer.alloc(0)),/invalid model reference/);
  assert.throws(()=>evaluateG08(clean,config,Buffer.alloc(reference.length)),/tail differs/);
  for(const mode of ["straight","noease","nowobble","nofade","wrongcolor"]){
    assert.throws(()=>evaluateG08(render(config,mode),config,reference),/INSUFFICIENT|G08_/);
  }
  assert.throws(()=>evaluateG08(clean.filter((_,i)=>i%8===0),config,reference),/INSUFFICIENT/);
});
