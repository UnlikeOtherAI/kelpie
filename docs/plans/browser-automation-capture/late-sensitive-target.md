# Late sensitivity at target dispatch

Actual Windows f188 reproduction found two privacy failures: focus changing
autocomplete to current-password allowed one input event and leaked earlier
raw/URI/form outputs with two retained artifacts; focus changing input type to
password blocked editing but still leaked earlier outputs and retained media.
Diagnostic exit zero was not a security pass. Platform replay remains required.

## Internal fixed contract

The existing six resolver arguments retain their meanings. An optional seventh
private argument is {refuseSensitive:boolean}; native expression options accept
the same strict policy object. Omitted policy retains legacy dispatch behavior.
This field is not a new public workflow option or caller authority.

The token latches observed password/current-password/new-password classification.
Every explicit success and failure result includes sensitive:boolean, including
stale/moved/uncertain failures. Capture callers pass refuseSensitive:true at
resolution, recheck and dispatch. Atomic editing classifies again after focus,
before setting value. Focus-side effects preserve mayHaveCompleted uncertainty.
No-capture callers still receive inferred sensitivity and register edit text.
A prior sensitive classification cannot be cleared by removing autocomplete.

Adapters must consume returned classification before requireOK, cancellation,
document/current-tab checks or other post-evaluation guards. They register the
edit literal and latch capture discard independently of error replacement.
Use a private result callback at the actual decoded-result boundary, including
late callbacks retired by existing renderer fences. Final redaction/disposal
must await that retirement; no automatic edit replay is permitted.
The callback changes private redaction/disposal state only, never grants authority.
Current-run playing/finalizing status must expose artifacts:[]; current-run download
must return not-ready until retirement, classification and final scrub/discard have
finished. Earlier safe terminal runs may remain downloadable during another run.
This prevents irreversible media disclosure before a later sensitivity decision.

A destroyed context that produces no result cannot reveal an unobservable
transient classification. For an attempted target inspection with missing or
uncertain classification, register the current edit literal before final redaction,
even WITHOUT capture. If capture exists, also latch capture discard. Preserve the
first concrete failure and actual input-completion uncertainty: a lost read-only
inspection need not claim input was dispatched.
This is scoped to the current edit and uncertain target inspection; do not
blanket-redact unrelated ordinary inputs or claim zero input.

Canonical current-owner active-run retrieval refusal is ARTIFACT_NOT_READY;
foreign run refusal is ARTIFACT_NOT_FOUND. Tests/capture/uncertain-target-privacy.mjs
is an independent raw-response oracle: it checks retained uncertainty, first error,
raw/URI/form omission and empty terminal media without asserting no input.
The oracle parameter expectedMayHaveCompleted defaults true for focus/dispatch
loss; read-only loss callers pass false rather than fabricating uncertain input.
Its active-publication oracle checks running/finalizing status and three retrieval
branches (owner, foreign and earlier safe completed run).

Independent source intake of iOS b779c6849d935ab12b3ec852c605c6cb00a68689 confirms
the metadata callback executes inside actual renderer evaluation before post-result
guards and retirement completion. Root-approved no-result conservative handling
was still absent in that checkpoint and reported to its owner; source alone
does not establish actual transport-race or platform privacy acceptance.
Focused command node --test --test-concurrency=1
tests/capture/uncertain-target-privacy.test.mjs tests/capture/privacy-refusal.test.mjs
passed5/5 on Maxis after adding capture/no-capture and actual-uncertainty vectors. The initial test incorrectly lowercased ordinary letters in
the synthetic encoded value; corrected fixture folds only percent-triplet hex,
matching the case-sensitive raw policy. No production matcher change.

## Durable tests and pending evidence

tests/capture/target-regressions.test.mjs covers focus autocomplete/type/removal,
failed result metadata, latched classification and no-capture compatibility.
tests/capture/target-sensitive-focus.mjs exercises actual Chromium DOM focus
handlers for autocomplete/type/removal/URL changes with and without capture.
Generated native schema parity includes valid policy and invalid type/extra key.
Maxis Chromium151.0.7922.34 actual fixed DOM run passed all eight cases:
capture autocomplete/type/removal/URL changes produced no input event/value;
no-capture autocomplete edited once and returned sensitive:true; failed checks
retained sensitivity and uncertainty. Hard JobObject1CPU/Normal/2GiB,5.409s,
free16GiB; browser closed. Report privacy-late-checks/browser.json under common
artifacts SHA-256 fb6288969f48c602c19565a8a4113edeaee1a5db66bce127a536acfe9ba39259.

Required portable commands passed sequentially under the same hard policy:
pnpm --workspace-concurrency=1 -r lint (26.230s), build (16.696s), and
test --maxWorkers=1 --minWorkers=1 (55.926s): shared143,CLI703passed/1skip.
Focused target16/16 passed. Whole portable job99.890s.
Native gateway compile and generated policy parity passed on Maxis:
cmake --build D:/BuildArtifacts/kelpie/capture-observations-20261104/native
--config Release --target test_browser_gateway -- /m:1, then the resulting
core-mcp/tests/Release/test_browser_gateway.exe printed Browser gateway contracts
passed. Existing VS17 noCEF/noLLM stub tree only; hardJob1CPU/Normal/2GiB,
free17768524KiB,60.526s,exit0. It covers legacy default, valid policy serialization
and invalid policy shape/type; no shipping app was built. Existing MSVC
DNDEBUG/UNDEBUG override warning remains, no compile errors.
Platform callback wiring, final relinks and actual security replay remain pending.
This checkpoint does not close SEC-01.
