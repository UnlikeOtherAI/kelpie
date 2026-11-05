# Finite outstanding gates before PR and release

Snapshot: reviewed root49c3b914612648bf4b5fee340ec85b9d725b4d60 plus owner reports
received by the common reviewer. This is a closure list, not432 auto-approvals.
Every close records exact exercised source,target binary/version,protocol,
artifacts/hashes and actual outcome. Historical failing runs remain immutable.
Source mapping is in implementation-map.md.

| Gate | IDs | Runtime / owner | Concrete closure |
|---|---|---|---|
| G01 Registry/runtime projection | DOC-01,WFL-01,OWN-02 | Mac WK/CEF,Linux GTK/OSR; common+owners | Finish trusted runtime_mode windowed/offscreen seam and focused core tests; owners relink. Mac UI-only; Linux offscreen machine path only. Unknown mode and model/body capability forgery refuse; noCEF routes stay absent. Current compile deferred after resource gate incident; no pass claimed. |
| G02 Windows raw intake | OBS-01..03,EXT-01..04,RDY-01..02,WFL-01..05,TGT-01..05,VIS-01..02,CAP-01..08,ART-01..04,SEC-01..02,DIF-01 | Windows9333 /common+Windows | Ingest native29+security3+actions1+preflight1,OBS10,alias4 reports and39 artifacts. Independently rehash archived DLL27a474...,classify actual protocols and inspect all-frame marker/document reports. Owner reports corrected PNG/noPNG movies; do not replace c852 failures or infer UI pass. |
| G03 Android corrected replays | OBS-01..03,EXT-01..04,RDY-01..02,OWN-02,WFL-01..05,TGT-01..05,VIS-01..02,CAP-01..08,ART-01..04,SEC-01..02 | Android phone and tablet independently /mobile | Preserve first6-of11 and subsequent failing phone reports. Replay after fixture/preflight/startup/deadline/private-observer/PTS-document fixes; reach actual ready/extract flow. Run public HTTP,direct/generic MCP and CLI cases,all-frame lowfps marker/navigation,abort/recovery,revocation and secret vectors. Phone lowfps/Stop subset is not tablet/full-platform success. |
| G04 iOS actual simulator flow | OBS-01..03,EXT-01..04,RDY-01..02,OWN-02,WFL-01..05,TGT-01..05,PTR-01..02,VIS-01..02,CAP-01..08,ART-01..04,SEC-01..02,DIF-01,UI-01 | iPhone and iPad independently /acceptance | Complete user simulator handoff,then authorized standard XCUITest/public HTTP+MCP+CLI corpus. Compiled503 tests are not execution. Include lowfps movies-only marker/all-frame decode,legacy recovery,late callbacks and native Stop. |
| G05 Mac actual renderer flows | Same native OBS/EXT/RDY/WFL/TGT/PTR/VIS/CAP/ART/SEC families,DIF-01,UI-01 | macOS WK and CEF independently /workflows | Hosted Mac CI run41950256231 succeeded at28426edc (build evidence only). After compiled217/profile relink,launch exact app and test both renderer paths through supported transports. Verify owner-bound APIs,snapshot geometry,input,codec/capture budgets,all-frame markers,Stop and subsequent run. No source/codec-only inheritance. |
| G06 Linux mode/protocol coverage | Same native OBS/EXT/RDY/WFL/TGT/PTR/VIS/CAP/ART/SEC families,DIF-01 | Linux OSR and GTK independently /desktop_backend | Preserve actual90eb sandbox/HTTP6-action8-artifact/13-frame proof. After trusted mode assignment,verify direct/generic MCP discovery and public CLI,all-frame marker proof,deadline/abort/revocation and noCEF absence. GTK visible/native Stop requires its own authorized evidence; OSR must not claim local UI. |
| G07 Bounds and viewport geometry | OBS-03,EXT-02..04,RDY-02,TGT-02..04,SEC-01,DIF-01 | Every native renderer/device class | Apply large/deep/private/partial-provenance corpus and DPR/zoom/scroll/clipping races. Pinched visualViewport versus shared layout viewport eligibility needs actual iOS fixture; do not claim source-only geometry correctness. Retain missing/ambiguous/incomplete semantics. |
| G08 Pointer and pixel timelines | PTR-01..02,VIS-01..02,CAP-01..07,DIF-01 | Every native capture runtime | Inspect sampled early/middle/late decoded C/S path,ease,wobble/fade,color/radius and actual center/document. Held admission metadata alone is insufficient. Dwell remains separate from configured duration; screenshots-only/no capture avoid movie dwell. |
| G09 Owner and uncertain completion | OWN-02,WFL-05,ART-02,SEC-02,RDY-02 | Every native runtime +managed workers | Validate foreign/revoked/rotated/listener grants,provided native sessionId zero-action refusal,late callback fence,abort/status responsiveness and next-run recovery without manual state clearing. Keep known completed earlier steps distinct from uncertain failed step. |
| G10 Managed worker and LP | OWN-01,LP-01,LP-02,DIF-01 | Backend/LP scope,not native UI /desktop_backend+root | Managed Chromium production proof already exists. Run actual pinned Lightpanda1.0.2 Linux corpus under enforced bounded process/egress policy,owned fresh profile,no UOA/credential import,no visual capability inheritance; record task success/cost/unsupported differences. Preparation/Chromium proof is not LP proof. |
| G11 Optional WebMCP scope | WEB-01,WEB-02,SEC-02,DOC-01 | Managed positive path;native defaults off | Preserve actual Chromium151 private-world/grant/API/protocol evidence. Native support stays unavailable until exact trusted session/origin/document grant,API probe,encoding and completion-unknown fence land and run. A native refusal is not positive WebMCP evidence; final docs must state implemented scope. |
| G12 Status and action subset | WFL-01..04,RDY-02,DOC-01 | Every native runtime | Parse actual safe v1 status,failed/aborted partial artifact recovery,legacy-busy automatic admission recovery and no outputs/secrets in status. Reconcile declared supported action subsets against brief before closure; unsupported preflight cannot silently substitute for a required feature. |
| G13 Authorized native UI evidence | UI-01,VIS-01..02 | Applicable windowed/foreground apps | CUA,VNC and arbitrary OS-input helpers remain off. Root-authorized XCUITest/Compose and scoped native accessibility instrumentation are allowed under handoff/resource grants. Android phone Stop and Windows Session1 standard UIA Stop/partial/recovery/teardown (4ec) actual subsets are reported. Remaining simulator/app handoffs and changed-state evidence still need explicit outcomes. No offscreen local Stop claim. |
| G14 Integrated proof/docs | DOC-01,DIF-01,all48 ID audit | Root+common | Integrate every worker history; run required final shared/CLI/native/platform checks on final source; review precise9-runtime evidence and remaining limits. Preserve typed input-guarantee differences. No blanket acceptance from ingestion or codec build. |
| G15 Publish/install | REL-01,REL-02 | All affected components /root+platform owners | Bump each component's own manifest; one final integrated PR with required checks,then coordinated publication. Verify npm provenance/version/installed worker,Windows signed EXE/DLL/installer+timestamp and installed exact package,Apple signing/distribution/installation,Android signed APK/AAB phone/tablet install,and Linux DEB/RPM supported installs. Use immutable published hashes and fresh date tag; private candidates are not releases. |

The CI/PR screenshot requirement applies only to materially changed rendered
states,with matched base/final viewport/theme where applicable. Standard app
instrumentation authorization does not permit unrelated desktop input or turn
an exported frame into a local UI observation. Release/source gates are mandatory
even where a runtime-specific optional capability is correctly unavailable.

## Resource correction

A common -j1 native build incorrectly proceeded after printed preflight CPU85–87%
and free8,563,060KiB. Only its verified CMake24396/MSBuild49276 tree was stopped;
runtime-profiles-build.log is preserved. Registry compilation completed but the
full requested build/tests did not; no pass is claimed. The corrected ignored
Node launcher throws before child creation unless two fresh CPU samples are<65
and available memory is>=10GiB. Harmless CPU-denied and memory-denied tests both
proved no child marker,plus a harmless allowed-branch check. No host execution
policy was changed. Native compilation remains deferred until that real gate
permits it; Android's reserved runtime is not interrupted. Root authorized a fresh
local Minis test mirror at exact086d6070 for core/stub checks only. Existing VS18/
CMake4 toolchain was found; initial configure hit a quoted-policy-flag issue,
not a source failure. Corrected reruns were blocked before child creation by
fresh local load. No full native test pass is claimed yet.
