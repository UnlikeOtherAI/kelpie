# Privacy and public protocol source readiness

Independent source-only review,5 November2026. Current common snapshot
6f10b31bb724db74042ae7a40841ce4762ffe089; Windows callback source also inspected
at461b60ff6c62a5ccf9bf406c089d5b1208411e9b,integrated by rootdf3197.
No app/build/desktop input or native runtime was started for this audit.
The raw-response oracle is tests/capture/privacy-refusal.mjs; source readiness
does not mean that a platform has executed and passed that oracle.

## Privacy first-error and discard findings

| Runtime/source | Confirmed source state | Remaining gate |
|---|---|---|
|Desktop461b60ff|Inferred text registration precedes refusal. Atomic privacy_discard latches before refusal and on redactor failure; sampler retires before store discard; manifests clear independently of final error.|Follow-upfe8ee2d3 preserves an earlier action error through redactor failure while keeping uncertainty. f188883f revokes run-owned entries before physical cleanup and retries identity-checked failures at natural checkpoints; revoked entries cannot be read. Replay raw HTTP/direct/generic responses,old artifact IDs and next-run recovery.|
|Macb0273844,client91ff4b84|Registration precedes refusal. discardCapture snapshots privacy issue before redaction; redaction error forces discard and only supplies an issue if none exists. Late Stop only supplies an issue if none exists.|Hosted WK and CEF runtime,raw prior outputs/status/no edit/empty artifacts and cleanup. No remaining source ordering/latch/first-error defect found in this reviewed path.|
|iOS104a5184309ea6a8f7293721307d098252c0d612|Registration precedes refusal. Independent discardMedia latch survives redaction failure. Terminal selection uses action before capture before late Stop.|Hosted iPhone/iPad raw privacy replay and media/store teardown. Source/helper/XCTest compilation is not runtime success.|
|Androidb29c6e59b930b02d901ee468a41d36d9a4ecd8ab|Registration precedes refusal. stop latches privacy/redactor discard; outputs prepare once before finish/UI restoration; finish preserves first concrete failure and uncertainty. Four strict aliases align. Source reviewed,not compiled/runtime accepted.|Actual phone/tablet raw oracle and immutable packaged revision replay.|

The prior desktop inferred-output leak was reproduced by the Windows owner
against source9333: refused=true,untouched=true,leaked=true. The report contains
only those safe booleans and run identity,not the secret/raw output:
D:/BuildArtifacts/kelpie/capture-windows-20261104/inferred-secret-old-9333/report.json.
The old capture-retention wording was ambiguous; the newly clarified discard
rule is not retroactively described as a proven old artifact-policy violation.

Desktop461 requires both capture and discard callbacks for media admission.
Windows wires its owner-bound discard service. Linux must consume that trusted
callback/store seam before capture is available; a static registry profile does
not override the missing callback refusal.

## What hosted protocol sources actually call

Historical Mac tests/macos/runtime-client.mjs at91ff4b84 downloads artifacts only through
HTTP get-script-artifact. runtime-cases.mjs has direct named and generic
play/status calls; those do not prove either MCP chunk path. publicCLI runs
actual script run/download and pinned status; cliMCP performs initialize,
tools/list,descriptor discovery and a generic native status call. It does not
play or download an artifact through CLI stdio MCP. Follow-up92195219 adds an explicit >262KiB noise PNG case through the shared three-protocol helper,including real direct and generic tool names and per-request abort propagation. That is prepared source,not an executed Mac artifact-protocol pass. Native execution outcomes remain separate from these source facts.

Historical Android75590fb2 ScriptPublicFixture.retrieve alternates4093-byte chunks through
HTTP,direct named MCP and generic kelpie_extension. This is an explicit generic
call when the artifact reaches its third chunk,but one alternating reconstruction
does not establish independently identical whole-artifact retrieval per protocol.
Small artifacts need not reach all protocols. The current loop checks offset,
nextOffset,total size and final digest; it does not bound no-progress/chunk count/
deadline or independently check every echoed identity/MIME/size/hash and exact
EOF position. Owner was sent these finite test gaps. The hosted shell invokes
AndroidX instrumentation and evidence export; it does not invoke public CLI.
Do not promote instrumentation/MCP coverage to CLI proof. Follow-upb29c6e59 now reconstructs whole files separately per protocol with identity/MIME/size/hash/progress/count/deadline/EOF guards,adds a >262KiB noise PNG case,and a real hosted CLI pairing/run/pinned-status/download bridge. Compilation and actual hosted execution remain required; prior source gaps are not still-open implementation findings after that revision.

Common artifact-protocol.mjs now supplies a bounded >262KiB positive PNG case,
three independent reconstructions and exact metadata/EOF/hash comparison.
Owners can adapt the same checks; malformed ranges and foreign/stale grants
remain separate negative cases. No generic download acceptance is inferred
from discovery/status or HTTP chunk success.

## Finite next corpus

- Windows: consume fe8/f188 source fixes,raw privacy/reflection/old-ID denial/recovery;
  large PNG HTTP+direct+generic reconstruction. Existing9333/UIA/export evidence
  remains historical evidence for its exact binary.
- Mac WK and CEF: hosted raw privacy plus existing capture/Stop/geometry cases;
  three-path chunks and explicit CLI flow outcomes. Preserve pairing/listener
  failures rather than skipping to another app instance.
- iPhone and iPad: authorized hosted fallback,rendezvous scheduling recovery,
  raw privacy,Stop,movies/geometry and protocol/CLI outcomes independently.
- Android phone and tablet: compile/package b29 privacy fix,corrected hosted runtime
  corpus,bounded full three-protocol artifact case and public CLI evidence.
- Linux OSR: consume discard callback,relink,privacy/three-path chunks/public
  CLI and sandbox proof. GTK native UI remains its own runtime cell.

All release/install/signing gates remain open until root's coordinated cycle.
