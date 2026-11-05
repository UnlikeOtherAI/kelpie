import assert from "node:assert/strict";
// Legacy evaluation is intentionally BUSY during a workflow. Evidence reads
// and spatial validation happen only after native Stop and terminal status.
export async function finishNativeWindowEvidence({stopInvoked,completion,readStatus,readClick,validate,scene}){
 assert.equal(stopInvoked,true,"Native Stop must precede terminal evidence reads");
 const result=await completion;
 const status=await readStatus(result.runId);
 assert.equal(status.playing,false,"Wait for the exact run to become terminal");
 assert.equal(status.runId,result.runId);
 const response=await readClick();
 assert.equal(response.success,true,"POST_TERMINAL_CLICK_READ:"+response.error?.code);
 const event=response.result;
 assert.ok(event,"Fixture click event was not observed");
 assert.equal(event.trusted,true);
 assert.equal(event.documentId,scene.documentId);
 assert.ok(Math.abs(event.x-scene.target.x)<=1&&Math.abs(event.y-scene.target.y)<=1);
 assert.equal(event.dpr,scene.viewport.dpr);
 assert.equal(event.visualScale,scene.viewport.visualScale);
 const validated=await validate(event);
 return {result,status,event,validated};
}
