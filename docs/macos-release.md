# macOS-only releases

For a release containing only the macOS app, put this exact marker on the first
line of the GitHub release body:

```text
<!-- kelpie-release-components: macos -->
```

The release workflows skip unrelated Linux, Android, Windows and CLI builds when
this marker is present. Publish the Mac artifact yourself after its native build,
tests, signing checks and hands-on verification. Tag the committed, merged source
containing these workflow guards before publishing; editing release notes afterward
does not stop jobs already triggered. Releases without the marker retain their
existing multi-platform build behavior.

List the Mac component version, architecture, signing/notarization status and source
revision in the release notes. Keep a Mac-only release from replacing the global
latest release (`gh release create --latest=false`) so existing multi-platform
latest-asset links remain valid. Use `release/YYYY-MM-DD`, with a numeric suffix if
that date tag already exists. Download and verify the published artifact's SHA-256,
replace `/Applications/Kelpie.app`, then launch and verify that installed version.

Android and iOS CI are filtered to their app source, shared core/native/contract inputs
and relevant toolchain inputs. A Mac-only change or release-workflow edit does not
build those apps. Workflow-only changes can be checked with Actionlint; their
explicit `workflow_dispatch` entry points remain available for a platform build.

## Direct-distribution signing

Build the desired architecture with the existing UnlikeOtherAI Developer ID
identity. Copy the completed app into a separate release staging directory, then
run the inside-out signer from this repository:

```sh
node scripts/sign-macos-app.mjs --app /absolute/staging/Kelpie.app \
  --identity "Developer ID Application: UnlikeOtherAI s.r.o. (23B7GTLBN7)" \
  --team 23B7GTLBN7
```

The signer seals nested Mach-O files, their bundles and the containing app in
that order, with hardened runtime and secure timestamps. It preserves the
Chromium helper exceptions in `core/apple/Helpers/KelpieHelper.entitlements`;
they never apply to the main app. Ad-hoc and development identities are rejected.
`pnpm check:macos-signing` verifies the signing plan without accessing a certificate.

Submit the staged app as a ZIP through `xcrun notarytool submit --wait` using
the existing App Store Connect configuration on the signing Mac. Credentials
stay outside the checkout. Require Accepted, staple and validate the app, then
require `codesign --verify --deep --strict` and `spctl --assess --type execute`
before publication. Recreate the published ZIP after stapling; verify its hash
after downloading it. A successful Xcode signature alone is not notarization.

This direct-distribution procedure is separate from the WebKit-only, sandboxed
Store build described in [the browser core contract](../core/README.md).

After verifying the published signed, notarized ZIP, run
`scripts/publish-app-update.mjs` with the release tag, canonical Mac version,
the matching `macos-arm64` or `macos-x64` target and that ZIP's asset name.
Advertise only architectures that were built and verified. This marks the update
ready for installed apps; creating the release before its asset is ready does
not. Ad-hoc development builds are not eligible. See
[App update delivery](app-updates.md).
