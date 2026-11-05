# Final UI and release actions

Current review snapshot5f4c4fcb plus common cbce8f97. This is a finite readiness
map, not permission to bump versions, open a PR or publish before runtime gates.
Historical evidence stays attached to its actual source and binary.

## Changed native states and PR image inventory

Only requested script pointer/circle and recording/Stop states need images.
Unchanged pages/settings/navigation do not need screenshots. Capture the actual
base and final with matched fixture, viewport, theme and device. A genuinely new
strict overlay can say no prior equivalent in Before, but existing changed
recording chrome needs an actual base image; strict-v1 novelty alone is not proof
that the rendered UI had no predecessor.

| Runtime | Changed state | Actual evidence now | Missing final PR evidence |
|---|---|---|---|
| Windows CEF | Live pointer/circle and Stop | f188 attempt4 native WGC transparent canvas, DPR2 spatial/Stop; root viewed original PNG; receipt f89278a0... | Final privacy/G07 relink image; base-equivalence check for existing Stop chrome; native animation state where materially different. Do not composite transparent canvas onto an invented background. |
| Mac WK and CEF | Live pointer/circle and recording/Stop | Compiled adapters and hosted journeys; no whole-renderer acceptance inherited | Actual native app screenshots for each changed renderer state, matching base/final; distinguish exported movie frames. |
| iPhone and iPad WK | Live pointer/circle and Stop | Hosted native instrumentation authorized; per-journey failures remain | Passing final device-specific native image/Stop journey and matched base/final inventory. No new local handoff is automatically required. |
| Android phone and tablet | Live blue circle/pointer and Stop | Root viewed c71 native images: phone2c0fa76f535431dd57eda32196b1e7c867a88e22ae26a5136cf7d78de8558bb0; tabletcfb4fff928d521a2eb93548f7a9c981f14e540f0116aee76bb199d1dc4f6684e | Final mapped/pinch/privacy build images and passing Stop cases; phone Stop failed in that run. Prior blue pairing pixels are not the overlay oracle. |
| Linux GTK | Live pointer/circle and local Stop | Source/runtime owner preparing bounded native journey | Actual GTK native images and Stop outcome with base/final; OSR proof cannot substitute. |
| Linux OSR | No local UI | Separate offscreen protocol/media path | No local window/Stop screenshot claim. Review exported overlays as media evidence. |

Root can attach approved original native images using verified Maxis gh2.102
--attach and a Before/After Markdown table. No generated media commits or CUA
are needed. The current WGC After belongs to f188, not a later final binary.
See release-pr-readiness.md for the supported attachment route.

## Concrete later version sequence

On2026-11-05 npm.cmd view independently returned CLI0.1.22/shared0.1.10.
Recheck manifests/publication immediately before bumping; these next patches are
candidates only, not edits made by this audit.

| Component | Candidate next patch from observed manifest | Required mirrors / later action |
|---|---|---|
| Shared | 0.1.11 | packages/shared/package.json; regenerate native contracts from final built source, publish with CLI provenance route. |
| CLI/SDK | 0.1.23 | packages/cli/package.json; final lint/build/tests, publish via release.yml cli selection, install public package and test SDK/stdio/hidden/headless aliases. |
| macOS | 0.1.36 | Info.plist app version/build policy; final WK/CEF compile/runtime; existing ZIP release/signing decision, install latest /Applications/Kelpie.app and relaunch. |
| iOS | 0.1.22 | Project.swift MARKETING_VERSION/build; existing simulator ZIP release target and installed simulator verification. No new device IPA/App Store requirement is introduced. |
| Android | 0.1.20/code20 | build.gradle.kts; four existing signing secrets, verified APK/AAB, actual phone/tablet install and public workflows. |
| Windows | 0.1.16 | CMake project,kelpie.rc,device_info_windows.h,windows_runtime.cpp; Maxis package with sandbox/CEF assets, existing Azure signing on Minis, signature/timestamp/EKU and exact installed signed runtime. |
| Linux | 0.1.16 | KELPIE_LINUX_VERSION; authoritative DEB/RPM/AppImage routes and actual supported installed package/runtime verification. |

First finish privacy/G07 and each runtime's finite gates; then integrate all source,
bump affected manifests BEFORE final integrated checks and PR description/open.
Use one PR, required green checks, then coordinate the existing immutable date
release with exact component notes. Published npm versions cannot be overwritten.
After publication, install/exercise the exact published artifacts; private candidate
success is not installed-release verification.

## Package quality gate and current blockers

Registered lint workflow run41971414574 at8a2ecc invoked the same-ref reusable
Linux candidate route with linux_native_candidate=true. Root reports Ubuntu and
Fedora build/package/codec jobs green. This is quality verification only:
installed DEB/RPM smoke is not yet done and nothing was published.
Linux owner owns the callee installed-package extension; no workflow recipe copy.

Remaining groups: late sensitivity and lost-result disposal; final native G07
mapping/relink/pinch; bounded/deep observation/provenance variants; each runtime's
HTTP/direct/generic MCP/CLI and complete artifact downloads; native animation
and all-frame timeline/document checks; auth/revocation/uncertainty recovery;
changed-state final images; final integrated checks; signing/package install.
The exact requirement matrix remains acceptance.md/reviewed-cells.md; no whole
platform is promoted from a codec, source, packaging or spatial-only pass.
