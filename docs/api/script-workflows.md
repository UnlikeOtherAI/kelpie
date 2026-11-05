# Typed workflows and walkthrough exports

Where the selected browser advertises script v1, HTTP `POST /v1/play-script`, CLI `script run`, and MCP `kelpie_play_script` accept the same strict workflow. Consult the platform action matrix below before recording; unsupported actions and encoders are refused before input. Unversioned legacy scripts keep their separate behavior.

```json
{
  "version": 1,
  "tabId": "chosen-tab",
  "actions": [
    {"action": "click", "target": {"role": "button", "name": "Submit", "exact": true}},
    {"action": "wait-ready", "state": "complete", "timeoutMs": 10000},
    {"action": "screenshot", "name": "submitted"}
  ],
  "capture": {"formats": ["gif", "video", "screenshots"], "fps": 15},
  "tapIndicator": {"color": "#3B82F6", "radius": 20, "wobble": true, "fade": true, "durationMs": 700},
  "pointer": {"enabled": true, "curve": "s", "durationMs": 350, "easing": "ease-in-out"}
}
```

Targets are exactly one of role/name/exact, label/exact, CSS selector or explicit viewport x/y. The target must be unique, visible, eligible and unobscured. Label text excludes input, textarea, select/options and contenteditable/textbox subtrees, so default form values and editor contents cannot become a control name. Implicit and external labels retain their public text. A partially clipped target uses the center of its visual-viewport/ancestor-overflow-clipped visible rectangle. Coordinates remain layout CSS client pixels; visual viewport offsets, size and scale are fenced in the target token, so pinch/pan changes refuse before input. The same element object, document, URL, viewport and geometry are rechecked after visual motion. A moved/replaced/obscured target refuses input. Semantic traversal is bounded; `TARGET_QUERY_LIMIT` requests a narrower target rather than silently choosing a match.

When enabled, pointer motion defaults to 350 ms; set pointer.durationMs to choose another duration, including zero for immediate positioning. The tap indicator uses 70% base opacity, multiplied by its animation fade. The pointer is presentation only and does not cause hover. Native platforms report actual input guarantees; synthetic coordinate events are never described as trusted input. A mutation with uncertain completion is never retried. Before the final click or input event, target changes refuse remaining input. An acknowledged final event may navigate or replace its target; a lost callback remains uncertain and is never retried. Sensitivity discovered by a handler remains latched for redaction and capture disposal; an unavailable privacy classification is treated conservatively.

Typed actions include navigation, click/tap, fill/type, press-key, scroll, timed wait, bounded wait-ready, assertions, screenshots, commentary, named output and bounded extraction. Version 1 rejects unknown actions, arbitrary JavaScript and continue-on-error.

| Strict action | Windows and Linux | macOS, iOS and Android |
| --- | --- | --- |
| `press-key` | Supported trusted key plans | Refused in full preflight with `UNSUPPORTED_SCRIPT_ACTION` |
| `fill` and `type` | Supported | Supported using the platform input guarantee |

Mobile platforms mirror the same strict subset. On iOS and Android, `get-capabilities` exposes `scriptWorkflow.supportedActions`, `captureFormats`, the input guarantee and native-session availability. Video is advertised when iOS AVAssetWriter accepts representative H.264 settings or Android finds an AVC encoder. Availability of other actions and encoders is runtime-specific; unsupported requests refuse before any action. Not every native capability response enumerates individual workflow actions.

Strict version 1 inserts text atomically unless `typingDelayMs` is supplied for fill/type. macOS WebKit, macOS Chromium and iOS implement paced edits with a requested 1–1000 ms interval between Unicode scalars. Fill clears once before appending; type appends. A paced edit permits at most 1000 scalars and 60 seconds of intervals. An empty paced type resolves its target but sends no focus, input or delay, while an empty fill clears once. Each continuation requires known sensitivity and the same document, target, viewport and focus. An acknowledged final scalar with unknown sensitivity can complete only without capture, with the full literal redacted; capture is discarded. A missing or malformed mutation acknowledgement remains uncertain and is not retried. Adapters without paced support refuse the field before any action. Legacy typing options are separate from version 1 capture.

The complete attempted literal remains private during the run and is registered for output redaction if sensitivity is detected or inspection is uncertain. Ordinary confirmed non-sensitive text remains available in named outputs; timing alone does not make it secret. Each continuation requires explicit known sensitivity and the same document, target, viewport and focus. Interruption stops without retry and reports possible completion after prior input.

