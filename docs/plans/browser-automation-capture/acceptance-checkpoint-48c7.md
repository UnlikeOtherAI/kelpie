# Acceptance checkpoint at 48c7a7c8

This index records evidence available on integration revision
`48c7a7c87bc6e2de04b59b43bb44702acec78e73`. Each linked receipt identifies
the actual source, binary and environment exercised; this index does not
claim that those earlier candidates were tested at this revision. Running
jobs are not counted as results. Passes apply only to the named scopes.

| Scope | Verified evidence | Next closure |
| --- | --- | --- |
| Windows CEF | Owned Maxis window measurements passed the omitted-default 350 ms live C and S fits on separately identified native builds. Screenshot-only and no-capture marker transitions, Stop absence and cleanup have scoped receipts. In hosted [42147031897](windows-hosted-png-speed-421470.md), serial PNG-speed control and candidate produced 225/293 frames with 315/88 drops; the candidate GIF passed and MP4 was insufficient. Serial order and the changed post-fence timings confound attribution. | Verify final-source dense native/export correspondence and strict per-format results, Stop/recovery and installed release. The experiment is not native WGC or production acceptance. [Windows evidence](windows-evidence-intake.md) |
| Linux GTK and OSR | Hosted [42122562425](linux-installed-421225.md), source `455d1923`, passed the scoped installed Ubuntu DEB and Fedora RPM 58-case native corpus, media decode, strict marker and CLI checks. Separate offscreen terminal-clear and isolated Wayland receipts exist. The callback-only Fedora diagnostic build [42146862806](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42146862806) succeeded from separate diagnostic source `7eb99089`; its physical run was deferred at the resource gate and was not launched. | Establish final-source physical GNOME readiness, owned GTK/Stop and native/export timing, plus OSR dense coverage. Installed containers and earlier isolated Wayland do not prove the deferred GNOME run. Preserve the earlier readiness timeouts and diagnostic trace. [GNOME receipts](linux-gnome-c42.md), [Linux ledger](linux.md) |
| macOS WebKit | Hosted [42122266746](macos.md), source `455d1923`, passed the combined-format omitted-duration 350 ms case and dense C/S GIF checks; its video-only fast case and both dense MP4 baseline checks were insufficient. | Close video-only fast and strict MP4 evidence, final-source runtime, changed-state image pairs and installed release. |
| macOS CEF | Scoped renderer, Stop/recovery and navigation receipts and a separate synthetic stream control exist. The production fast and dense export cases remain insufficient or failed their stated checks. The separate common writer standalone [42149248875](macos.md), not a CEF-specific capture, encoded six synthetic faint-marker controls with 40/40 aligned frames each; all three marker regimes were insufficient under the fixed metric. | Obtain production native/export agreement and strict fast/dense results. Synthetic controls establish neither native retirement nor a safe pixel tolerance. |
| iPhone WebKit | Hosted simulator [42134918643](ios.md) passed nine of ten selected geometry methods, including the listed live marker, PNG and pinch checks. Its MCP capture returned `CAPTURE_VIEWPORT_CHANGED`. The later immersive [42144385113](ios.md) passed the inset unit but refused a same-document CSS-height change from 812 to 778; its post-run identity trace assertion failed. | Close paired capture, keyboard, dense timeline and final signed-device gates. |
| iPad WebKit | The same simulator run passed seven of ten selected methods, including paired MCP and decoded media. Default-mode pinch did not zoom and the clipped-refusal case recorded termination. In immersive [42144385113](ios.md), the inset unit passed and the centered marker and MCP response succeeded; media downloads were not retained and the post-run identity trace assertion failed. | Resolve those failures and close keyboard, dense timeline and final signed-device gates independently of iPhone. [iOS ledger](ios.md) |
| Android phone | API 35 emulator [42145950644](android.md), source `b39d1191`, passed the corrected real owned-WebView Enter control before/during/after playback and the delayed-navigation native Stop/recovery case. | The separate system-key case failed at `child.requestFocus()` before dispatch; no delegation outcome follows. Close that case, API 29, full corpus, native/export timing and signed-device checks. |
| Android tablet | The same API 35 run independently passed the owned-WebView Enter and Stop/recovery cases and reported clean teardown. The overall native job failed at the separate pre-dispatch system-focus case. | Resolve system-key focus and complete tablet-specific full corpus, timing and signed-device checks; phone results do not substitute. |
| Lightpanda | The pinned 1.0.2 explicitly selected public reader passed its scoped stdio corpus and documented refusals. One earlier paired comparison was ineligible after forced cleanup and did not start its Chromium arm. Later [42140073364](lightpanda-analysis.md) ran Chromium but failed 37 of 63 checks, so no comparative ratio was supported. | Close the public comparison without treating reader results as native input, layout, pixels, media or WebMCP. The separate managed-history draft's hosted lint attempts failed before build/test and are not a verified fix. [Reader intake](lightpanda-public-intake.md), [comparison and draft](lightpanda-analysis.md) |

