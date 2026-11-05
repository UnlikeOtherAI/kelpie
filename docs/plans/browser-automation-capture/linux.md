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

GTK media independently decoded all nine artifacts and 51 frames (`db2f9e720091dcc125dfe31030ac4d899caef7d2327d4dac430d43d8e3653560`). Receipts were copied to `D:/BuildArtifacts/kelpie/capture-desktop-20261104/linux-native/gtk-windowed-3001`; report hash `d00a3816574ad9cfa9b65e03b50ed81863deb993063de6079dbd338c3152e723` and native Stop receipt hash `55125613a27f767f67a0cd1ec2e225a1f5de712aa70d30fbd156be12d1a3517d`.

The old strict marker mask failed only GIF frame 9: 133 accepted pixels implied center (92.5,113), versus expected (92.97,107.03). The same-time MP4 frame had 849 accepted pixels centered (93.5,107.5); full-strength GIF frames centered (92.5,107). The fixed 3/3/2-bit GIF palette makes the absolute saturation mask background-dependent during fade. Three deterministic regression tests now cover faded circles over white/gray button surfaces and black text, reproduce the old biased centroid, and reject neutral UI, blue pixels and near-zero alpha. The detector compares red/green excess (equal precision in this palette) and excludes blue-dominant pixels. Center assertions retain four-pixel tolerance and require at least 40% of nominal circle area so sparse near-transparent pixels do not establish geometry. Initial calibration failed two vectors and is retained in the work log; corrected vectors pass 3/3. Actual corrected-media analysis remains pending; no production compositor change follows from this test correction.

## Installed candidate CI gate

The reusable `linux-native.yml` now adds a separate fresh Ubuntu 22.04/Fedora 44 container after package creation. It installs the exact sole DEB/RPM candidate, records package metadata and package/installed ELF/CEF hashes, verifies the installed executable matches the compiled candidate, and tests the regular `/usr/bin/kelpie-linux` entry point as a new unprivileged test UID. The source mount is read-only and only the evidence directory is writable. The existing native corpus covers HTTP/direct/generic MCP, all formats, artifact chunks, abort/partial/recovery and collision finalization. The existing packaged CLI alias flow separately checks launch, MCP, recipes, download and natural cleanup. Independent decoding follows; no GUI/Wayland screenshot claim follows from a headless container run.

The build creates a private CLI package from the same source, reusing frozen workspace dependencies. The test container installs only the native package's declared dependencies plus test utilities; it does not reuse build-container native development libraries. Node's pinned test-runtime archive is checked against official SHA-256 sums. Neither package nor test client is published by this workflow.

A real unprivileged user/network/PID namespace probe must pass before app launch. Default hosted Docker or host policy may refuse it; that is an explicit runtime-host blocker. The workflow does not add capabilities, disable seccomp/AppArmor, change kernel policy, set a new privileged helper, or pass a Chromium sandbox bypass. A passing namespace preflight is a prerequisite, not by itself proof of renderer policy. The installed corpus remains unverified until root dispatches this exact source. Bash syntax and seven focused workflow/security/scope tests pass on Maxis. The earlier `41971414574` candidate run passed both distro build/package jobs, but predates this installed-runtime gate.

## Linux visual viewport consumer checkpoint

Linux now consumes the shared captured `visualViewport` (offsets, visible dimensions and scale) in the Cairo path used by both native GTK presentation and exports. Target geometry maps through full-frame/layout scale, then observed pinch scale and offset subtraction; it does not divide by the scrollbar-excluding visible width. Commentary keeps its original viewport UI transform. Private invalid/non-finite dimensions fail closed. The shared engine remains the sole CDP input implementation and supplies layout-minus-observed-offset coordinates; Linux introduces no input scaling or new public API.

The decoder exposes original validated PNG dimensions before width limits/even rounding. Capture fences those physical dimensions as well as retained frame dimensions, so a source resize cannot hide behind an unchanged rounded export size. New native pixel vectors cover zoom/pan center and radius, byte-identical classic-gutter behavior, viewport-pinned commentary and invalid scale, plus two original source sizes that produce the same rounded retained size. This checkpoint is source-reviewed but uncompiled; the focused native tests and final current-source runtime/privacy/geometry replay remain required.

