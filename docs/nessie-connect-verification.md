# Native Nessie connection verification

## Canonical browser-control migration

The account transport now carries the same browser-control v1 requests as native
HTTP, MCP and the CLI. These checks exercise the added account job/document guards
and the persistent gateway; they do not establish live production UOA dispatch.

| Host | Revision | Check | Result |
| --- | --- | --- | --- |
| FedoraMaxis / CEF-enabled Linux | `13ce64f8` | Full native/app build and CTest | Build passed; 34/34 tests |
| Maxis / Windows 0.1.13 candidate | `d3c7b150` | CI CEF build and existing native control acceptance journey | Passed MCP, nested inference/cancellation, canonical snapshot/append typing/stale refs/screenshot and late-callback ownership |
| dictator / macOS WebKit | `ea4cccd6` | Account job navigation, cancellation and effect-time document checks | 3/3 focused tests; SwiftLint zero violations across 280 files |
| dictator / iOS 26.5 simulator | `63922b34` | Real WebKit account goto/new document pin, shared-ref append typing, stale-document refusal and callback retirement | 1/1 focused test |
| umac / Android verification-profile emulator | `112bdd7e` | JVM tests and connected account navigation tests | Gradle passed, including canonical goto/new pin and competing human navigation |
| dictator / native Release | `e8be48a4` | iPhoneOS archives and macOS native build | Passed; navigation URL normalization remains C++17-compatible |

The iOS 27.0 disposable fixture stalled in WebKit's synchronous Screen Time XPC
path; only the 26.5 runtime pass is counted above. A disposable macOS CEF account
fixture reached native navigation but crashed during CEF GPU/network startup, so
that account-specific CEF journey remains unverified. Root-slash normalization and
conservative redirect refusal have unit coverage. Apple account connections do not
advertise unsupported trusted key presses.

Release publication, signature verification and physical-device installation are
separate checks. The tables below record the preceding account-connection work.

## Initial account connection

Initial verification on 2026-10-11 used dedicated worktrees and profiles. No existing Kelpie
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
| Minis / MSVC 19.51 | `f052d65` | Durable early-cancellation receipts, retention/clock rollback/capacity, Unicode terminal errors | Passed, CTest |
| dictator / macOS arm64 | `f052d65` | Native owned GGUF request cancellation and journal tests | Passed, two CTest executables |
| dictator / macOS arm64 | `45a0314` | Strict SwiftLint, 275 files | Passed, zero violations |
| dictator / macOS arm64 | `f052d65` | Debug build including CEF, seven authorization and four page-context tests | Passed, 11 tests |
| dictator / iOS 27 arm64 simulator | `f052d65` | Rebuilt native owned-request C API, eight authorization and five page-context tests | Passed, 13 tests |
| umac / Android | `0e607b1` plus formatter-only `45a0314` | Strict ktlint, 122 JVM tests, arm64/x86_64 debug and instrumentation APK builds | Passed, zero failures |
| umac / Android emulator x86_64 | `0e607b1` plus formatter-only `45a0314` | Actual WebView navigation, page guards, isolated inference cancellation, observed selectors | Passed, six tests |
| dictator / consolidated macOS source | `7af3d5a` | Strict SwiftLint; full Debug build including CEF; owned router admission, shared reader and page-context XCTest | Zero violations in 278 files; 12 tests passed |
| dictator / consolidated iOS arm64 simulator | `7af3d5a` | Fresh core-MCP/automation archives, shared value-free reader and job ownership XCTest | 15 tests passed |
| dictator / iOS simulator visible UI | `d7573f4` (same Apple behavior) | More → Settings → Nessie, signed-out state | One UI test passed; screenshot reviewed |
| dictator / native C++ | `d7573f4` | Fixed reader C API input bounds/ownership and durable connection journal | Two CTest executables passed |
| umac / consolidated Android | `057d38868` (equivalent to `d7573f4` Android sources) | Strict ktlint, JVM tests, arm64/x86_64 JNI, isolated debug/test APKs | 139 tests passed; APK versions 0.1.15 code 15 |
| umac / Android emulator x86_64 | `057d38868` | Actual shared-admission ConnectBrowser navigation, cancellation, selector/value exclusion and local-request isolation | Six instrumentation tests passed |
| umac / Android visible UI | `057d38868` | Isolated app, More → Settings → Nessie | Signed out rendered at port 18420; screenshot reviewed |
| dictator / iPhoneOS arm64 | `d7573f4` | Fresh native archives and normal Apple Development device build | Compile/link passed; signing still blocked by SSH keychain interaction |

