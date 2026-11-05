# Linux native automation and capture

Owner: Linux (desktop_backend), Maxis source development only.
Source worktree: D:/Worktrees/kelpie/capture-linux-20261104,
branch codex/capture-linux-20261104, integrated base dc0648e284c46582708b2ea31431de85a9f9946a.
Portable worker prerequisites are integrated and verified separately; they do not
prove Linux native behavior. Assigned bounded Linux test checkout:
 /home/ondre/Projects/kelpie-worktrees/capture-linux-20261104.

The native implementation checkpoint is explicitly unverified before transport
through Git to Fedora. The48 rows below distinguish actual case evidence from remaining gates;
source presence is not a passing result.

## Source inventory and reuse

- apps/linux/src/linux_desktop_app.cpp already builds DesktopApp configuration,
  exact per-launch readiness bearer, CEF offscreen viewport and shutdown lifecycle.
- linux_desktop_actions.cpp routes native browser requests and account-connected
  jobs through the shared desktop MCP/gateway coordinator.
- GtkBrowserView paints the offscreen BGRA frame through Cairo. This is the seam
  for displaying the same numeric overlay that captured media composites.
- apps/linux/CMakeLists.txt has CEF and no-CEF variants plus optional GTK/headless.
  The no-CEF gateway sets browserAvailable:false and must not advertise fake
  screenshots, DOM, input or script capture.
- Linux runtime/RPM/DEB/AppImage scripts package the shared CEF assets. New native
  codec dependencies must be reflected in build inputs and package/runtime lists.
- Windows owner has a shared DesktopScript coordinator, actions, sampling,
  redaction, input/session and owner-bound artifact hooks in
  native/engine-chromium-desktop. Consume its reviewed commits through root.
  Do not copy or fork that runtime into apps/linux.
- The portable capture seam is DesktopScriptCapture::AddFrame(BrowserScreenshot,
  presentation,elapsed,index,stepPNG), then Finish(partial,reason,terminalms).
  Linux supplies OS adapters; canonical schemas/validators and numeric presentation
  stay shared.
- Windows WIC/GDI compositor is platform-bound. Linux draws through its own Cairo
  image adapter using the same shared tap/pointer numeric state, then uses that
  one composition path for display and exports.

## Native adapters to implement

1. Linux capture/output store: exclusive owner-bound files, opaque artifact ids,
   bounded authenticated chunks, hashes/MIME/dimensions/time/provenance, safe
   finalization, cancellation and partial-output recovery.
2. Bounded PNG decode/compose/encode using existing Cairo/CEF facilities; inspect
   dimensions before allocating decompressed frame storage.
3. GIF and MP4 codec adapters with actual PTS/duration, bounded retained frames,
   explicit backpressure/drop accounting and independent decode validation.
   Prefer installed system codecs rather than bundling an unreviewed executable.
   The exact native library/encoder choice must be checked before implementation;
   preserve valid sibling artifacts when one format cannot finalize.
4. GTK recording state/Stop and viewport locking, without unrelated UI.
   Reuse the same composited frame state and numeric presentation for visible and
   exported overlays.
5. Trusted WebMCP launch-origin/encoding settings, default empty, through the
   shared grant/probe/fence seam after common review. No HTTP/model self-grant.
6. Native optional script.sessionId: absent means current authenticated grant and
   pinned tab. A supplied id requires a real existing owner-bound resolver or the
   shared full-preflight SESSION_UNSUPPORTED refusal before any action.
   No parallel native allocator or silent ignore.

## Canonical requirement checklist

Partial rows name their actual Linux case evidence. Shared source or another
platform's test is not a Linux pass.

