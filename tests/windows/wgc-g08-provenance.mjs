import assert from "node:assert/strict";
// Facts are collected by the owned harness from public/native interfaces.
// Fixture document IDs are checked only within the fixture, never as native IDs.
export function verifyWgcProvenance(facts){
 const {source,identity,window,active,terminal,before,after,fixture,artifacts,summary}=facts;
 assert.match(source,/^[a-f0-9]{40}$/);assert.ok(["c","s"].includes(facts.curve));assert.ok(identity&&window&&active&&terminal&&before&&after&&fixture&&summary);
 assert.ok(Number.isInteger(identity.pid)&&identity.pid>0&&identity.sessionId===1);
 assert.ok(typeof identity.executable==="string"&&identity.executable.length>0&&/^\d+$/.test(identity.startFileTime));
 assert.ok(typeof identity.launchId==="string"&&identity.launchId.length>0&&identity.port>0);
 assert.equal(window.processId,identity.pid);assert.equal(window.startFileTime,identity.startFileTime);
 assert.equal(window.className,"KelpieScriptPresentation");assert.ok(/^\d+$/.test(window.windowHandle));
 assert.equal(summary.processId,identity.pid);assert.equal(summary.startFileTime,identity.startFileTime);
 assert.equal(summary.windowHandle,window.windowHandle);assert.equal(summary.className,window.className);
 assert.equal(summary.sessionClosedBeforeEncoding,true);
 assert.equal(summary.cursorCapture,false);assert.equal(summary.secondaryWindows,false);assert.equal(summary.borderRequired,true);
 assert.equal(summary.framePoolBuffers,2);assert.equal(summary.memoryLimitBytes,134217728);
 assert.ok(Number.isInteger(summary.sessionDurationMs)&&summary.sessionDurationMs>=0&&summary.sessionDurationMs<=26000);
 assert.ok(Number.isInteger(summary.accepted)&&summary.accepted>=0&&summary.accepted<=520);
 assert.ok(Number.isInteger(summary.written)&&summary.written>=0&&summary.written<=summary.accepted);
 assert.equal(facts.frameCount,summary.written,"WGC_STREAM_COUNT_MISMATCH");
 for(const key of ["writerReplaced","poolReplaced","rateSkipped"])assert.ok(Number.isInteger(summary[key])&&summary[key]>=0);
 assert.ok(["item-closed","frame-limit","capture-deadline"].includes(summary.endReason));
 assert.match(active.runId,/^[a-f0-9]{48}$/);assert.equal(active.playing,true);
 assert.equal(terminal.runId,active.runId);assert.equal(terminal.success,true);
 assert.ok(typeof before.tabId==="string"&&before.tabId.length>0);assert.equal(after.tabId,before.tabId);
 assert.equal(before.active,true);assert.equal(after.active,true);
 assert.ok(typeof before.url==="string"&&before.url.length>0);assert.equal(after.url,before.url);
 assert.equal(fixture.url,before.url);assert.equal(fixture.pageRequests,1);assert.equal(fixture.dropped,0);
 assert.equal(fixture.events.length,3);assert.deepEqual(fixture.events.map(event=>event.target),["finish","start","finish"]);
 assert.ok(fixture.events.every(event=>event.trusted===true&&event.documentId===fixture.events[0].documentId));
 assert.ok(fixture.events.every((event,index)=>index===0||event.timeMs>fixture.events[index-1].timeMs));
 assert.ok(Array.isArray(artifacts)&&artifacts.length===2);
 assert.deepEqual(artifacts.map(item=>item.mimeType).sort(),["image/gif","video/mp4"]);
 assert.equal(summary.analysisWidth,artifacts[0].width);assert.equal(summary.analysisHeight,artifacts[0].height);
 const doc=artifacts[0].documentId;assert.ok(typeof doc==="string"&&doc.length>0);
 for(const artifact of artifacts){
  assert.equal(artifact.runId,active.runId);assert.equal(artifact.documentId,doc);assert.equal(artifact.partial,false);
  assert.match(artifact.sha256,/^[a-f0-9]{64}$/);assert.ok(Number.isSafeInteger(artifact.byteLength)&&artifact.byteLength>0&&artifact.byteLength<=33554432);
  assert.ok(Number.isInteger(artifact.width)&&artifact.width>0&&artifact.width<=640&&Number.isInteger(artifact.height)&&artifact.height>0&&artifact.height<=1600);
  assert.deepEqual(artifact.viewport,artifacts[0].viewport);
  assert.equal(artifact.width,artifacts[0].width);assert.equal(artifact.height,artifacts[0].height);
 }
 assert.deepEqual(artifacts[0].viewport,fixture.events[0].viewport);
 return {source,runId:active.runId,documentId:doc,curve:facts.curve,width:artifacts[0].width,height:artifacts[0].height,
  factSources:{identity:"public launch plus OS process and listener",window:"owned HWND descriptor",active:"public script status",
   terminal:"public script result",documentId:"native artifact metadata",tab:"public tabs before and after",
   fixture:"controlled server request count and event consistency",capture:"owned WGC helper summary"}};
}