Capture continuously samples rendered frames and composites the same markers/pointer used in the live presentation. Defaults are15 FPS, width1280, duration60000ms and retained bytes67108864; maxima are30 FPS, width1920, duration300000ms and bytes268435456. Encoder backpressure drops frames, preserves elapsed timing and reports counts. Resize stops recording with partial output. Abort, ordinary failure and resource limits finalize valid partial artifacts. Privacy refusals are an exception: when a sensitive DOM target is recognized during capture, all capture artifacts from that run are discarded, including earlier frames. Output-redaction failure also discards capture. The privacy-discard decision is latched independently of later error replacement; it cannot be undone by finalization, abort or a redaction error.

Each artifact manifest contains `id,mimeType,byteLength,sha256,partial,width,height`, optionally duration, frame count, dropped frames, action index and viewport/document provenance. Video MIME is `video/mp4`; GIF and step PNGs use `image/gif` and `image/png`.

## Native MCP discovery

Windows Chromium, iOS WebKit, Android Chromium, macOS WebKit/Chromium and
Linux Chromium register `kelpie_play_script`, `kelpie_abort_script`,
`kelpie_get_script_status`, and `kelpie_get_script_artifact` in the native catalogue.
Playback requires the native app renderer and presentation/Stop factory. A hidden
normal app is supported; this does not advertise pure headless-backend playback.
Their schemas come from the shared generated contract and work through direct tool
calls or `kelpie_extension` with the same names. Playback and abort are mutations;
status and artifact reads remain available to read-only sessions, subject to the
existing authenticated run-owner and browser-grant checks. Discovery still filters
out any endpoint the selected native router does not implement. iOS/WebKit and
Android/Chromium expose UI-required, non-headless profiles for all four tools. Windows retains its existing Chromium
profile; iOS Chromium/Gecko and Windows WebKit/Gecko refuse. Mac's compiled profiles
are windowed and UI-required. Linux uses an explicit trusted native runtime mode:
windowed/GTK requires UI; offscreen/OSR permits only its supported machine path
without local UI claims. The mode defaults to windowed, rejects unknown values
and cannot be supplied in HTTP/MCP bodies. Legacy C API catalogue queries retain
windowed projection. A profile never creates missing no-CEF routes. See the
[profile verification record](../plans/browser-automation-capture/runtime-profiles.md). Registry presence establishes a
compiled binding, not actual capture/Stop/media acceptance.

## Version 1 status

An owner-authorized `get-script-status` query succeeds with `success:true`,
`supportedVersions` (a bounded unique positive-integer list including1),
`playing` and `state`. States are `idle`, `running`, `finalizing`,
`completed`, `failed` and `aborted`. Running/finalizing require a runId and
playing:true; finalizing keeps Stop/status active until all work retires.
Terminal states require a runId, playing:false and runSuccess (true for completed,
false for failed/aborted). Terminal failures use a fixed safe `runError`, never
a top-level error: the query itself succeeded, allowing MCP callers to recover
partial artifact IDs. Status never returns outputs or secret literals.

Optional progress fields are actionIndex,totalActions,elapsedMs,totalDurationMs,
abortRequested. Optional metadata includes artifacts (at most1002),mayHaveCompleted,
inputGuarantee,targetGuarantee. The portable strict response schema is
`scriptStatusV1Schema`. Missing runId may return bounded latest terminal metadata
only for the same current owner; otherwise it returns safe idle. Another owner's
run is never revealed.

Legacy status retains its separate unmarked envelope. While legacy playback owns
the browser, strict v1 admission can refuse the missing marker. When legacy ends,
v1 support/status must recover automatically without clearing runtime state.

## Native session preflight

Without `sessionId`, a native workflow uses the current authenticated browser grant and pinned tab. A supplied ID must resolve to an existing owner-bound native session and tab grant. Native bindings without that resolver refuse with `SESSION_UNSUPPORTED` before target resolution, navigation, admission or input; they never ignore the ID or create a parallel session. This code is preserved through direct and generic MCP with a fixed safe message. Explicit completion uncertainty remains `mayHaveCompleted:true`; a timeout never proves a definite refusal.

## Artifact retrieval

`POST /v1/get-script-artifact` and MCP `kelpie_get_script_artifact` accept `{runId,artifactId,offset?,length?}`. Offset is a nonnegative integer. Chunk length defaults to262144 and is at most1048576 bytes. The authenticated run owner and current browser grant must match on every status/cancel/download request.

