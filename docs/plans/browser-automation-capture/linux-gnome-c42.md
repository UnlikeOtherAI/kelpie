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

## Instrumented 0732 GNOME run

A separately instrumented build at source
`0732d2ca8baf43130ea1c838afe7b38347f28179` used historical base c42,
ELF SHA-256
`cf23a2f1da2e335f03c001e17fa58d3d736e982d80851695f6f97e0de718df0c`
and manifest SHA-256
`4d692268ef3ab5673aad76d3177e3a100a5959e86b29ec36709d5cecd32ff9eb`.
All 70 referenced runtime assets matched the hosted build; the loader
relocation check and six required capture-factory checks passed before the
Fedora GNOME Wayland test.

The valid, nontruncated trace reached CEF_INIT_OK at 158.423309 ms and
FIRST_BROWSER_ENTER at 158.463685 ms after its first marker. No first-browser
return marker was observed before the 30.091-second readiness timeout. The
earliest observed unreturned call boundary is
`CefBrowserHost::CreateBrowserSync`; this does not establish its internal
cause or prove the behavior of uninstrumented c42. No HTTP, MCP or AT-SPI
operation was attempted.

The owned child was SIGKILLed after timeout, its private runtime was removed,
the unit was inactive with MainPID zero and no cgroup, and the unrelated
listener remained present. The bounded unit ran 35.255 seconds. Sanitized
receipt SHA-256:
`1e231140c7c22efdec40e39ab2dbe4428dc9d24bfcf80b65dd9fe81b791610da`.
No native Stop or physical displayed-pixel pass follows from this run.

## Same-binary headless control

A separate no-display headless control used the same 0732 diagnostic ELF
(`cf23a2f1da2e335f03c001e17fa58d3d736e982d80851695f6f97e0de718df0c`),
manifest (`4d692268ef3ab5673aad76d3177e3a100a5959e86b29ec36709d5cecd32ff9eb`)
and test harness source
`7ea903315e1a8b09015c56add648fd8311534a7d`. All 70 referenced runtime
assets matched, and loader and required capture-factory checks passed.

The nontruncated trace reached START_ENTER, ENGINE_ENTER and CEF_INIT_ENTER,
then the owned process exited with SIGTRAP after 712 ms, before a CEF init
return or browser creation. No readiness, HTTP, MCP or acknowledged public
close was reached. The owned unit retired, its private runtime was removed,
and the unrelated listener remained present. Sanitized receipt SHA-256:
`3b4ef6828114163bcaad78bd79caaad8990255b7fc73dcc11c843cd69f6ad665`.

This is a failed control, not a headless pass or a diagnosis of the GNOME
wait. The native `--headless` path selects Ozone headless; the test launcher
removed display and session-bus references. More than GTK context therefore
differs between the two attempts.

## Instrumented 720 GNOME run

A separate GNOME Wayland diagnostic used source
`72003c1502da153dbab6305c63ba214e536d6213`, ELF SHA-256
`3671d816e5c87282300d1383a8d3184fa6df3ecbbb8a0daeded9938a76007251`
and manifest SHA-256
`712999bce1e2d6e1c04524be6441acac3d891a152d7b36c760c355ad890e5780`.
All 70 referenced runtime assets matched; relocation and required
capture-factory checks passed before launch.

The valid nontruncated core prefix reached FIRST_BROWSER_ENTER, with no return
marker before the 30.033-second readiness timeout. The separately bounded
auxiliary trace observed SCHEDULE_FIRST 55.927546 ms and CONTEXT_INITIALIZED
1.235540 ms before FIRST_BROWSER_ENTER. GTK_PUMP_FIRST was not observed;
a missing marker does not prove callback absence or establish a cause. No
HTTP, MCP or AT-SPI action was attempted.

The owned child was SIGKILLed after timeout, its private runtime was removed,
the unit was inactive with MainPID zero and no cgroup, and the unrelated
listener remained present. The unit ran 35.218 seconds. Sanitized receipt
SHA-256:
`47e8555724c309cdbe7ee092b38b71466752093392cc87c4b89fc1d109c8efc1`.
No native Stop or physical displayed-pixel pass follows from this run.
