# Windows 9333 evidence intake

This is evidence intake for manual review, not whole-platform acceptance.
The product source is `9333ff507ec91d06d86e338b1d2d9378daca2ac5`;
the archived private candidate DLL is 8,007,168 bytes, version0.1.15, SHA-256
`27a474291206310a64e17cce27f6f9c50836af55b997b275d5f31e0fc71bca8c`.
The intake independently rehashed that binary.

## Preserved reports and outcomes

Owner artifacts under
`D:/BuildArtifacts/kelpie/capture-windows-20261104` remain immutable.
The common reviewer copied approved reports/media into the separate ignored root
`D:/BuildArtifacts/kelpie/capture-observations-20261104/intake/windows-9333`.
The copy manifest retains original paths, byte counts and source/copy hashes.

- Native flow:29 passed checks,30 original downloaded artifacts.
- Observation corpus:10 passed checks. WEB-01 is default-off/API-probe refusal,
  not a positive native WebMCP authorization claim.
- Public browser-alias flow:4 checks,6 artifacts.
- Security flow:3 checks,3 artifacts.
- Separate ordered-actions and malformed-preflight reports remain available.
- Separate standard UIA Stop source
  `4ec1496e0ad5b4305c2575a72b41072f1e499665` invoked exactly the owned native
  Button once in Session1, observed aborted partial status, recovered and cleaned
  up the owned process/task. This is native accessibility evidence. It does not
  prove screenshots, foreground/modal states or arbitrary desktop input.
- The three UIA partial media files were transferred from existing authenticated
  same-host downloads by SCP, not cross-host API retrieval.

The original39 media files were copied with independently checked source/copy
hashes. Client decode reports retain full single-thread GIF/MP4/PNG decoding.
Newer geometry/UIA/resize artifacts are separate evidence sets; they are not
silently added to the original39. Earlier c852 missing-marker pixels and failed
alias attempts remain historical failures.

## Protocol and visual scope

The permanent Windows corpus uses actual direct and generic native MCP calls.
Direct play/status/artifact chunks and failed-run recovery have explicit calls.
Generic play/abort/status are exercised. Generic artifact chunk coverage must
not be inferred from direct chunks or public CLI stdio calls. CLI alias evidence
is classified as CLI even when it forwards HTTP.

The common reviewer inspected exported old-document frame0002 and destination
frame0004 for movie-only FPS1 navigation. The source frame has a red marker
centered on Next document; the destination has none. Root independently inspected
the same pair and C/S contact sheets, three samples each. These bounded exported
image reviews remain separate from machine all-frame pixel assertions and native
window/UI evidence.

## Reproducible intake

At harness revision `e0cbe05d`, run:

```text
node tests/capture/native-coverage.mjs <intake>/curated-evidence.json <intake>
```

The actual run produced22 curated records,432 runtime/requirement rows,
10 independently verified report files,zero unclassified records and
**zero accepted rows**. All rows remain unreviewed. Curated JSON SHA-256:
`02c447ccc2f5645e581b3c89e9f70720bab2308993fd6b4f6727d803c9594479`.
The raw coverage output was redirected by Windows PowerShell as UTF-16LE;
its byte-preserving SHA-256 is
`c0f862cc8c790dc497b21958cb3bad0cc71d78b2122928b197a2a87c4f01ba52`.
Raw identity/task JSON with UTF-16 BOM was preserved and decoded explicitly,
rather than rewritten. Reports/artifacts are ignored outputs, not committed
generated files. No app launch, browser build, CUA or desktop input was used
during intake.

## 5877 Session1 replay and remaining boundaries

On Maxis the exact unsigned 0.1.16 candidate at source
`5877e6fa438385cab6ae44de0343a748d2251053`, DLL SHA-256
`231683fbb5f6025caf71d0c32eaaedba1594c09711ea24ebf75fa34478a9c0b3`,
was exercised with test revision `d16a71d9384f3c6b900b1fe8ff3dcf21aaabfabb`.
The initial task failed before launch because the fresh worktree lacked built
shared output. The retry used a copy of 152 matching shared dist files from
`66a0f0bc`; shared sources and lockfile matched, and every dist file hash was
checked. Both attempts and task definitions remain in
`D:/BuildArtifacts/kelpie/capture-windows-20261104/uia-wgc-5877-resume*`.

