import assert from "node:assert/strict";

export function g08Curves(mode){
 assert.ok(mode===undefined||mode==="--single-c","Unknown capture mode");
 return mode==="--single-c"?["c"]:["c","s"];
}

const publicFailures=new Set(["CAPTURE_NATIVE_PRESENTATION_FAILED","CAPTURE_VIEWPORT_CHANGED",
 "CAPTURE_DOCUMENT_UNAVAILABLE","CAPTURE_FAILED","SCRIPT_ABORTED"]);
export function safeG08Failure(error){
 return publicFailures.has(error?.code)?error.code:"PLAY_SCRIPT_FAILED";
}
