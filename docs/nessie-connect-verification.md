# Native Nessie connection verification

Verification on 2026-10-11 used dedicated worktrees and profiles. No existing Kelpie
installation, account store, or running user's process was replaced or stopped.

| Host | Revision | Check | Result |
| --- | --- | --- | --- |
| Minis / MSVC 19.51 | shared core through `9922afc` | `kelpie_connect_test` CTest, Release | Passed |
| dictator / macOS arm64 | `6131775` | Strict SwiftLint, 266 files | Zero violations |
| dictator / macOS arm64 | `6131775` | Tuist generation and Debug Xcode build, including CEF bridge | Passed |
| dictator / iOS 27 arm64 simulator | `2eb3042` | Three `ConnectAuthorizationTests` | Passed |
| dictator / iOS 27 arm64 simulator | `2eb3042` | `ConnectControlsUITests`, More → Settings → Nessie | Passed; screenshot reviewed |
| umac / Android | `3ce1a11` | `ktlintCheck`, `testDebugUnitTest`, `assembleDebug` | Passed; 114 tests, zero failures |
| umac / Android emulator x86_64 | `3ce1a11` | Separate `.nessieverify` app, More → Settings → Nessie | Screenshot reviewed; Signed out displayed |
| dictator / merged Apple source | `b657376` | Strict SwiftLint, 274 files; macOS arm64 Debug build | Passed, zero lint violations |
| dictator / iOS 27 arm64 simulator | `b657376` | Six connection authorization tests and five page-context tests | Passed, 11 tests |
| umac / merged Android source | `b657376` plus test formatting | `ktlintCheck`, 122 JVM tests, debug app and instrumentation APK builds | Passed, zero failures |
| umac / Android emulator x86_64 | `39b841b` (equivalent formatted verification source) | Real `ConnectBrowser` → router → navigation handler → WebView callbacks | Passed, four instrumentation tests |
| dictator / iPhoneOS arm64 | `a723aad` | Native Release archives and development-device app compile/link | Passed; final signing blocked |

The navigation instrumentation proves a new document pin is returned after an owned
navigation, cancellation and person tab selection refuse completion, an unrelated
redirect cannot borrow its completion pin, and page-context reads enforce authority
before and after JavaScript evaluation. It uses an explicit local response latch,
not a timing delay, and an injected authority predicate; it does not prove production
UOA or WebSocket authentication. The production predicate remains the existing
immutable job/account/deadline/connection authority.

The Android APK compiled both arm64-v8a and x86_64 JNI libraries. The isolated debug
profile uses port 18420; ordinary builds retain 8420. The initial isolated launch
encountered an input-focus ANR while the host was busy and sharing the ordinary port.
After assigning its own listener and restarting only the verification app, the
Settings surface rendered. UIAutomator intermittently returned a null hierarchy on
that emulator, so the final Android UI evidence is a rendered screenshot rather
than an instrumentation test. The cause of the first startup timeout was not proven.

The Apple checks used arm64 simulator archives. An unrestricted generic simulator
build attempted x86_64 and could not link the available arm64 native archives;
the verified command explicitly selects `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`.
Unchanged core-AI/LLM archives were reused read-only after verifying their source
matched; the changed core-connect and supporting portable libraries were rebuilt
in the verification worktree. This is compile/link evidence, not local-model inference evidence.

Focused commands:

```sh
cmake --build native/.build-connect --config Release --target kelpie_connect_test --parallel 2
ctest --test-dir native/.build-connect -C Release -R kelpie_connect_test --output-on-failure
swiftlint lint --strict
xcodebuild -project Kelpie.xcodeproj -scheme Kelpie -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build -jobs 2 \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Kelpie.xcodeproj -scheme Kelpie -configuration Debug \
  -destination 'platform=iOS Simulator,id=3F45D6E6-EEC9-4F39-8FF0-D61E838CC930' \
  -derivedDataPath .build -jobs 2 -parallel-testing-enabled NO \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
  -only-testing:KelpieTests/ConnectAuthorizationTests \
  -only-testing:KelpieUITests/ConnectControlsUITests test
./gradlew :app:ktlintCheck :app:testDebugUnitTest :app:assembleDebug \
  -PkelpieVerificationProfile=true --max-workers=2
```

The focused native tests cover document pin invalidation, cancelled/replaced/deadline
authorization, immediate socket-failure/closing/oversize revocation before buffered
commands run, and Unicode boundaries for labels/evidence. Shared-core tests cover
deduplication, crash recovery, completion immutability, and terminal acknowledgement
sequencing. An existing OpenAI cancellation fixture failed once in an earlier broad
Android run and passed on its focused retry and the final complete suite.

Physical iPhone/iPad/Android browser operation, signed release installation, real UOA scope
reauthorization and ticket issuance from these native apps, actual gateway-driven
browser jobs, foreground pause/stop during a live remote job, live CEF driving, and
GGUF extraction were not exercised here. Background extraction is intentionally
not advertised: all three adapters require a visible foreground browser, and the
installed embedded model advertises text capability with delegated browsing false.

The dedicated verification trees retain build logs and the iOS result bundle; local
`native/.build-connect/ios-settings.png` and `android-settings-now.png` retain the
reviewed screenshots. Preserve needed artifacts before removing those worktrees.

Read-only device inventory on dictator found a paired, available iPhone 16 Pro Max
and iPad Air 13-inch (M3); both already contain `com.unlikeotherai.kelpie` 0.1.5 build 5.
Their containers, credentials and running apps were not inspected or changed. A
normal development upgrade of the merged 0.1.15 build 15 compiled and linked, and
automatic provisioning found the existing Apple Development certificate and team
`59S95D279D`. It failed signing `Kelpie.debug.dylib` with `errSecInternalComponent`:
private-key access in the SSH session must be resolved interactively before retrying.
No installation was attempted, so device developer-mode and install permissions remain unverified.

For macOS, the keychain advertises Apple Development and Mac App Store distribution
identities, but no Developer ID Application identity. A normally signed, notarized
distribution artifact is blocked by that missing identity. The installed Mac app was
observed as 0.1.29 with an ad-hoc signature; it was preserved, and no new ad-hoc
artifact was produced or installed by this lane.

Verification roots to preserve before cleanup:

- Mac: `/Volumes/External/Projects/kelpie/.worktrees/kelpie-connect-native-verify`.
  Logs include `swiftlint-navigation-merged.log`, `mac-navigation-merged.log`,
  `ios-navigation-merged.log`, `iphone-native-build.log`, and
  `iphone-device-merged-build.log`; simulator evidence is
  `apps/ios/.build/connect-navigation-merged.xcresult`.
- Ubuntu: `/home/umac/Projects/kelpie/.worktrees/kelpie-connect-native-verify/source`.
  Preserve `android-navigation-merged-build.log`, `android-navigation-merged-rebuild.log`,
  `android-navigation-merged-test.log`, JVM XML reports, and the isolated debug APKs.

After server release and signed device upgrade, the live travel scenario still needs
fresh UOA consent in the phone's Kelpie, the same UOA account in Nessie on the iPad,
and a foreground phone tab. Verify device discovery, exact-phone selection, pinned
snapshot/navigation, local extraction with a loaded GGUF model, visible pause/stop,
background refusal, and sign-out revocation. This is an explicit remaining live test,
not a claim based on simulator or injected-authority evidence.