| ID | Linux implementation/evidence target | Status |
| --- | --- | --- |
| OBS-01 | Native shared value-free snapshot/private canaries | Pending |
| OBS-02 | Scoped/prioritized observation under real bounds | Pending |
| OBS-03 | Text/name/element/metadata limits and truthful truncation | Pending |
| EXT-01 | Scalar extraction with missing/ambiguity/source checks | HTTP90eb products passed; missing/ambiguity cases pending |
| EXT-02 | Nested/repeated deterministic records | Pending |
| EXT-03 | Bounded publisher metadata and JSON-LD allowlist | Pending |
| EXT-04 | Document/source/truncation provenance | Pending |
| RDY-01 | Actual DOM status and unavailable diagnostic facts | Pending |
| RDY-02 | Explicit readiness/hidden/duplicate/failure cases | Pending |
| OWN-01 | Managed backend prerequisite real sessions; native scope not expanded | Portable eee passed; LP c774 one-tab diagnostic; public LP pending |
| OWN-02 | Exact native lease/refs/pins/late callback ownership | Pending |
| WFL-01 | Shared strict v1 validation before admission/action | HTTP90eb six actions passed; malformed cases pending |
| WFL-02 | Typed inputs/secrets without executable interpolation | Pending |
| WFL-03 | Ordered waits/assertions/extractions/outputs | HTTP90eb ordered six actions; extended cases pending |
| WFL-04 | Existing legacy route with no v1 privilege widening | Pending |
| WFL-05 | Unknown mutation stops; one activation; self-recovery | Pending |
| TGT-01 | Unique eligible semantic target | HTTP90eb unique target passed; extended cases pending |
| TGT-02 | Visible hit-tested center | HTTP90eb visible center passed; extended cases pending |
| TGT-03 | Scroll/DPR/zoom/clipped viewport correctness | Pending |
| TGT-04 | Exact object/document/geometry revalidation | Pending |
| TGT-05 | Real input trust matches advertised guarantee | HTTP90eb trusted-coordinate passed; extended cases pending |
| PTR-01 | C/S eased visible trajectory/endpoints | Pending |
| PTR-02 | Numeric display/export correspondence | Pending |
| VIS-01 | Requested marker color/radius/opacity in decoded pixels | Codec red-center units passed; app pixel checker pending |
| VIS-02 | Wobble/fade timeline and clean end state | Pending |
| CAP-01 | Real GIF/MP4/every-step PNG through public script | HTTP90eb GIF/MP4/six PNG passed; recovery pending |
| CAP-02 | GIF loop/frame delays/fixed dimensions | All13 actual GIF frames decoded; extended timing pending |
| CAP-03 | MP4 independent decode/PTS/duration/dimensions | All13 actual MP4 frames/PTS decoded; app limits pending |
| CAP-04 | Step marker captured at intended timestamp | Pending |
| CAP-05 | Document/viewport coherence and resize partial refusal | Pending |
| CAP-06 | Duration/FPS/width/bytes/steps resource preflight | Pending |
| CAP-07 | Bounded encoder backpressure, drop count, real time | Pending |
| CAP-08 | Cancel/failure partial finalization and next run | Pending |
| ART-01 | Separate remote CLI/MCP chunk retrieval | HTTP90eb chunks/hash passed; MCP/CLI pending |
| ART-02 | Same/foreign/revoked owner status/cancel/download | Pending |
| ART-03 | Integer/range/size/id/path refusal without unbounded read | Pending |
| ART-04 | MIME/size/hash/partial/time/document manifest | HTTP90eb manifests passed; partial/failure pending |
| SEC-01 | No synthetic secrets in output/error/log/manifest | Pending |
| SEC-02 | Page instructions/metadata never authority or code | Pending |
| DIF-01 | Same frozen corpus/normalized Linux CEF output | Pending |
| LP-01 | Proven restricted Linux-native worker methods only | Actual1.0.2 diagnostics c774; public admission pending |
| LP-02 | Unsupported dispatch refusal and owned isolation | One context/page limit; single managed session passed; public pending |
| WEB-01 | Native grant plus actual private-world API gate | Pending |
| WEB-02 | Bounded untrusted tools, no grant expansion, unknown fence | Pending |
| DOC-01 | Linux guarantees/limits/API/CLI examples verified | Pending |
| UI-01 | Requested UI only; changed-state evidence/limitations | Pending |
| REL-01 | Root integrated PR/checks/affected version | Root/platform pending |
| REL-02 | Published package/hash/install/runtime verification | Root/platform pending |

## Read-only target inventory, 2026-11-04

Fedora host answered as fedora-maxis, Linux 7.2.9-200.fc44.x86_64.
The assigned test worktree did not exist; it was not created. No package was
installed and no build, server, encoder workload, CUA or desktop input ran.

Node22.23.1, pnpm12.11.2, CMake, Ninja, pkg-config and ffmpeg are present.
Installed ffmpeg-free8.1.3 reports libopenh264, libaom-av1, libsvtav1, GIF and PNG
encoder candidates. This is availability metadata, not a successful encode.
Cairo/GTK development packages are present. giflib/libavcodec/libavformat/
libavutil/libswscale development headers were absent under the queried package
names. Native dependency preparation must be scoped and verified in the assigned
Linux test phase; codec selection is not yet complete.

