# Linux desktop parity

The Linux shell predates the shared desktop runtime: it owns a separate HTTP/MCP
implementation and a single renderer, so restyling alone cannot provide Windows
tabs, tab leases, start pages, or account-aware bookmarks. Replace the CEF build's
runtime with DesktopApp, retaining the existing stub build for development without
CEF. Reuse the shared desktop account module and its Linux curl/OpenSSL transport.
The GTK shell stays native and the CEF renderer stays offscreen.

DesktopApp owns the engine and browser stores. Linux supplies device metadata,
home/fullscreen/toast/shutdown callbacks, profile persistence and native input.
All CEF API/MCP requests go through the shared router/server; do not maintain a
second protocol path in that build. Bind the listener to loopback and publish a
profile-scoped readiness capability using the same ownership/session mechanism
as the shared desktop runtime where available. Preserve Avahi LAN discovery only
when its announced address actually reaches the configured listener.

Use a native GTK title strip (52px), active curved tab, fixed gray inactive tabs,
left plus, right window controls, 72px navigation row with 44px URL field, optional
44px favorites row, and a one-pixel 10% contrasting separator. The active tab and
navigation/favorites rows animate together over 220ms toward the rendered page
edge; the title background stays RGB(229,234,243). Sample the existing offscreen
frame's top band, tied to the active tab generation, without a second screenshot.
Keep native entry/completion, keyboard shortcuts, resize and window dragging.
Show account identity, sign-in/cancel/refresh/sign-out using the shared service;
launch OAuth outside the inspectable Kelpie renderer and keep tokens memory-only.

Shutdown stops account admission, cancels/drains account work, gates HTTP requests,
and continues the CEF pump until browser callbacks finish before destroying the
runtime. GTK timers and callback contexts must be removed before stack-owned UI
objects go out of scope. Store writes happen only after successful mutations.

Validate on the Linux host: build with CEF, shared account tests, HTTP/direct MCP,
CLI bridge, tabs/isolated tabs/session restore, native input and completion,
empty favorites, color changes and static inactive tabs; visually inspect over
the existing VNC viewer. Windows and macOS keep their native verification.

## Cross-Provider Review

Completed before Linux implementation: independent Codex source review and an
external Claude Code advisory review, both read-only apart from this record.

### Codex source review

The migration is appropriate, with these concrete requirements established by
the current source before implementation:

- Offscreen frames need an active tab lease, width, height, stride and revision.
  `DesktopCefClient::OnPaint` currently ignores browser identity and paint type
  and replaces one global byte buffer. Reject background-tab paints and handle
  popup surfaces separately; activation must invalidate old pixels, resize and
  request a fresh active view. The GTK painter must use captured dimensions,
  not reinterpret old bytes using the widget's newly allocated width. Color
  sampling must consume the same accepted view frame as page rendering.
- Native input includes keyboard press/release, text composition, modifiers,
  smooth/horizontal scrolling and focus transfer. The current GTK view only
  forwards mouse events, and the engine has no native key/IME entry points.
  Keep GTK shortcuts ahead of page input and use direct owner-thread CEF input,
  never a synchronous CDP wait on the thread that pumps CEF.
- Implement POSIX profile ownership rather than referencing the Windows-only
  helper: acquire `flock` before loading/migrating stores, retain the descriptor,
  use a private profile directory and 0600 no-follow capability files, publish
  with an atomic same-directory rename, and remove readiness only when its
  launch ID matches. Publish only after a live browser and bound HTTP listener.
  Add launcher-compatible readiness and stdio-MCP flags; loopback-only service
  must not be advertised as LAN-reachable through Avahi.
- Restore full session metadata, including stable tab IDs, the next ID, active
  tab, names and partition persistence. Read `session_url.txt` only as a legacy
  migration fallback. Snapshot on the CEF owner thread and persist atomically;
  transient tabs and account credentials must not enter the saved session.
- Intercept GTK close before widget destruction, gate API admission, cancel
  account work, drain both while pumping CEF, then persist and destroy. Retain
  the account service until callbacks finish but destroy it before its borrowed
  bookmark store. Store/remove GLib source IDs and callback contexts explicitly.
  Headless signals should set a signal-safe flag, leaving shutdown to the loop.
- Select the CEF/shared-runtime and no-CEF/legacy sources at build time, with
  exactly one server implementation linked into each build. Remove Linux's
  forced `BUILD_TESTING=OFF`; verify both variants and the shared account tests.
  Linux OAuth must launch a known external browser when Kelpie is the default;
  use an argument vector rather than a shell command. Exercise curl cancellation,
  TLS failures and ETag conflicts with its real platform adapter.

### Claude review and disposition

Claude independently confirmed the offscreen-frame, input, shutdown, profile,
session and loopback-discovery findings above. Accepted additional requirements:

- The no-CEF engine deliberately fails initialization, so retain its existing
  runtime behind one build-time switch. Do not require account curl/OpenSSL
  dependencies in the no-CEF variant. Share only the minimal shell-facing
  interface needed by both variants, rather than cloning the desktop router.
- Wire the CEF pump scheduler to one tracked GLib source and marshal native
  callbacks onto the GTK owner thread. Supply viewport read/resize/reset
  callbacks explicitly; the shared fallback changes only renderer dimensions.
  Cancel queued native calls when shutdown closes admission.
- Extend the CLI browser launcher, whose current launch/readiness branches
  include Windows-only assumptions and a hard-coded Windows platform. Keep
  Linux readiness compatible with the same alias bridge and verify private
  regular-file ownership/mode when consuming its capability on POSIX.
- Preserve the existing Linux `cef-cache` location; explicitly configure its
  root and persistent partitions directory underneath it. Otherwise isolated
  tabs remain in memory and lose state when the application exits. Reuse
  portable session parsing/serialization rather than copying Win32 file APIs.
- OAuth's open-browser callback executes on the account worker. Use a safe
  argument-vector process launch or marshal a GTK-dependent launch to its
  owner. Mark profile-lock and listener descriptors close-on-exec so browser
  child processes cannot keep ownership or callbacks alive after shutdown.
- Curl cancellation must have a verified upper bound, including DNS. Initialize
  curl before concurrent use, check asynchronous resolver support on the target,
  and exercise cancellation and timeout with the real curl adapter. Avoid
  claiming that the progress callback interrupts a blocking resolver.

Advisory findings assessed but not adopted literally: `xdg-open` alone does not
guarantee OAuth leaves Kelpie when Kelpie owns the default browser association;
retain the external-browser requirement. Manually shutting down curl sockets
adds descriptor-ownership races and is not required if the deployed resolver
and total timeout provide bounded cancellation. Moving all Windows profile
code during this Linux change is optional; the required invariant is one clear
POSIX owner with portable metadata and no duplicated session semantics. Use
`mdns = nullptr` for a loopback-only CEF listener instead of reachability probes.

Verification adds two concurrent profile launches, a stale/crashed readiness
record, sign-out and close during blocked account work, two differently colored
tabs with background animation, select popups, resizing during paint, focused
page typing/IME and tab switching, and persistent versus transient partition
restoration. These are acceptance checks for the identified failure modes,
in addition to the build and API checks above.