The retry used one CPU, Normal priority, a 2 GiB Job limit and Session1. The
standard UIA InvokePattern on the exact owned Stop button passed abort, partial
artifact retrieval and next-run recovery. The native viewport measured DPR2.
The WGC helper failed after 17.5 seconds; no presentation marker image is
claimed. The separate Stop image was captured. Public CLI stop failed; the Job
ended and the exact owned PID and listener were subsequently absent. Therefore
supported graceful cleanup is not claimed. The matching task was unregistered.
The prior f188 successful WGC image remains evidence only for that older build.

The prior 5877 geometry/motion API report passed seven checks, while the legacy
pixel verifier failed its fade-disabled opacity assertion. Its single fixed
sample can include pointer or background, so this failure alone does not identify
a product opacity defect. Preserve it and measure actual pixels with the shared
G08 oracle before drawing a conclusion.

Windows exposes one immutable desktop HTTP control token per listener and no
native pairing dialog or second valid grant on that listener. Invalid bearer,
unknown-run and distinct-grant unit checks do not establish a foreign valid
grant in the same app. Two independently owned listeners can provide a separate
cross-listener test, without describing them as two grants on one listener.

A bounded single-thread decode of the 5877 C-curve MP4 subsequently measured
the verifier's first fixed sample at frame 12 as RGB (17,17,17), surrounded by
gray and white pixels. Frames 14 through 20 at that same point measured
approximately (79,193,255). The old test includes that achromatic pointer/edge
sample in its marker-opacity range: its fade-disabled failure is a pixel-oracle
false positive. This does not prove the full motion/fade timeline. The 39-frame
measurements and Job policy are retained under
`D:/BuildArtifacts/kelpie/capture-windows-resume-20261105/legacy-pixels*`.

A separate exact-5877 shared G08 replay on Maxis failed at public CLI launch,
before recording a browser identity or any fixture facts. Public stop also
failed. The Job ended; no candidate process or listener remained. Both failures
and the absence of timeline evidence are preserved under
`D:/BuildArtifacts/kelpie/capture-windows-resume-20261105/g08-5877*`.
The harness did not retain exit/signal details for that run; its subsequent
diagnostic change cannot retroactively determine the cause.

The next 5877 capture-free public launch and stop both succeeded under low load:
launch took 1.581 seconds, stop 4.312 seconds, and the pinned process exited.
The earlier failure remains unclassified; this pass does not identify its cause.
Then the shared G08 fixture completed both C and S workflows over Windows HTTP,
with trusted ordered event facts, verified artifact chunks and public cleanup.
The shared oracle at `775384d7` passed C and S in both GIF and MP4 after
independent frame decode and PTS verification; the capture reported 47 and 48
dropped frames respectively. Reports and immutable media are under
`D:/BuildArtifacts/kelpie/capture-windows-resume-20261105/g08-5877-2` and
`g08-oracle-5877.json`. This is exported-media evidence, not native overlay
or overall Windows acceptance.

A later 5877 Session1 diagnostic used the exact candidate with a pin that
checks process path, start time and one visible owned `Kelpie` top-level HWND
without traversing the CEF accessibility subtree. Stop inspection retains its
subtree and exact-button guards. Under one CPU and a 2 GiB Job, the new pin
took 175 ms, listener verification 70 ms and device-info 22 ms. Public stop
completed and process, listener, readiness, running alias and scheduled task
were absent. Receipt: `D:/BuildArtifacts/kelpie/capture-windows-resume-20261105/start-probe-5877/report.json`.
The earlier c9 failure was not recorded with sufficiently specific stages to
prove that its cause was the prior subtree traversal. This is a capture-free
startup result, not WGC or Stop-button evidence.

