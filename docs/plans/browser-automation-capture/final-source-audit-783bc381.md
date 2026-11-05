# Source and brief audit at 783bc381

Reviewed integration source: `783bc3816a3bcfe2c39333d1c300db2680fd7b43`.
This is a source, brief and public-claim audit of all 48 IDs in
[acceptance.md](acceptance.md), not a runtime acceptance or release approval.
Existing historical reports and failures remain at their original revisions.
The [implementation map](implementation-map.md) contains detailed source
anchors; the [open gates](outstanding-gates.md) track runtime and delivery.

## Concrete issues and decisions

- **Linux cross-document capture:** an acknowledged final click can retire the
  original realm before privacy classification. Actual a05 CDP evidence passed
  40 of 42 corpus cases but refused two positive next-document capture cases.
  Unknown must still discard capture. The test-only CEF context-release proof
  has not run; no source fix or platform pass follows from it.
- **macOS owned WebKit focus:** the owner reports a real final-source-path
  failure when the new document-focus guard meets an owned WebKit view without
  native first-responder preparation. The guard refused input and discarded
  capture. A native focus fix is in progress; CEF is unproven, not a confirmed
  duplicate defect.
- **Windows CLI launch lifecycle:** an actual readiness timeout cleared the
  running record while the detached candidate remained alive. The Windows
  owner is implementing and testing recovery; a crash between process spawn
  and pending-record persistence remains a reported limitation.
- **iOS observed geometry:** earlier iPhone evidence showed a marker about
  62 points from its reported target and separate viewport-change refusals.
  The cause and the later geometry fix remain unconfirmed. Treat these as
  actual failures requiring replay, not as a proven current-source defect.
- **Action scope:** standalone press-key is a documented native subset, not a
  required mobile implementation. Android and iOS both admit the same 13
  strict actions in source and refuse press-key; Windows/Linux admit supported
  trusted key plans. The original recording catalogue requires text entry.
  Required fill/type behavior and public capability parity still need their
  final native replays.
- **Optional workers:** the pinned Lightpanda 1.0.2 public proof covers the
  explicitly selected navigation and four reader methods only. Default
  admission remains empty; native input, geometry, capture and WebMCP do not
  follow. Managed WebMCP has a separate actual API/grant proof; native and
  Lightpanda support remain unavailable unless independently implemented.

## Requirement coverage and remaining proof

The table maps every canonical ID to the current source/contract position.
“Evidence open” means the invariant still needs the named final-source
runtime or release evidence; it is not a finding that implementation is absent.

| IDs | Source/brief position and remaining work |
| --- | --- |
| OBS-01, OBS-02, OBS-03 | Shared fixed readers and native adapters exist. Check value exclusion, scoped ordering and truthful bounds on each final renderer; Lightpanda proof is restricted to its pinned profile. |
| EXT-01, EXT-02, EXT-03, EXT-04 | Canonical bounded scalar/nested extraction and provenance exist. Verify missing/ambiguous results, metadata and document changes through final public transports. |
| RDY-01, RDY-02 | Explicit readiness predicates and unavailable diagnostics are implemented. Verify hidden, duplicate, timeout and navigation behavior on each runtime. |
| OWN-01, OWN-02 | Managed isolation and native owner/pin checks exist. Exact multi-owner, revoked grant, stale ref and late callback evidence is still runtime-specific. |
| WFL-01, WFL-02, WFL-03, WFL-04, WFL-05 | Strict schema, binding, ordered actions and uncertainty fencing exist. Final transport, legacy and recovery evidence remains open; see launch lifecycle issue above. |
| TGT-01, TGT-02, TGT-03, TGT-04, TGT-05 | Target resolution, clipping and pre-final-event fences exist. Final geometry, actual input trust and mobile focus handling require independent native proof. |
| PTR-01, PTR-02 | Shared C/S/easing model and native adapters exist; normal default is 350 ms and G08 deliberately requests 2400 ms. Final native/display/export trajectories and the fast profile remain open. |
| VIS-01, VIS-02 | Color, radius, wobble and fade models/compositors exist. Dense actual presentation and export evidence remains open; iOS observed geometry failure is retained. |
| CAP-01, CAP-02, CAP-03, CAP-04 | Native GIF/MP4/PNG paths exist with platform admission checks. Final real decoding, timings and every-step markers remain open. |
| CAP-05, CAP-06, CAP-07, CAP-08 | Generation/viewport fences, budgets, drop accounting and partial/recovery paths exist. Cross-document privacy and platform-specific actual results remain open. |
| ART-01, ART-02, ART-03, ART-04 | Opaque owned artifacts and bounded chunk downloads exist. Final public HTTP/MCP/CLI identity, integrity, revocation and failure evidence remains open. |
| SEC-01, SEC-02 | Fixed readers, privacy latches and output scrubbing exist. Unknown classification must remain fail-closed; per-platform secret/reflection and cross-document cases remain open. |
| DIF-01 | Cross-runtime fixtures and normalized comparisons exist. Final-source evidence for all nine runtime profiles has not been reviewed. |
| LP-01, LP-02 | Explicit opt-in and candidate allowlist are implemented; the pinned public reader subset has bounded proof. Other methods, binaries and release installs need separate evidence. |
| WEB-01, WEB-02 | Managed grants and API probing are implemented; unsupported native and Lightpanda profiles remain explicit. Preserve the distinction between managed positive proof and native refusal. |
| DOC-01 | Workflow matrix and help were corrected; final generated capability/schema/help and examples must be checked against the released binary. |
| UI-01 | Existing requested overlay/Stop behavior is the changed-state scope. Matched before/after evidence remains necessary only for visibly changed states. |
| REL-01, REL-02 | Final versions, integrated checks, one PR, publication and exact installed artifacts remain coordinator-owned open gates. |

The Linux deterministic GIF model is test-only and not wired into verifier
acceptance. Exact decoded model equality can support an encoded-visible tail
statement only after candidate provenance and real retained-marker controls
are established. It cannot prove physical zero alpha or relax MP4 criteria.
