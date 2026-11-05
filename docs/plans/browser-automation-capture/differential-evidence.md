# Native differential evidence ingestion

DIF-01 uses the permanent fixture, assertions and v1 evidence records. The
normalizer is intentionally narrow: snapshot refs become ordered element refs;
only an exact declared fixture document-marker name becomes a generation marker.
Same-origin URLs normalize only in structured document URL slots, href/src field
values and known publisher URL/image/logo/sameAs metadata. Text values, external
URLs, element order/count, extra fields and unknown provenance stay exact.

Call assertDifferentialBundles with leftFixture/rightFixture {origin,documentId}.
Privacy canaries are checked before normalization. Missing/ambiguous/incomplete
fields, scope, matches/matchesLimited, metadata indices/provenanceComplete,
truncation, readiness and unavailable network/error evidence remain comparisons.
An unavailable diagnostic cannot become available/zero by normalization. Different
input guarantees require an explicit expected pair; the returned result retains
both guarantees. Geometry/layout differences require distinct matched fixture
conditions or separately reviewed expectations, not global erasure.

## Record identity and native cells

Existing version1 reports remain valid. New native records add:
- deviceClass: desktop,phone,tablet (worker is separate);
- runtimeMode: windowed or offscreen (stub/worker stay separate);
- protocol: http,mcp-direct,mcp-generic,cli.

These join requirement/platform/renderer/kind/revision/binary/version in evidence identity,
allowing phone/tablet and protocol outcomes to coexist. Renderer uses canonical
engine names (webkit/chromium); source/binary lineage identifies the actual
WebKit/CEF/Android binding.

native-coverage.mjs emits all48 requirements for nine distinct native runtime
cells: Windows CEF; Linux GTK; Linux CEF offscreen/OSR; macOS WebKit; macOS CEF;
iPhone;iPad;Android phone;Android tablet. A hidden normal Windows app remains
windowed mode, not an offscreen backend. Linux noCEF stub and external
Lightpanda/managed workers do not fill native cells. Missing identity fields
remain unclassified rather than guessed.

Protocol sets combine only within the exact exercised source revision,target
binary SHA-256 and target installed version. Source/unit evidence and manual UI
records are retained separately. The output always says acceptance:unreviewed:
complete protocol labels cannot certify semantic outcomes, required scope,
actual media decode, local UI/Stop or installed release. Operator review still
must reconcile every requirement and supported-interface outcome.

## Supported ingestion command

```sh
node tests/capture/native-coverage.mjs /absolute/report.json /absolute/artifact-root
node --test --test-concurrency=1 tests/capture/differential.test.mjs tests/capture/native-coverage.test.mjs tests/capture/harness.test.mjs
```

The command bounds report files to16MiB, validates record provenance, refuses
artifact paths outside the selected root and symlink components, limits each
artifact to256MiB, streams SHA-256 and compares independent bytes. A shared file
is hashed once. A binary hash remains an owner/reviewer claim unless that binary
is itself supplied as a hashed artifact; source lineage and remote installed
identity are still reviewed separately. Capture stdout as UTF-8 when saving a
report; Windows PowerShell5 redirection defaults to UTF-16.

Maxis Node24.19.0 lightweight tests passed14/14 in0.29s. Manual invocation of the
public command used synthetic unit evidence and independently hashed abc bytes:
432 rows,1 verified file,0 machine sets,all acceptance unreviewed. This is
ingestion-interface evidence, not an iOS or native runtime pass. Artifacts:
D:/BuildArtifacts/kelpie/capture-observations-20261104/dif-ingestion-fixture/.
No app,browser,desktop input or Computer Use ran for this check.
