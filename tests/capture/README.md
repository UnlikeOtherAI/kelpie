# Browser automation capture acceptance

This suite supplies a shared synthetic page and independent evidence checks.
It does not certify native functionality without a real browser run.

Run lightweight harness checks with:

```sh
node --test tests/capture/harness.test.mjs
```

Start the fixture only after obtaining the host's resource slot:

```sh
node tests/capture/fixture-server.mjs
```

It prints a loopback URL. For a physical device, set `CAPTURE_FIXTURE_HOST` to the
specific permitted LAN interface and `CAPTURE_FIXTURE_PORT` to the reserved port.
Use synthetic fixture content only; this server has no product authentication.
Do not expose it publicly. Stop it after the bounded test run.

Open that URL in the real Kelpie UI. Exercise the documented public CLI/MCP
workflow APIs. The fixture records event target, hit-tested target, CSS viewport
coordinates, visible bounds, DPR, scroll, viewport scale, monotonic timestamp,
document ID and `isTrusted`. Read `/events` after actions and retain the response
as evidence. Event storage is bounded to 10,000 records; any nonzero `dropped`
count invalidates a trajectory comparison. Start a fresh fixture server per run
to avoid mixing owners or prior documents.

Targets include unique/duplicate/hidden/disabled/covered/moving buttons, a scroll
target, replacement of the original object, navigation, delayed success/failure,
nested catalogue records and publisher metadata. Private form/editor values and
an unapproved JSON-LD field contain synthetic canaries. Snapshot/extraction
checks must exclude them. These canaries are deliberately visible in the fixture
source: do not confuse a source fixture with a sanitized browser observation.
Screenshot privacy is a separate documented product policy.

`assertions.mjs` validates current visible-center clicks, advertised event trust,
nonlinear eased trajectories and private-value exclusion. It compares normalized
public snapshot meaning while excluding only unstable document IDs; it does not
erase renderer differences to manufacture parity. Add renderer-specific
expectations where a deliberate capability difference exists.

The fixture records pointer events across the document, not only over buttons.
Synthetic macOS coordinate events and native trusted events must be labelled
according to their actual guarantees. When an implementation renders a purely
visual pointer without dispatching pointermove, trajectory evidence must come
from decoded frame pixels plus the shared numeric model, not fabricated events.

Use the matrix in
[acceptance.md](../../docs/plans/browser-automation-capture/acceptance.md).
Save reports/media/logs in an ignored artifacts directory, never source control.
Validate a report using:

```sh
node tests/capture/evidence.mjs /absolute/path/report.json
```

For native protocol ingestion and scoped differential comparison, see
[differential-evidence.md](../../docs/plans/browser-automation-capture/differential-evidence.md).
The native matrix separates all48 IDs across nine runtime cells, including
Linux GTK and OSR; ingestion never certifies acceptance.

Reports contain `version:1` and `records`. Each record identifies requirement,
host, platform, renderer, full exercised source SHA, reviewer, UTC observation
time, status, evidence kind and observed result. Passed records require source
paths, steps and artifacts with SHA-256. Real flows also require installed
version, binary SHA-256 and entry point. Manual-media records require what the
reviewer actually saw. Blocked records require a concrete blocker. The validator
checks evidence shape; it never treats a unit pass as a native pass.

GIF/MP4 acceptance requires full decode and actual playback/visual inspection.
Header signatures alone are insufficient. Inspect every step PNG and sample
early/middle/late animation frames, confirm overlay color/wobble/fade, compare
document markers and viewport, and check frame delays/timestamps, dimensions,
looping, duration and partial-state metadata. Verify authenticated chunk downloads
from another client/process against independent file hashes.


The current user-authorized rollout proceeds in parallel through separate Windows, macOS, iOS, Android and Linux owners. The earlier Windows-first gate is historical. Computer Use, VNC and desktop-input helpers remain OFF; record real supported machine-interface evidence separately from blocked native UI/Stop verification. Fixed-reader source regressions use Node 24: node --test --test-concurrency=1 tests/capture/target-regressions.test.mjs. The initial 7c597780 contract fails four of these checks; see the workflow review ledger. A source regression pass still requires the corresponding real-renderer flow.
