import assert from "node:assert/strict";
export function acceptPresentation(result,identity,pid){
 assert.equal(result.processId,pid);assert.equal(result.sessionId,1);
 assert.equal(result.startFileTime,identity.startFileTime);
 assert.equal(result.executable.toLowerCase(),identity.executable.toLowerCase());
 assert.ok(Array.isArray(result.ownedWindows)&&result.ownedWindows.length===1);
 const window=result.ownedWindows[0];assert.equal(window.processId,pid);
 assert.equal(window.className,"KelpieScriptPresentation");assert.equal(window.offscreen,false);
 assert.match(window.windowHandle,/^\d+$/);return {...window,startFileTime:result.startFileTime};
}
export function presentationNotVisible(error){
 return String(error.stderr??"").trim()==="InvalidOperationException: Exactly one visible owned target window is required";
}
