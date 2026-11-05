import test from "node:test";
import assert from "node:assert/strict";
import {parseWgcStages} from "./wgc-stage-timing.mjs";
test("retains only ordered allowlisted stage clocks",()=>{
 assert.deepEqual(parseWgcStages("WGC_STAGE raw-write 100\nsecret TOKEN\nWGC_STAGE png-open 145\n"),[{stage:"raw-write",tick:100},{stage:"png-open",tick:145}]);
 assert.throws(()=>parseWgcStages("WGC_STAGE raw-write 100\nWGC_STAGE png-open 99"),/ORDER/);
 assert.deepEqual(parseWgcStages("WGC_STAGE token 123\n"),[]);
});