The response echoes `runId,artifactId` and contains base64 `data`, `offset,nextOffset,eof,mimeType,byteLength,sha256`. Verify offsets, decoded size and final SHA-256. No device filesystem path or arbitrary URL is an artifact locator. Status and abort accept an optional runId; runs belong to the authenticated owner.

## Reusable inputs and secrets

A workflow can declare `inputs:{name:{type:"string"|"number"|"boolean",required:true}}` and use `text:{input:"name"}` in fill/type. CLI/MCP host bindings validate declarations and compile values into the same play-script runtime.

A secret uses `text:{secret:"reference"}`. Trusted CLI argv supplies an explicit reference-to-environment-variable mapping. MCP uses only an operator-startup allowlist configured through `KELPIE_WORKFLOW_SECRET_REFS`; mapping and values are captured per launch and no model/HTTP setter exists. Model requests cannot name ENV variables. The host resolves authorized references before transmission and redacts echoed values from results. URI/form encodings match percent-triplet hex digits in either case while ordinary characters and raw secrets retain case-sensitive matching. Values are never argv arguments or MCP secret literals. Secret-bearing workflows cannot request capture or screenshot actions. Native direct callers must provide already bound literals or an explicitly supported native binding mechanism; unresolved references refuse safely.

## Structured extraction and recipes

An extraction step uses the canonical bounded page extraction schema and reader:

```json
{"action":"extract","name":"products","params":{"scope":"#products","fields":[{"name":"title","selector":"h2","source":"text","multiple":true}],"metadata":true,"maxChars":8000}}
```

The named output retains canonical field status, bounds, metadata authority and selector/source provenance. Form-control values, arbitrary attributes and caller JavaScript are unavailable. A duplicate output name is refused during workflow preflight.

See the [walkthrough recipe](../examples/workflows/submit-walkthrough.json) and [extraction recipe](../examples/workflows/extract-products.json); adapt tab IDs and page selectors explicitly before running.

Resolved secret steps carry `sensitive:true` as non-secret provenance on the wire. Native and host result handling redact actual marked values, including reflected URL/title/output strings. Password/current-password/new-password DOM targets are sensitive even if the caller omitted the marker. Once an edit target is recognized as sensitive, its text is registered for redaction before any capture refusal, so earlier named outputs are scrubbed too. Strict privacy refusal uses `SENSITIVE_CAPTURE_REFUSED`. A privacy refusal or output-redaction failure discards every capture artifact from the run; ordinary failures retain valid partials. The marker never grants access or changes authentication.

Downloads pin the exact authenticated socket and credential for all chunks, refuse redirects/re-pairing/alternate sockets, bound streamed responses and aggregate retained bytes, and compare every chunk with the original run/artifact identity and manifest. Failed or interrupted transfers delete only the exclusive temporary file this transfer created; existing files and symlinks are never replaced. A transport failure during playback has uncertain completion: inspect status before starting another run.
Strict version 1 playback first reads `get-script-status` on the pinned authenticated socket and requires `success: true` with an explicit `supportedVersions: [1]`. Older browsers must be updated: missing, invalid, or refused support returns `UNSUPPORTED_SCRIPT_VERSION` before any playback, with no legacy fallback. Unversioned scripts retain legacy behavior.


Authorized active-current artifact downloads return ARTIFACT_NOT_READY until the run's renderer work retires and its final privacy decision completes. Request shape/range validation precedes this phase fence. Foreign owners receive ARTIFACT_NOT_FOUND; earlier safe terminal runs retain their ordinary owner/expiry checks. The shared Apple store exposes an internal optional blockedRunID parameter for owner-checked platform adapters; its default preserves existing callers.

### Apple late sensitivity and active artifacts

Mac target callbacks consume sensitivity before document/deadline guards. An attempted target evaluation whose classification is missing registers the current edit literal for output scrubbing, including without capture; capture also latches media disposal for uncertain click/tap or edit inspection. Proven nonsensitive results require the fixed reader's explicit known classification; a later abort or document guard failure preserves ordinary partials rather than reclassifying an already known result as sensitive uncertainty. Sampling admission stops and freezes the capture end timestamp before waiting for existing renderer retirement. Retirement precedes final output redaction and capture retention. Privacy disposal survives replacement errors; the first concrete failure remains authoritative.

Authorized current-run downloads validate their body before returning `ARTIFACT_NOT_READY`; foreign requests return `ARTIFACT_NOT_FOUND`. Running/finalizing status exposes no artifacts. Earlier safe terminal runs remain readable. The hosted Mac corpus includes focus-to-password/autocomplete, document change, delayed callback and post-input classification cases. These are acceptance cases, not a claim of completed native execution.
