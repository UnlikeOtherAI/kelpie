# Linux public alias offscreen launch

The native Linux runtime already accepts --headless and derives its trusted
offscreen mode from that launch flag. The CLI previously had only Windows
--hidden and always launched Linux aliases windowed. That prevented public
alias OSR verification without bypassing owned launch/readiness state.

The minimal CLI change adds browser launch <name> --headless. Both host and
alias must be Linux. Refusal occurs before port allocation,readiness probing,
process creation or running-state mutation. Windows --hidden remains distinct;
mixed flags refuse because no host/alias pair supports both. Linux defaults
remain windowed. This adds no public native authority,allocator or user UI.

Existing profile/readiness/PID/launch-ID/token validation,borrowed existing
instance refusal and supported browser stop cleanup are reused. No running
record/token is hand-edited or copied. Actual native offscreen capabilities
remain the authority; no-CEF or GTK UI support is not inferred from a flag.

Focused Maxis checks:29/29 passed across subcommand-port,browser-readiness,
browser-lifecycle and help/explain tests in3.79s,one worker under hard Windows
JobObject affinity1/Normal,2GiB memory. Fresh free10,884,616KiB. A first harness
invocation failed before tests because cmd.exe parses its quoted /c command
differently; that log is retained. The corrected Node driver ran the same
Vitest command. No app,browser,emulator or CUA ran.

Artifacts:
D:/BuildArtifacts/kelpie/capture-observations-20261104/headless-focused-2.log
and headless-focused-2-policy.json. Full required Maxis checks passed with workspace/testworker1,Node heap2048,
hard JobObject affinity1/Normal and2GiB total: lint44.274s,build24.442s,shared143
and CLI703 tests passed with one existing skip. Whole job122.662s,exit0; fresh
memory samples15,215,276/15,206,284KiB. Logs/policy/phases are in headless-checks/.

The freshly built production CLI on Maxis actually displayed --headless help,
registered a private task-local Linux alias,refused its --headless launch on the
Windows host with PLATFORM_NOT_SUPPORTED/exit5,created no profile/running port,
and removed that alias through the supported command. The report is
headless-checks/public-entry-report.json; no app launched. Actual Linux public
alias OSR flow remains the Linux owner's separate runtime gate.

Linux owner next real supported flow: register fresh owned alias/profile with
exact compiled binary; browser launch --headless; inspect authenticated
readiness and runtime capability projection; public --browser alias HTTP/
direct/generic MCP and CLI script/artifact cases; browser stop; verify exact
owned process/socket/readiness/running record retirement. Do not adopt another
instance or populate state manually. Local GTK Stop/UI remains a separate cell.
