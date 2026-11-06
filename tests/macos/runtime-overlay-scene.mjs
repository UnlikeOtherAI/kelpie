// Only fixed synthetic fixture facts are retained; document IDs and raw events stay private.
export function overlayScene(events){
 const first=events.find(e=>e.type==="click"&&e.target==="first"),second=events.find(e=>e.type==="click"&&e.target==="second");
 if(!first||!second||typeof first.documentId!=="string"||first.documentId!==second.documentId)return null;
 const viewport=first.viewport,other=second.viewport;
 if(!viewport||!other||![viewport.width,viewport.height,other.width,other.height,first.x,first.y,second.x,second.y,
  first.time,second.time].every(Number.isFinite)||viewport.width<=0||viewport.height<=0||
  viewport.width!==other.width||viewport.height!==other.height||second.time<first.time||second.time-first.time>60000)return null;
 const center=event=>{
  const r=event.rect;if(!r||![r.left,r.top,r.right,r.bottom].every(Number.isFinite)||r.right<=r.left||r.bottom<=r.top)return null;
  return {x:(r.left+r.right)/2,y:(r.top+r.bottom)/2};
 };
 const firstCenter=center(first),secondCenter=center(second);if(!firstCenter||!secondCenter)return null;
 return {width:viewport.width,height:viewport.height,first:{x:first.x,y:first.y},second:{x:second.x,y:second.y},
  firstCenter,secondCenter,clickSeparationMs:Math.round(second.time-first.time)};
}
