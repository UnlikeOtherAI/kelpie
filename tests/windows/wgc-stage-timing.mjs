const names=new Set(["raw-open","raw-write","raw-hash","raw-flush","raw-complete","png-open","png-encode","png-encoded","png-hash","png-flush","png-complete"]);
export function parseWgcStages(stderr){
 const stages=[];
 for(const line of String(stderr??"").split(/\r?\n/)){
  const match=/^WGC_STAGE ([a-z-]+) (\d{1,15})$/.exec(line);
  if(!match||!names.has(match[1]))continue;
  const tick=Number(match[2]);if(!Number.isSafeInteger(tick)||stages.length>=30)throw Error("WGC_STAGE_BOUND");
  if(stages.length&&tick<stages.at(-1).tick)throw Error("WGC_STAGE_ORDER");
  stages.push({stage:match[1],tick});
 }
 return stages;
}
