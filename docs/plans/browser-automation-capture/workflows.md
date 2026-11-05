# Workflow and capture acceptance

- [ ] WLOCAL-REPLAY-01 Strict versioned actions extend existing play-script.
- [ ] WLOCAL-REPLAY-02 Declared typed inputs and explicit secret references.
- [ ] WLOCAL-REPLAY-03 Typed assertions/readiness with bounded timeouts.
- [ ] WLOCAL-REPLAY-04 Structured named outputs with provenance.
- [ ] WLOCAL-REPLAY-05 Unsupported actions rejected; no implicit evaluation/model loop.
- [ ] WLOCAL-REPLAY-06 Abort/failure/uncertainty retain execution ownership.
- [ ] WLOCAL-CAP-01 HTTP, CLI and MCP accept the same script.
- [ ] WLOCAL-CAP-02 Semantic unique visible center; ambiguity, occlusion, movement and detachment refuse safely.
- [ ] WLOCAL-CAP-03 Configurable tap color, radius, wobble, fade and duration appear in media.
- [ ] WLOCAL-CAP-04 Optional eased S/C pointer between resolved targets.
- [ ] WLOCAL-CAP-05 Continuous bounded overlay-inclusive capture; playable GIF and video.
- [ ] WLOCAL-CAP-06 Step screenshots retrievable remotely.
- [ ] Verify no capture, an explicit screenshot without capture, screenshots-only,
  movies-only and combined formats separately on each native runtime. Screenshot
  paths must not add movie-only marker-expiry dwell; movie finalization must
  retain the intended clear frame. Source review at `0b2ff349` found
  unconditional final marker waits in the shared desktop and iOS runners;
  corrected runtime parity is pending. Mac gates the wait on movies, while
  Android gates marker admission on requested movie encoders. These are source
  observations, not per-platform timing passes.
- [ ] WLOCAL-CAP-07 Abort/time/byte bounds finalize partial outputs and release ownership.
- [ ] WLOCAL-CAP-08 Authenticated scoped bounded artifact retrieval and integrity checks.
- [ ] Windows on Maxis real CEF user flow, direct MCP, CLI MCP, decoded media and recovery paths. The earlier Windows-first sequencing gate is historical; the five authorized platform workstreams proceed in parallel, as described in [README.md](README.md).
- [ ] iOS/Android parity with real flows and media inspection.
- [ ] Windows/Linux native and MCP/CLI verification.
- [ ] Durable semantic safety, readiness and media evals.
- [ ] Feature/API/CLI docs and discovery match supported behavior.
- [ ] QA evidence names host, revision, flows, results and concrete limitations.

## Canonical capture acceptance

- [ ] CAP-01 Actual GIF, MP4 and step PNG exports.
- [ ] CAP-02 GIF timing, loop and dimensions.
- [ ] CAP-03 MP4 decoding and frame timestamps.
- [ ] CAP-04 Overlay-inclusive step PNGs.
- [ ] CAP-05 Document and viewport coherence.
- [ ] CAP-06 Hard resource bounds.
- [ ] CAP-07 Backpressure preserves elapsed timing.
- [ ] CAP-08 Cancellation/failure finalization and recovery.

[The master acceptance ledger](acceptance.md) owns canonical IDs and evidence. WFL-03 also requires bounded workflow extraction with named structured outputs and provenance; URL/title/status alone does not satisfy it.