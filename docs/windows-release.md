# Windows release packages

The release workflow builds an unsigned candidate and retains it as a GitHub
Actions artifact. It does not attach unsigned binaries to the public release.
Sign and verify the final archive on Maxis before publishing it.

The existing UnlikeOtherAI Azure Artifact Signing setup owns signing. Use its
protected local `sign.ps1` script; no PFX, credentials or new publisher is needed.
The local signer checks the source revision and input hash, the exact publisher,
the profile-specific EKU, timestamp and SignTool trust.

CEF's [bootstrap contract](https://github.com/chromiumembedded/cef/blob/708dc14/libcef_dll/bootstrap/bootstrap_win.cc)
requires `kelpie.exe`, `chrome_elf.dll` and `kelpie.dll` to have the same valid
primary certificate thumbprint. Matching publisher names alone is insufficient.
Signing only the launcher and client DLL produces a package that fails before
the browser starts. Keep this bootstrap validation and the Chromium sandbox.

## Build and sign

Build and package through `scripts/build-windows.ps1` and
`scripts/package-windows.ps1`. Verify the compiled source revision and unsigned
archive SHA-256. Obtain the existing profile-specific `WINDOWS_SIGNER_EKU` from
the Nessie repository's Actions variables; it is configuration, not a credential.

Run `scripts/sign-windows-package.ps1` with these mandatory parameters:

- `InputPackage`: the unsigned ZIP.
- `ExpectedSha256`: its verified SHA-256.
- `SourceCommit`: the compiled 40-character revision.
- `ExpectedSignerEku`: the configured profile OID.
- `OutputDirectory`: a new artifact directory.
- `SigningScript`: the existing `$env:USERPROFILE/.config/unlikeotherai/windows-signing/sign.ps1`.

The output directory must be new. It preserves unsigned inputs, signed files,
the staged package, final ZIP, SHA-256 and provenance. All three binaries must
be valid, timestamped, signed by UnlikeOtherAI and use the configured profile
and the same certificate. A failed signing attempt never replaces earlier
artifacts; retry into a new directory after resolving the cause.

## Verify and publish

Extract the exact signed ZIP, verify its hash, and launch `kelpie.exe` with a
fresh absolute `--profile-dir`, a free `--port` and an explicit `--url`. Inspect
the rendered page and use the native browser controls. A valid signature alone
does not prove the package starts.

After the PR passes its required checks and merges, upload the verified signed
ZIP, hash and provenance to the component's dated release. Download the published
archive, compare its SHA-256, extract and launch that copy. Keep the source
revision and signing evidence with the release record.

After the published download has been verified, advertise it to installed apps
with `scripts/publish-app-update.mjs`: use the release tag, target `windows-x64`,
the canonical Windows component version and the signed ZIP asset name. The
publisher checks the version against the tagged source and requires GitHub's
uploaded-asset digest. Never advertise the unsigned CI candidate. See
[App update delivery](app-updates.md).