The navigation instrumentation proves a new document pin is returned after an owned
navigation, cancellation and person tab selection refuse completion, an unrelated
redirect cannot borrow its completion pin, and page-context reads enforce authority
before and after JavaScript evaluation. It uses an explicit local response latch,
not a timing delay, and an injected authority predicate; it does not prove production
UOA or WebSocket authentication. The production predicate remains the existing
immutable job/account/deadline/connection authority.

The consolidated DOM tests reuse the canonical value-free collector and return
distinct observed selectors for duplicate IDs, buttons and empty fields. Every
selector resolves to exactly one element; input values, textarea defaults and
contenteditable text are excluded. Apple uses the private browser-control world;
Android retains its documented page-realm limitation. Owned
cancellation tests cancel a separate extraction request before dispatch and verify
another request remains available. They do not use a loaded GGUF fixture and therefore
do not establish live token-generation cancellation or model quality.

The journal tests cover unknown cancel before command delivery, duplicate and
post-completion cancel receipts, no cancellation of another active attempt, exact
terminal acknowledgements, compact tombstones, capacity recovery without dropping
unacknowledged results, and restart after forward-clock retirement followed by a
backward clock jump. Expired attempts cannot execute after their tombstone is retired.

The Android APK compiled both arm64-v8a and x86_64 JNI libraries. The isolated debug
profile uses port 18420; ordinary builds retain 8420. The initial isolated launch
encountered an input-focus ANR while the host was busy and sharing the ordinary port.
After assigning its own listener and restarting only the verification app, the
Settings surface rendered. UIAutomator intermittently returned a null hierarchy on
that emulator, so the final Android Settings UI evidence is a rendered screenshot
rather than a doorway instrumentation test. The cause of the first startup timeout
was not proven. The consolidated browser instrumentation's first cold-boot run
was killed by Android because its Google FontsProvider process died; ActivityManager
recorded the exact dependency kill, with no native crash trace. After boot settled,
all six tests passed in the same isolated profile. Both logs are retained.

The Apple checks used arm64 simulator archives. An unrestricted generic simulator
build attempted x86_64 and could not link the available arm64 native archives;
the verified command explicitly selects `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`.
Earlier unchanged core-AI/LLM archives were reused read-only after verifying their source
matched. The final owned-request gate rebuilt the changed core-AI runtime and its
LLM dependency for the arm64 simulator, and rebuilt core-connect in the verification
worktree. This is compile/link evidence, not loaded-model inference evidence.

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

Logs, XCTest result bundles, JVM reports, and reviewed Settings screenshots are preserved
outside disposable worktrees in `C:/Users/ondre/.codex/artifacts/kelpie-connect-20261011/native`.
Host equivalents are `/Users/dictator/.codex/artifacts/kelpie-connect-20261011/native`
and `/home/umac/.codex/artifacts/kelpie-connect-20261011/native`. The Apple and Android
archives include their exact source revision. The app containers and credentials were
not copied. Built packages still need the coordinated signed release process.

Read-only device inventory on dictator found a paired, available iPhone 16 Pro Max
and iPad Air 13-inch (M3); both already contain `com.unlikeotherai.kelpie` 0.1.5 build 5.
Their containers, credentials and running apps were not inspected or changed. A
normal development upgrade of the merged 0.1.15 build 15 compiled and linked, and
automatic provisioning found the existing Apple Development certificate and team
`59S95D279D`. It failed signing `Kelpie.debug.dylib` with `errSecInternalComponent`:
private-key access in the SSH session must be resolved interactively before retrying.
The final 0.1.16 build 16 retry, after the user's GUI unlock, reached the same signing
failure. Read-only diagnosis selected `login.keychain-db` as default/search-list
keychain, found the logged-in Aqua session owned by dictator, and returned
`User interaction is not allowed` from `SecKeychainCopySettings` over SSH.
`launchctl asuser` could not switch audit sessions; an owned, valid LaunchAgent
bootstrap into `gui/501` failed with input/output error before any job was created.
No trust, ACL, password or keychain setting was changed. This distinguishes the
SSH interaction barrier from a claim that the user's GUI keychain remains locked.
The exact normal build command is preserved in `iphone-gui-build.sh` in the durable
Mac artifact directory, for execution in the logged-in user's Terminal. No physical
installation was attempted, so developer-mode and install permissions remain unverified.

