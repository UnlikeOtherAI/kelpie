# Combined release and PR readiness map

Read-only audit,5 November2026. Source snapshot234c0d1ac511f1849a12e5448e81699cc0567e88,
plus checked common CLI2c4b0fb8. No version bump,tag,PR,upload,dispatch,
installation or publication was performed. New platform runs remain owned by
their workers; this map is not a release approval.

## Versions and affected components

Primary main was independently queried as
195eb90fa5df47291a75e8d165c72fc2f825e3c9. GitHub connector read the default-branch
manifests; public npm latest metadata was queried separately.

| Component | Owned version location | Current manifest / publication observed | Release obligation |
|---|---|---|---|
|CLI + public SDK|packages/cli/package.json|0.1.22,also npm latest|Patch/version,provenance publish,install exact published package and exercise CLI/SDK. Private2c4 archive is not published.|
|Shared package|packages/shared/package.json|0.1.10,also npm latest|Independent patch/publish; native generated contracts rebuilt from final source.|
|macOS|apps/macos/Kelpie/Info.plist|0.1.35; release/2026-11-04.2 has matching Mac ZIP|Own app version/build,signing/distribution decision,WK/CEF runtime and installed release.|
|iOS|apps/ios/Project.swift MARKETING_VERSION|0.1.21; latest date release has simulator ZIP|Own version/build,declared distribution scope and installed simulator/device verification. Simulator ZIP is not App Store/device distribution.|
|Android|apps/android/app/build.gradle.kts|versionName0.1.19/versionCode19; latest date release APK/AAB filenames are date-labelled|Own versionName/versionCode,signed APK/AAB,phone/tablet installation and runtime proof. Filename alone does not establish embedded version/signing.|
|Windows|apps/windows/CMakeLists.txt,resources/kelpie.rc,src/device_info_windows.h,src/windows_runtime.cpp|0.1.15; latest date release has0.1.15 ZIP|Keep four values aligned,sandboxed package,Azure signing and exact signed installed runtime.|
|Linux|apps/linux/CMakeLists.txt KELPIE_LINUX_VERSION|0.1.15; published packages use2026.11.04.4 date label|Own native version,DEB/RPM/AppImage/runtime bundles and supported installed GTK/OSR verification.|

The observed latest published GitHub release was release/2026-11-04.4,
published2026-11-04T22:13:57Z. Draft releases also exist; draft ordering must not
be mistaken for latest published. The above version names are inventory,not
proposed bumps or proof that older artifacts satisfy this brief.

