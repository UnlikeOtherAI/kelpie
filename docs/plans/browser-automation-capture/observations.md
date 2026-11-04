# Shared observations, extraction, and readiness

Base revision: b6784ff723b27da4096fdd8d9227f2a00dfc9084.
Implementation worktree: D:/Worktrees/kelpie/capture-observations-20261104 on Maxis.
Branch: codex/capture-observations-20261104.

## Requirements and decisions

- OBS-1: Prioritized value-free snapshots. Actions, headings, landmarks, then prose;
  stable document order within each class. Explicit prioritize:false retains source order.
  Existing hard output bounds and traversal bound remain. Fresh references still belong
  to one snapshot/tab/gateway. No persistent content script.
- OBS-2: Scope is an optional CSS selector matching exactly one element. It narrows
  the current authorized document, never changes session/tab ownership. Missing or
  ambiguous scopes refuse. Hidden/editor text and referenced editable labels stay excluded.
- OBS-3: Deterministic structured extraction. Three mapping levels, repeated records,
  missing/ambiguous distinction, explicit selector/source/match provenance, global
  100-record and 512-nested-field budget. Only text/href/src/datetime sources.
  No arbitrary attribute, form-value, script evaluation, or model-generated code.
- OBS-4: Publisher metadata is explicitly untrusted publisher-claim evidence.
  Meta tags are allowlisted (canonical, description, author, publisher, published time,
  title). JSON-LD: application/ld+json only; eight scripts, 32 KiB/script,
  64 KiB total, at most 32 objects including @graph; allowlisted @type/name/headline,
  datePublished/dateModified/url, author/publisher names. No raw objects, script
  bodies, articleBody, arbitrary attributes, or arbitrary fields are returned.
- OBS-5: Compact status returns document load/visibility, viewport, visible dialog,
  busy-region, and aria-invalid counts. Network and runtime-error evidence are
  explicitly unavailable, never reported as zero. No background listeners.
- OBS-6: Readiness is an immediate predicate over interactive/complete document
  state and an optional exactly-one visible selector. It has no timeout parameter
  and makes no claim about network idle, SPA completion, or task success.
  Workflows owns bounded repeated waits.
- OBS-7: One authoritative strict v1 schema and fixed portable reader per operation;
  native generation serializes the same functions used by Playwright.
  Native fixedReader capability gates observations; no unsupported native locators
  or screenshots are silently emulated.

## Verification checklist

- [x] Read global/repository AGENTS.md, CLAUDE.md, brief, architecture, stack,
  and shared-browser API documentation.
- [x] Maxis dependency install: pnpm.cmd install --frozen-lockfile --ignore-scripts;
  exit 0, 1m36.7s; PID32000; log D:/Temp/capture-observations-20261104/install.log.
- [x] Required pnpm lint/build/full tests: shared 91, CLI 626 pass; 64 existing CLI skips.
- [x] Focused schema/read-only/authorization evals: three tests pass.
- [x] Real Chromium portable and serialized fixed-reader evals: 24 tests pass; scoped priorities,
  nested records, metadata/JSON-LD, private canaries, missing/ambiguous selectors,
  document state and visibility recovery.
- [x] Native core gateway and extension checks: 2/2 CTest cases pass.
- [x] Manual shared SDK calls against acceptance HTTP fixture on real Chromium; details below.
- [ ] Windows native acceptance at integrated revision (native owner), then Mac; user changed the first native gate to Windows.
- [ ] Other native rollout after Windows/Mac; no mock result is physical-device evidence.

Premature lint/build attempts before dependency installation finished failed for missing
eslint/typescript; they do not establish a source defect or count as passing checks.
No native app build, release, or native UI verification has run in this worktree.
ChatterBox tools are unavailable; resource coordination uses the root agent.

## Durable eval locations

- packages/shared/tests/browser-observations.test.ts: schema bounds, read-only
  classification, authorization before page resolution.
- packages/shared/tests/browser-control.browser.test.ts: real Chromium fixtures
  through Playwright and serialized fixed native readers. The native transport
  fixture does not establish actual device parity.
