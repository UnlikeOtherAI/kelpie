# Linux native automation and capture

Owner: Linux (desktop_backend), Maxis source development only.
Current prerequisite source worktree:
D:/Worktrees/kelpie/capture-desktop-20261104.
Linux worktree to create only after the backend prerequisite is integrated:
D:/Worktrees/kelpie/capture-linux-20261104,
branch codex/capture-linux-20261104.
Assigned future bounded Linux test checkout:
 /home/ondre/Projects/kelpie-worktrees/capture-linux-20261104.

No Linux source implementation, native build or acceptance is claimed by this
initial inventory. The user now requests all platforms; Windows remains the first
shared runtime gate, but that does not remove any Linux requirement below.

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

Every row is pending Linux real-interface evidence; shared source or another
platform's test is not a Linux pass.

| ID | Linux implementation/evidence target | Status |
| --- | --- | --- |
| OBS-01 | Native shared value-free snapshot/private canaries | Pending |
| OBS-02 | Scoped/prioritized observation under real bounds | Pending |
| OBS-03 | Text/name/element/metadata limits and truthful truncation | Pending |
| EXT-01 | Scalar extraction with missing/ambiguity/source checks | Pending |
| EXT-02 | Nested/repeated deterministic records | Pending |
| EXT-03 | Bounded publisher metadata and JSON-LD allowlist | Pending |
| EXT-04 | Document/source/truncation provenance | Pending |
| RDY-01 | Actual DOM status and unavailable diagnostic facts | Pending |
| RDY-02 | Explicit readiness/hidden/duplicate/failure cases | Pending |
| OWN-01 | Managed backend prerequisite real sessions; native scope not expanded | Prerequisite pending follow-up |
| OWN-02 | Exact native lease/refs/pins/late callback ownership | Pending |
| WFL-01 | Shared strict v1 validation before admission/action | Pending |
| WFL-02 | Typed inputs/secrets without executable interpolation | Pending |
| WFL-03 | Ordered waits/assertions/extractions/outputs | Pending |
| WFL-04 | Existing legacy route with no v1 privilege widening | Pending |
| WFL-05 | Unknown mutation stops; one activation; self-recovery | Pending |
| TGT-01 | Unique eligible semantic target | Pending |
| TGT-02 | Visible hit-tested center | Pending |
| TGT-03 | Scroll/DPR/zoom/clipped viewport correctness | Pending |
| TGT-04 | Exact object/document/geometry revalidation | Pending |
| TGT-05 | Real input trust matches advertised guarantee | Pending |
| PTR-01 | C/S eased visible trajectory/endpoints | Pending |
| PTR-02 | Numeric display/export correspondence | Pending |
| VIS-01 | Requested marker color/radius/opacity in decoded pixels | Pending |
| VIS-02 | Wobble/fade timeline and clean end state | Pending |
| CAP-01 | Real GIF/MP4/every-step PNG through public script | Pending |
| CAP-02 | GIF loop/frame delays/fixed dimensions | Pending |
| CAP-03 | MP4 independent decode/PTS/duration/dimensions | Pending |
| CAP-04 | Step marker captured at intended timestamp | Pending |
| CAP-05 | Document/viewport coherence and resize partial refusal | Pending |
| CAP-06 | Duration/FPS/width/bytes/steps resource preflight | Pending |
| CAP-07 | Bounded encoder backpressure, drop count, real time | Pending |
| CAP-08 | Cancel/failure partial finalization and next run | Pending |
| ART-01 | Separate remote CLI/MCP chunk retrieval | Pending |
| ART-02 | Same/foreign/revoked owner status/cancel/download | Pending |
| ART-03 | Integer/range/size/id/path refusal without unbounded read | Pending |
| ART-04 | MIME/size/hash/partial/time/document manifest | Pending |
| SEC-01 | No synthetic secrets in output/error/log/manifest | Pending |
| SEC-02 | Page instructions/metadata never authority or code | Pending |
| DIF-01 | Same frozen corpus/normalized Linux CEF output | Pending |
| LP-01 | Proven restricted Linux-native worker methods only | Pending exact 1.0.2 phase |
| LP-02 | Unsupported dispatch refusal and owned isolation | Pending exact 1.0.2 phase |
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
