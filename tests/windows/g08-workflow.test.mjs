import test from "node:test";
import assert from "node:assert/strict";
import {g08Workflow} from "../capture/g08-fixture.mjs";
import {applyG08MotionProfile} from "../capture/g08-motion-profile.mjs";
import {scriptV1Schema} from "../../packages/shared/dist/index.js";
test("shared G08 Windows requests pass the production workflow schema",()=>{
 for(const curve of ["c","s"]){
  const result=scriptV1Schema.parse(g08Workflow("owned-tab",curve));
  assert.equal(result.pointer.curve,curve);
  assert.deepEqual(result.capture.formats,["gif","video"]);
  assert.deepEqual(result.actions.filter(action=>action.action==="click").map(action=>action.target.name),["G08 Finish","G08 Finish","G08 Start","G08 Finish"]);
 }
});

test("Windows motion profiles exercise explicit and default pointer timing",()=>{
 for(const [profile,duration] of [["dense",2400],["fast",350],["default",350]]){
  const request=applyG08MotionProfile(g08Workflow("owned-tab","c"),profile);
  assert.equal(Object.hasOwn(request.pointer,"durationMs"),profile!=="default");
  assert.equal(scriptV1Schema.parse(request).pointer.durationMs,duration);
 }
 assert.throws(()=>applyG08MotionProfile(g08Workflow("owned-tab","c"),"unknown"));
});
