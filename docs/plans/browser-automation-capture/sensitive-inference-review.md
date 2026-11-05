# Sensitive target refusal and prior output review

Source-only independent review,5 November2026, common contracts/acceptance owner.
Exact reviewed integration source:
`2e08956fa0f1a67bbf05b533efac5eb05b5ba0b7` (origin/codex/script-capture-integration-20261104).
No native source edits,app launch,build,desktop input or runtime reproduction
were performed by this reviewer.

## Confirmed source defect: inferred secret registered after refusal

SEC-01 remains open for this case. The contract in
docs/api/script-workflows.md states that password/current-password/new-password
DOM targets are sensitive even when the caller omits sensitive:true,and that
native result handling redacts actual sensitive values including reflected
title/URL/output strings.

Desktop desktop_script_actions.cpp resolves the target,then returns
SENSITIVE_CAPTURE_REFUSED when capture or a screenshot action exists. Only
after that branch does it append the fill/type literal to redactions.
desktop_script_handler.cpp retains earlier named outputs and runs
RedactScriptOutputs after a returned action failure. The missing inferred
literal therefore cannot be scrubbed from an earlier output.

Both Apple interact paths have the same ordering:
ScriptWorkflowActions.swift and IOSWorkflowActions.swift calculate sensitive,
throw for capture,then append edit text to secrets. Their runners catch the
failure and redact actions.outputs using actions.secrets before returning
outputs. The thrown branch skips registration.

Android ScriptActions.kt registers edit text with run.redactor before its
capture guard. That ordering covers this specific branch; it is not a claim
that every Android final-output path is accepted.

## Concrete regression expectation

Prepare a synthetic fixture whose title equals a private canary. Run version1:

1. output source:title name:before.
2. fill a unique password target with the same literal text,without the optional
   sensitive marker.
3. Request capture formats:[screenshots],or include a screenshot action.

Target resolution must infer sensitivity; input must be refused. The failed
response's earlier before output must redact the canary. Also exercise type,
current-password/new-password targets,and encoded URI/form title/output
reflections,including mixed/lower percent-triplet hex. Inspect raw failed
HTTP/direct/generic MCP responses rather than a host that already knows the
secret. Status must remain output-free. Verify no edit event/value mutation
and subsequent supported recovery.

The narrow fix is to register newly inferred edit text before any refusal
following successful sensitivity inference. No selector fallback,changed target
ABI or general relaxation is needed. Owners received these expectations.
Source ordering proves the missing provenance path; actual platform regression
execution remains required.

## Earlier capture retention: contract distinction

Desktop returns prior artifacts marked partial after this action failure.
Both Apple runners explicitly discard capture on SENSITIVE_CAPTURE_REFUSED.
The output defect is unambiguous under the documented string-redaction
contract; these different artifact policies are a separate issue.

The general capture paragraph says failure/abort/limits finalize valid partial
artifacts. The reusable-secret paragraph forbids capture for secret-bearing
workflows,while DOM inference happens only at runtime. The docs do not explicitly
say whether every earlier pre-input artifact must be discarded after late
sensitivity inference. This review does not invent an all-artifact purge rule
or claim ordinary partial retention is always unsafe. Root subsequently settled
that precise policy: privacy refusal and output-redaction failure discard all
run capture artifacts. A latched privacy-discard flag must survive later issue
replacement; ordinary failure/abort still retain valid partials. A reflected title can
already be visible in earlier captured pixels,so string redaction alone cannot
establish pixel secrecy if those artifacts are returned.

## Status

- Desktop: source defect confirmed; owner notified; fix/runtime replay pending.
- macOS WK/CEF: source defect confirmed; owner reports a draft ordering fix and hosted raw/URI/form regression for both renderers; immutable checked fix/runtime replay pending.
- iOS: source defect confirmed; owner notified; fix/runtime replay pending.
- Android: registration order covers this branch; no new runtime pass inferred.
- Earlier-artifact policy: clarified by root after this review,not retroactively
  classified as a proven violation of the earlier ambiguous wording. All
  privacy captures discard; later error replacement cannot clear that latch.
- Shared acceptance oracle tests/capture/privacy-refusal.mjs checks raw result/
  owner status,raw+URI/form reflection,no edit and empty artifact manifests.
  Its synthetic tests are harness evidence only,not native execution.
