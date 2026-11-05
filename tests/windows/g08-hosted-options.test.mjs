import test from "node:test";
import assert from "node:assert/strict";
import {g08Curves,safeG08Failure} from "./g08-hosted-options.mjs";

test("single-C mode is explicit and the standard two-curve run stays intact",()=>{
 assert.deepEqual(g08Curves(),["c","s"]);assert.deepEqual(g08Curves("--single-c"),["c"]);
 assert.throws(()=>g08Curves("--single-s"));
});
test("hosted failure reports use only fixed public codes",()=>{
 assert.equal(safeG08Failure({code:"CAPTURE_NATIVE_PRESENTATION_FAILED"}),"CAPTURE_NATIVE_PRESENTATION_FAILED");
 assert.equal(safeG08Failure({code:"SYNTHETIC_SECRET"}),"PLAY_SCRIPT_FAILED");
});
