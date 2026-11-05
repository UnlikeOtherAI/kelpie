# Common CLI verification

Owner: common-contracts agent, isolated Maxis worktree
D:/Worktrees/kelpie/capture-observations-20261104. Computer Use remains OFF.

## Host secrets and explicit Windows hidden launch

SEC-01: host result redaction matches URI/form percent-triplet hex digits in either
case while retaining ordinary/raw case sensitivity. Synthetic Aa b+! and
token%2FValue vectors mirror the common native matcher. Actual native secret
entry/output flow remains a platform acceptance requirement.

DOC-01/OWN-02: browser launch accepts operator --hidden only for a Windows alias
on a Windows host, before allocating a port or spawning. It sets windowsHide:true
through the supported process API. The existing profile/readiness/PID/launch-ID
flow remains; default options remain detached:true,stdio:ignore. Hidden launch
does not advertise a headless backend. Unsupported host/alias combinations refuse.

Maxis checks: recursive lint/build passed; shared131 tests; full CLI685 passed,
1 skipped. Focused CLI secret/launch tests26 passed. Full help test initially
expected obsolete macOS-only text; its assertion now verifies hidden-launch
restrictions and the full CLI suite passed afterward. That test was separately
linted after editing. Commands/logs are recorded in observations.md COMMON-11.

Manual machine interface: built CLI browser launch --help displays --hidden and
its Windows-host restriction. Actual normal/hidden launch, verified readiness and
orderly stop require the Windows owner's supported alias flow with the packaged
client. Those outcomes are not claimed from mocks or help output.
