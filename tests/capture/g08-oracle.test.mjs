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
  for(let timeMs=0;timeMs<=6400;timeMs+=50){
    const bytes=Buffer.alloc(width*height*3,255);
    const phase=Math.max(0,Math.min(1,(timeMs-200)/config.pointerMs));
    let p=scriptPointerPosition(mode==="wrongcurve"?{...config,curve:"s"}:config,mode==="noease"?inverse(phase):phase);
    if(mode==="straight")p={x:config.from.x+(config.to.x-config.from.x)*phase,y:config.from.y};
    p={x:p.x*scale.x,y:p.y*scale.y};
    const progress=(timeMs-2800)/(mode==="wrongduration"?config.markerMs*.65:config.markerMs);
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
    if(mode==="palette")for(let i=0;i<bytes.length;i++)bytes[i]=Math.round((bytes[i]>>(i%3===2?6:5))*255/(i%3===2?3:7));
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
test("sparse samples are insufficient rather than a timeline pass",()=>{
  const config={...base,curve:"s"};
  assert.throws(()=>evaluateG08(render(config).filter((_,i)=>i%8===0),config),/INSUFFICIENT/);
});

for(const curve of ["c","s"])test("CSS curve amplitude is projected after model evaluation "+curve,()=>{
 const config={...base,curve,from:{x:64,y:180},to:{x:576,y:180},radius:48,scale:{x:.5,y:.5}};
 assert.equal(evaluateG08(render(config),config).passed,true);
});