## Verification and release sequence

1. Finish and integrate backend prerequisite; consume reviewed Windows shared
   coordinator/input/artifact seams; create the exact clean Maxis Linux worktree.
2. Implement Linux OS adapters there with focused source checks. Commit/push source
   before transferring it through Git to the assigned Fedora test checkout.
3. Reserve resources and recheck Maxis/Fedora load before a bounded Linux-specific
   CEF build and no-CEF/headless checks. Preserve the existing sandbox.
4. Run actual native HTTP, direct MCP and production CLI forwarding against one
   exact candidate/profile/port; exercise every main/refusal/cancel/recovery flow.
5. Decode every generated artifact independently and compare frame timing/color/
   marker/document evidence to the event oracle. Retrieve from a separate client.
6. Exercise Linux GNOME/Wayland and RPM install/package behavior where available.
   Computer Use, VNC and custom OS input are off; do not claim controls were
   manually clicked. Use supported own native machine APIs and state UI-evidence
   limitations explicitly.
7. Run bounded actual Lightpanda1.0.2 binary/hash/resource/egress/correctness/cost
   work from lightpanda-verification.md. Never host a persistent development worker.
8. Root owns the integrated PR/release; platform owner supplies exact source,
   package/binary hashes and installed published native flow evidence. No
   independent PR or release is opened by this owner.

## Initial native build, 5 November2026

Source2f5db3c2 was transferred through a SHA-256-verified Git bundle to the
assigned owned Fedora checkout (GitHub SSH credentials were absent; none copied).
Native configuration passed with pinned CEF120.2.7 and GCC16.2.1, GTK3.24.52,
Cairo1.18.6, giflib6.1.3 and GStreamer1.28.8. The existing native frozen
pnpm/shared/generator bootstrap was retained.

The first environment-only npm_config_store_dir was ignored by pnpm12 and used
the existing global store (261 reused,0 downloaded). The corrected explicit
--store-dir wrapper was verified under this task's .native-cache/pnpm-store/v11,
then a supported frozen force install relinked only this checkout's dependencies.
Subsequent configuration uses the private wrapper; no integrity check was bypassed.

The first native build compiled the shared engine and Linux codec sources, then
failed at GTK draw registration: a comma-bearing frame initializer inside a
G_CALLBACK macro argument was split by the preprocessor. Composition now has its
own helper outside the callback. This fixes the cause and separates native
presentation from GTK event registration. Full app/link/tests remain pending.

Official signed dev dependency installation pulled matching Mesa GBM/EGL/GL
updates transitively. DNF reported an existing offline transaction invalidated
by its online transaction. No update queue was manually edited or rescheduled.
The GTK app and both focused test executables then linked at7c959a0b.
Private artifact tests passed:0700/0600 modes, foreign owner/run refusal,
seven-byte chunks reconstruct the PNG, inode replacement refuses access, and
the1024-byte PNG budget retained928 bytes across8 files without an excess file.

The first media run refused in preflight before any browser action. Native
GStreamer diagnostics showed that auto-linking an unconstrained appsrc selected
mp4mux's audio_0 pad, which rejected actual AVC video caps. The fixed pipeline now
constrains H.264 caps before pad selection. This preserves the real codec proof
rather than bypassing negotiation. All-frame media success remains pending.
## Linux sandbox boundary

The prior shared Linux initialization explicitly set no_sandbox=true, so no CEF
app acceptance was attempted under it. Root authorized a Linux-only correction;
Windows bootstrap/false behavior and other platform branches are preserved.

The pinned SDK actually includes Release/chrome-sandbox (0755, ondre-owned,
752152 bytes), contrary to the stale source comment. SHA-256:
35163229e509ebc8b471790203d9d5720842627bc56f18fa90b070c705bb7419.
No helper permissions/ownership were changed and no privileged helper installed.
Fedora's unprivileged user+PID+network namespace probe succeeded; SELinux stayed
Enforcing, max_user_namespaces47584. No sysctl or security policy was changed.

