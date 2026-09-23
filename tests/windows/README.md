# Windows release acceptance

`run-release-acceptance.mjs` is the release gate for a built Windows Kelpie
artifact. It starts a local fixture, starts only the supplied `kelpie.exe` with
an isolated profile, waits for the ACL-protected readiness file, and drives the
real HTTP and MCP endpoints. The runner owns every process it starts. It uses
the authenticated `close-browser` control route for graceful shutdown, then
terminates only that exact PID tree if the owned child refuses to exit. It never
kills by executable name or port.

Run it from the repository root after producing a Windows Release artifact and
building Nessie's MCP client in the caller-selected Nessie worktree:

```powershell
$nessieRoot = "C:\path\to\nessie-worktree"
pnpm --dir $nessieRoot --filter @nessie/mcp-client build
node tests/windows/run-release-acceptance.mjs `
  --exe C:\path\to\kelpie.exe `
  --cli C:\path\to\kelpie-cli\bin\kelpie.js `
  --nessie-root $nessieRoot
```

The executable contract is deliberately product-facing:

```text
kelpie.exe --profile-dir <absolute> --port <loopback-port> \
  --readiness-file <absolute> --url <fixture-url> --width 1280 --height 720
```

Readiness must be published atomically only after the browser and HTTP control
server are usable. Its version-1 JSON shape is:

```json
{
  "version": 1,
  "launchId": "opaque per-launch id",
  "deviceId": "stable device id",
  "port": 8420,
  "token": "per-launch bearer capability",
  "controlMode": "loopback",
  "mcp": { "http": true, "stdio": false, "endpoint": "/mcp" }
}
```

The token must remain only in a file ACLed to the current Windows user and
administrators. Do not pass it in command output, CI logs, mDNS, or issue text.
The runner prints only the device ID and bound port.

The acceptance covers bearer/Origin/Host/body validation, tabs and background
targeting, native trusted input, navigation, dialogs, cookies and storage,
console/network inspection, bookmarks/history, PNG decoding, a JPEG scaled to
`maxWidth`, `wait-for-navigation` after a click (and its `TIMEOUT` after a
click that does not navigate), direct stateless MCP with a screenshot sent
once, a real `@nessie/mcp-client` flow, profile locking, occupied ports, and
clean-restart session restoration. The fixture never calls the internet.

The browser is started visible, the way a person starts it: the app refuses a
browser child that is not visible, so a hidden launch never becomes ready.

It also proves the CEF sandbox from Windows process tokens: the runner finds
every renderer descendant of its owned bootstrap PID and requires each to run
below Medium integrity. A missing or unreadable renderer token fails the
release gate.

The CLI phase registers an isolated alias, launches it, reuses its saved
readiness record for a CLI navigation, and opens `kelpie --browser <alias> mcp`
through Nessie's real stdio transport. The MCP client receives no readiness
path, loopback URL, or bearer capability.

The Nessie check imports the published-client build and supplies its explicit
test-only `fetchImpl` override for this loopback fixture. Nessie's normal cloud
connector policy continues to reject private and localhost targets. A signed
local-executor integration must be exercised separately once it is available;
this check proves client protocol compatibility, not permission to bypass that
policy.

`--profile-dir` is accepted only when the directory does not exist, so a release
run cannot alter a developer's browser profile. By default it creates a Unicode
temporary profile and deletes it on success or failure. Use `--keep-artifacts`
only while diagnosing a failed run.

Native visual review is still required after the automated gate: verify the tab
strip and close buttons, Ctrl+T/Ctrl+W/Ctrl+Tab/Ctrl+Shift+Tab, Ctrl+L and URL
focus after page focus, navigation controls, history completion acceptance and
rejection, settings/panels, resize, and fullscreen with real keyboard and mouse.
