# Chromium maintenance and public review evidence

Kelpie checks available stable CEF/Chromium builds in GitHub Actions every six
hours. It proposes source updates, verifies upstream downloads, and starts
candidate checks. The repository, workflow source, run summaries, and pull
requests are public. This is the maintenance pipeline; it is not an Apple
entitlement approval or proof that a candidate has shipped.

## Links for reviewers

- [Scheduled monitor and timestamped runs](https://github.com/UnlikeOtherAI/kelpie/actions/workflows/engine-updates.yml)
- [Candidate builds and results](https://github.com/UnlikeOtherAI/kelpie/actions/workflows/engine-candidate.yml)
- [Latest public status issue](https://github.com/UnlikeOtherAI/kelpie/issues?q=is%3Aissue%20is%3Aopen%20label%3Aengine-update)
- [Engine update PRs](https://github.com/UnlikeOtherAI/kelpie/pulls?q=is%3Apr%20head%3Aengine-update%2F)
- [Published releases](https://github.com/UnlikeOtherAI/kelpie/releases)
- [Monitor source](../.github/workflows/engine-updates.yml) and [candidate workflow](../.github/workflows/engine-candidate.yml)

For an Apple submission, link a specific successful monitor run, its candidate
PR, the checks at that PR's final commit, and the corresponding signed release
and installed-app verification. A workflow definition alone proves intent, not
execution. A merged PR alone does not prove publication. Failed checks stay
visible and must not be presented as successful qualification.

## What runs automatically

1. At 00:23, 06:23, 12:23 and 18:23 UTC, read the
   [CEF build index](https://cef-builds.spotifycdn.com/index.json) and the
   [Chrome VersionHistory API](https://developer.chrome.com/docs/web-platform/versionhistory/reference).
2. Select the numerically newest **stable minimal** CEF archive for macOS arm64,
   Windows x64 and Linux x64. A recently published older maintenance branch
   cannot downgrade an existing pin. Show Chrome stable separately so CEF's
   availability lag remains visible.
3. If no candidate PR is open, stream each changed platform's archive, verify
   its published SHA-1 and byte length, and calculate SHA-256. Update the
   existing source pins and their package/test consumers together. Windows
   retains both hashes in its download script. Mac/Linux's existing download
   scripts are unchanged apart from their version pins; the scan's verified
   digests are evidence, not a new checksum-enforcement promise for those scripts.
4. Create a branch and PR without modifying `main`. If a candidate already
   exists, preserve its commits and report that newer updates are waiting.
5. Explicitly dispatch candidate, lint, and macOS project checks at the candidate
   branch. GitHub can require approval for PR events generated with
   `GITHUB_TOKEN`; dispatch avoids depending on those events. No PAT, signing
   identity, LLM service or scraper credential is needed by this monitor.
6. Update one public status issue and retain JSON/Markdown reports for 90 days.
   The run summary contains the same evidence. Errors produce failed runs and
   update the status issue when the GitHub API remains reachable.

GitHub Actions schedules are best effort. They can be delayed or disabled after
repository inactivity. Check the timestamp and workflow state; there is no
independent watchdog here that can detect GitHub itself stopping the schedule.
GitHub notification preferences control failure notifications.

## Candidate qualification

| Platform | Automated candidate check | Still required before publication |
| --- | --- | --- |
| Windows x64 | Existing sandbox-enabled CEF build, native tests and unsigned package | Signing and installed-package browser/automation/passkey flows |
| Linux x64 | CEF build, native tests and runtime bundle on Ubuntu | Installed-package flows and other supported distro/Wayland checks |
| macOS arm64 | Compile the Swift/Objective-C++ browser library with the selected CEF headers/framework | Full containing-app build, signing/notarization and installed-app flows |
| iOS/iPadOS | Uses the OS WebKit runtime; no CEF pin | Apple platform updates and WebKit/passkey integration checks |
| Android | Uses the device's Android System WebView; no bundled CEF pin | WebView/provider updates and Android passkey integration checks |

Native jobs run only when that platform's CEF version changes. Updating the
monitor's code or docs exercises its tests and skips unrelated native builds.
The macOS library check is labelled as compilation: the existing standalone
macOS CI does not provide a complete containing-app CEF build.

The pipeline does not automatically merge or publish browser binaries. CEF
major updates can require API changes. Resolve them in the candidate branch,
rerun qualification, bump each affected app's version, and follow the existing
[macOS](macos-release.md), [Windows](windows-release.md) and Linux release
procedures. Verify navigation, login/passkeys, automation and recovery on the
installed artifact. Keep the release link and that evidence on the PR.

## Running and recovering the monitor

From **Actions → Chromium update monitor → Run workflow**:

- Leave **dry_run** checked to report available updates without GitHub writes.
- Check **verify_downloads** to exercise archive verification without creating a PR.
- Clear **dry_run** to create or resume the candidate and public status issue.

The same read-only interface works locally with Node 22 or newer:

```sh
node --test tests/engine-updates/*.test.mjs
node scripts/engine-updates/scan.mjs
node scripts/engine-updates/scan.mjs --verify-downloads
```

Local reports go under ignored `.cache/engine-updates/`. `--publish` additionally
requires `GH_TOKEN` and `GITHUB_REPOSITORY`, and only accepts the current `main`
revision when creating a candidate. The workflow grants contents, PR, issue and
Actions write permissions only to its monitor job. Candidate builds have
read-only repository access.

A failed upstream scan retries on the next schedule. An interrupted PR creation
reuses the identical candidate branch; dispatch retries start only missing
workflow runs. Human commits and closed review decisions are preserved. A
failing candidate needs a source fix, not deletion or a force-push by the bot.
After a human fix, the next monitor dispatches checks for the new commit.

## Scope and earlier prototype

`monitoring/` contains an earlier optional LLM-powered issue/dashboard prototype.
It is not the scheduler, status authority or evidence source for this pipeline.
No deployed `kelpie.works` or `monitor.kelpie.dev` service is assumed. Gecko's
experimental downloader is outside this Chromium pipeline. Vulnerability
triage, response deadlines, Web Platform Tests, regional engine eligibility and
Apple's entitlement requirements need separate evidence; a green Actions run
does not certify them.