[Chromium120 sandbox documentation](https://raw.githubusercontent.com/chromium/chromium/120.0.6099.234/docs/linux/sandboxing.md)
describes supported namespaces as the default modern alternative to a setuid
helper. The SDK cef_types.h documents no_sandbox as the disabling setting.
Linux now leaves that setting false and lets Chromium fail closed when no usable
sandbox exists. This is source/kernel prerequisite evidence, not yet proof of a
sandboxed renderer. Actual child namespace/seccomp/flags and native API flows
remain pending.
## Startup diagnostics after sandbox correction

The2657 native smoke exited before readiness. A bounded GDB run identified
Chromium's ProcessSingleton socket setup CHECK. The task's deeply nested TMPDIR
can exceed Linux AF_UNIX's108-byte pathname field; a short0700 owned runtime
directory advances startup beyond that check without deleting the failed profile.
The permanent smoke now creates short private runtime scratch and can reuse its
preserved synthetic profile through KELPIE_TEST_PROFILE. Build caches remain
inside the assigned test checkout. Early child exit is reported immediately.

That run exposed a separate headless defect: the exact stack entered Ozone's
X11CursorFactory and failed its property cache because the SSH session has no X
display. Windowless rendering alone does not select a display backend.
[Chromium120 Ozone documentation](https://raw.githubusercontent.com/chromium/chromium/120.0.6099.234/docs/ozone_overview.md)
documents Linux's default X11 backend and explicit headless backend.
The Linux-only CEF command-line hook now selects ozone-platform=headless for the
existing headless launch flag. Windows behavior is preserved. Actual startup,
renderer sandbox and HTTP/MCP success remain pending this source checkpoint.

At570d2c5e, the real system codecs passed independent all-frame decoding:
GIF5 frames/500ms/1691 bytes; H.264 MP4 5 frames/500ms/1487 bytes, matching
red overlay centers and100ms timestamps. The2200-byte GIF budget retained a
fully decodable10-frame/2171-byte prefix. These codec tests do not prove native
capture, marker ACK, UI Stop, cancellation or final-container recovery.

The c1e13a7c app rebuild passed. The same preserved profile reached authenticated
HTTP readiness with headless Ozone and namespace sandbox enabled. Initial
attestation timed out because Chromium rewrites /proc/cmdline into a single
space-delimited argument. A bounded owned-process probe found two actual
renderers: NoNewPrivs1, Seccomp2, nested NSpid counts3. The smoke now recognizes
that real process shape and waits for loaded fixture text plus actual PNG bytes,
rather than treating a configured tab URL as navigation proof. Full namespace
comparison, MCP/shutdown and script capture remain pending the revised corpus.

## Movie frame admission candidate

Root's78e049d6 integration includes the shared c852787f frame-ACK interface.
The Linux adapter now tags sampled visible markers by their creator action and
document, keeps at most18 pending tags, and acknowledges only the minimum
actual retained source prefix of all requested movie writers. GIF counts a
complete compressed image, not pending BGRA. H.264 counts a retained complete
AVC access unit containing a VCL NAL, not raw input or SPS/PPS-only buffers.
Final mux failure still fails the run and marks retained artifacts partial.
The compositor uses the shared clamped progress helper so a marker deliberately
held before its fade clock is visible at progress0. New pixel/prefix/MP4-budget
tests are source-complete and await the bounded native run.

Installed Fedora package provenance was captured separately from selected plugin
license metadata. Runtime GStreamer plugins report LGPL/BSD; the Fedora
gstreamer1-plugins-good RPM carries a mixed license expression including GPL
components. No blanket LGPL claim is made for the package or machine. Selected
factory binaries and installed RPM signatures/hashes are recorded in the
private codec-provenance artifact; no codec binary is bundled or copied into source.

## Actual headless native smoke

Binary90eb6830 SHA-256
a33a42ccdb55a5a19514ab6996ba5b643aa8f67cbfda809b0ade71812549ee35,
exercised with harness63423c7f on Fedora44, passed loaded fixture snapshot,
actual viewport PNG, authenticated native HTTP, MCP initialize/catalogue and
authorized shutdown with readiness removal. Two owned renderer children had
NoNewPrivs1, Seccomp2, nested NSpid count3 and user/network/PID namespaces
different from the browser, with no sandbox-disabling flags. The same failed
synthetic profile recovered without state edits. Native MCP reports its existing
serverInfo{name:kelpie,version:1}; no release-version equivalence is inferred.

At90eb6830, focused media/artifact tests passed, including held marker pixels,
dual-writer committed prefix0..4 before finalization and5 afterwards, all-frame
GIF/MP4 decode, private artifact admission, and a90000-byte MP4 recording limit
that retained/finalized a five-frame1487-byte decodable prefix.

The Linux launcher now reuses the integrated Windows public capture corpus via
the actual Linux executable, authenticated HTTP/MCP and artifact chunks; no
parallel workflow implementation is introduced. It records exact executable
hash/source, preserves synthetic profiles and shuts down its owned app.
Initial direct-HTTP continuous capture is next; discovery expansion and other
script/cancellation/cost/package claims remain pending actual results.

## First public capture result and harness recovery

The994f8a45 launcher exercised compiled90eb6830 through the shared continuous
HTTP corpus: six actions passed, the unique button received trusted input at
visible center(119,137), extraction returned Green tea/Black tea, and eight
GIF/MP4/PNG artifacts were downloaded through authenticated chunks and hashed.
The app exited cleanly and removed readiness. Independent system FFmpeg/FFprobe
decoding passed all eight artifacts: each movie had13 frames with strictly
increasing timestamps through about3.533s; all six step PNGs decoded.

The launcher then remained alive because the reused test command helper's
Promise.race deadline timer was not cleared after child exit. Its outer bounded
command therefore failed despite completed app checks; that failed-run history
is preserved. The Linux launcher now owns and clears its child/deadline timers,
with explicit signal cancellation and app cleanup. This changes test lifecycle,
not browser state. The next run must prove clean launcher exit.

A separate decoded-pixel check now crops the actual trusted target's coordinates
and checks the requested red marker, its center and disappearance in final movie
frames. Its source is complete; pixel success remains pending actual execution.

## Finalization failure candidate and release graph

The next native checkpoint refuses a nominally successful capture missing any
requested artifact family. A requested movie that finalizes empty is a failure.
Permanent focused tests inject a collision after both writers have retained a
picture, verify the GIF sibling remains decodable, and reject empty movie output.
The public Linux supplement injects that collision only in its own0700 synthetic
capture directory after observing the trusted click (therefore after movie ACK),
then checks failed run/status, partial downloadable GIF and next-run recovery.
These new failure assertions are source-complete, not yet executed.

Root-approved release source15d2ae3c adds official distro native capture headers/
plugins, actual factory and native codec-test gates, explicit linked GIF ABI,
system-codec provenance and truthful AppImage requirements. Fedora44 replaces
the EOL40 build row; Ubuntu22 remains. Distro-container build/package execution
is pending. No codec binary, third-party repository or privileged helper is added.

## Trusted runtime projection source checkpoint

Root881f066b includes the common tested runtime_mode projection. The Linux
native host now selects offscreen only from its existing trusted headless launch
flag, otherwise windowed, and propagates the same value into outbound authorized
MCP configuration. There is no request-body setter. Unknown modes fail closed;
no-CEF has no callable script routes. This is source wiring, not a shipping
native relink/MCP/CLI success claim. Those actual gates remain pending.

The independent actual Lightpanda phase now includes seven passing production stdio cases; see
lightpanda-analysis.md for all four revisions, failed expectations and measured
limits. No public reader/WebMCP/pixel profile was enabled.

The finalization supplement now observes its in-flight public play Promise
immediately through the common observeInFlight helper, preserving the original
rejection for the main assertion. Cleanup awaits it for at most5 seconds before
the launcher's owned app shutdown. Four early-rejection/cleanup regressions
passed on Maxis using the common helper. The real Linux fault run remains
pending the native slot; no product state was edited to manufacture recovery.

## Privacy discard and identity-safe cleanup candidate

The Linux adapter now wires root df3197ff's private discard(run, owner) callback.
Late inferred-sensitive capture refusal and output-redaction failure revoke all
published artifacts for that exact run and owner; the shared privacy latch
survives later error replacement. Ordinary failure/abort still retains safe
partial media. This clarifies the previously ambiguous artifact policy; no
Linux runtime leak was reproduced or claimed by the source change.

The store revokes read grants before deletion, checks the original device/inode,
and preserves replacement files/symlinks and other owners/runs. A denied unlink
retains revoked cleanup ownership for normal retry, while storage admission
counts that retained data against its existing bounds. Destruction/expiry use
the same identity check. The existing replacement regression now requires the
replacement to survive, rather than treating a path as deletion authority.

Capture cleanup now tracks only identities of successfully created outputs.
It no longer enumerates and deletes unrelated entries in the private directory.
The synthetic post-ACK finalization collision must retain its exact inode and
bytes while the run returns failed status, partial GIF and successful recovery.
Focused C++ tests cover owner/run scope, replaced inodes/symlinks, denied deletion,
revoked access and cleanup retry. These source tests are not yet compiled.

Node syntax checks and Git whitespace checks passed on Maxis. Native C++ build,
all-frame decode and real HTTP/MCP/CLI/GTK replay remain pending the next allocated
Linux slot; this checkpoint is explicitly an unverified native implementation.

## Large artifact transport acceptance candidate

The real Linux launcher now invokes the common b9a458c0 artifact verifier using
its already-owned authenticated socket and deterministic 512-pixel noise page.
The planned native PNG must exceed 262 KiB. HTTP, the direct named MCP tool and
the actual generic kelpie_extension wrapper must reconstruct identical bytes,
hash, length, offsets, EOF and MIME. Callback fetches honor the supplied abort
signal; the helper creates no app or authority. The fixture closes in finally.
Node syntax/whitespace checks passed; real native transport execution is pending.

## Compiled privacy/identity checkpoint, 5 November 2026

Exact integrated source 3001aa4171030b241657df9e3da4e247045fc5e1 built the Linux
app, linux_script_media_test and linux_script_artifact_test on Fedora 44. Both
focused tests passed (2/2, 0.26 seconds), including scope/replacement revocation,
denied-unlink cleanup retry, decoded GIF/MP4 retained prefixes, budgets and
finalization failure. Compiler diagnostics contained no warning/error matches.
This is native compilation/unit evidence; the new browser-level privacy,
finalization/profile/HTTP/MCP/CLI and GTK flows are still pending.

Native executable SHA-256:
efd1b73dc8bcb557344cefd4689b327dcd1870d6d32d1c3d458f73f0a0f070f0.
Generated browser contract SHA-256:
a4c274fedfa14433baebcdb0b34ade0f7b19fec1e92ddb9215482d87138dd831.
The authoritative configure graph validated the unchanged frozen lock/cache
(33 ms, no resolution/download), rebuilt shared TypeScript and regenerated the
contract. Existing pinned CEF/cache assets were reused; no CEF/bootstrap install
or general portable suite ran in Fedora.

Actual unit limits were one CPU/CPUWeight 1, 2 GiB, 256 tasks, 15 minutes,
NoNewPrivileges and loopback-only egress. A process sample showed one compiler.
Build cost was 3 minutes 55.330 seconds wall, 3 minutes 50.088 seconds CPU and
727 MiB peak; no memory-limit increase was needed. The initial orchestration
wrapper stripped embedded shell quotes and exited 2 at its CTest expression
after successful compilation. That failure is retained. CTest then ran directly
in a separate 60-second unit under the same limits and passed. Both units were
collected, their cgroups absent, and no compiler/app/LP process remained.
Maxis free memory was 14.88 GiB at start and 18.64 GiB after teardown.

Evidence:
D:/BuildArtifacts/kelpie/capture-desktop-20261104/linux-native/native-3001-incremental,
including build.log, ctest.log, unit journals/teardown, cgroup-limits.txt,
processes.txt, generated/final hashes and actual runtime/package provenance.
The separate common visual-viewport correction must land and relink before
claiming the final geometry case; this build does not pre-empt that gate.

## Actual offscreen replay at 3001aa41

The actual native app replay completed 32 of 36 canonical checks on Fedora,
then exited cleanly and removed readiness. Privacy refusal, earlier-output
redaction, discarded artifact manifests, status, recovery, foreign grants,
direct/generic MCP, native input and navigation-marker cases passed. Four
failures remain explicit: readonly-focus uncertainty, moving-target recovery,
the retained-byte-budget expectation and replacement during movie-evidence hold.
Their cause is not yet established; no canonical assertion was weakened.

All 27 downloaded PNG/GIF/MP4 artifacts independently decoded every frame with
matching dimensions/counts and increasing timestamps. OSR cost was 61.460 seconds
wall, 16.979 seconds CPU, 334.7 MiB peak; decode cost was 8.048 seconds wall,
7.779 seconds CPU and 43.4 MiB peak under the same one-CPU/resource/egress policy.
The OSR unit exited 1 from the failed assertions. Its app/readiness and both
unit cgroups were cleaned; no compiler/app/LP/decoder remained.

The wrapper previously asserted the canonical subprocess exit before independent
protocol/finalization supplements, preventing those facts from being collected.
It now runs them independently and still fails overall on canonical/supplement
failure. An optional four-case diagnostic records actual result codes, uncertainty,
read-only/input state, moving-target hit/recovery, encoded byte sizes and page
replacement timing. It does not replace acceptance or enable a capability.
Node syntax and whitespace checks passed; that diagnostic replay is pending.

The first independent supplement replay verified an 802,134-byte native PNG over
HTTP, direct MCP and generic MCP: four chunks per transport, identical SHA-256
f4898af43ab2b72f788179b484855839fa740b8e0102792a64a4b6324f430ef7.
Its finalization/readonly/moving probes exposed a harness assumption: semantic
native refusals use HTTP 400 (DesktopRouter::StatusForResponse), while these
helpers required every response to be HTTP 200. They now parse an HTTP 400 only
when it contains success:false and a structured error code; other non-200
statuses still fail. No production response or acceptance assertion changed.
The byte-budget probe returned a complete 64,751-byte, ten-frame GIF below its
150,000-byte limit, so that particular fixture did not exercise overflow.
Replacement/click times were observed, but initial target-resolution timing was
not; no unsafe identity conclusion follows yet. The replay's failing status,
227.6 MiB peak and clean app/readiness teardown remain in its evidence.

The corrected independent replay (native 3001aa41, test source 9b79b91e) passed
the three-transport PNG reconstruction and the post-ACK finalization fault:
CAPTURE_FINALIZE_FAILED, failed terminal status, one downloadable partial GIF,
unchanged collision file and next-run recovery. The app/readiness retired.
Readonly diagnostics showed TARGET_MOVED with mayHaveCompleted:true, no input
events and an unchanged empty control. Moving-target setup was offscreen after
same-URL scroll restoration (TARGET_NOT_FOUND before any action), rather than
a completed click on a stale moving target. These facts inform fixture fixes;
the first 32/36 result remains retained.

A separate durable driver now uses the actual packaged CLI to register a fresh
Linux alias, launch with --headless, verify exact executable/PID/start ticks and
readiness, run the existing observation and alias MCP/recipe/secret cases, then
stop through the public alias command. It never writes running records or copies
grants. The checked private package is source2c4b0fb8, SHA-256
ef4b2c77954ab4120331c88dc567b8c2b6b140dac67387ae7b26caf230e8a6b9;
it is not a newly published release. Driver syntax passed; actual alias replay
is the next bounded gate.

The first packaged --headless alias replay passed all five public launch/MCP/
recipe/secret cases and all ten observation cases (native3001, package2c4).
Public stop removed readiness and its running record; service cost was16.626s
wall/11.094s CPU/403.4MiB. It did not observe natural process/socket retirement
before unit exit, so that stronger cleanup claim is deliberately unmade.
The driver now waits up to8 seconds for the exact PID/start-ticks identity to
disappear or recycle, checks the credential-free socket refuses connection, then
checks readiness/running absence before exiting its unit. It also explicitly
requires the offscreen catalogue to advertise the mutating play-script schema.
Readiness format version1 is labelled separately from actual device app version
and native MCP serverInfo. These strengthened assertions await their replay.

## Durable fixture corrections prepared

Windows ownership explicitly delegated the portable capture-corpus test hunks
in this Linux worktree. Fixture navigation now performs an explicit public
scroll reset after same-URL reload; product navigation behavior is unchanged.
Focus-change checks keep uncertainty/no-input/no-edit and record the actual
enumerated safe refusal reason. The GIF budget case uses the fixed 512-pixel
RGB-noise asset, expanded to cover the native capture, with a 512 KiB cap and
unchanged partial/recovery/sum-within-cap assertions. This forces encoder
pressure instead of assuming a mostly-white page exceeds an estimated budget.

The unsound 300 ms replacement timer is replaced by deterministic whole-target
replacement on trusted pointerdown after movie ACK. It requires uncertainty,
observed trusted pointerdown, no click/navigation and recovery. The distinct
pre-input requirement has its own whitebox critical-PNG/SSE supplement below;
the two phases are not conflated. Node syntax/whitespace checks passed. Real
replay of these corrected cases is still pending; earlier failures remain.

The before-input replacement supplement uses whitebox coordination explicitly:
only the new owned0700 capture directory and its complete step-0.png are read.
That critical pre-input sample proves target resolution/presentation before a
fixed SSE command clones the target. Renderer mutation events must precede any
pointerdown; a lost race fails setup rather than being called a product defect.
The saved native PNG is independently decoded for the requested red marker.
The public result must refuse with no pointerdown/click/navigation, partial
artifacts remain downloadable/hashed, and a fresh run must recover.
No product API, arbitrary page command or longer timing guess is added.
The fixture command/cleanup test passed on Maxis (1/1,178ms total); module syntax
checks passed. Real native barrier execution is pending the next exact replay.

The corrected full replay passed all36 canonical cases plus protocol and
finalization supplements on native3001/test9a69c8dc. The whitebox pre-input
barrier also passed: native critical PNG had439 red pixels, SHA-256
bee3f065ba3e60b2a429d3dc6461ce915d5e68631c6f1831ba7686cec70bf633;
SSE replacement acknowledged at863.8ms, then STALE_TARGET with definite
noncompletion, zero pointerdown/click, no navigation, three partial formats and
recovery. App/readiness cleanup completed. Unit totals:90.485s wall/19.885s CPU/
361.4MiB peak. All prior failing attempts remain retained.

The stronger packaged alias replay (driverbd431f62) passed5 public cases and
10 observations, positively advertised play-script in the actual offscreen
catalogue, and observed natural exact-process absence before unit exit
(0.51ms probe), socket refusal and readiness/running absence. Device app version
was0.1.15; readiness format1 and native MCP serverInfo version1 are distinct.
Unit totals:16.267s wall/10.704s CPU/407MiB. No manual kill or state editing
established those results.

A durable independent verifier now combines canonical, finalization, pre-input
and large-PNG artifacts, decodes every frame and checks dimensions/counts/times,
then checks the completed continuous run's marker center and fade. Its source
syntax passed; this combined decoding/pixel pass is next, not yet claimed.

## GTK Stop acceptance entry point

`tests/linux/run-native-alias-acceptance.mjs <binary> <packaged-cli> <new-output-directory> windowed` uses the regular CLI registration, launch, MCP/recipe and stop flows. It additionally invokes the existing native `Stop script` GTK button through standard AT-SPI `Action.DoAction`. The helper pins the executable hash, process owner and `/proc` start ticks, selects only accessibility connections owned by that exact PID, and excludes embedded document subtrees. It requires one visible, showing and enabled native button before invoking its single standard action. It sends no focus, keyboard or pointer input and does not inspect another application's UI.

The runtime gate requires the existing unlocked GNOME Wayland session, successful abort/partial artifacts and recovery, followed by public CLI stop and natural process/socket/readiness retirement before the resource unit exits. Accessibility metadata is not compositor or displayed-pixel proof. At this source checkpoint the new GTK gate has only JavaScript syntax/self-review checks; actual GTK results are pending the bounded Fedora run.

## Actual GTK Stop and public windowed flow

Fedora GNOME Wayland, native `3001aa4171030b241657df9e3da4e247045fc5e1` (SHA-256 `efd1b73dc8bcb557344cefd4689b327dcd1870d6d32d1c3d458f73f0a0f070f0`), test `76d4d1c04dc6802c526a3543ca6498c55e5546d4`, checked packaged CLI `2c4b0fb8`: six public windowed alias/MCP/recipe/Stop checks and ten observations passed. The exact owned GTK PID/start ticks exposed one visible, showing and enabled native Stop button; its standard AT-SPI `click` action returned true. The run reported `SCRIPT_STOPPED`, terminal `aborted`/`runSuccess:false`, three partial formats, one trusted click only, and successful next-run recovery. Public CLI stop retired the exact process before the unit ended; socket refused connections and readiness/running records disappeared. This is native accessibility evidence, not a compositor screenshot or displayed overlay pixel claim.

Unit `kelpie-linux-gtk-3001-1793857432`: one CPU quota/low weight, 2 GiB, 256 tasks, no-new-privileges, loopback-only egress, 300-second limit; actual 28.928 seconds wall, 27.779 CPU seconds, 421.4 MiB peak. Unit inactive, MainPID zero and cgroup absent after completion. Receipts are under the owned Fedora `.native-artifacts/gtk-windowed-3001` directory. Independent GTK media decode is pending.

The preceding corrected OSR replay independently decoded all 35 retained artifacts (102 frames). Its stricter continuous-marker center oracle failed; that failure remains open. The oracle now persists per-frame expected/observed centers and violations before failing, retaining the original four-pixel tolerance and red-pixel threshold. No visual-center/fade success follows from codec decode alone.