Sources: [primary manifests](https://github.com/UnlikeOtherAI/kelpie/tree/main),
[latest release API](https://api.github.com/repos/UnlikeOtherAI/kelpie/releases/latest),
[CLI npm metadata](https://registry.npmjs.org/@unlikeotherai%2fkelpie/latest),
[shared npm metadata](https://registry.npmjs.org/@unlikeotherai%2fkelpie-shared/latest).

## Existing workflow and signing routes

- release.yml runs on release published. A notes body beginning with the selected
  components header enables per-component markers. cli publishes BOTH shared and
  CLI packages,using NPM_TOKEN and npm provenance. android requires all four
  configured secrets: ANDROID_KEYSTORE_BASE64,ANDROID_KEYSTORE_PASSWORD,
  ANDROID_KEY_ALIAS,ANDROID_KEY_PASSWORD; it verifies APK and AAB signatures.
  linux calls reusable linux-native.yml. The attach job gathers those artifacts.
- release-windows.yml intentionally builds only an unsigned candidate, with
  contents:read. It cannot publish an unsigned Windows release. Build and sign
  on Maxis by default; Minis is the signing fallback. Verify the unsigned
  source commit and SHA-256 first, and preserve the original and prior outputs.
  On Maxis use the durable
  `$env:USERPROFILE\.config\unlikeotherai\windows-signing\sign.ps1` helper
  with `-InputPath`, a new `-OutputPath`, `-ExpectedSha256` and
  `-SourceCommit`; its local README records the procedure. Verify the exact
  publisher, profile EKU, timestamp, valid Authenticode status and SignTool
  trust, then test the exact signed installed package before upload. Do not
  transfer Azure tokens or caches.
- linux-native.yml supports PR,manual and reusable force_build/release_tag/
  artifact_prefix inputs. Shipping source graph is affected here; final Linux
  builds are justified. Verify package dependencies,codec/sandbox assets and
  actual DEB/RPM installs. No-CEF refusal remains separate from native success.
- macos.yml compiles affected Mac inputs; runtime_acceptance=true selects its
  isolated hosted WK/CEF journeys. ios.yml native_workflow_tests=true selects
  hosted iPhone/iPad journeys. These are acceptance/build routes,not automatic
  signed Apple distribution jobs. Mac signing and local installed-app handoff
  remain unanswered product/release prerequisites; no Keychain copy/storage.
- android.yml builds/lints and runs its hosted phone/tablet corpus. A new CI
  compile or codec pass does not erase earlier native test failures.

Only changed app graphs are rebuilt; this combined run affects all five native
apps through actual source/shared contracts. CI status names and successful
skips alone never authorize an unrelated app build.

## Native Before/After images without CUA or generated commits

The GitHub connector has PR body editing and attachment download,but no image
upload action. Actions artifact ZIP links are downloads,not inline image hosts.

A supported route already exists on Maxis: installed gh2.102.0 exposes
gh pr create/edit --attach (locally verified help,up to50 files). Minis gh2.95.0
does not. No install/upgrade is needed. Official GitHub CLI uploads attachments
to GitHub and rewrites matching local Markdown image references to uploaded
URLs,including references in a Before/After table. Files stay in ignored evidence,
not Git history. See [official attachment documentation](https://docs.github.com/en/github-cli/github-cli/attaching-files-with-github-cli).

After all acceptance gates,root can use a body file containing a two-column
Before/After table and matching --attach flags. Example shape only:

```text
gh pr create --base main --head codex/script-capture-integration-20261104
  --title <title> --body-file <owned-body.md>
  --attach <base-native.png> --attach <final-native.png>
gh pr view <number> --json body,headRefOid,statusCheckRollup
```

Use actual base/final source,matching theme/viewport/state. Enumerate only visibly
changed native recording/Stop/marker/pointer/commentary states and supported
devices/renderers. A genuinely new strict state may say no prior equivalent
in Before; do not invent a base image. Exported movie/PNG frames are media
evidence and cannot stand in for native-window UI screenshots. Linux OSR has no
local UI claim. Existing unchanged navigation/settings screens need no new pair.

Attachment upload can partially succeed while gh exits nonzero; inspect and
reconcile the existing PR/body before retrying. Do not blindly create a second
PR. Verify uploaded image URLs/rendering and every required table cell. No
attachment was uploaded during this audit. Root independently confirmed the same
Maxis gh2.102.0 attachment help and owns a separate coordinator review worktree
at D:/Worktrees/kelpie/capture-integration-review-20261105 (branch
codex/capture-integration-review-20261105,initial canonical rootc71aeabd).
Workers must not edit it. Final PR commands must explicitly use
--repo UnlikeOtherAI/kelpie and --head codex/script-capture-integration-20261104,
not infer the head from that review checkout. No PR exists from this audit.

## Finite final sequence,not executed

1. Integrate every worker history and first obtain the owners' actual runtime
   outcomes for G07/privacy/protocol/codec/UI. Keep failures and remaining gates;
   no version bump is authorized by this read-only audit.
2. Once those runtime prerequisites pass,bump only affected component manifests,
   with independent npm/shared versions and required native mirrors/build
   numbers. Integrate and push those bumps BEFORE the final fully integrated
   checks,final PR description or PR opening. Recheck npm primary versions and
   choose a fresh date tag; published npm versions cannot contain changed code.
3. Run final shared/CLI/native/platform checks on that complete versioned source;
   finish matching native changed-state images and the single PR description.
   Only after the complete brief audit and rendered flows pass,open the one PR
   with verified Maxis attachment route. Required green checks precede merge.
4. Prepare signed/provenanced platform packages from the reviewed merge SHA.
   Root may create a draft date release,upload verified manually produced
   Windows/Apple assets,then publish to trigger selected CLI/Android/Linux jobs.
   Required notes markers must be exact; cli covers shared too. Commands are
   gh release create --draft/--target/--notes-file,release upload,and release edit
   --draft=false,only at the later authorized release step.
5. Verify workflow outcomes,published hashes/signatures/npm provenance,then
   install and exercise the actual published artifacts on appropriate hosts.
   Replace /Applications/Kelpie.app and relaunch on the Mac after its release.
   Verify Windows direct /mcp,public alias stdio,tabs/navigation and cleanup;
   Linux GTK/OSR and supported packages;Android phone/tablet;declared iOS target.
6. Final delivery includes exact versions,source/hash/install/runtime evidence.
   Only then remove completed owned worktrees/branches after preserving ignored
   evidence and checking ownership. No current worker data is disposable.

Current blockers remain in outstanding-gates.md and each platform ledger.
This plan does not silently waive Mac signing/handoff,remaining device/UI/
geometry/native protocol cases or installed-release verification.