The subsequent exact 5877 Session1 WGC/Stop run passed with the narrowed pin.
The helper captured only its owned presentation HWND with cursor disabled,
default border and no secondary windows. The separate Stop window was captured,
the spatial marker validator passed at DPR2, and standard UIA Stop invocation
aborted the run, recovered partial artifacts and allowed a following run.
Public stop and process, listener, readiness, alias and task cleanup passed.
The WGC call took 1.378 seconds with unchanged 8-second helper and 10-second
parent bounds. Raw BGRA and PNG were independently hashed. The successful
wrapper discarded the helper's stage stderr, so no per-stage times can be
claimed; the earlier WGC failure remains unexplained.

Evidence root:
`D:/BuildArtifacts/kelpie/capture-windows-resume-20261105/wgc-5877-pin907`.
The report is 19,843 bytes, SHA-256
`c1adc24ca0ba8231ef2f5350841cd3f80ebe08feddd66e807c1a1e58e1f1f41d`.
The 9,703-byte presentation PNG SHA-256 is
`1a74b88fada0e8941811bbab5a1a4081f66efff3b02805accff13ff9c2b09e98`;
the 641-byte native Stop PNG SHA-256 is
`fa6854ba2b4e8e32254d69bc78f13e35cb872dd60f9fc256713c46f73784055b`.
This is a bounded native spatial and Stop result, not a full animation or
signed-release result.

A source diff from 5877e6fa to root revision 65fe4866 found no changes under
`apps/windows`, `native`, `packages/shared/src` or `packages/cli`,
and no changes to root lockfile or Windows build scripts. This maps the tested
binary's inputs to that revision; it does not replace the final rebuild.

## Windows finite gate audit at 65fe4866

All runtime results below refer to the unsigned 5877e6fa candidate unless
otherwise stated. Its Windows production/build inputs are unchanged at
65fe4866, as recorded above. Evidence is bounded to the named flows.

- Native HTTP corpus: 36/36, including semantic trusted input, capture
  limits, preflight refusals, navigation, abort/recovery, partial artifacts,
  sensitivity, invalid bearer and unknown session/run cases. The original
  combined run's CLI alias case failed; a separate exact-candidate alias
  replay passed four cases after its readiness barrier. Preserve both.
- Observations/extraction/readiness: 10/10. Public alias CLI and stdio MCP:
  separate 4/4. Direct/generic MCP and HTTP artifact publication and chunk
  download checks ran, including the 906,882-byte PNG with four chunks on
  each protocol. Focus, post-input and realm privacy replays passed their
  recorded cases; their raw reports remain under `native-api-5877`.
- Geometry/motion API: 7/7 in `native-motion-5877`, including CSS zoom and
  clipped targets. Legacy fixed-pixel fade assertion is a documented false
  positive; the newer shared G08 oracle independently passed both curves in
  GIF and MP4 with 47/48 reported dropped frames. The longstanding
  `get-viewport` DPR value is 1; capture geometry uses page metrics and
  the Session1 scene independently measured DPR2.
- Native UI: exact owned Session1 presentation WGC centroid and radius agreed
  with the trusted click at DPR2; separate native Stop pixels, UIA Stop,
  partial export, recovery and supported cleanup passed. Export timeline and
  native spatial evidence use different fixtures and are not a simultaneous
  native-versus-export frame comparison. Root visual intake remains required.
- Ownership boundary: invalid bearer and unknown run are tested. This listener
  offers one immutable valid control token, so a second valid foreign grant on
  the same app is not claimed; see the boundary above.

Windows 0.1.16 is consistent in CMake, RC, device info and runtime at
65fe4866. The final integrated revision still requires the sandboxed CEF
rebuild/package and candidate replay, keyless signing of verified copies on
Maxis (Minis fallback), signature/timestamp/EKU and SignTool verification, immutable upload,
then exact published-package install and runtime checks. The current candidate
and native screenshots do not establish those release steps.

## Windows candidate and warmup diagnostics

