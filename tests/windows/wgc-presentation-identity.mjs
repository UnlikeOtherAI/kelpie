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

export function presentationCaptureExecutable(identity){
 assert.ok(typeof identity.executable==="string"&&/^[a-z]:\\/i.test(identity.executable)&&!identity.executable.includes("/"));
 return identity.executable;
}

export function safeUiaFailure(error){
 const reasons=new Map([
  ["InvalidOperationException: Exactly one visible owned target window is required","owned-window-unavailable"],
  ["InvalidOperationException: Candidate executable/session identity mismatch","process-session-mismatch"],
  ["InvalidOperationException: Candidate start-time identity mismatch","process-start-mismatch"],
  ["InvalidOperationException: UIA test requires interactive Session1","wrong-session"]
 ]);
 return {category:reasons.get(String(error.stderr??"").trim())??"uia-other",
  code:typeof error.code==="number"?error.code:null,signal:error.signal??null,killed:error.killed===true};
}