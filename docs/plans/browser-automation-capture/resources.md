# Resources, access and release audit

Recorded 2026-11-04. This is a coordination snapshot, not a resource reservation.
Only the coordinator grants workload slots. ChatterBox tools were unavailable;
directed coordinator messages carry resource changes. A later supported local MCP fallback was found, but registration failed; see below.

| Host | State / evidence | Work allowed |
|---|---|---|
| Maxis | SSH IPv4 works; Node present; ffmpeg/ffprobe absent from current PATH | workflows owns MAXIS-PORTABLE-1, maximum two workers; observations install finished; other heavy work held |
| Mac dictator | DNS failed from this session; IPv4 SSH works | builds/servers/browser launches held by coordinator |
| Ubuntu umac | coordinator reports unreachable | no jobs |
| FedoraMaxis | bounded Linux-only verification target | no general development jobs |
| Minis | local CUA available | UI access inventory only so far |

Coordinator reports Mac load 27-49 on 10 CPUs, 31 GB used and 32 GB swap.
Read-only inventory found one DeviceHub PID 545, Kelpie PID 12718 in the
`favorites-tree` worktree, and existing Android scrcpy/emulator work. These are
other owners' processes; coordinate before replacing any Kelpie instance or
consuming simulator resources. No process was stopped by acceptance.

## Real UI and MCP access

CUA inventory exposed local Windows apps and Chrome, with no Kelpie window and
no remote Mac browser. TigerVNC is installed but was not running. Inventory alone
does not prove remote GUI access. No UI action or screenshot has been performed.

Mac SSH reports `/usr/sbin/screencapture`; cliclick, ffmpeg and ffprobe were absent
from its nonlogin PATH. The coordinator verified ffmpeg at /Users/dictator/.homebrew/bin/ffmpeg; the nonlogin PATH omits it. This does not prove absence of the other tools from the filesystem. No custom
input tool has been installed or run. Remote shell screenshot capability alone
does not establish permission to read the current desktop or interact with it.

The repository supports debug AppReveal with launch-context identity plus
screenshot/UI tools. Once the coordinator grants the Mac slot, the native owner
must launch the exact built revision and expose its supported test interface.
Acceptance then verifies bundle/version/process identity and uses actual public
HTTP/MCP/CLI entry points. AppReveal screenshots or a supported remote GUI can
corroborate the visible pointer and playback. A backend-produced screenshot does
not alone prove that an overlay appeared in the real app window.

## Release audit

The coordinator reports `release/2026-11-04` already published for an earlier Mac
fix. Never overwrite, move or reuse its assets for this integrated change.

At the reviewed base, `.github/workflows/release.yml` accepts `release/*` for npm
publication and validates versions only for `v*` tags. Repository policy still
requires a date tag. Use a fresh actual publication date, for example
`release/2026-11-05` if publication happens on that date. A same-day suffix would
need an explicit policy decision from the coordinator; workflow permissiveness is
not policy authorization.

Before release, enumerate every affected component manifest, bump each affected
version and list all versions in the release description. The release workflow
publishes shared/CLI npm packages as well as Android/Linux artifacts. The Windows
release workflow currently builds/packages ZIP assets; it does not show an Azure
Artifact Signing step, so green CI cannot establish Authenticode signing.
macOS and iOS distribution evidence must be audited separately. Do not use the
Mac-only release marker for this multi-component release.

For each affected artifact record source SHA, unsigned hash, final published
hash/size, signature/provenance, public download check, installed version and
user-flow evidence from the installed artifact. Windows must use the existing
UnlikeOtherAI Public Trust signing identity. Android requires all configured
signing secrets and verified APK/AAB signatures. macOS must replace and relaunch
the installed app after publication. No publishing action is authorized to this
acceptance worker.
## Lightweight acceptance check

QA-LIGHT-1 was granted for at most 10 seconds, one worker, no dependency install,
browser, media encoder or native process. Maxis passed Node syntax checks for the
fixture server/page script, assertions and evidence validator. All six
harness-only tests passed in 1.03 seconds. These checks validate the acceptance
harness, not any product capability. The temporary loopback fixture HTTP server
was created and closed by the harness test. No persistent service was launched.
## ChatterBox fallback audit

The local Codex configuration names the existing
C:/Users/ondre/.chaterbox/codex-mcp.cmd shim. The supported
C:/Users/ondre/.chaterbox/board-client.mjs can invoke named MCP tools.
board_help returned the worker/setup guidance. board_register and directed
board_messages (pending=true, limit=10) both returned: hub unavailable or
registration rejected. No registration, message delivery or inbox read is
confirmed. No general feed, sibling transcript, token or connection-file contents
were printed. No hub restart or configuration change was attempted.

## Coordination update

The coordinator attempted its own registration once as
kelpie-capture-root-20261104. Registration and the directed inbox returned the
same hub unavailable or registration rejected response. No delivery or inbox
access is confirmed; do not retry registration without a supported recovery.
The coordinator has asked the user asynchronously about Mac availability because
of heavy swap and the other owner's favorites-tree Kelpie process. Await that
answer or explicit coordinator clearance before Mac builds, browser launches or
process replacement. No Mac process has been changed by acceptance.