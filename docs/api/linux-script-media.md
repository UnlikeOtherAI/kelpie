# Linux script capture

This is the Linux CEF implementation contract. The initial native candidate is
unverified until the Linux ledger records its actual build and machine-interface
results. The shared desktop coordinator, validators, target resolver, input,
ownership, status, redaction and HTTP/MCP routing remain authoritative.

Linux supplies Cairo PNG decoding/composition, giflib GIF compression, a native
GStreamer/OpenH264 MP4 adapter, private POSIX artifacts and a GTK Stop control.
The same Cairo function draws tap markers, presentation pointers and commentary
in the GTK viewport and exported frames. Pointer motion remains presentation only.
The active tab/generation, current document and active GTK window gate live marks.
CEF screenshots are real rendered pixels; Lightpanda layout images are not used.

## Native dependencies and provenance

CEF builds need Cairo, giflib, OpenSSL and GStreamer application development
headers. MP4 uses only fixed system factories: appsrc, videoconvert, openh264enc,
h264parse, mp4mux and appsink. Startup checks their actual plugin license metadata;
only the selected LGPL/BSD/MIT factories are accepted. Actual first-frame H.264
encoding and MP4 muxing are proven before the first workflow action. Missing or
unusable codecs refuse without input. No automatic codec fallback, external
encoder process, copied codec source or bundled new codec executable is used.

Read-only Fedora44 inventory on 5 November2026 found GStreamer1.28.8:
openh264enc reports BSD; appsrc/appsink, videoconvert, h264parse and mp4mux report
LGPL. Installed OpenH264 is2.6.0-3.fc44. Their exact files, package signatures,
hashes and actual test results belong in the Linux ledger. These observations are
component facts, not legal advice or a redistribution approval.

Fedora's ffmpeg-free8.1.3 reported GPLv3-or-later. It is not linked or used by the
product encoder. A package name is not evidence of its library license.

- Fedora build prerequisites: cairo-devel, giflib-devel, gstreamer1-devel,
  gstreamer1-plugins-base-devel and the existing CEF/native prerequisites.
- Fedora runtime: cairo, giflib, gstreamer1-plugins-base,
  gstreamer1-plugins-good, gstreamer1-plugins-bad-free and
  gstreamer1-plugin-openh264, plus matching CEF assets and existing app libraries.
- Debian/Ubuntu package declarations use libcairo2, libgif7,
  libgstreamer1.0-0, libgstreamer-plugins-base1.0-0 and the base/good/bad plugin
  packages. Native verification here targets Fedora; it does not claim an Ubuntu
  install. The Ubuntu26.04 package lists OpenH264 as a dependency.
- AppImage/runtime bundles require these system plugin packages. They are not
  silently made self-contained by copying a codec binary into the bundle.

Primary API references:
[appsrc](https://gstreamer.freedesktop.org/documentation/app/appsrc.html),
[appsink](https://gstreamer.freedesktop.org/documentation/app/appsink.html),
[OpenH264 encoder](https://gstreamer.freedesktop.org/documentation/openh264/openh264enc.html),
[MP4 muxer](https://gstreamer.freedesktop.org/documentation/isomp4/mp4mux.html),
[giflib](https://giflib.sourceforge.net/gif_lib.html),
[FFmpeg licensing](https://ffmpeg.org/legal.html),
[Ubuntu26.04 plugin package](https://packages.ubuntu.com/resolute/amd64/libs/gstreamer1.0-plugins-bad).

## Bounds and finalization

One capture worker retains a pending BGRA frame. Step PNG samples do not increase
the configured movie frame rate. All formats share the retained-byte budget.

GIF compression uses a fixed256-color palette. Each complete encoded frame and
its timing extension are admitted before append; the final trailer is reserved.
GIF rounds cumulative boundaries to centiseconds and retains a playable prefix
when byte admission stops.

MP4 retains bounded complete encoded access units with actual elapsed PTS and
durations. Header/trailer and per-packet overhead are reserved. Final mux bytes
are admitted exactly; unexpected overhead removes complete tail packets and
remuxes the owned encoded prefix. This never retries a browser mutation.
Codec queues, raw frames, packets, output bytes, execution waits and frame count
are bounded independently. Failure/abort/limits finalize available outputs and
mark partial manifests. A finalization error is not reported as full success.

Artifacts use atomic private directories and exclusive0600 files. Publication
binds opaque IDs to the authenticated run owner, MIME, length and SHA-256.
Range reads verify ownership, run, regular-file device/inode and unchanged size;
they never accept arbitrary paths or URLs. Storage expires after one hour and
evicts oldest entries over256MiB or4096 artifacts. A run can retain its at-most1002
artifacts within the shared capacity. No UOA identity/profile copy is stored.

## Flavors and verification

GTK shows native Stop outside the renderer; only that small control receives
input. Headless CEF uses the same coordinator and composited media, with
authenticated status/abort/artifact recovery and no local Stop or live-window
claim. Its catalogue availability requires actual OSR input/capture proof and a
trusted per-runtime override; static Windows metadata is not broadened globally.
No-CEF builds retain explicit unavailable capabilities before mutation.

The focused native tests decode every GIF/MP4 frame, inspect timing and overlay
color, prove PNG scaling/decompression bounds and exact budget-prefix behavior,
and exercise private-file/chunk/foreign-owner/inode/budget failures.
Actual app HTTP/MCP/CLI, cancellation/failure recovery, native UI limits and
packaging results remain in
[the Linux ledger](../plans/browser-automation-capture/linux.md).
Computer Use is off; no manual Stop click or before/after UI screenshot is claimed
without actual evidence.
