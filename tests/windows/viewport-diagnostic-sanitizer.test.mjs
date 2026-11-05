import test from "node:test";
import assert from "node:assert/strict";
import {parseViewportDiagnostic} from "./viewport-diagnostic-sanitizer.mjs";
const line=value=>"KELPIE_CAPTURE_VIEWPORT_DIAGNOSTIC "+JSON.stringify(value);
test("viewport diagnostics retain only known fence and bounded numeric metrics",()=>{
 const value={fence:"before-after",before:{width:1042,visual_scale:1},after:{width:1042,visual_height:647}};
 assert.deepEqual(parseViewportDiagnostic(line(value)),value);
 for(const bad of [
  {...value,fence:"unknown"},
  {...value,before:{secret:"do-not-retain"}},
  {...value,before:{width:1000001}},
  {...value,before:[]},
 ])assert.equal(parseViewportDiagnostic(line(bad)),null);
 assert.equal(parseViewportDiagnostic("unrelated secret"),null);
 assert.equal(parseViewportDiagnostic("KELPIE_CAPTURE_VIEWPORT_DIAGNOSTIC {"),null);
});
