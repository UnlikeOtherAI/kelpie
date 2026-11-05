import {test} from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";

test("hosted comparison defaults to identity preparation and explicit hashes gate measurement",async()=>{
 const workflow=await readFile(new URL("../../.github/workflows/worker-comparison.yml",import.meta.url),"utf8");
 const caller=await readFile(new URL("../../.github/workflows/lint.yml",import.meta.url),"utf8");
 const corpus=await readFile(new URL("./worker-comparison.mjs",import.meta.url),"utf8");
 assert.match(workflow,/prepare_only:\s*\n\s*description:[^\n]*\n\s*type: boolean\s*\n\s*default: true/);
 assert.match(workflow,/if: inputs\.isolation_only == false && inputs\.prepare_only == false/);
 assert.match(workflow,/\[\[ "\$archive_sha" == "\$CHROMIUM_ARCHIVE_SHA256" \]\]/);
 assert.match(workflow,/\[\[ "\$binary_sha" == "\$CHROMIUM_BINARY_SHA256" \]\]/);
 assert.match(caller,/prepare_only: \$\{\{ inputs\.worker_comparison_mode != 'execute' \}\}/);
 const input=caller.match(/worker_comparison_mode:\s*\n([\s\S]*?)\n      worker_comparison_archive_sha256:/);
 assert.ok(input);
 const options=[...input[1].matchAll(/^\s*- (?:'([^']+)'|([^\s]+))\s*$/gm)].map(match=>match[1]??match[2]);
 assert.deepEqual(options,["off","probe","prepare","execute"]);
 const [setup,build]=workflow.split("      - name: Build comparison CLI and shared packages");
 assert.ok(build);assert.doesNotMatch(setup,/pnpm --filter @unlikeotherai\/kelpie(?:-shared)? build/);
 assert.match(build,/^\s*if: inputs\.isolation_only == false && inputs\.prepare_only == false/m);
 assert.match(build,/pnpm --filter @unlikeotherai\/kelpie-shared build/);
 assert.match(build,/pnpm --filter @unlikeotherai\/kelpie build/);
 assert.match(workflow,/name: Probe isolation without a browser[\s\S]*?if: inputs\.isolation_only == true/);
 assert.match(caller,/isolation_only: \$\{\{ inputs\.worker_comparison_mode == 'probe' \}\}/);
 assert.doesNotMatch(corpus,/--no-sandbox/);
});
test("retirement requires the whole owned cgroup to be empty",async()=>{
 const shell=await readFile(new URL("../../scripts/testing/run-worker-comparison-hosted.sh",import.meta.url),"utf8");
 assert.ok(shell.includes('[[ -r "$cgpath/cgroup.procs" ]] || return 1'));
 assert.ok(shell.includes('[[ -r "$cgpath/cgroup.events" ]] || return 1'));
 assert.ok(shell.includes("grep -cx 'populated 0'"));
 assert.ok(shell.includes('[[ -z "$procs" ]] || return 1'));
 assert.ok(shell.indexOf("arm_retired=1")<shell.indexOf('local observation_status=1'));
});
