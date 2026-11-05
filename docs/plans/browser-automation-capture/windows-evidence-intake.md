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
Minis, signature/timestamp/EKU and SignTool verification, immutable upload,
then exact published-package install and runtime checks. The current candidate
and native screenshots do not establish those release steps.