The remaining [finite gates](outstanding-gates.md) include the full integrated
brief audit, matching changed-state screenshots, final-source builds and real
user flows, the single integrated PR and required checks, publication, and
verification of actual installed releases. No final PR or release is claimed.
Earlier failures and their original receipts remain part of the evidence.

## Current checkpoint at f8343bf1

The following updates the index above for integration source
`f8343bf1fcf776513fbb747d41e949da563e6eca`. Linked receipts retain their
own tested revisions; they are not claims that the integrated head has
passed every native or release gate. Hosted Fedora and macOS PNG experiments
were pending at this checkpoint and are not counted as results.

- **Pointer speed:** The shared default and native fallbacks specify 350 ms
  when enabled and omitted; explicit durations remain supported. Windows has
  scoped live C and S omitted-default measurements, and macOS WebKit has one
  combined-format 350 ms export pass. Those are separate observations, not
  final-source cross-platform live/export agreement. Linux, mobile and the
  remaining macOS and Windows formats still need their named timing evidence.
  See [Windows](windows-evidence-intake.md), [macOS](macos.md),
  [Android](android.md) and [iOS](ios.md).
- **Windows codec control:** The standalone production-writer experiment
  encoded identical synthetic clean source pixels but found differing decoded
  MP4 baseline and tail pixels; paired GIFs were identical. This establishes
  that the writer path can vary decoded pixels, not the cause of an earlier
  native result or a basis for relaxing its oracle. [Control receipt](windows-hosted-png-speed-421470.md)
- **iOS:** In [paired simulator run 42156136625](ios.md), iPhone passed the
  selected MCP capture and decoded four PNGs, a GIF and an MP4; iPad returned
  `CAPTURE_VIEWPORT_UNSTABLE` before a matched action sample. The iPhone result
  does not close iPad parity, keyboard, pinch or final-device gates.
- **Android:** API 35 phone and tablet passed the targeted Enter, system-key
  delegation and Stop/recovery cases in [42152217154](android.md), without a
  physical HID claim. The API 29 phone smoke [42156048209](android.md) failed
  at canonical `tab.ready` during fixture loading, before capture or input;
  its precise public refusal was not retained. API 29, tablet and full-corpus
  acceptance remain open.
- **Lightpanda and managed history:** The pinned opt-in reader's same-host
  pair [42153661939](lightpanda-analysis.md) passed 63 scoped checks per arm
  and four additional Lightpanda refusals, with bounded isolation and cleanup;
  it is not UI or native parity. The managed-history candidate passed hosted
  portable lint, build and test; public Chromium BFCache and click-created
  hash Back/Forward passed their scoped checks. A one-entry no-history control
  remained insufficient, and iframe, replacement and exact raw dispatch-count
  evidence remain open. [Comparison and history](lightpanda-analysis.md)

Final integrated-source platform flows, physical-device and desktop evidence,
changed-state screenshots, the single PR and required checks, publication,
signing, and verification of the actual installed releases remain open. The
separate platform ledgers above retain the detailed passes and failures.
