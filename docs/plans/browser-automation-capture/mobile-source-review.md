# Independent mobile workflow source review

Reviewer: common-contracts agent. Frozen source: iOS
7fa261efc909f8f99c1cc83301049fe8ffbd82be; Android
62f95a05014ba1bc8986b8bf65f2130e81b0215e (integrated in dc0648e284c46582708b2ea31431de85a9f9946a).
Read-only review in the isolated common worktree. No platform source edited,
app built, simulator operated or desktop input used by this reviewer.

Owner evidence is distinct: iOS reports generic simulator build-for-testing plus
SwiftLint; Android reports Kotlin/JVM173 tests, with JNI shipping link pending.
Neither establishes actual native workflow/capture parity.

## Concrete findings

| Finding | Source invariant / outcome | Owner acknowledgement |
|---|---|---|
| MOB-01, blocking RDY/EXT | Android BrowserGatewayBinding.scriptObservationSession sets selected targeting but declares only get-current-url, no get-tabs. Common gateway removes all tab/page methods under that combination. Canonical ready/extract and output readers therefore refuse despite fixedReader. | Android confirms; will use direct targeting only in the already pinned private session, preserving exact tab/WebView/authority checks, then run actual JNI-backed public ready/extract flow. |
| MOB-02, blocking VIS/CAP | Android ScriptActions.interact dispatches input before overlay.indicate and stamps the marker with current document. Navigation can therefore move the marker to a later document or omit it from movies. | Android confirms pre-input old-document held marker plus per-format encoder acknowledgement, FPS discipline and final exact-target recheck are required. |
| MOB-03, parity | Android rejects inputs:{} while iOS rejects only non-empty unbound declarations. | Android accepts allowing the empty map; unresolved references/non-empty declarations still refuse. |
| MOB-04, parity/security | Android sensitive-capture refusal is nested under edit&&sensitive; iOS refuses capture for any sensitive resolved target. | Android accepts aligning refusal while adding private text provenance only for edits. |

Owners will commit fixes after their frozen build. These findings remain open
until reviewed source and actual relevant supported-interface tests land.
No selector fallback or copied native reader can close MOB-01/02.

## Architecture and security observations

Both transports derive immutable owner references from existing authenticated
principal, grant/token hash and listener incarnation, never request-body owner or
session fields. iOS re-evaluates existing AccountPairingAuthorization and listener
identity; Android supplies asynchronous plus main-thread grant fences. No duplicate
UOA identity/profile authority was introduced in these reviewed files.

Both preflight through the generated strict workflow contract and reject supplied
native session IDs with SESSION_UNSUPPORTED. Both pin the selected tab/WebView and
recheck document/geometry before fixed input. iOS uses private-world fixed functions;
Android JNI delegates schemas, target functions, presentation and output scrubbing
to shared native code. No new caller-authored JavaScript surface was found.

iOS renderer deadlines retain original callback retirement/lease until it resolves
or the renderer terminates. Android holds existing gateway retirement during
finalization. Neither source retries uncertain input. Actual callback timeout,
abort, revocation, listener replacement and next-run recovery remain required.

Status metadata is constructed separately from outputs, with query success distinct
from terminal runSuccess/runError. Owner-scoped latest metadata and bounded terminal
stores do not confer authority. Artifact IDs resolve only to registered app-private
files; Android hashes in64KiB chunks and bounds downloads to1MiB. iOS media budgets,
partial flags and owner-bound store registration were reviewed. Actual full decode,
retention cleanup, credential rotation and cross-client chunk/hash tests remain open.

## Canonical requirement coverage

This is a source-review map of all48 master IDs, not an acceptance pass.
Each native phone/tablet cell still requires its own exact source/binary/artifact
hashes and HTTP/direct+generic MCP/CLI evidence. Unsupported required behavior
does not count as parity; native UI/Stop evidence is blocked by Computer Use OFF.

| Master IDs | iOS reviewed seam | Android reviewed seam | Remaining evidence |
|---|---|---|---|
| OBS-01,OBS-02,OBS-03 | canonical router/fixed observation assets | private observation session | Real bounded/scoped/privacy corpus; MOB-01 blocks Android readers. |
| EXT-01,EXT-02,EXT-03,EXT-04 | IOSWorkflowActions.read + shared extraction | ScriptActions.read + shared extraction | Nested records/JSON-LD/provenance limits on each renderer; MOB-01. |
| RDY-01,RDY-02 | predicate/read + deadline | ready/assertion + retirement | Delayed task, ambiguity, timeout, cancel and next run; MOB-01. |
| OWN-01,OWN-02 | IOSScriptGrant,IOSWorkflowTab | ScriptAuthority,ScriptHttpAuthority,ScriptRunStore | Native session refusal/zero-action; foreign/revoked/listener cases. Managed allocator stays B/L/T scope. |
| WFL-01,WFL-02,WFL-03,WFL-04,WFL-05 | IOSBoundWorkflow,IOSWorkflowRunner | ScriptPreflight,ScriptRuntime | Public reusable inputs/secrets, preflight, legacy recovery and strict terminal status. |
| TGT-01,TGT-02,TGT-03,TGT-04,TGT-05 | IOSWorkflowTab.target + shared resolver | ScriptActions.resolve + JNI | Real implicit/external label, clipping, replaced target, focus mutation and uncertainty. |
| PTR-01,PTR-02 | IOSWorkflowPresentation + shared model | ScriptOverlay + shared model | Decoded natural S/C path/easing and actual input center. |
| VIS-01,VIS-02 | pre-input sampler.prepare/presentation latch | post-input marker currently defective | Lowfps movies-only navigation all-frame proof; MOB-02/04. |
| CAP-01,CAP-02,CAP-03,CAP-04,CAP-05,CAP-06,CAP-07,CAP-08 | IOSFrameSampler,IOSWorkflowMedia,shared Apple codecs | ScriptCapture,GIF/video encoders | Continuous timing, declared FPS, budgets, resize, cancellation/partial, full media decode; MOB-02. |
| ART-01,ART-02,ART-03,ART-04 | shared ScriptArtifactStore | ScriptArtifacts,ScriptRunStore | Cross-client chunks/hashes, owner/revoke/expiry, cleanup and subsequent run. |
| SEC-01,SEC-02 | C ABI redactor adapter + grant/revalidation | JNI redactor + authority guards | Actual encoded/dynamic-key/Unicode canaries, UTF boundary and provenance; MOB-04. |
| DIF-01 | same fixture catalogue | same fixture catalogue | Side-by-side renderer reports, no normalization of deliberate differences. |
| LP-01,LP-02 | native unsupported | native unsupported | Restricted worker is backend scope; these refusals do not prove its positive corpus. |
| WEB-01,WEB-02 | default unavailable | default unavailable | Explicit native grant/probe/fence not claimed; managed backend evidence remains separate. |
| DOC-01 | ios.md,common API docs | android.md,common API docs | Align actual capability subset and final source revisions after fixes. |
| UI-01 | presentation/Stop source only | overlay/Stop source only | Actual native UI blocked by user hold. |
| REL-01,REL-02 | no release evidence | no release evidence | Coordinator release/sign/install cycle after all gates. |
