# Bounded Lightpanda Linux verification

Status: prepared, not run. The coordinator must assign the exact committed source,
owned Fedora test worktree and resource slot before execution. Fedora is a bounded
Linux-native test target, not a development host or ongoing worker service.

## Inputs and ownership

- Source: a pushed desktop/backend checkpoint containing lifecycle corrections,
  canonical public worker wiring and production stdio corpus, integrated by root.
  No uncommitted source is copied to Fedora.
- Proposed test path: an explicitly assigned worktree under
  /home/ondre/Projects/kelpie-worktrees/capture-linux-20261104. Do not create/reuse it until root gives
  the exact path and branch and verifies ownership/status.
- Executable: upstream stable 1.0.2, source commit
  c5f7bb29b127040c899d4e181b5709f76fc71a6f.
- Asset: lightpanda-x86_64-linux, expected 76,408,136 bytes and SHA-256
  ae7d01d261efb9e480e18ce3424533332883863bcf70b12a4321b5733f37e19e.
  Verify downloaded bytes, executable version and --help before accepting it.
- Download endpoint:
  https://github.com/lightpanda-io/browser/releases/download/1.0.2/lightpanda-x86_64-linux
  (the asset digest was obtained from the exact release API, not moving nightly).
- Stage executable/artifacts only in task-owned ignored scratch. Never commit or
  bundle it, copy AGPL source, install WSL or change native Kelpie engines.

## Resource and network preflight

Check Maxis CPU/free memory and existing reservations first, then Fedora's memory,
CPU and active test processes. One bounded Linux worker process at a time; no
concurrent Windows full app build. Keep total worker/test memory within 2 GiB,
CPU within one core and the whole phase below 120 seconds per corpus run.

Require an operator-enforced transient Linux process/egress boundary before
declaring the restricted worker policy exercised. A possible root-reviewed
implementation is a transient systemd service running as ondre with MemoryMax,
CPUQuota, TasksMax, RuntimeMaxSec and IPAddressDeny=any / IPAddressAllow=localhost.
Probe actual cgroup/BPF and noninteractive sudo support first. Do not claim these
controls worked merely because systemd accepted a command line.

Node fixture, client and Lightpanda must use dedicated loopback ports and synthetic
data only. No human browser profiles, auth cookies, UOA identity records or network
credentials are imported. Telemetry/core-dump environment controls can be set as
documented upstream, but they do not replace an enforced egress boundary.

If required Linux controls or credentials are unavailable, report that concrete
limitation to root. Do not disable CORS/TLS validation, change global security
settings or silently downgrade the declaration to an unenforced sandbox.

## Bounded corpus sequence

1. Inspect Git status on source and target, fetch the exact pushed branch and
   create/switch only the assigned clean test worktree. Record git rev-parse HEAD.
   Use the already prepared portable bundle where practical; dependency/runtime
   preparation is bounded test setup, not native development/compilation.
2. Verify the actual 1.0.2 binary size/hash/version and supported serve arguments.
   Record OS, architecture, Node, Playwright, binary and source revisions.
3. Start the exact external process on an owned loopback port under the confirmed
   resource/egress unit. Start a temporary deterministic fixture in the same allowed
   boundary. No normal application service is hosted in Fedora.
4. Use the supported connectOverCDP interface with fresh contexts/pages, not a
   model-supplied endpoint or upstream unrestricted MCP tool catalogue.
5. Run owned-tab/navigation/title/URL and context/cookie/storage isolation checks.
   Exercise closed/foreign/expired handles and clean shutdown without terminating
   another browser. A failure refuses that capability; no compatibility fallback.
6. Run the fixed Kelpie public-observation functions against the frozen corpus,
   including scoped/prioritized snapshots, extraction/provenance, input/textarea/
   editable and referenced-label omission, hidden/inherited-hidden content,
   metadata, truncation, diagnostics and readiness. Check independent expected
   fixture facts rather than self-consistency between two shared-reader calls.
7. Keep text-layout image behavior separate. Canonical screenshot, geometry,
   pointer, tap effect, GIF/video and native UI claims must refuse. Never compare
   a text-layout PNG with rendered Chromium pixels.