The unsigned d849ee41 Windows production build used the pinned sandboxed CEF
wrapper and normal local-inference graph. Its DLL SHA-256 is
`7a0136fc35698e9353dac31b844d90726b36466fd128ce76afd9ddb834feaf8e`;
the pinned bootstrap EXE SHA-256 is
`54c8be31e003853947182c9461755bf4e7be5f91a2c64fcfb97ed5da1a32d755`.
These files are build evidence, not a signed release.

The earlier a916f4db candidate passed all 65 native CTest cases in one
interactive Windows Session 1. Its DLL SHA-256 was
`a15c00c4d9f32a8e1516ebcd5da2db6386a0097205c88cf491689e9b26844c29`.
The d849 rebuild includes a later shared target change, so that 65/65 result
does not establish a full test pass for d849.

On a916, the omitted-duration default C workflow completed six actions with
trusted page events, GIF and MP4, and 322 actual owned-window WGC frames.
Recorded native and export dimensions matched at 640x276. The final motion
was observed from the last start frame to the first endpoint frame in a
266.7 ms sampling bracket; this is not an exact duration measurement or a
dense easing pass. Public stop, process exit and private alias removal passed.
The dense oracle is intentionally not applied to the 350 ms profile.

A separate a916 dense C run returned successful media and 407 real WGC
frames, but lacked the required two exact stable pre-dispatch endpoint frames.
Its canonical native result remains insufficient. The first d849 four-click
warmup run reached the owned presentation and recorded 524 frames but the
public workflow returned `CAPTURE_DURATION_EXCEEDED` at the 33 s test cap.
Both failures and their raw reports remain preserved. A source audit found
pointer progress uses monotonic elapsed time; the separate fixed-step wait
loop accumulates callback/sleep overhead and is being corrected and verified.

The d849 full native verification, the final warmup C/S and same-run native/export
comparison, current parent-window and Stop imagery, signing, package and
installed-release checks remain open. The single-listener foreign-grant limit
recorded above is unchanged.

The later a44f6a50 candidate contains the monotonic wait correction. Its real
four-click warmup C workflow completed with four trusted events, two movie
exports, 409 actual WGC frames and 640x276 native/export dimensions; public
cleanup passed. The native dense oracle failed with
`G08_PATH_OR_EASING_MISMATCH`. Analysis of 29 in-path samples spanning
1,850 ms found timed RMS 6.26 px and maximum 14.56 px, while the nearest
geometric-curve RMS was 0.324 px. This is a retained failure, not a dense pass.

A separate direct-owned diagnostic build at eceb6d4c used the same four-click
C workflow and an opt-in bounded numeric trace. Its DLL SHA-256 was
`574c5251c7d38f576452a7e4cb937cae142592cb3e02ebaa916d64e8320a3af0`.
The workflow, four trusted events, public close and owned-process cleanup
passed. Across 223 completed sampler latch observations, the median was
83.635 ms, p90 106.709 ms and maximum 164.146 ms. Across 225 recorded
owner-thread queue observations, p99 was 7.676 ms and maximum 11.299 ms.
Neither stream truncated; non-latched queue waits below 10 ms were deliberately
not logged. The latch measurement includes mutex acquisition, and tracing
may perturb timing. It supports investigation of the sampler latch; it does
not prove actual paint time or replace the earlier same-run WGC evidence.
The sanitized report SHA-256 is
`7d4a4f861361244abbd09fd9046261a071d92f4f85a23bc5211b6459b2952799`.
The supported Windows G08 runner evaluates short default/fast profiles with
`tests/windows/wgc-fast-profile.mjs`, which maps actual WGC positions and
timestamps into fixture CSS coordinates before calling the shared
`tests/capture/g08-fast-profile.mjs` fitter. It writes the input points and
result to `fast-profile.json` after provenance verification. Dense runs still
use the independent dense oracle. For de318b47, a separate retained fit on the
original default C WGC samples passed: 350 ms RMS 6.00 CSS px versus 500 ms
RMS 90.47 px, five intermediate positions and a 383.34 ms sampled bracket.
The original `FAST_PROFILE_NOT_DENSE` receipt remains unchanged.
The retained de318 dense C and S WGC runs reached the marker-opacity gate
after the canonical path/easing gate, but both remained insufficient at
marker onset. An independent owned layered-window calibration used partial
red BGRA [0,0,178,178], partial green [0,89,0,89], opaque blue and clear
patches. The exact-owner WGC deep copy reported `straight` while all 3x3
interior raw samples retained their premultiplied input bytes at the observed
2x DPI. Red white-backed as straight became [201,77,77], matching the failed
observations; interpreted as premultiplied it became [255,77,77]. Green and
opaque/clear controls corroborated the distinction.

