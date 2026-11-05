import assert from "node:assert/strict";
import {scriptPointerPosition} from "../../packages/shared/dist/index.js";

const distance=(a,b)=>Math.hypot(a.x-b.x,a.y-b.y);
const rms=values=>Math.sqrt(values.reduce((sum,x)=>sum+x*x,0)/values.length);

// Input positions must come from independently decoded native frames and share
// the CSS coordinate space of the fixture. This measures a path, not provenance.
export function fitFastPointer(samples,{from,to,curve}){
  assert.ok(["c","s"].includes(curve),"FAST_INVALID_CURVE");
  assert.ok([from?.x,from?.y,to?.x,to?.y].every(Number.isFinite),"FAST_INVALID_GEOMETRY");
  const dx=to.x-from.x,dy=to.y-from.y,length2=dx*dx+dy*dy;
  assert.ok(length2>=120**2,"FAST_INSUFFICIENT_PATH");
  assert.ok(Array.isArray(samples)&&samples.length>=6&&samples.length<=800,"FAST_INSUFFICIENT_SAMPLES");
  assert.ok(samples.every((p,i)=>[p.timeMs,p.x,p.y].every(Number.isFinite)&&
    (i===0||p.timeMs>samples[i-1].timeMs)),"FAST_INVALID_PTS");
  const endpoint=samples.filter(p=>distance(p,to)<8).at(-1);
  assert.ok(endpoint,"FAST_INSUFFICIENT_ENDPOINT");
  const offset={x:to.x-endpoint.x,y:to.y-endpoint.y};
  const corrected=samples.map(p=>({timeMs:p.timeMs,x:p.x+offset.x,y:p.y+offset.y}));
  const start=corrected.filter(p=>p.timeMs<endpoint.timeMs&&distance(p,from)<4).at(-1);
  assert.ok(start,"FAST_INSUFFICIENT_START");
  const end=corrected.find(p=>p.timeMs>start.timeMs&&distance(p,to)<4);
  assert.ok(end,"FAST_INSUFFICIENT_END");
  const path=corrected.filter(p=>p.timeMs>start.timeMs&&p.timeMs<end.timeMs);
  assert.ok(path.length>=4,"FAST_INSUFFICIENT_SAMPLES");
  const selected=[start,...path,end];
  assert.ok(selected.every((p,i)=>i===0||p.timeMs-selected[i-1].timeMs<=100),"FAST_INSUFFICIENT_CADENCE");
  const progress=p=>((p.x-from.x)*dx+(p.y-from.y)*dy)/length2;
  assert.ok(Math.min(...path.map(progress))<.35&&Math.max(...path.map(progress))>.65,
    "FAST_INSUFFICIENT_COVERAGE");
  const motion={from,to,curve};
  function fit(duration){
    let best=Infinity,onset=null;
    for(let time=start.timeMs;time<=path[0].timeMs;time+=2){
      const error=rms(selected.map(p=>distance(p,scriptPointerPosition(motion,(p.timeMs-time)/duration))));
      if(error<best){best=error;onset=time;}
    }
    return {rms:best,onset};
  }
  const current=fit(350),previous=fit(500);
  assert.ok(current.rms<9&&previous.rms>current.rms+6,"FAST_DURATION_MISMATCH");
  return {observedSpanMs:end.timeMs-start.timeMs,intermediateSamples:path.length,
    maximumGapMs:Math.max(...selected.slice(1).map((p,i)=>p.timeMs-selected[i].timeMs)),
    fit350Px:current.rms,fit500Px:previous.rms,onset350Ms:current.onset,
    endpointOffsetPx:distance(endpoint,to)};
}
