# Shared observations, extraction, and readiness

Base revision: b6784ff723b27da4096fdd8d9227f2a00dfc9084.
Implementation worktree: D:/Worktrees/kelpie/capture-observations-20261104 on Maxis.
Branch: codex/capture-observations-20261104.

## Requirement crosswalk

Historical worker aliases in early reports map to the canonical master IDs:
OBS-1 -> OBS-02/OBS-03; OBS-2 -> OBS-01/OBS-02; OBS-3 -> EXT-01/EXT-02/EXT-04;
OBS-4 -> EXT-03/EXT-04; OBS-5 -> RDY-01; OBS-6 -> RDY-02;
OBS-7 -> DOC-01/DIF-01/OWN-02. The requirements below use canonical IDs.

## Requirements and decisions

- OBS-02/OBS-03: Prioritized value-free snapshots. Actions, headings, landmarks, then prose;
  stable document order within each class. Explicit prioritize:false retains source order.
  Existing hard output bounds and traversal bound remain. Fresh references still belong
  to one snapshot/tab/gateway. No persistent content script.
- OBS-01/OBS-02: Scope is an optional CSS selector matching exactly one element. It narrows
  the current authorized document, never changes session/tab ownership. Missing or
  ambiguous scopes refuse. Hidden/editor text and referenced editable labels stay excluded.
- EXT-01/EXT-02/EXT-04: Deterministic structured extraction. Three mapping levels, repeated records,
  missing/ambiguous distinction, explicit selector/source/match provenance, global
  100-record and 512-nested-field budget. Only text/href/src/datetime sources.
  No arbitrary attribute, form-value, script evaluation, or model-generated code.
- EXT-03/EXT-04: Publisher metadata is explicitly untrusted publisher-claim evidence.
  Meta tags are allowlisted (canonical, description, author, publisher, published time,
  title). JSON-LD: application/ld+json only; eight scripts, 32 KiB/script,
  64 KiB total, at most 32 objects including @graph; allowlisted @type/name/headline,
  datePublished/dateModified/url, author/publisher names. No raw objects, script
  bodies, articleBody, arbitrary attributes, or arbitrary fields are returned.
- RDY-01: Compact status returns document load/visibility, viewport, visible dialog,
  busy-region, and aria-invalid counts. Network and runtime-error evidence are
  explicitly unavailable, never reported as zero. No background listeners.
- RDY-02: Readiness is an immediate predicate over interactive/complete document
  state and an optional exactly-one visible selector. It has no timeout parameter
  and makes no claim about network idle, SPA completion, or task success.
  Workflows owns bounded repeated waits.
- DOC-01/DIF-01/OWN-02: One authoritative strict v1 schema and fixed portable reader per operation;
  native generation serializes the same functions used by Playwright.
  Native fixedReader capability gates observations; no unsupported native locators
  or screenshots are silently emulated.

## Verification checklist for checkpoint e52240e7

These results apply to the pushed checkpoint, not the untested bounded-work follow-up below.

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

- OBS-01/OBS-02/OBS-03: main snapshot prioritized Confirm order and other buttons; ambiguous
  button scope refused rather than selecting an arbitrary root.
- EXT-01/EXT-02/EXT-03/EXT-04: catalogue extraction returned Green tea 12.50 and Black tea 9.00 with
  source selectors and relative detail links. JSON-LD Product/name and description
  retained publisher-claim provenance. Private form/editor/JSON-LD canaries absent.
  A single button mapping reported ambiguous with no arbitrary first match.
- RDY-01: complete/visible/1280x720 status reported unavailable network/error evidence.
- RDY-02: explicit task selector was false during delayed work, true after completion,
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


## Bounded-work follow-up (integration e877888a plus owned source)

Root cause: output caps were applied after full querySelectorAll/Array.from collection
and script.textContent copying, while accessible-name/style ancestor reads did not share
a work budget. Small output did not imply bounded reader work.

OBS-01/OBS-02/OBS-03, EXT-01/EXT-02/EXT-03/EXT-04, RDY-01/RDY-02:
one shared self-contained DOM helper now walks first-child/next-sibling links before
materialization, with at most 5,000 visited nodes per traversal, depth 40, and a shared
20,000-unit node/ancestor-style budget. Text uses CharacterData.substringData and a
shared 65,536-character copy budget; oversized JSON-LD text refuses before copying.
Metadata provenance no longer constructs sibling-index CSS paths. It reports a source
selector plus exact source index only after a complete source scan; partial evidence
sets provenanceComplete:false and omits the index. Scope uniqueness not provable within
the bounds refuses. Missing/unique results are never claimed from partial extraction
searches. Status counts are explicitly lower bounds when truncated.