The Windows WGC numeric adapter therefore records the API alpha label and
uses premultiplied composition only for the exact owned layered overlay,
rejecting channels above alpha. The original raw and PNG evidence is unchanged;
the older timeline reports remain insufficient because they did not retain
every raw frame. Fresh runs are required for dense acceptance. The calibration
raw SHA-256 is
`d8e9fea696fdec1e7b3455eeb498f7cf0c8ba5eec9c141b0e3f085f01e82a7c4`,
and the retained PNG SHA-256 is
`7e17ebc50b0956fe91b354c2374ddd6ef7d4365f2bb4d3d1b0b32293eba75735`.

The calibrated de318 native WGC C and S runs subsequently passed the unchanged
dense path, easing and marker oracle. Their case SHA-256 values are
`feeca5123401c2c878559662aee11602f2481e1e003e532141ab093b4f9bf1c5`
and `e4e86ff3c977644b69a619139fec0ce9d8e4584aab779ae2a5d5acde0c89f318`.
The separate exported GIF/MP4 oracle remained insufficient; the native pass
does not establish export correspondence.

On Maxis Session 1, the ceec9e9d LLM-on sandbox build and focused owned-window
lifecycle and marker-policy checks passed. A real public CLI/HTTP workflow
then completed two trusted clicks and three actions with screenshots-only
capture in 3,918 ms. Its final actionIndex=2 PNG was downloaded with chunk
identity, length and SHA-256 checks. A fresh WGC session started only after the
HTTP response, against the same exact owned presentation HWND with cursor off
and the default border. Its raw frame contained 29,124 red pixels in the target
region (maximum alpha 135); owned UIA inspection found zero visible Stop
controls. Public stop and alias removal passed, and the owned PID, listener,
scheduled task and Job processes were absent.

The evidence directory is
`D:/BuildArtifacts/kelpie/capture-windows-resume-20261105/production/marker-transition-ceec-r1/evidence/`.
The product DLL SHA-256 is
`84ae1497ccf0b78929eaab2d53204995614b67c321649f6ed23e0f3abde00d40`;
test revision is `63bc86b4f5a00c2151d882320d8e969d9407b5a0`.
The 3,115-byte report SHA-256 is
`f76d06b9d32801064768ec50e1ea2d079e24b9b018640fd88310efe61cebe842`,
the 2,397-byte terminal PNG is
`aee50ba07cb8cf461f2f756873d2e93c4f478c639118d4fe8d39e0bb21a9261d`,
and the 10,020-byte post-response WGC PNG is
`94a1b3c9983e0f2c45a51b04d3d79124d26f18211d888969cc313c03158f3120`.
The 6,367,760-byte raw BGRA frame is
`29b5c2c093bd1b199d46fc6bd116a2330f95b63c7fbcec26bf5fe961f6661c23`.
This single transition does not establish expiry, no-capture behavior,
resize/revocation recovery, or full Windows acceptance. The earlier c89
fixture-ready HTTP 400 reports and their successful cleanups remain retained.


