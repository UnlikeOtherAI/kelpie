# Browser automation and walkthrough capture

This plan covers the full Lightpanda-inspired browser automation brief and the original walkthrough export request. The QA acceptance ledger records actual evidence by revision and platform.

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

## Phases

1. Audit existing gateway/play-script and agree portable target, capture, workflow and artifact contracts.
2. Implement observation, extraction, status/readiness and diagnostics in the canonical gateway.
3. Extend play-script with strict workflows and native capture. Windows on Maxis end-to-end is the first acceptance gate. Mac follows only after Windows completes.
4. Implement identical contract on iOS/Android together and Windows/Linux; advertise only implemented capabilities.
5. Exercise every capability through real UI, direct MCP and CLI forwarding. Durable cross-platform conformance evals supplement real-device evidence.
6. Evaluate optional backend and WebMCP boundaries without weakening native browser guarantees.
7. Audit every ID, docs, affected releases and installed published artifacts. Coordinator owns the integrated PR and release cycle.

## Invariants

The canonical gateway owns execution. Workflows reuse play-script. Strict v1 rejects arbitrary evaluation, ambiguous targets and unsupported steps before mutation. Semantic targets resolve to one visible hit-tested center and are rechecked after visual movement.

The pointer is visual, independent of the OS cursor. Capture continuously samples rendered output and composites the overlay timeline; timed step screenshots alone are not video recording. Bound FPS, resolution, duration and retained bytes. Abort/failure finalizes valid partial artifacts. Retrieve authenticated bounded chunks rather than device-local paths.

Secret references resolve only on the authorized host. Secret values stay out of progress, manifests and error messages. Page content and declared page tools remain untrusted. Unsupported capabilities fail explicitly.

See [workflows checklist](workflows.md). QA owns the master acceptance checklist.

The canonical IDs and evidence requirements are in [acceptance.md](acceptance.md). Local workflow authoring items use WLOCAL identifiers; historical family ranges above are scope categories, not a second acceptance ledger.
