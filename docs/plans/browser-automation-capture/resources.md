# Resources, access and release audit

Recorded 2026-11-04. Current user gate: Windows on Maxis first; Mac only after Windows acceptance. Earlier Mac access notes below are historical. This is a coordination snapshot, not a resource reservation.
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

## Windows-first gate

The user changed the execution order: build and verify the Windows app remotely on Maxis first. Required evidence is actual CEF native UI, direct MCP, CLI forwarding, decoded GIF/MP4/PNG and manual media inspection. Mac drafts remain preserved; no Mac build, launch or process replacement until Windows completes and the coordinator grants the next slot. Shared Maxis heavy workloads remain serialized after host-load checks. The macOS worker is being reassigned a separate Windows worktree; desktop backend work retains session/Lightpanda/WebMCP ownership.

## Windows GUI access inventory
Read-only checks found TightVNC 2.8.89.0 installed on Maxis. Existing tvnserver PID 5724 at C:/Program Files/TightVNC/tvnserver.exe listens on 0.0.0.0:5900; a TCP connectivity check from Minis passed. Local CUA inventory includes installed TigerVNC, not yet launched. This supplies a supported existing remote-viewer route without starting a new service. Authentication has not been tested and no credentials were read. Maxis has an active ondre console session; RDP TermService is stopped. No AppReveal or remote-CUA MCP is configured in the inspected Maxis Codex configuration. Coordinate the shared desktop before GUI input, then use the installed viewer through CUA after the resource grant. No remote app was launched, stopped or changed during this inventory.

## VNC connection attempt
The coordinator authorized access setup only. Acceptance launched the existing TigerVNC through supported local CUA and connected to 192.168.1.90::5900. The server responded with a VNC authentication dialog (local window ID 29890784). No remote desktop appeared; saved authentication did not complete. The prompt was left open for the user to enter the existing password directly in the viewer. No credential was read or typed, no authentication setting changed, and no remote foreground app was touched. This is an authentication blocker for manual remote UI verification, not a failed Kelpie test. Do not request the password in chat.
Windows codec ownership is now separate: the former mobile worker owns WIC/MediaFoundation modules in D:/Worktrees/kelpie/capture-windows-media-20261104 at assigned base ef9f8eda. The Windows runtime owner retains sampling/compositing/overlay/artifacts/auth/routes/CMake. One shared heavy-test slot remains; Apple/mobile drafts stay preserved. Codec evidence must include actual decoding, timing/duration, hash and partial-output recovery, plus displayed/exported-frame correspondence.

## VNC authentication resolved
The coordinator completed authentication and observed the actual Maxis desktop in the existing viewer, window ID 45946812 titled maxis - TigerVNC. No password was saved, and no remote click or process change was made. The earlier authentication blocker is resolved. The viewer currently shows unrelated remote work; acceptance must refresh its own CUA inventory before use and must not interact with that work. Actual Kelpie UI testing still waits for the exact candidate revision and resource grant. No credential material is stored in this ledger.

## Source-review hold after Windows draft
Computer Use remains off after the user's cursor-release request. No viewer,
control helper or native interaction is authorized by this review. The coordinator
reports another task's Kelpie PID47784 at
D:/BuildArtifacts/kelpie/session-capture/windows-0.1.12/kelpie.exe; preserve that
process while its owner is resolved. Acceptance has performed only source reads,
docs edits and Git operations; it has not started a test/build/media process.
