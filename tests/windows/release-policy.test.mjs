import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import test from "node:test";
test("Windows CI retains unsigned candidates without release-publishing authority",async()=>{
 const workflow=await readFile(new URL("../../.github/workflows/release-windows.yml",import.meta.url),"utf8");
 assert.match(workflow,/contents:\s*read/);
 assert.doesNotMatch(workflow,/contents:\s*write|id-token:\s*write|action-gh-release|gh\s+release\s+(upload|create)/i);
 assert.match(workflow,/name: windows-unsigned-candidate-/);
 assert.match(workflow,/\*-unsigned\.zip/);
});
test("Windows packaging labels unsigned output and records its signing status",async()=>{
 const source=await readFile(new URL("../../scripts/package-windows.ps1",import.meta.url),"utf8");
 assert.match(source,/"-unsigned\.zip"/);
 assert.match(source,/signing_status=unsigned/);
});
