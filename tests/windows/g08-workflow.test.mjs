import test from "node:test";
import assert from "node:assert/strict";
import {g08Workflow} from "../capture/g08-fixture.mjs";
import {scriptV1Schema} from "../../packages/shared/dist/index.js";
test("shared G08 Windows requests pass the production workflow schema",()=>{
 for(const curve of ["c","s"]){
  const result=scriptV1Schema.parse(g08Workflow("owned-tab",curve));
  assert.equal(result.pointer.curve,curve);
  assert.deepEqual(result.capture.formats,["gif","video"]);
 }
});