8. Probe the real WebMCP API shape and exact supported argument encoding without
   automatically invoking a tool to guess it. If available, run explicit grant,
   discovery/call, mutation-hint refusal, toolchange/document invalidation and
   bounded output/uncertain-completion cases. Unsupported API is explicit evidence,
   not a polyfill pass.
9. Only after compatibility passes, add those exact candidate methods to the
   restricted adapter's operator-verified profile and run the public production
   worker stdio surface. Do not advertise methods simply because CDP implements a
   similarly named command.
10. Collect absolute task wall time, process-tree peak RSS/CPU time, task success,
    request/tool count and response bytes. Preserve failures in the denominator.
    Separate process startup from warm task execution.
11. Shut down through owned session/context/process controls, retain sanitized
    evidence and failure reports, then confirm the exact transient unit and owned
    processes/ports are gone. Do not hand-edit product state or retry an uncertain
    mutation to turn a failure into a pass.

## Differential cost scope

Use an existing verified Chromium Linux executable on the same Fedora host if
available, with matching fixture, concurrency, timeout, adapter path and sandbox
policy. Do not install/download a browser or start additional native workloads
without the coordinator's next bounded resource assignment.

If no comparable same-host Chromium is available, report LP absolute cost and
correctness only. A Windows/Maxis Chromium result can establish independent fixture
expectations, but is not a valid engine speed/memory ratio for the Fedora LP run.
No upstream marketing benchmark is reproduced by assertion.

## Required report

Retain a machine-readable report and concise ledger entry containing:

- Exact source/binary hashes and runtime versions, operator flags and confirmed
  resource/network controls.
- Every attempted task, independent expected result, actual result, refusal/
  uncertainty status and safe artifact path.
- Candidate methods admitted and excluded, with the binary/corpus scope.
- Cold/warm cost samples and repetition count; no silent omission of failed cases.
- Existing Chromium comparison environment or an explicit incomparable/pending row.
- Verified teardown of the exact owned test resources.

A successful protocol handshake, source inspection or mocked test is not a
completed LP compatibility result. No real LP task or performance result is
claimed by this plan.

The candidate Linux IP controls and their unsupported-kernel caveat are documented by [systemd.resource-control](https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html#IPAddressAllow=ADDRESS[/PREFIXLENGTH]%E2%80%A6). This plan requires an actual enforcement probe and does not treat unit acceptance as proof.

## Actual boundary probe, 5 November2026

Root assigned the existing owned Fedora checkout
/home/ondre/Projects/kelpie-worktrees/capture-linux-20261104. Exact probe source:
6fb0091aa9379e89ff0071fac2c34337032ba91f. Lightpanda itself has not run.

Fedora systemd259.9 has cgroupv2/BPF support. The unfiltered documentation-address
UDP baseline completed; the same send returned EPERM inside the restricted
transient service, while its own TCP loopback handshake completed. Kernel
cgroup files reported memory.max2147483648, cpu.max100000/100000 and pids.max64.
The unit used operator User=ondre, CPUWeight1, NoNewPrivileges=yes,
IPAddressDeny=any, IPAddressAllow=localhost, RuntimeMaxSec8 and control-group
cleanup. These are resource/packet-egress controls, not a claim of a complete
filesystem or local-service isolation boundary.

Actual successful service runtime was266ms, CPU201ms and peak14.7MiB.
It exited0 and the collected unit was not-found/inactive/MainPID0. No LP,
browser or native compiler ran during the probe. The original pipe transport
failed before service creation; manager-opened append stdout failed209 before
execution. Default journal transport worked without policy changes. Failed
transport evidence is preserved rather than counted as enforcement success.

Sanitized artifacts are retained on Maxis at
D:/BuildArtifacts/kelpie/capture-desktop-20261104/linux-boundary, notably
worker-boundary-journal-report.txt, worker-boundary-journal-unit.txt and
worker-boundary-baseline.json. Future corpus execution must use the verified
journal transport, retain the exact unit identity and recheck teardown. Runtime
execution remains subject to the coordinator's functional-workload slot.