For macOS, the keychain advertises Apple Development and Mac App Store distribution
identities, but no Developer ID Application identity. A normally signed, notarized
distribution artifact is blocked by that missing identity. The installed Mac app was
initially observed as 0.1.29 with an ad-hoc signature. The latest read-only check
found the upstream 0.1.30 app signed with Apple Development and actively running;
it was preserved. No new ad-hoc artifact was produced or installed by this lane.
Development signing is acceptable for local verification, but this lane's signing
access remains blocked. Missing Developer ID still blocks notarized public distribution.

Android release signing preflight found no release identity in the conventional
`.android`, `.gradle`, `.config/kelpie` or `.kelpie` locations across the four hosts.
Only debug keystores and an internal Gradle cache keystore were found. No credential
contents were read. The existing workflow references `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`; repository
secrets contain none of these, and release `2026-10-11.2` explicitly describes its
APK/AAB as unsigned. A proper existing Kelpie release key path and alias, or an
explicitly approved new signing identity, is required before release packaging.
This lane produced no unsigned or debug-signed release substitute. Durable isolated
debug/test APKs are verification artifacts only, with SHA-256 digests.
The release workflow now fails before expensive Android work if any of its four
signing secrets is absent, signs through Gradle, and checks APK/AAB signatures
before staging assets. The signing identity choice remains pending; this guard
does not provision credentials or establish a signed release.
Focused validation parsed the workflow and checked both Bash scripts, exercised
each missing-secret case and the complete configuration-presence case, verified
an existing debug APK through the real Android SDK tool, and rejected unsigned
APK/AAB fixtures before staging. No key was generated and no real signed release
build was claimed. The validation log and script are retained with native evidence.

iOS CI uses CMake's Xcode generator, which places static archives in each target's
`Debug-iphonesimulator` directory. Its output-flattening step must include
`core-connect` alongside the other native libraries so `Project.swift` finds
`libkelpie_core_connect.a` at its declared search path. The CI native build has no
archive cache and builds all targets; the missing copy caused the PR169 link failure.
The focused Mac check built this arm64 simulator archive in a fresh Xcode-generator
directory, ran the corrected workflow's actual flattening script, and linked a
native probe through that declared library path. Other native targets and the full
app were not rebuilt for this packaging-only check. Logs are in durable native evidence.

Verification roots to preserve before cleanup:

- Mac: `/Volumes/External/Projects/kelpie/.worktrees/kelpie-connect-native-verify`.
  Logs include `swiftlint-navigation-merged.log`, `mac-navigation-merged.log`,
  `ios-navigation-merged.log`, `iphone-native-build.log`, and
  `iphone-device-merged-build.log`; simulator evidence is
  `apps/ios/.build/connect-navigation-merged.xcresult`.
  Consolidated evidence adds `mac-reader-test.log`, `ios-reader-test.log`,
  `ios-reader-doorway.log`, `native-reader-host-test.log`, `iphone-reader-device-build.log`,
  and the `connect-reader.xcresult` / `connect-reader-doorway.xcresult` bundles.
- Ubuntu: `/home/umac/Projects/kelpie/.worktrees/kelpie-connect-native-verify/source`.
  Preserve `android-navigation-merged-build.log`, `android-navigation-merged-rebuild.log`,
  `android-navigation-merged-test.log`, JVM XML reports, and the isolated debug APKs.
  Consolidated evidence adds `android-reader-build.log` and `android-reader-test.log`.

After server release and signed device upgrade, the live travel scenario still needs
fresh UOA consent in the phone's Kelpie, the same UOA account in Nessie on the iPad,
and a foreground phone tab. Verify device discovery, exact-phone selection, pinned
snapshot/navigation, local extraction with a loaded GGUF model, visible pause/stop,
background refusal, and sign-out revocation. This is an explicit remaining live test,
not a claim based on simulator or injected-authority evidence.
