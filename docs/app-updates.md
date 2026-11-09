# App update delivery

Date-tagged GitHub releases can contain independent app versions and may be
published before their assets finish building. Apps therefore read explicit,
ready component metadata from the stable releases list, rather than comparing
the release tag or assuming that `/releases/latest` updates every platform.

## Release metadata

After an artifact is built, signed where applicable, uploaded and verified, run:

```sh
node scripts/publish-app-update.mjs --tag release/2026-11-09 \
  --target windows-x64 --version 0.2.1 --asset kelpie-windows-x64-0.2.1.zip
```

The command requires the version from the tagged component manifest and checks
that the asset name matches its platform and architecture. It verifies the
uploaded asset has GitHub's SHA-256 digest and adds one
machine-readable comment to the release notes:

```text
<!-- kelpie-update: {"target":"windows-x64","version":"0.2.1","url":"https://github.com/UnlikeOtherAI/kelpie/releases/download/release/2026-11-09/kelpie-windows-x64-0.2.1.zip","sha256":"<64 lowercase hex characters>"} -->
```

Enabled app targets are `windows-x64`, `macos-arm64`, `macos-x64`,
`linux-x64-appimage`, `linux-x64-deb`, `linux-x64-rpm`, `linux-x64-tar`,
and `android`. Only advertise architectures that were actually built. Versions
are numeric `major.minor.patch` from the component manifest, never the date tag.

Android store releases use `--store-url` instead of `--asset` with the Kelpie
Play Store page. Publish metadata only once that version is available to users.
iOS app integration is deferred until its distribution route is ready. The
metadata tooling reserves an `ios` target for an App Store page, but the iOS app
does not check for updates in this delivery. A Simulator ZIP cannot update a
physical iPhone or iPad and is rejected by the publisher.

The release workflow advertises Linux and Android only after their verified
artifacts have been attached. Direct Mac and Windows publishers run the command
above after signing and verifying the published download. Each target is updated
independently; release notes and other targets' metadata are preserved. Run
publishers sequentially to avoid concurrent edits to the same release body.

## Prompt and preference behavior

Apps check the public GitHub releases API without credentials on launch and
every six hours. They select the highest compatible component version in the
latest 100 releases before considering the user's choices. Skipping the newest
must never cause a prompt for an older release. A new version can prompt in the
same launch even after an earlier version was deferred or skipped.

Skip version is durable local app data. Not now, dismissing the dialog, and
successfully starting an update suppress that version for the current process
only. No automatic installation happens after Not now: the next launch asks
again. Network, rate-limit, malformed-feed and server failures retry after fifteen
minutes. Download or verification failures keep the current app and show an error.

Release checks belong to standalone hosts in `apps/`, not the embeddable browser
libraries. They are absent from embedded browser sessions and Linux headless runs.
The Mac keeps a discovered update pending until an active window can present its
sheet, including when the check finishes before the first window opens.

## Desktop installation

Desktop helpers are copied to a private temporary directory before they start.
They download over HTTPS, compare SHA-256 against release metadata, stage the
complete package, and validate it before asking the app to exit. The helper then
waits for that exact process to close before replacing files and restarting with
the original arguments. Profiles and browsing data remain outside the package.

- Windows stages a sibling directory on the same volume. ZIP traversal and
  symlink entries are refused. The bootstrap, client DLL and `chrome_elf.dll`
  must have valid timestamped UnlikeOtherAI signatures with the same certificate,
  preserving CEF's sandbox contract. The expected app version and runtime files
  are checked. Other running instances using that installation prevent replacement.
- Mac requires a normal `.app` bundle in a writable parent directory. It verifies
  the new bundle's signature, matching TeamIdentifier and bundle identifier,
  Gatekeeper acceptance and component version. Ad-hoc or unnotarized builds are
  not eligible for automatic installation.
- Linux AppImages and extracted tar bundles stage alongside the existing
  installation. `.deb` and `.rpm` installations at `/opt/kelpie` retain package
  manager ownership through their existing root-owned update helper, invoked
  through `pkexec`. The privileged helper downloads and verifies a separate copy
  in a root-owned temporary directory before invoking `apt-get` or `dnf`; it never
  installs the mutable user-owned download. System authorization and dependency
  failures are handled by the package manager; portable directory
  replacement is never applied to a managed installation.

Portable installs preserve a uniquely named `.previous-*` copy. If a directory
swap or immediate restart fails, the helper attempts to restore and relaunch
that copy. Failed new files are retained separately for diagnosis. Update helpers
never delete a prior installation or change browser profile state to recover.

## Verification

The native update policy tests run independently of CEF:

```sh
cmake -S apps/updates -B .cache/update-tests
cmake --build .cache/update-tests
ctest --test-dir .cache/update-tests --output-on-failure
node --test tests/packaging/app-updates.test.mjs
bash tests/linux/app-update-install.sh  # Linux portable install and recovery fixtures
```

The Mac prompt UI fixture lives only in the non-shipping
`KelpieUpdateVerificationMac` target. It has a separate bundle identity,
preferences and an in-memory HTTP response. Its Update action is simulated and
cannot run an installer or change a real Kelpie profile. Regular apps have no
environment-variable or intent override for release data. Test their restart
choices through the corresponding verification schemes; do not inject synthetic
versions into an ordinary Kelpie app on a person's desktop.

Windows and GTK use the same production dialog functions from isolated
`kelpie_update_verification` hosts. Build them with
`-DKELPIE_UPDATE_UI_VERIFICATION=ON` in the update test CMake project. Their
preferences stay in the verification directory and Update is simulated.
Android's separate `com.unlikeotherai.kelpie.updateverification` app is opt-in:
run `gradlew -PupdateVerification=true :update-verification:assembleDebug` from
`apps/android`. It compiles the production update controller with a local mock
HTTP server and simulated Update action. None of these hosts is packaged with
the ordinary apps or release artifacts.

Before releasing, also exercise each native prompt, Not now followed by restart,
Skip version followed by restart, a later version, offline recovery, a failed
download/checksum, and installing/restarting an exact signed published package.
Capture the new prompt and download state on each changed native screen. The
absence of a previous prompt should be identified in each screenshot's Before
cell; no unchanged browser screens need screenshot evidence.

The Linux update compatibility workflow compiles the production GTK integration
against Ubuntu 22.04 headers, then checks update policy and installer recovery.
Keep the integration compatible with that distribution's GLib version.

On Windows, `tests/windows/app-update-install.ps1 -SignedPackage <absolute ZIP>`
exercises the shipping helper against an isolated signed installation. Transport
is replaced only in the test process; signatures, hash, shutdown, directory swap,
profile preservation and restart are real. It keeps its evidence under `.cache/`.
Desktop installers wait for CEF children to finish after the browser parent exits
before copying a profile or replacing the installation, so cache journals cannot
disappear during the copy.
Windows profile copies use extended paths because staging can put existing
Chromium cache filenames beyond the legacy 260-character PowerShell limit.
