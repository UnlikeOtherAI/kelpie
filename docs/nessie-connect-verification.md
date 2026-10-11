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

Physical iPhone/iPad/Android devices, signed release installation, real UOA scope
reauthorization and ticket issuance from these native apps, actual gateway-driven
browser jobs, foreground pause/stop during a live remote job, live CEF driving, and
GGUF extraction were not exercised here. Background extraction is intentionally
not advertised: all three adapters require a visible foreground browser, and the
installed embedded model advertises text capability with delegated browsing false.

The dedicated verification trees retain build logs and the iOS result bundle; local
`native/.build-connect/ios-settings.png` and `android-settings-now.png` retain the
reviewed screenshots. Preserve needed artifacts before removing those worktrees.