## Isolated Wayland rendered UI capture route

Fedora already supplies Weston 15.0.1, its standard `weston-screenshooter` and `weston-debug`, kiosk shell and Xwayland 24.1.14. `tests/linux/run-isolated-wayland.mjs` creates a disposable private 0700 runtime, random socket and private D-Bus session, explicitly dropping the shared display/Wayland/accessibility/D-Bus references. Weston uses its headless Pixman backend and kiosk shell, with standard output capture enabled only on that isolated compositor. The compositor exits with its owned test client. No GNOME capture, focus operation, keyboard/pointer injection, portal picker or production capture endpoint is used.

Before and after standard screenshooter capture, the helper pins compositor and app executable hashes/start ticks and reads Weston's one-shot `scene-graph` stream. Its upstream implementation derives each surface PID from Wayland client credentials. Capture requires an owned GTK surface and refuses any non-internal view with another PID; surface inventory must remain identical. The existing exact-PID AT-SPI Stop/public CLI driver runs inside this private session. Images are labelled `ISOLATED_WAYLAND`, never physical GNOME screenshots. Source syntax/self-review passes; runtime/capture permission and output verification remain pending the authorized bounded test.

Primary interface/source references: [Weston manual](https://cgit.freedesktop.org/wayland/weston/tree/man/weston.man), [Weston 15.0.1 scene graph credentials and one-shot stream](https://gitlab.freedesktop.org/wayland/weston/-/blob/15.0.1/libweston/compositor.c), and [GNOME screenshot interface](https://github.com/GNOME/gnome-shell/blob/main/data/dbus-interfaces/org.gnome.Shell.Screenshot.xml). The shared GNOME API has no atomic PID/window target; its window method selects the focused window and its area method includes compositor contents. Only metadata introspection was performed there.

The first isolated Wayland attempt (`kelpie-linux-isolated-wayland-1793858978`) failed before compositor/app launch: Fedora uses dbus-broker and had no `dbus-run-session`. Its 208 ms/143 ms CPU/14.2 MiB failure and teardown are preserved. The harness now checks prerequisites explicitly and persists spawn/setup failures. The official Fedora `dbus-daemon-1.16.2-1.fc44.x86_64` RPM was downloaded into owned ignored test storage, without installing packages/services. RPM signature verified against Fedora 44 fingerprint `36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6`; archive SHA-256 `1b5671b58f987ff8dde9b88840ef9163905abf91135f10689099bb6df3148289`. Only `dbus-run-session` and `dbus-daemon` were extracted; existing dynamic libraries resolve. Their hashes are `8b6317a9c457093b96eb9d16f87b52e332d0314b659ea0b23f454494240d64e2` and `cbb05276d0a322ddbfd71e58c135625117dfab72967ad743c60fdaf10970545e`. The documented `--dbus-daemon=<privatebinary>` option selects the private daemon. [D-Bus test-session interface](https://dbus.freedesktop.org/doc/dbus-run-session.1.html), [Fedora signing fingerprints](https://fedoraproject.org/security/). No shared bus fallback is permitted.

Isolated attempt 2 (`kelpie-linux-isolated-wayland2-1793859232`) reached the owned GTK window on Weston's private Xwayland `:2` and private D-Bus. It then failed because the installed AT-SPI launcher itself hardcodes `/usr/bin/dbus-daemon`. Public CLI stop naturally retired the app and the compositor/unit ended (16.720 seconds, 16.426 CPU seconds, 284.5 MiB). No capture was taken and no global package was installed. The private rendered-image flow now uses supported HTTP abort after the trusted click and credential-pinned compositor capture; actual shared-GNOME native AT-SPI Stop evidence remains a separate passed gate. Native Stop is inspected visually in this isolated image, not falsely reported as invoked there. This removes the extra private accessibility-bus dependency.

The runtime bundle now embeds `source-revision.txt` and names the package source in its README. Installed smoke compares that file with the exact CI build revision and records its hash, alongside the independently checked installed ELF/CEF hashes and native app/package versions. This is packaging provenance associated with the build receipts, not a new component-version authority or an assertion that an ELF intrinsically proves its source. Bash syntax and three installed-smoke policy checks pass; a candidate rebuilt from this source must still complete the installed gate.

Isolated attempt 3 (`kelpie-linux-isolated-wayland3-1793859486`, test `f161e401`) passed six public alias/recording/abort checks plus ten observations and natural cleanup. Weston credential inventory before/after capture contained only owned GTK PID 651356 and its internal kiosk background. Standard 1280×900 PNG hash `2764288b20f62ee2d51c456cd4f361515dc90c8d56e089d85ec9506d26a72718` was personally inspected: native Stop is visible but backdrop-styled, with no live pointer/circle. GTK intentionally gates live overlays on an active window; Weston's headless default has no seat. This is preserved as an inactive-window observation, not a compositor defect or live-overlay pass. The next isolated-only test uses Weston's documented `--fake-seat` compatibility capability, allowing normal sole-window autoactivation without any focus/input call. Unit 33.808 seconds/33.512 CPU seconds/504 MiB; app retired naturally and cgroup disappeared. Receipts copied under `D:/BuildArtifacts/kelpie/capture-desktop-20261104/linux-native/isolated-wayland-3001-3`.

Isolated active-window attempt 4 (`kelpie-linux-isolated-wayland4-1793859924`, test `cbfec13f`) passed six public checks and ten observations, supported HTTP abort/partials/recovery, and natural process/socket/readiness cleanup. The personally inspected original 1280×900 screenshot shows the active native Stop button and red circle/virtual pointer on Confirm order. A separate unmoved compatibility-seat compositor cursor remains visible on the heading; it is not the script pointer or injected input. Before/after credential inventories contain only the owned GTK client (PID 654173/start ticks 12047793) and internal background. PNG hash `ce9b2d8d088df6ca1aefefffac7a49dbd1e575a2cedbefa68521119aa33fba04`; receipt `2fb847eb1b2f90b754f50670d81352620ee52110b918a759eee56ef9613020ee`. Unit 30.597 seconds/30.323 CPU seconds/507 MiB, inactive/MainPID zero/cgroup absent. Root independently copied, rehashed and viewed the image. This establishes isolated native spatial evidence at compiled `3001`, not physical GNOME display, animation or final-source acceptance. Final relink must produce a fresh After image.

The recording/Stop/overlay state has no equivalent in base `195eb90fa5df47291a75e8d165c72fc2f825e3c9`: [base GTK viewport constructor](https://github.com/UnlikeOtherAI/kelpie/blob/195eb90fa5df47291a75e8d165c72fc2f825e3c9/apps/linux/src/gtk_browser_view.cpp#L13) creates the drawing area and status label, with no native recording Stop or presentation compositor. The PR Before cell should say new recording state/no prior equivalent, with the verified final native image in the After cell.


## Integrated Fedora verification, 5 November 2026

Fedora 44 built GTK/CEF, HEADLESS_ONLY CEF, and HEADLESS_ONLY no-CEF/LLM-off from
`0d3d4e892b3993baa5fbac97e27a8aec9396767b` with cached dependencies in bounded
one-CPU, 2-GiB units. The GTK executable SHA-256 is
`58d3e50a8e15fbe5a2186da9ccb0d0eb49d28dd2ec0c49187b67795c7011f5a5`;
the focused media and artifact tests passed 2/2. The offscreen native HTTP/MCP
corpus passed 36/36 plus artifact protocol, finalization fault, and pre-input
replacement supplements, then retired the app and readiness file. Its first
two attempts timed out before readiness while inheriting GNOME session variables;
a private display-free runtime completed. Both failures remain in the receipts.

The independent full-frame decode succeeded, but the continuous marker check
failed on 19 red pixels in the last MP4 frame. The paired GIF ended with zero
red pixels; a localized MP4 compression trace is plausible, not established.
The shared G08 oracle returned insufficient evidence for C and S in both GIF
and MP4 at one CPU and at two CPUs. Each two-CPU run retained 60 frames and
dropped about 250 across 15 seconds at requested 20 fps. PTS intervals average
253 ms; this is sustained sparse cadence, not a 60-frame cutoff. Do not mark
the fade or dense animation gate passed without further evidence.

Instrumented Linux offscreen profiling on the same GTK executable measured
median state, viewport, and screenshot calls at 10.16, 61.04, and 62.73 ms.
Each capture frame fences two state and two viewport reads around its screenshot.
A separately built one-millisecond headless-pump candidate reduced those medians
to 1.35, 6.72, and 37.54 ms and retained 34 instead of 15 frames in the same
three-second instrumented diagnostic; its ten-second idle main-process CPU
was 12 ticks instead of five at USER_HZ 100. It has not passed the G08 gate.

Public CLI alias checks passed on the integrated GTK executable and a CLI
package built from matching 0d3d CLI/shared/lock inputs. Offscreen covered five
checks and ten observations; isolated Weston Wayland covered six checks and ten
observations, partial media after public HTTP abort, recovery, and natural
process/socket/readiness cleanup. The actual private-compositor PNG SHA-256 is
`e538f31fc7fe68e512e4cee56ee87e974e636f62651818d54f921a668d621462`;
it shows the red indicator and pointer on the target and the Stop control.
This is isolated Wayland evidence, not a physical GNOME Stop click.

The original no-CEF runtime published port zero after an ephemeral bind. A
separate fix uses getsockname; on test revision
`8114738b272d38498cc5592e82388f8234bd7926` the HTTP server test passed,
and the no-CEF runtime refused HTTP and MCP script execution with zero fixture
requests, unchanged URL, and clean SIGTERM exit. The Fedora VM already has an
installed Kelpie RPM, and Ubuntu was unreachable. Fresh installed DEB/RPM
candidate verification remains open; neither the existing Fedora package nor
the sandbox is altered as a workaround.

The offscreen harness isolation change was then exercised against the same 0d3d
executable with deliberately invalid inherited display and session-bus variables.
Test revision `cb520132e3b83a3fc405cf45e109a30afa5d664c` passed 36/36 cases
and all supplements, and removed readiness on clean exit.

A further uninstrumented one-CPU G08 run of the headless-pump candidate
(retaining the exact screenshot and five-metric fences) retained 128 C frames
and 129 S frames across about 13 seconds, while dropping 144 and 140 cadence
slots. The shared oracle passed S/MP4, reported S/GIF marker stuck, and found
insufficient C/GIF marker phases and C/MP4 wobble phases. The full gate remains
open. This candidate ELF is
`b012335bc2f025a8c365e77317eadd3f096c5322589e6579026651b2c622ae82`;
the test source includes the no-CEF port fix and pump candidate.

Matched 1000x702 GIF and OpenH264 MP4 controls used the actual Linux production
encoder and marker compositor, with matching requested 15 fps, 14 frames and
3.85-second duration. With a wobble/fade history, all four clean tail frames
contained zero thresholded red pixels in both formats. A retained two-pixel
radius marker produced 16 GIF and eight MP4 red pixels; a fainter retained marker
produced zero in both under the existing threshold. Therefore a 19-pixel MP4
allowance would hide a demonstrably retained marker, and the current metric also
cannot prove absence of a fainter marker. The strict failed result is retained
pending a stronger validated oracle; no tolerance was relaxed.

The headless-pump candidate subsequently passed the 36-case offscreen
HTTP/MCP regression and all supplements; the owned process and readiness file
retired normally. In the candidate S/GIF final frame all 18 pixels flagged as
blue had equal red and green channels and occupied the stationary pointer.
Their three RGB triplets are consistent with neutral pointer antialiasing
quantized by the GIF 3/3/2 palette. This finding does not by itself exclude a
real overlapping blue marker; the shared oracle result remains failed until a
control can distinguish those cases.

A production-compositor and production-encoder pointer-only control reproduced
the candidate S/GIF tail exactly: 18 flagged pixels, 23 chromatic pixels, and
center (484.5, 228.5). All 18 real-tail pixels have equal red and green channels
and the blue channel matches the coarser GIF palette quantization of neutral
pointer antialiasing. Matched overlapping blue controls produced 32 flagged
pixels for a small retained marker, 33 for a faint marker and 1804 for a full
marker, against 18 for the pointer alone. This supports a matched pointer-baseline
oracle but does not validate a generic 18-pixel allowance; no oracle was changed.

The canonical Fedora test RPM for source
`f9cc1c6ffa142689d20b9acc2cb2e2a4d72f1040` was built with verified Fedora
RPM tools, SHA-256
`4b70530296ee4e8553cdbccd16c329511102d86d00cdc6dc74304cc2bac1e794`.
This was an unsigned test package, not a release. Two private COW install
attempts failed before package installation: first the nonrecursive root bind
returned EINVAL; then recursive read-only binding passed for all 34 mounts but
overlayfs failed to clone the lower path. Host mount/package/binary snapshots
matched before and after both attempts.

The test RPM was then installed by the supported Fedora package manager. Its
installed app and CEF hashes matched the tested build; the real installed entry
point passed 36/36 HTTP/MCP checks, supplements, and five CLI alias checks with
ten observations and clean shutdown. Full-frame decode completed; the strict
marker check failed on three final MP4 pixels and remains open. Calibrated
Finish/Start/Finish G08 runs had no fixture-event loss but all four current
oracle results were insufficient on pre-dispatch pointer position. The prior
published Fedora RPM was restored with the package manager and its package
identity, file manifest, executable/CEF hashes, and rpm verification matched
the pre-test snapshots.

## Frozen Fedora offscreen checkpoint

Fedora 44 exercised product revision 0c8526b872209af176e16f1d37792fb17a5e1781
with test revision 692841e1c4986ffc02e40e8a07afa9d7c4c68737. The only
difference between them is the test assertion placement; native/product build
inputs are identical. The app ELF SHA-256 was
dc368f394f42a5ce5595670884094b8286115f3d213347910569b5b990902e52
and libcef.so was d6bee514adcc2ea2d6e8a450939f7a09da746f1e9b7c8275b9be61b60cd26d99.

The isolated offscreen native HTTP and direct/generic MCP corpus passed 54/54,
including all nine paced typing cases, acknowledged navigation, captured-input
privacy refusal, pointerup replacement, late release acknowledgement and
recovery. All configured supplements passed; the owned process exited and its
readiness file was removed. An unrelated Fedora process on port 18425 was
preserved. C ABI, post-mutation classification and terminal uncertainty native
tests passed. The independent decoder validated 44 retained artifacts and 126
frames (21 PNG, 14 GIF, 9 MP4), including continuous marker center, fade and
clear checks.

The owned evidence root is
/home/ondre/Projects/kelpie-worktrees/capture-linux-resume-20261105/.native-artifacts/692-brand-full/.

| Evidence | SHA-256 |
| --- | --- |
| launch-report.json | 7b4128c9f7a26ab46b083d87b4eec4e5b0b67dcb986a7a4e445893b729410e16 |
| media-verification.json | 3da735055e59a05fd55f772150825bc485df2d8b2257ad4cb4a729845309c96c |
| all-frame-decode.json | 2df8f8a1b95200ab00949681d851f59521e3af1aa0b8e70394ff9f4c0dd1b67d |
| continuous-marker-pixels.json | 00f8acefb72f4c971fa4f58241d9a918ad15cf3f024daca71ef974deae2f718a |

This checkpoint does not close the full G08 easing/wobble oracle, final
HEADLESS_ONLY and no-CEF/LLM-off runtime flavors, physical GNOME visual proof,
Ubuntu installed-package verification, final published package installation, or
the pending CI zygote diagnosis. The production GIF reference remains
insufficient until its loader-binding provenance and controls are verified.
