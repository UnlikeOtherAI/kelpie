# Mobile automation and capture rollout

Source audit only, 4 November 2026, revision b6784ff723b27da4096fdd8d9227f2a00dfc9084.
Implementation waits for the integrated, manually verified macOS base. iOS/iPadOS and Android ship together.

## Current source and feasibility

| Surface | iOS/iPadOS | Android | Gap |
| --- | --- | --- | --- |
| Playback | Handlers/ScriptHandler.swift runs action dictionaries through Router | handlers/ScriptHandler.kt runs action maps through Router | Typed validation before side effects |
| Screenshot | ScreenshotHandler.swift uses WebView snapshot and scroll/stitch | ScreenshotHandler.kt uses bitmap capture and scroll/stitch | Frame rate/performance unmeasured |
| Artifacts | Explicit screenshot action saves device temporary file | Explicit screenshot action saves cache file | Sandbox paths are not remote downloads |
| GIF/video | No script encoding pipeline in audited handlers | Same | Recording mode hides chrome; it does not encode media |
| Input | click uses selector then first exact/partial text fallback; tap requires coordinates | Matching behavior | Semantic target ambiguity and current-center tap |
| Marker | Ephemeral page dot/ripple, scale/fade, removed at 1100 ms | Matching implementation | No wobble, C/S pointer curve or deterministic capture clock |
| Abort | Polled waits; normal returns clear state | Polled waits; coroutine delay can throw | Unconditional cleanup needed for cancellation |
| Suspension | Scene changes update connectivity/discovery, not playback abort | onPause updates connectivity, not playback abort | Explicit foreground/suspension terminal policy |
| Status | Active session in memory, terminal result only in response | Matching state model | Retained bounded terminal results and downloads |

Paths are under apps/ios/Kelpie and apps/android/app/src/main/java/com/kelpie/browser.
Audio recording implementations do not establish screen-video support.

Bounded viewport frames from existing native snapshot interfaces, shared overlay/timeline metadata and desktop encoding are a plausible simple capture path. This is not implemented or measured. The shared workflow contract must choose encoding ownership and expose formats, duration/frame/byte limits and explicit unsupported failures. Lightpanda stays optional on desktop; mobile engines remain native.

## Requirements and handoff

| ID | Both mobile platforms must provide | Shared interface dependency |
| --- | --- | --- |
| MOB-01 | Validate reusable typed scripts before recording/page mutation; reject invalid actions/timing | Versioned schema, compatibility and limits |
| MOB-02 | Resolve unique semantic button, scroll if allowed, reject disabled/hidden/obscured/ambiguous targets, re-resolve after layout changes, tap current center | Target schema, document revision, coordinates and bounded diagnostics |
| MOB-03 | Colored wobbling/fading circles and optional C/S eased pointer movement visible in exports | Seeded trajectory, easing/timestamps, color and coordinate transforms |
| MOB-04 | Usable GIF, video and ordered step screenshots with deterministic timing/final frame and bounded memory | Capture options, codec/container support, frame manifest, encoding owner |
| MOB-05 | Authenticated remote artifact retrieval; never return only a phone filesystem path | Opaque artifact ID, MIME/size/digest/dimensions/duration, download and expiry |
| MOB-06 | Abort, timeout, request cancellation, renderer loss, tab closure and suspension finalize truthful partial output; second run works | Session ID, pinned tab, cancellation, terminal reason and retained partial manifest |
| MOB-07 | Always restore chrome, orientation, viewport and transient overlays | Cleanup lifecycle and restoration/finalization order |
| MOB-08 | Prioritized scoped value-free snapshots, excluding password/form values by default | Generated shared reader, budget and truncation semantics |
| MOB-09 | Extraction metadata/provenance and compact readiness without unbounded DOM/screenshots | Source, scope, tab/document, observed time and freshness |
| MOB-10 | Explicit sessions prevent concurrent runs and conflicting mutations | Ownership, conflict errors, allowed status/download calls, terminal idempotency |
| MOB-11 | No persistent content scripts, silent cloud model or second identity authority | Existing native/generated shared gateway integration |

These are semantics, not final field names. Workflow owner supplies the canonical script/export contract; observations owner supplies portable readers. Mobile consumes those contracts rather than creating another schema. Shared Apple files under macOS belong to the macOS owner.

## Durable evals and real usage

One deterministic fixture must include duplicate named buttons, obscuring modal, moving target, disabled controls, delayed hydration, navigation, large page, nested scope and secret form values. Run authenticated native HTTP/MCP and CLI remote downloads on both platforms.

| Eval | Required assertion |
| --- | --- |
| MOB-E01 | Valid script works; invalid script changes neither page nor recording state |
| MOB-E02 | Unique semantic target increments exactly once at current center; duplicate/obscured/disabled targets fail truthfully |
| MOB-E03 | Rotation, scroll, layout changes and screenshot/CSS scaling preserve input/marker alignment on phone/tablet |
| MOB-E04 | Decode outputs; verify MIME, size, digest, ordered frames, duration, colors/wobble/fade and C/S trajectories |
| MOB-E05 | Retrieve bytes on controlling computer; foreign/expired IDs fail; documented retention survives disconnect |
| MOB-E06 | Abort wait, typing, movement, capture/export; inspect decodable partial output, restored controls and successful next run |
| MOB-E07 | Background/foreground, closed tab and lost renderer produce documented outcome without stuck busy state |
| MOB-E08 | Snapshot priority/scope/budget and value exclusion hold; provenance/readiness name pinned document |
| MOB-E09 | Concurrent sessions and stale targets fail; approved status/download calls work during recording |
| MOB-E10 | Equivalent contracts/export semantics on iPhone, iPad, Android phone and Android tablet |

Unit tests cover validation, terminal transitions and cleanup. Native integration tests cover input/capture; decoded artifact and timeline assertions remain durable regression tests. Manual usage enters the real browser, starts playback, uses Stop and inspects downloaded media. Before/After evidence covers only visibly changed recording states with matched viewport/theme on phone/tablet.

## Verification record

- Source inspection completed over SSH on dictator at the revision above.
- Native generation, lint, builds and automated tests: not run; no native source changes.
- Simulator/device inventory: not inspected; reuse compatible existing devices before creating any.
- iPhone/iPad and Android phone/tablet HTTP/MCP/UI usage: not run.
- Artifact decoding, timing, marker/trajectory capture and remote retrieval: not run.
- macOS-first gate and native build/resource slot: pending coordinator authorization.
- Android verification checkout/hardware: not assigned; availability unconfirmed.
- No apps, simulators, DeviceHub, servers or heavy jobs started.
- ChatterBox tools absent from exposed tool inventory; reports go to assigned coordinator.