A separate no-capture ceec Session 1 workflow completed two trusted clicks and
three actions in 3,063.6 ms with zero artifacts. A fresh post-response WGC
capture of the exact owned presentation HWND found 29,147 red pixels in the
target region (maximum alpha 168), and UIA found no visible Stop control.
After a further 5.5 seconds the presentation was absent and Stop remained
absent while the listener and active tab still responded. Foreground ownership
at that later instant was not independently measured, so this establishes
absence after the requested lifetime, not the cause of the hide. Public
cleanup passed and the owned PID, listener, task and Job processes retired.
The report SHA-256 is
`3f7b26f9cc4a3b40f21d7254f63b7649ec0f375036e2365772c554bab273f850`;
the retained WGC PNG is
`975e88d1feea54301949964d6468af30844aad4c79d0d121fc1ff5e43fca9290`.

A separate omitted-duration S workflow on the same ceec binary passed the
native fast-profile fitter: 350 ms RMS 4.917 CSS px versus 500 ms RMS
87.276 px, four intermediate positions, a 350.0 ms observed bracket and
220 actual owned-HWND WGC frames. Eight actions and four trusted events passed;
GIF and MP4 artifacts were retained and probed. This is short-profile native
motion evidence, not dense export correspondence. Public cleanup and exact
owned-process retirement passed. The report SHA-256 is
`f4867d20784da43e3ec1aed837e95837ae909a20461699367b5aa32b4e306ae2`;
the fast-profile input and result SHA-256 is
`63facb3535652e8dcfc3bfbc345dbd9ac3d33f7aae8f7ac09f2baa24cf541651`.
Both runs used test revision `cc303fe271e6e1abda3c0b9c1d1f9600e0669907`.


The normal completion-receipt candidate 5fc5f353 was built on Maxis with
CEF and local LLM enabled. Its DLL SHA-256 is
`be132690a0c8fff25decbfc5a3175d41f50254ca0683ff71d08f49adf9d78f35`.
The focused capture-state and DevTools protocol tests passed. A separate
Session 1 real HTTP/MCP safety session passed five selected checks: both
navigation-marker formats, target replacement with recovery, MCP abort with
recovery, and sensitive-target capture refusal. Public close exited normally,
the readiness file was absent, and the owned PID, listener, task and Job
processes retired. The 622-byte diagnostic report SHA-256 is
`50c82ccc4d3a3503d553b34ef3f5c3ed5a3338202cc786f0c5c77748af7177fb`.
These checks are not a cadence or release pass.

The separate 736a0453 test-hook build forced a real navigation after screenshot
completion and before the pinned viewport read. Its fixed checkpoint events
were navigation, torn-frame drop and new-frame admission. An independently
decoded ROI from the actual generic old screenshot was red [255,0,0], while
the downloaded final action PNG ROI was blue [0,0,255]; a public recovery run
passed. Public close, readiness cleanup and exact owned-process retirement
also passed. The test-hook DLL SHA-256 is
`f5b584165e32d9db4156a2f68249551601a48d19468e4b1ec713e07efe77b247`;
it is not a normal candidate or release artifact. The 640-byte report
SHA-256 is
`c218711f48062a8e0f0c2a36632c7561bcf76ec101fe853fa19c6f378d98eb94`.
The 6,545-byte old control PNG SHA-256 is
`d07f014e9e127dad44d4fd3f0f102d84c71c1c3670ce07f6f601b36767cfe0ac`;
the 1,391-byte final PNG SHA-256 is
`3da13d45e7c01d5662e3a4738e1aefce0a49115c91f7d71eb6a302049eb1106b`.
Actual replacement and shutdown at this checkpoint and matched normal-build
cadence comparison remain open.

### Capture receipt A/B: no measured improvement

