#!/bin/bash
set -euo pipefail
# Factory registration is insufficient for a noopenh264 placeholder codec.
# The native media test separately proves actual encoding and MP4 muxing.
gst-inspect-1.0 --version
for factory in appsrc appsink videoconvert openh264enc h264parse mp4mux; do
  echo "Required native capture factory: ${factory}"
  gst-inspect-1.0 "${factory}" | sed -n '/Plugin Details:/,/GObject/p'
done
