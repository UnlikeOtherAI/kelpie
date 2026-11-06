# Fedora GNOME c42 launch diagnostics

These results are scoped to the Fedora VM, source
`c42fc68d7fdfa01fae0cbe9cda82dc39bd8c4dc2` and owned GTK executable
SHA-256 `6439d5decf10b5a405f123612fa03ea55cb76a5ff3e5825d5f78d54711c2116c`.
They are not evidence for the hosted 455d RPM.

An older CLI launch failed before readiness after 13.028 seconds; its report
contains no stderr, so the cause is unknown. The exact owned unit retired and
the unrelated listener remained present. The report SHA-256 is
`b5ded7c892676302a12f5d418a5fde251626e6f2efcd0e13c20063b4df0a5dc4`.
A prior no-app invocation failed because its working directory was incorrect;
no native test ran in that attempt.

A direct native launch, without that CLI, used diagnostic source
`36d44fe1ee991cfd74fb9db6982235f24c92c028`. The process spawned but did
not publish readiness by 30.096 seconds. Broad sanitized stderr classifications
matched display and sandbox text; they do not establish the failing stage.
No HTTP, MCP or AT-SPI operation was attempted. The owned process required
SIGKILL after timeout, and its private runtime was removed after retirement.
The unit was inactive with MainPID zero and empty cgroup; the unrelated
listener remained present. The sanitized report SHA-256 is
`e82435666f5dd889aad78f04f74ac53c380792f08acf255b33a803c0c535f95e`.
There is no native Stop or physical-pixel pass from these attempts.

Source inspection shows that this CEF-enabled windowed build publishes
readiness only after the GTK canvas is realized and `DesktopApp::Start`
returns successfully. A pre-realization stall, startup stall or startup failure
could therefore leave readiness absent; the retained evidence does not select
among them. The window is created as a plain GTK window rather than through a
GTK application single-instance handoff. The existing GNOME session was local,
Wayland, active and unlocked, with display and session-bus variables present;
those facts do not prove successful GTK or CEF initialization.

## Proposed test-only trace

The source-only diagnostic adds `KELPIE_LINUX_STARTUP_TEST_TRACE`, default
OFF and accepted only with testing, GTK and CEF enabled. An explicitly enabled
test build emits at most 32 fixed startup markers to its captured stderr, with
monotonic timestamps and no page, token, profile or error text. The launcher
keeps raw stderr in bounded memory, validates the fixed ordered prefix and
retains only event names, offsets and a possible-truncation flag. A missing,
malformed or truncated sequence cannot establish that a later event did not
occur. The instrumented executable must be tied to its exact committed source,
CMake options and executable hash; its results are not measurements of the
uninstrumented c42 binary.

The markers separate GTK init, show, canvas realization, attachment,
DesktopApp start and readiness publication. No marker identifies the internal
cause of a failed or stalled DesktopApp start. A future separately authorized
owned GNOME run can locate the last observed boundary, with no focus change or
desktop-wide capture; it does not by itself prove a cause or final visual
acceptance. No native compilation or runtime has yet exercised this trace.

The diagnostic receipt separates `historicalBase` c42 from the exact
`diagnosticBuildSource` and `testSource`. The launcher requires an
independently reviewed bounded manifest with exact source, executable SHA-256,
target and test-only build options, verifies the supplied manifest SHA-256 and
checks the build source is an ancestor of the test checkout. The manifest is
evidence supplied by the build workflow, not proof of its own origin. A
`PUBLISH_RETURNED` marker means only that the publish call returned;
the separate readiness/listener check establishes external readiness.

A source-only hosted build proposal uses the opt-in
`linux_gtk_startup_diagnostic` dispatch on the existing lint-to-Linux
workflow. It selects the pinned Fedora 44 image and existing Fedora dependency
recipe and CEF bootstrap, builds only the `kelpie-linux` target with the
trace enabled, and does not package, install or run the app. The fixed artifact
contains only the executable, diagnostic manifest, verified build options,
runtime asset hashes, ELF dependencies, lock and CEF identity hashes, and
checksums. No source archive, page data or credentials are uploaded. Normal
package/smoke inputs remain independent and default to their existing path.

A later Fedora test may reuse local CEF and runtime assets only after each
required asset matches the hosted hashes and the system-library ABI is checked;
otherwise the exact matching assets must be transferred. This proposed build
has not been dispatched or exercised.

## Instrumented 2447 GNOME run

A separate instrumented build at source
`2447ac8685aedb6da0b7fe8cea89b33ab5d0d274` used historical base c42,
ELF SHA-256
`9eb310b2773d4945b9cb5b39baca68d0ed8bc12e17008f8119448f24a0e9bce9`
and manifest SHA-256
`c9045adec1bd82647802f219a79d8f4f5e430e3cb66d3be6d421e41f65e567a3`.
Before the test, all 70 referenced runtime assets matched the hosted build;
loader relocation and required capture-factory checks passed. The Fedora
GNOME Wayland session was active and unlocked.

The fixed, nontruncated trace prefix was GTK_INIT_ENTER, GTK_INIT_RETURN,
SHOW_ENTER, CANVAS_REALIZE, ATTACH_ENTER and START_ENTER. START_ENTER occurred
85.650578 ms after the first marker. No start-return or publication marker
was observed before the 30.023-second readiness timeout. This localizes the
observed wait inside `DesktopApp::Start` for this instrumented build; it
does not establish its internal cause or prove identical behavior for the
uninstrumented c42 executable. No HTTP, MCP or AT-SPI action was attempted.

The bounded unit exited after 35.212 seconds; the owned child was SIGKILLed
after timeout, its private runtime was removed, the unit was inactive with
MainPID zero and no cgroup, and the unrelated listener remained present.
The sanitized receipt SHA-256 is
`f2abcbaaa97c4218db95620194d79e016ee20ddef4a72ff3e4126b16088e3d7f`.
No native Stop or physical displayed-pixel pass follows from this run.
