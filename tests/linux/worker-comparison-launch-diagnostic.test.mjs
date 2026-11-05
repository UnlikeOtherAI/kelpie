import {test} from "node:test";
import assert from "node:assert/strict";
import {classifySpawnError,classifyChromiumStderr,createBoundedStderr} from "./worker-comparison-launch-diagnostic.mjs";
test("launch errors and stderr produce only bounded fixed categories",()=>{
 assert.equal(classifySpawnError("EACCES"),"EACCES");
 assert.equal(classifySpawnError("private path"),"OTHER");
 assert.deepEqual(classifyChromiumStderr("No usable sandbox; apparmor blocked path /secret"),["sandbox-unavailable","apparmor"]);
 assert.deepEqual(classifyChromiumStderr("error while loading shared libraries: private"),["loader"]);
 const capture=createBoundedStderr(4);capture.append("abcdefgh");
 assert.deepEqual(capture.result(),{categories:["other"],bytes:4,truncated:true});
 assert.ok(!JSON.stringify(capture.result()).includes("abcd"));
});
