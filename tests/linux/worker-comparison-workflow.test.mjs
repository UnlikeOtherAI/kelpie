import {test} from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";

test("hosted comparison defaults to identity preparation and explicit hashes gate measurement",async()=>{
 const workflow=await readFile(new URL("../../.github/workflows/worker-comparison.yml",import.meta.url),"utf8");
 const caller=await readFile(new URL("../../.github/workflows/lint.yml",import.meta.url),"utf8");
 const corpus=await readFile(new URL("./worker-comparison.mjs",import.meta.url),"utf8");
 assert.match(workflow,/prepare_only:\s*\n\s*description:[^\n]*\n\s*type: boolean\s*\n\s*default: true/);
 assert.match(workflow,/if: inputs\.isolation_only == false && inputs\.sandbox_only == false && inputs\.eof_only == false && inputs\.prepare_only == false/);
 assert.match(workflow,/\[\[ "\$archive_sha" == "\$CHROMIUM_ARCHIVE_SHA256" \]\]/);
 assert.match(workflow,/\[\[ "\$binary_sha" == "\$CHROMIUM_BINARY_SHA256" \]\]/);
 assert.match(caller,/prepare_only: \$\{\{ inputs\.worker_comparison_mode != 'execute' && inputs\.worker_comparison_mode != 'execute-2204' \}\}/);
 const input=caller.match(/worker_comparison_mode:\s*\n([\s\S]*?)\n      worker_comparison_archive_sha256:/);
 assert.ok(input);
 const options=[...input[1].matchAll(/^\s*- (?:'([^']+)'|([^\s]+))\s*$/gm)].map(match=>match[1]??match[2]);
 assert.deepEqual(options,["off","probe","sandbox","sandbox-2204","eof-2204","execute-2204","prepare","execute"]);
 assert.match(input[1],/options:\s*\n {10}- 'off'\s*\n {10}- probe\s*\n {10}- sandbox\s*\n {10}- sandbox-2204\s*\n {10}- eof-2204\s*\n {10}- execute-2204\s*\n {10}- prepare\s*\n {10}- execute/);
 const [setup,build]=workflow.split("      - name: Build comparison CLI and shared packages");
 assert.ok(build);assert.doesNotMatch(setup,/pnpm --filter @unlikeotherai\/kelpie(?:-shared)? build/);
 assert.match(build,/^\s*if: inputs\.isolation_only == false && inputs\.sandbox_only == false && inputs\.eof_only == false && inputs\.prepare_only == false/m);
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

test("live namespace handoff precedes all engine processes and sandbox precedes corpus",async()=>{
 const corpus=await readFile(new URL("./worker-comparison.mjs",import.meta.url),"utf8");
 const gate=corpus.indexOf('assert.ok(boundaryReady,"PRIVATE_NETWORK_NOT_VERIFIED")');
 const version=corpus.indexOf("const version=(await exec(executable,");
 const spawn=corpus.indexOf("engine=spawn(executable,");
 const sandbox=corpus.indexOf("queryRendererPidsAtOwnedPort(port,engine.pid,engineStart)");
 const corpusRun=corpus.indexOf("await check(\"second session refused");
 assert.ok(gate>=0&&gate<version&&version<spawn&&spawn<sandbox&&sandbox<corpusRun);
});

test("sandbox smoke has a separate pinned and corpus-free dispatch",async()=>{
 const workflow=await readFile(new URL("../../.github/workflows/worker-comparison.yml",import.meta.url),"utf8");
 const smoke=await readFile(new URL("./worker-comparison-sandbox-smoke.mjs",import.meta.url),"utf8");
 assert.match(workflow,/name: Smoke test pinned Chromium sandbox[\s\S]*?inputs\.sandbox_only == true/);
 assert.ok(smoke.indexOf("assert.ok(ready")<smoke.indexOf("browser=spawn("));
 assert.doesNotMatch(smoke,/kelpie_worker_session|kelpie_browser_control/);
 assert.ok(smoke.indexOf("assert.ok(canaryObserved")<smoke.indexOf("browser-identity.json"));
 assert.ok(smoke.indexOf("SANDBOX_BROWSER_CHANGED")<smoke.indexOf("browser-identity.json"));
});

test("alternate runner is allowlisted for reviewed runs",async()=>{
 const workflow=await readFile(new URL("../../.github/workflows/worker-comparison.yml",import.meta.url),"utf8");
 const caller=await readFile(new URL("../../.github/workflows/lint.yml",import.meta.url),"utf8");
 assert.ok(workflow.includes('ubuntu-22.04) [[ "$ISOLATION_ONLY" == false && ( "$SANDBOX_ONLY" == true || "$PREPARE_ONLY" == false || "$EOF_ONLY" == true ) ]] || exit 1 ;;'));
 assert.ok(caller.includes("worker_comparison_mode == 'sandbox-2204'"));
});

test("EOF smoke requires the live fixture, natural child exit and distinct engine retirement",async()=>{
 const smoke=await readFile(new URL("./worker-comparison-eof-proof.mjs",import.meta.url),"utf8");
 const workflow=await readFile(new URL("../../.github/workflows/worker-comparison.yml",import.meta.url),"utf8");
 const shell=await readFile(new URL("../../scripts/testing/run-worker-comparison-hosted.sh",import.meta.url),"utf8");
 assert.match(workflow,/name: Probe public worker EOF in isolated unit[\s\S]*?inputs\.eof_only == true/);
 assert.ok(shell.includes('run_arm eof "$assets/lightpanda"'));
 const gate=smoke.indexOf('assert.ok(verified,"PRIVATE_NETWORK_NOT_VERIFIED")');
 const engine=smoke.indexOf('engine=spawn(binary,');
 const identity=smoke.indexOf('relay.result().stage');
 const eof=smoke.indexOf('child.stdin.end()');
 const disposed=smoke.indexOf('const witness=relay.result()');
 const term=smoke.indexOf('engine.kill("SIGTERM")');
 assert.ok(gate<engine&&engine<identity&&identity<eof&&eof<disposed&&disposed<term);
 assert.ok(smoke.includes('assert.deepEqual(report.cli.signals,[])'));
 assert.doesNotMatch(smoke,/client\.close\(\)|child\.kill\("SIG(?:TERM|KILL)"\)/);
});