import {test} from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";

test("hosted comparison defaults to identity preparation and explicit hashes gate measurement",async()=>{
 const workflow=await readFile(new URL("../../.github/workflows/worker-comparison.yml",import.meta.url),"utf8");
 const caller=await readFile(new URL("../../.github/workflows/lint.yml",import.meta.url),"utf8");
 const corpus=await readFile(new URL("./worker-comparison.mjs",import.meta.url),"utf8");
 assert.match(workflow,/prepare_only:\s*\n\s*description:[^\n]*\n\s*type: boolean\s*\n\s*default: true/);
 assert.match(workflow,/if: inputs\.prepare_only == false/);
 assert.match(workflow,/\[\[ "\$archive_sha" == "\$CHROMIUM_ARCHIVE_SHA256" \]\]/);
 assert.match(workflow,/\[\[ "\$binary_sha" == "\$CHROMIUM_BINARY_SHA256" \]\]/);
 assert.match(caller,/prepare_only: \$\{\{ !inputs\.worker_comparison_execute \|\| inputs\.worker_comparison_prepare \}\}/);
 assert.doesNotMatch(corpus,/--no-sandbox/);
});
