# Shared workflow contract review

Reviewed source: `7c597780e226fc69d82d70ba867d5cafbd7f5dca`.
Result: blocking defects found; fixes assigned to workflows. Native acceptance
remains pending. The contract commit is an implementation checkpoint.

## Reproduced defects

On Maxis, Node 24.19 ran four independent pure-stub regressions against
`script-target.ts` exported from the exact reviewed Git object. All four failed
in 85 ms. No browser, renderer, native application or media encoder ran.

| Finding | Source at reviewed revision | Reproducer and actual result | Required invariant |
|---|---|---|---|
| TGT-03: clipped target center | script-target.ts:103 | Button rectangle x=-80,width=100 leaves 20px visible; resolver returns false because full-box center is outside viewport | Document the chosen policy. Agreed implementation direction is center of the viewport/ancestor-clipped visible rectangle, then hit-test; never choose an arbitrary exposed pixel |
| TGT-04/WFL-05: detached descendant receives later events | script-target.ts:138-153 | pointerdown replaces the child under the pointer while parent button stays; old child receives mousedown/up/click and resolver returns ok | Retain/check actual dispatch object identity and connectivity between events; stop with mayHaveCompleted=true |
| TGT-04: focus navigation is not fenced | script-target.ts:120-129 | Focus handler changes URL; resolver writes input value and reports ok | Recheck URL/document/viewport/geometry after focus before setter |
| TGT-04: focus can revoke editability | script-target.ts:117-129 | Focus handler makes input readonly; resolver still writes and reports ok | Recheck supported input type, readonly, disabled and current object identity after focus |

The durable regressions are in `tests/capture/target-regressions.test.mjs`.
For the initial audit, `KELPIE_TARGET_MODULE` named the exact Git-exported source
under `tmp/acceptance-review/script-target.ts`; no source from another worktree
was edited. Reproduce on the integrated checkout with:

```sh
node --test --test-concurrency=1 tests/capture/target-regressions.test.mjs
```

This requires Node 24 TypeScript syntax stripping. It must pass after the fix, then
the same cases must run against real DOM/native input. Stub results are proof of
the fixed reader's branch behavior, not of renderer fidelity.

## Additional blocking source findings

**Secret screenshot bypass (SEC-01/WFL-02/CAP-04).** `bindScriptInputs` refuses
a secret reference only if `script.capture` is present. A workflow that fills a
secret then executes a `screenshot` action passes this guard. Reject every explicit
capture path for secret-bearing workflows and retain secret provenance for
downstream progress/error/output redaction. An ordinary string after binding
cannot by itself tell the native runtime whether it was a secret. The source
branch establishes the bypass; it has not been exercised in a native app.

**Unbounded target traversal (WFL-01/CAP-06).** `querySelectorAll("*")` and
selector result materialization have no visit/candidate bounds, and each match
walks ancestors and reads accessible-name text. A large/deep page can monopolize
the renderer before a timeout is observed. Bound traversal before materialization,
ancestor depth, candidates and name text; return an explicit diagnostic when the
bound prevents a safe unique result. Slicing a completed wildcard query is not a
bound on the work already performed.

**Workflow extraction missing (WFL-03/EXT-01..04).** Named output currently supports
only URL/title/status. Reusable structured extraction remains unimplemented.
Reuse canonical `tab.extract` after the observation contract lands; avoid a second
schema/DOM extraction runtime.

Workflows acknowledged these findings and is implementing focused fixes and tests.
No finding is closed until its exact fixing revision and regression outcome are
recorded.

## Positive source findings and remaining evidence

Strict v1 discriminated action schemas reject unknown keys, arbitrary evaluation
and continue-on-error. Capture settings and chunk lengths have explicit bounds.
Input types are checked before binding; errors do not include supplied values.
Numeric C/S motion uses a deterministic cubic curve with smoothstep timing and a
shared wobble/fade function. These are source findings; native copies must be
compared with the shared model and decoded media.

Artifact IDs/schema alone do not prove transport owner authorization, revocation,
chunk reassembly, streaming hashing or bounded C ABI payloads. Session descriptions
alone do not establish isolated contexts. Final native handlers and real-interface
evidence must establish those guarantees.

The native maxBytes policy must distinguish retained artifact bytes from bounded
scratch/intermediate/encoder overhead. Do not claim a strict instantaneous disk
cap from a retained-output limit. Backpressure and encoder footer reserve need
actual media tests; preserve valid partial output instead of silently deleting the
entire MP4 on finalization overflow.
