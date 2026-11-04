# Observation implementation review

Reviewed source: `e52240e7fe127b4b43aac51fd4eb2db4e64dd574`.
Result: useful ABI/source checkpoint; bounded-work follow-up required.
No independent native app or browser execution occurred during this review.

## Source findings

The request schemas are strict and share defaults across canonical interfaces.
Extraction permits only text/href/src/datetime, supports three mapping levels,
caps records/nested fields/output characters and distinguishes missing,
ambiguous and incomplete results. Form controls, editor descendants and script
text are excluded from ordinary extraction. Publisher metadata is allowlisted
and marked untrusted publisher-claim evidence; JSON-LD objects are not copied
wholesale. Current document URL and source selectors are retained. Unavailable
document revision, network and runtime-error evidence are explicit.

Readiness is immediate, with no hidden polling, and requires document state plus
an optional unique selector. The native generator serializes the same fixed
reader functions used by Playwright. Native dispatch uses existing authorized
tab/gateway state; new observations are classified read-only. These source
properties do not prove native rendering or transport parity.

## Required follow-up

| Concern | Affected source | Required result / canonical IDs |
|---|---|---|
| Full candidate materialization precedes slicing | snapshot.ts visit; observations.ts extract/count/scopes | Bound traversal/copy before allocating all matches. A partial search must not claim uniqueness, missing or ready. OBS-02/03, EXT-01/02, RDY-01/02 |
| Recursive public text and ancestor/style work | snapshot.ts content; observations.ts publicText/readable | Count all visited nodes and bound ancestor/style work, including large empty/deep subtrees. OBS-01/03, EXT-01 |
| Metadata materialization | observations.ts publisher metadata and JSON-LD | Bound candidate iteration, sibling-path search and script text read before copying a huge string or collection. EXT-03/04 |
| Truncated provenance may appear exact | JSON-LD ancestor path construction | If a bound prevents a complete unique source path, refuse/omit it or explicitly mark provenance unavailable; do not imply exact attribution. EXT-04 |
| Visibility differs from semantic actions | status/readiness visible predicates | Decide/document/test opacity-zero, hidden ancestors, collapse and viewport semantics consistently. Do not imply task success from document readiness. RDY-01/02 |
| New canonical method ABI examples | generator parity cases | Add extraction nested/default/unknown-key and readiness default/refusal cases to generated native normalization checks. DOC-01, DIF-01 |

The owner acknowledged bounded-work follow-up and is authoring durable large/deep
DOM evals. A fixed number of returned values is not a bound on work already done
by querySelectorAll/Array.from. Tree traversal can cap JavaScript visits/copies;
arbitrary CSS selector evaluation remains browser-engine work unless the accepted
selector grammar is restricted. State that limitation honestly.

## Reported evidence and limits

The implementation owner reports Maxis lint/build, shared 91/CLI 626 tests, 24 real
Chromium portable/serialized-reader tests and two native-core tests passed.
Manual supported SDK fixture calls returned ordered catalogue records and
publisher provenance with private canaries absent; readiness changed on the
explicit delayed-task selector. Those reports are recorded in observations.md,
with exact commands and artifact locations. They are portable/SDK and native-core
evidence, not Windows Kelpie GUI or mobile acceptance.

The manual SDK run was recorded at base c01b2038 plus scoped working changes,
rather than an installed published binary. Acceptance of the final integrated
revision still requires a repeatable real native user flow.

## Canonical ID alignment

The master acceptance ledger is authoritative. Historical observation aliases map
as follows; the owner is updating its checklist to avoid false completion:

| Historical alias | Canonical IDs |
|---|---|
| OBS-1 priority/bounds | OBS-02, OBS-03 |
| OBS-2 scope/value exclusion | OBS-01, OBS-02 |
| OBS-3 extraction | EXT-01, EXT-02, EXT-04 |
| OBS-4 publisher metadata | EXT-03, EXT-04 |
| OBS-5 diagnostics | RDY-01 |
| OBS-6 immediate readiness | RDY-02 |
| OBS-7 shared ABI/schema | DOC-01, DIF-01, OWN-02 |
