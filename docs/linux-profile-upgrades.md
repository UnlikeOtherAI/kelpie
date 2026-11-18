# Upgrading a Linux CEF 120 profile

Before replacing a Linux installation based on Chromium 120, run the profile
migration below. Keep the old executable and its runtime files available until
the migration finishes. The new package alone does not migrate the old cookies.
Current Chromium uses `cef-cache/Default` instead of the old flat `cef-cache`
directory, and no longer upgrades its cookie database schema (version 19).
Copying the database into `Default` silently drops those cookies.

The migration runs both applications against private copies of Chromium data, reads cookies with
the old application's API, imports them with the new API, and compares their
values and security attributes after a full restart. Cookie values stay in memory
and are never logged or saved as a plaintext export. The original profile is
replaced only after verification, and remains in a private sibling backup.
Verification profiles exclude native account credentials, device identity, saved
tabs, bookmarks and other app settings. Those files are copied unchanged into the
finished profile after verification; the test launches cannot refresh the user's
native account session, join their cookie-sync peers or replace their saved tabs.
Existing modern cookies take precedence over old cookies with the same domain,
path and name. Site-storage directories are copied only when no modern `Default`
directory exists. Partitioned or transient cookies stop migration rather than
being silently converted into ordinary persistent cookies.

Close Kelpie, verify the published package's checksum, and unpack it alongside the
old installation. Use Node.js 22+, `flock`, and an available X11 display (or Xvfb):

```sh
node scripts/migrate-linux-profile.mjs \
  --old-binary /absolute/path/to/old/kelpie-linux \
  --new-binary /absolute/path/to/new/kelpie-linux \
  --new-sha256 VERIFIED_NEW_EXECUTABLE_SHA256 \
  --profile "$HOME/.config/kelpie"
```

On success, switch the desktop launcher to the new executable. The profile stays
at its original path; the backup is `PROFILE.chromium-upgrade/original`. Repeating
the command is safe. An interruption between the final directory renames restores
the original automatically on retry. A failed import or verification leaves the
original active. Do not delete the backup until signed-in sites have been checked.

Focused checks: `node --test tests/packaging/profile-migration.test.mjs`.
For a real old-to-new upgrade test, set `KELPIE_LEGACY_LINUX_BINARY` and
`KELPIE_LINUX_BINARY`, then run
`node --test tests/packaging/linux-profile-upgrade.test.mjs` under a display.
That test checks a server-issued HttpOnly cookie, HTTP delivery after restart,
wrong-hash rejection, preservation of the original database, and interruption
recovery. Neither test uses a person's cookies.

Upstream context: [CEF bootstrap migration](https://github.com/chromiumembedded/cef/issues/3721)
and [Chromium cookie database compatibility](https://chromium.googlesource.com/chromium/src/net/+/HEAD/extras/sqlite/sqlite_persistent_cookie_store.cc).
