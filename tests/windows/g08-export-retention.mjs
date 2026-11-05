import assert from "node:assert/strict";

export function observeG08Native(promise){
 return promise.then(value=>({ok:true,value}),error=>({ok:false,error}));
}

// Export retention has no dependency on native WGC capture succeeding.
export async function retainG08Exports({terminal,activeRunId,budget,parse,download}){
 assert.equal(terminal.success,true);assert.equal(terminal.runId,activeRunId);
 const items=(terminal.artifacts??[]).map(parse);assert.equal(items.length,2);
 const formats=new Set(items.map(item=>item.mimeType));
 assert.deepEqual(formats,new Set(["image/gif","video/mp4"]));
 const artifacts=[];
 for(const item of items)artifacts.push(await download(item,budget));
 return artifacts;
}
