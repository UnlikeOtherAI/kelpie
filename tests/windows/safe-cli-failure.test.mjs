import test from "node:test";
import assert from "node:assert/strict";
import {safeCliFailure} from "./safe-cli-failure.mjs";
test("classifies public CLI errors without retaining untrusted output",()=>{
 const input={code:6,killed:false,stdout:JSON.stringify({error:{code:"BROWSER_LAUNCH_FAILED",message:"Kelpie did not publish a valid local readiness file"},token:"SYNTHETIC_SECRET"})};
 const actual=safeCliFailure(input);assert.equal(actual.category,"readiness-timeout");assert.equal(actual.cliErrorCode,"BROWSER_LAUNCH_FAILED");assert.ok(!JSON.stringify(actual).includes("SYNTHETIC_SECRET"));
 assert.equal(safeCliFailure({stdout:JSON.stringify({error:{code:"BROWSER_LAUNCH_FAILED",message:"Kelpie exited before publishing readiness (exit 1)"}})}).category,"exited-before-readiness");
 assert.equal(safeCliFailure({stdout:JSON.stringify({error:{code:"SYNTHETIC_SECRET",message:"SYNTHETIC_SECRET"}})}).cliErrorCode,null);
 assert.equal(safeCliFailure({killed:true,signal:"SIGTERM"}).killed,true);
});

test("retains only bounded allowlisted retirement facts",()=>{
 const value=safeCliFailure({stdout:JSON.stringify({error:{code:"BROWSER_LAUNCH_PENDING",retirement:{outcome:"exit-wait-expired",elapsedMs:12000}}})});
 assert.deepEqual(value.retirement,{outcome:"exit-wait-expired",elapsedMs:12000});
 assert.equal(safeCliFailure({stdout:JSON.stringify({error:{retirement:{outcome:"SYNTHETIC_SECRET",elapsedMs:1}}})}).retirement,null);
});