- native/core-mcp/tests/test_browser_gateway.cpp: native gateway dispatch,
  strict capability gating, result validation, reference lifetime.


## Manual supported-interface evidence

Environment: Maxis Windows, real headless Chromium through the built shared SDK,
base c01b2038bdb663cb9d5c7add134d587635da17ca plus this scoped working change.
The owned ephemeral HTTP fixture bound 127.0.0.1:58613 and closed at completion.
The browser context closed at completion; no ongoing fixture service remains.

- OBS-1/2: main snapshot prioritized Confirm order and other buttons; ambiguous
  button scope refused rather than selecting an arbitrary root.
- OBS-3/4: catalogue extraction returned Green tea 12.50 and Black tea 9.00 with
  source selectors and relative detail links. JSON-LD Product/name and description
  retained publisher-claim provenance. Private form/editor/JSON-LD canaries absent.
  A single button mapping reported ambiguous with no arbitrary first match.
- OBS-5: complete/visible/1280x720 status reported unavailable network/error evidence.
- OBS-6: explicit task selector was false during delayed work, true after completion,
  and false after failing-task recovery. Document load alone was insufficient.

Inspected artifact: D:/BuildArtifacts/kelpie/capture-observations-20261104/manual-observations.json.
Invocation: node tmp/manual-observations.mjs (ignored one-off verification script).
Log: D:/Temp/capture-observations-20261104/manual.log.
This is portable SDK evidence, not Windows Kelpie app or physical mobile evidence.

## Generated script bridge dependency

## Exact verification commands

All portable commands ran from the owned worktree on Maxis with task TEMP/TMP
D:/Temp/capture-observations-20261104. Logs stay there; artifacts stay under
D:/BuildArtifacts/kelpie/capture-observations-20261104. No native application build ran.

- pnpm.cmd lint: pass, shared and CLI, zero lint errors.
- pnpm.cmd build: pass, shared TypeScript and CLI bundle/declarations.
- pnpm.cmd -r --workspace-concurrency=1 test --maxWorkers=2 --minWorkers=1:
  pass, shared 91 and CLI 626; 64 pre-existing CLI skips.
- pnpm.cmd --filter @unlikeotherai/kelpie-shared test:browser --maxWorkers=1 --minWorkers=1:
  pass, 24 real Chromium tests, including serialized native-reader fixtures.
- node scripts/native/generate-browser-contract.mjs D:/BuildArtifacts/kelpie/capture-observations-20261104/browser_contract.h:
  pass, authoritative reader/schema/ABI parity assets regenerated.
- cmake -S native -B D:/BuildArtifacts/kelpie/capture-observations-20261104/native
  -G "Visual Studio 17 2022" -A x64 -DKELPIE_BUILD_DESKTOP_ENGINES=OFF
  -DBUILD_TESTING=ON -DKELPIE_LOCAL_LLM=OFF -DKELPIE_AI_USE_HTTPLIB=OFF:
  pass. CMake is the VS BuildTools bundled binary.
- cmake --build D:/BuildArtifacts/kelpie/capture-observations-20261104/native
  --config Release --target test_browser_gateway test_native_extensions --parallel 2:
  pass. Initial test assertion quote escape failed compilation and was corrected.
- ctest --test-dir D:/BuildArtifacts/kelpie/capture-observations-20261104/native
  -C Release -R "test_browser_gateway|test_native_extensions" --output-on-failure:
  pass: 2/2 cases, 1.33 seconds.

The native generator serializes workflow-owned strict v1/target schemas and the
six-argument fixed resolver. C ABI validate_script validates schema shape/defaults;
the runner owns session authorization, unresolved-binding refusal, sensitive/capture
preflight, and scrubbing. Capture format uniqueness is projected to uniqueItems:
Zod refinements are not emitted into JSON Schema. Native generic array validation
honors uniqueItems. Generated parity fixtures compare native normalization/refusals
with actual Zod output. Host-only values and secretEnv are stripped from native
extension projection.
