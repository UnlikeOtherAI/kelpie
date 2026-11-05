#!/bin/bash
set -euo pipefail
# Official distro repositories only. An unavailable real OpenH264 package fails
# the release build; no third-party repository or codec fallback is added.
case "${1:-}" in
  ubuntu)
    apt-get install -y --no-install-recommends libcairo2-dev libgif-dev \
      libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev gstreamer1.0-tools \
      gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad
    ;;
  fedora)
    dnf install -y cairo-devel giflib-devel gstreamer1-devel \
      gstreamer1-plugins-base-devel gstreamer1 gstreamer1-plugins-base \
      gstreamer1-plugins-good gstreamer1-plugins-bad-free gstreamer1-plugin-openh264 openh264
    ;;
  *) echo "Expected ubuntu or fedora native capture dependencies" >&2; exit 1 ;;
esac