The normal, test-hook-OFF 455d1923 baseline and 5fc5f353 receipt candidate used the same LLM-ON CEF/sandbox graph, matching bootstrap and 234 inventoried runtime assets, the same runner (SHA-256 96cb0977f9be2e0c574170a1978ca1651d55c46cf63c86576e33a94564b1a047), C fixture, GIF/MP4 outputs, and 2-CPU/2-GiB Job. Both workflows and public shutdown passed; their exact owned processes, listeners, tasks and Jobs retired. Baseline DLL SHA-256 a6aeaa071cd47f6a59de37b9c2b510991c13fa81c628ec4826ad2cdd55a2e4fb; candidate 7ea338f5103cb9a2ada1ef343384351723fd63e3c4ca35b71737f6f99fb2ecb1. Reports are retained under production/receipt-ab-baseline-455-runtime-r3 and production/receipt-ab-candidate-5fc-r1, hashes 12f22c7ecb03f37b104a16f68f39dfa595a41b80d7a6d3268a92d0b7e610e930 and e625c8f24c64dcb05da90f0407146dad8ffda586970a1710d65a784e9d602b59.

Baseline versus candidate admitted 225 versus 218 frames and reported 307 drops each. Median combined screenshot/post-navigation/post-viewport time was 77.582 versus 77.289 ms; total pre/screenshot/post/encode was 84.771 versus 84.721 ms. Post-navigation moved from 47.787 to 0 ms while post-viewport moved from 1.171 to 48.013 ms. Total Job CPU was 12.14 versus 12.16 seconds. Independently hash-checked exports and ffprobe on Minis (SHA-256 afe05347caaabe479b3c4eae71992b6ec1e11c57266a1d665deb0f9fe9847208) found MP4 median/p90 frame gaps 108.60/154.0 versus 108.25/156.2 ms; GIF timing was consistent to its centisecond precision. All timestamps increased. The serial pair has load/order confounds, shows no speed improvement and does not justify integrating the receipt optimization. The runner validated four trusted fixture events but did not retain their scene coordinates/timestamps; canonical scene-dependent G08 density is therefore unclaimed. The 736a0453 hook navigation checkpoint and normal 5fc safety results remain separately scoped above.

### Four-core public C export and WGC clock failure

One Maxis Session 1 C-curve retest used the reconstructed normal 455d1923
graph, DLL SHA-256 `a6aeaa071cd47f6a59de37b9c2b510991c13fa81c628ec4826ad2cdd55a2e4fb`,
and d2473b73 test sources whose Windows and capture test trees match b6a18315.
The reconstructed runtime assets matched the recorded baseline inventory; the
auxiliary Vulkan ICD matched pinned CEF 152 but was not recorded at the earlier
baseline. The owned 4-CPU/4-GiB Job executed eight actions, observed four
trusted fixture events without drops, retained both exports by the public API,
and completed public stop/removal. The exact process, listener and task were
absent afterward and the Job had no active processes.

The separately compiled WGC helper (SHA-256
`d5ac6e7140f66cfd96455cfb9a6b14a3d673699af64b526ac8d3132adb129f1e`)
failed with `WGC_CLOCK_NONINCREASING` after retaining 252 actual frames through
19,516.59 ms. The rejected tick was not recorded, so equality and regression
cannot be distinguished. No native dense or native/export correspondence pass
is claimed. The earlier 303-frame WGC clock failure remains separate.

Both independently decoded exports contained 213 frames and reported 317
dropped frames. GIF SHA-256
`fc3273650c85b5e0954cd340817a57f7fffcf223a54db3e16c477e0dd1794f7b`
(253,957 bytes) had median/p90/max PTS gaps of 110/160/230 ms; MP4 SHA-256
`5c229008a8d1a2db7c6432c094b5d7072fe04d3dd11ad60eb4edbb88115247bf`
(86,261 bytes) had gaps of 110.55/156.95/227.25 ms. The unchanged per-case
oracle reported `INSUFFICIENT_EVIDENCE dense motion samples` for both formats.
Oracle input and output SHA-256 values are
`83a4bce7af99feb24341bdb29fd87e921bbeaf65ca6f211aba1aa30591f44046` and
`15660de7544607fde3a1b5f5fd04bb6a97e3ec259283ef2ee2b8f60060b8e366`.
The retained evidence is under
`D:/BuildArtifacts/kelpie/capture-windows-resume-20261105/production/g08-455-d247-fourcore-c-r1`.
This one C case is not S-curve, release, or a controlled CPU-affinity comparison.
