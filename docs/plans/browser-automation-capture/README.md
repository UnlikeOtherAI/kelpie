# Browser automation and walkthrough capture

This plan covers the full Lightpanda-inspired browser automation brief and the original walkthrough export request. The QA acceptance ledger records actual evidence by revision and platform. Historical independently reviewed source snapshot:5f4c4fcb, plus common privacy-oracle cbce8f97. The later coordinator snapshot and open gates are recorded in the 2026-11-05 supplement at the end of outstanding-gates.md.

The [a132 integration status supplement](current-integration-status-a132.md)
indexes the latest scoped platform receipts and remaining release gates.
The [0c9433b9 integrated acceptance audit](integrated-audit-0c943.md) retains earlier findings. The [783bc381 source and brief audit](final-source-audit-783bc381.md) records the later scoped source review.
The [integration branch](https://github.com/UnlikeOtherAI/kelpie/tree/codex/script-capture-integration-20261104)
is the moving source reference; every evidence receipt retains its exact older
binary/source identity. See outstanding-gates.md and reviewed-cells.md for current
closure decisions. Earlier bases/checkpoints remain historical.

| IDs | Scope | Dependencies |
| --- | --- | --- |
| CAP family | Script authoring; continuous bounded capture including overlays; playable GIF/video; step screenshots; remote artifacts; cancellation/partial output; colored wobbling fading taps; eased S/C visual pointer | REPLAY, SESSION |
| OBS family | Prioritized scoped snapshots, explicit budgets, deterministic extraction, metadata/provenance | Canonical gateway |
| EXT family | Typed extraction fields, bounds, structured outputs and discovery | OBS |
| DIA family | Navigation, network, dialog and error diagnostics with explicit unsupported states | OBS |
| READY family | Page status, bounded readiness, timeout and cancellation | OBS, DIA |
| SESSION family | Explicit ownership, scope, expiry, cancellation and safe recovery; uncertain mutations never retried | Gateway ownership |
| REPLAY / WFL family | Reusable typed workflows, declared inputs and secret references, assertions/readiness, structured outputs, one play-script runtime | READY, SESSION |
| BACKEND family | Restricted optional Lightpanda adapter exploration; opt-in, capability boundaries and conformance; no AGPL copying | OBS, SESSION, evals |
| WEBMCP family | Page tool discovery/invocation exploration with explicit origin/session permission; untrusted declarations, no automatic invocation | SESSION, DIA |

The finite changed-native-state screenshot inventory and later per-component
version/release actions are in [final UI and release actions](final-ui-release-actions.md).

## Phases

1. Audit existing gateway/play-script and agree portable target, capture, workflow and artifact contracts.
2. Implement observation, extraction, status/readiness and diagnostics in the canonical gateway.
3. Extend play-script with strict workflows and native capture across the five user-authorized per-platform workstreams in parallel. The earlier Windows-first gate remains historical evidence, not a current dependency.
4. Keep iOS/Android contracts aligned and implement Windows/Linux/macOS bindings; advertise only implemented, verified capabilities.
5. Exercise every capability through real supported HTTP, direct/generic MCP and CLI forwarding. Computer Use, VNC and arbitrary desktop-input helpers remain OFF. Root-authorized hosted XCUITest/Compose and scoped native accessibility instrumentation are permitted; Android phone Stop and Windows Session1 UIA Stop have actual subset evidence. Remaining native UI/runtime rows require their own results,not a new blanket user handoff. Durable cross-platform conformance evals supplement real-device evidence.
6. Evaluate optional backend and WebMCP boundaries without weakening native browser guarantees.
7. Audit every ID, docs, affected releases and installed published artifacts. Coordinator owns the integrated PR and release cycle.

## Invariants

The canonical gateway owns execution. Workflows reuse play-script. Strict v1 rejects arbitrary evaluation, ambiguous targets and unsupported steps before mutation. Semantic targets resolve to one visible hit-tested center and are rechecked after visual movement.

The pointer is visual, independent of the OS cursor. Capture continuously samples rendered output and composites the overlay timeline; timed step screenshots alone are not video recording. Bound FPS, resolution, duration and retained bytes. Ordinary abort/failure finalizes valid partial artifacts. Privacy refusal and output-redaction failure discard all run capture under an independent latch. Retrieve authenticated bounded chunks rather than device-local paths.

Secret references resolve only on the authorized host. Secret values stay out of progress, manifests and error messages. Page content and declared page tools remain untrusted. Unsupported capabilities fail explicitly.

See [workflows checklist](workflows.md). The common-contracts owner maintains the master acceptance checklist and per-platform evidence; platform owners supply exact exercised revisions and artifacts.

Read-only final component/signing/install and native attachment routes are mapped in [release-pr-readiness.md](release-pr-readiness.md). Actual newer Windows API/media intake is [windows-f188-intake.md](windows-f188-intake.md); it does not replace native UI gates.

The canonical IDs and evidence requirements are in [acceptance.md](acceptance.md). Local workflow authoring items use WLOCAL identifiers; historical family ranges above are scope categories, not a second acceptance ledger.
