# macOS network capture responsiveness

## Evidence and root cause

On 4 November 2026, the installed macOS 0.1.30 process remained alive through the
reported sign-out/sign-in stall. macOS recorded 90 CPU seconds over 99 seconds
(91% average). Its heaviest stack was the main-thread network bridge calling
`NetworkTrafficStore.append`, exporting the entire C++ store to JSON and decoding
it back into Swift. Every request also serialized the full history again and wrote
it to UserDefaults. The live `kelpie_network_traffic` value was about 8.7 MB;
CFPreferences repeatedly rejected it for exceeding its 4 MB limit.

The native account login already uses the default WebKit data store. The earlier
Google login failure was in an explicitly isolated test tab. Those findings do not
prove the native login lifecycle is healthy under load; verify it after removing
the demonstrated main-thread bottleneck. The unrelated Safari session is out of
scope, as are changes to other platforms.

## Change

Keep the shared C++ store and its filtering/selection behavior. Update the existing
Swift UI mirror incrementally after a successful append, normalize the added entry
as the core does, and derive trimming from the core's count. Build document entries
through the same append path. Whole-store export/decode remains a startup operation,
not a per-request operation. Tests compare the mirror with the core summary and
selection after normalization and eviction.

Move macOS traffic persistence to an owner-readable Application Support JSON file.
A serial utility queue coalesces the latest immutable Swift snapshot, encodes it and
atomically writes it at most once per second under continuous traffic. There must
be at most one pending snapshot, not one queued encode per request. A final flush
on normal app termination preserves recent traffic. A clear supersedes pending
traffic and must survive restart; serial writes cannot resurrect older snapshots.

Read the legacy UserDefaults data/string format at startup when no file exists.
Remove the old preference only after a successful file write. Failed writes keep
the original data for retry; never clear the person's history to improve speed.
Existing retention, request detail and API contracts remain unchanged.

## Verification

- Regression tests: retained history and bodies, legacy migration and failed-write
  recovery, clear with a pending write, normalization, filtering and selected-entry
  behavior when the oldest entries are evicted.
- Compare sustained appends into a full 2,000-entry store with large synthetic
  bodies before and after. Use the same workload and build configuration.
- Build and test macOS, then exercise the installed app's network inspector and
  account sign-out, cancel, sign-in, Google reuse in normal tabs, and isolation.
  Preserve the live legacy history to exercise automatic migration.
- No intended visible UI change; no screenshots of unchanged screens are required.

## Cross-Provider Review

Claude reviewed the design before implementation. Accepted: bounded pending work,
private file permissions, migration only after a successful write, ordered clear
and shutdown writes, failure recovery, and measuring total processing cost.
The live legacy value is readable; its bytes were inspected without printing any
request content. Startup load remains synchronous, so appends cannot overtake it.

The reviewer assumed in-place core updates; this store only appends, trims, clears
and selects. No update operation exists. Retain the existing core instead of adding
a delta protocol and revision counter for a Mac-only repair. Regression tests must
compare the incremental mirror with core output through retention and selection.
One background encode per second is measured rather than assumed to consume a
core; the expensive repeated C++ export and Swift decode are removed entirely from
capture. Normal termination flushes the serial writer; force-quit can lose the
last second of capture. File write failures retain the latest snapshot for retry.

## Release scope

The release workflow currently builds Linux, Android and Windows on every published
release. This Mac-only repair must not trigger unrelated native builds. Add an
explicit `<!-- kelpie-release-components: macos -->` marker on the first line of the release body that skips
those jobs and CLI publishing. Releases without the marker retain their existing
behavior. Move the independent Windows build/attachment jobs to their own release
workflow to keep each workflow below the repository's 500-line limit. Publish the
locally built Mac artifact with that marker; no other component version changes.

The release review correctly identified tag ordering and latest-release consumers:
the tag will point to the merged workflow change, and the Mac-only release will
not replace the repository's multi-platform latest release. The independent
Windows workflow has the same first-line marker guard and retains both its build
and upload jobs. It does not currently use OIDC or environments. No dependency is
moved across workflows. Expressions read the body as data, never as shell input.
Publishing and installing are already explicitly required by the repository's
release instructions; no additional permission is required.

## Implementation review and measured result

A second Claude review led to preserving history after read errors as well as
malformed JSON, a regression for failed clear/retry, and comparison of all entry
fields with actual C++ output. The Swift mirror preserves the existing bridge's
ASCII method conversion, integer conversion, nil/empty body handling, whole-second
timestamps and default browser initiator. Document navigation uses the same field
values as the old dedicated bridge. The core's existing initiator default is not
changed in this Mac-only repair.

The existing timestamp format already omits fractional seconds. A sub-second test
now checks that the incremental path matches the old core round-trip. Removed the
wall-clock assertion from CI; the controlled benchmark remains separate. Native
login tests are part of the original bug report: a synthetic cookie uses a unique
name on an invalid test domain and is deleted after checking normal/isolated stores.

The same Debug workload (2,000 retained entries with 10 KB bodies, then 100 appends)
took 281.131 seconds before and 0.193 seconds after. The final background encode and
file write took 0.210 seconds. Coalescing removes the per-request whole-store
export/decode and bounds serialization frequency; it does not claim zero disk or
CPU work. Clear/quit wait for the serial writer to preserve ordering. An unavailable
disk still prevents durable storage; the latest snapshot retries with backoff.

On this Mac, the 0.1.34 development build migrated the real 8.6 MB legacy history
to a mode-0600 file and removed the preference only after success. Native login
cancel/reopen, Google account reuse, sign-out and a second sign-in all completed.
The process stayed alive and a later CPU sample was 0.5%; this is a live observation,
not a controlled before/after CPU benchmark. Network inspector filtering, request
selection and response headers worked with retained history. Real history was not
cleared; clear/recovery are tested with disposable fixtures.

Strict Swift lint passed. 65 focused Mac XCTest cases passed, covering network,
account/session, login window and cookie-scope behavior. Debug and Apple Silicon
Release builds succeeded; existing warnings remain in AppReveal, BrowserView
captures, BrowserViewHelpers and CEF bridge code. No warning originated in the new
persistence or tests. Other native platforms were not built or changed.

Portable verification ran on Windows Maxis in an isolated D: worktree at the same
base revision (the package source and dependency graph are unchanged in this fix):
`pnpm lint`, `pnpm build`, and `pnpm test` passed; 79 shared and 626 CLI tests passed,
64 CLI tests were skipped by platform/test configuration. Release workflows pass
Actionlint 1.7.12; an object-level comparison confirms all seven original jobs and
dependencies are preserved except the four explicit root-job guards.