RDY-02 visibility excludes ancestor opacity zero and hidden/collapsed styles and
intersects the viewport and ancestor overflow clips. Snapshot/extraction still permit
rendered offscreen content. Unknown visibility/uniqueness cannot prove ready.
Complex :scope expressions refuse instead of changing their meaning; simple root,
descendant, and direct-child forms have defined support.

DOC-01/DIF-01/OWN-02: a host-only composer embeds the exact same fixed helper/collector
source for Playwright and native assets. Callers supply JSON parameters, never source.
Browser-internal CSS matching/layout costs are outside JavaScript instrumentation;
the stated limits bound our traversal, copying, materialization, and ancestor work.

- [x] Required lint/build/full tests: shared 121 and CLI 632 pass, with 64 existing CLI skips.
- [x] Real Chromium: 15,000-element and 100-deep DOMs, truthful incomplete/truncated.
- [x] Real Chromium: oversized 1 MiB JSON-LD with forbidden collection/text getters,
  measured bounded substringData copying, and private canaries.
- [x] Real Chromium: ancestor opacity/collapse/overflow clipping and viewport predicate.
- [x] Real Chromium: partial metadata provenance and explicit :scope refusal.
- [x] Native generated Zod parity: nested extraction defaults, readiness defaults,
  bad scope types/unknown fields; native core gateway tests.
- [x] Manual supported SDK normal and bounded/failure flows pass; native app acceptance remains native owner.


### Follow-up verification outcomes

Environment: Maxis Windows, integration e877888a merged into the owned branch with
the scoped follow-up source. Slot MAXIS-PORTABLE-3. Initial host load 17%; before
native core build CPU 2%, free physical memory 22,853,312 KiB. TEMP/TMP and all logs
use D:/Temp/capture-observations-20261104; ignored native artifacts remain under
D:/BuildArtifacts/kelpie/capture-observations-20261104/native.

Exact commands and results:
- pnpm.cmd install --frozen-lockfile --ignore-scripts: pass (2.1s, PID24028).
- pnpm.cmd lint: pass; pnpm.cmd build: pass.
- pnpm.cmd -r --workspace-concurrency=1 test --maxWorkers=2 --minWorkers=1:
  pass, shared 121 and CLI 632; 64 existing CLI skips.
- pnpm.cmd --filter @unlikeotherai/kelpie-shared test:browser --maxWorkers=1 --minWorkers=1:
  pass, 27 real Chromium tests, 2.23s including the actual large/deep/oversized corpus.
- cmake --build D:/BuildArtifacts/kelpie/capture-observations-20261104/native
  --config Release --target test_browser_gateway test_native_extensions --parallel 2:
  pass; automatic regeneration consumed the fixed composed reader and updated schemas.
- ctest --test-dir D:/BuildArtifacts/kelpie/capture-observations-20261104/native
  -C Release -R "test_browser_gateway|test_native_extensions" --output-on-failure:
  pass 2/2, 1.78s. Existing MSVC NDEBUG/UNDEBUG test-option warning remains.
- node tmp/manual-observations.mjs: normal public catalogue/metadata/scoped snapshot,
  delayed completion and failing-task readiness paths pass with no private canary.
- node tmp/manual-bounded-observations.mjs: inspected incomplete late-target extraction
  and readiness on 15,000 elements, lower-bound status, ambiguous/unprovable scope
  refusal, partial publisher provenance without an exact index, clipped/transparent
  targets false and normal target true. Generic typed WebMCP discovery refused
  UNSUPPORTED before any page tool was accessed.

Logs use portable3-*.log in the task temp directory. Inspected manual JSON artifacts:
manual-observations.json and manual-bounded-observations.json in the task artifact
directory. Both browser instances and the owned ephemeral HTTP fixture closed.

The first browser attempt exposed a source-composition defect: the test bundler
rewrote imported helper identifiers inside serialized collectors. The fixed source
composer now supplies the one helper factory explicitly, so collector defaults cannot
resolve bundle-specific host imports. The full browser corpus passed afterward, and
required lint/build/full tests were rerun after that source correction.

Canonical WebMCP request schemas/read classification are now a typed seam only.
Generic Playwright and default native capabilities remain closed; actual managed/
native session-origin-generation grants, API probe and encoding are the next owners'
runtime dependency. Native JSON Schema shape projection does not replace shared
semantic origin/input validators; no native WebMCP support is claimed here.
