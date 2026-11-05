#!/usr/bin/env bash
set -euo pipefail
[[ $# == 2 ]]
fixture="$(realpath "$1")"
out="$2"
mkdir -m 700 "$out"
python3 tests/linux/extract-mux-vcl.py "$fixture" "$out/input"
c++ -std=c++20 -O0 tests/linux/mux-vcl-probe.cpp -o "$out/probe" $(pkg-config --cflags --libs gstreamer-app-1.0 gstreamer-1.0)
gst-inspect-1.0 --version > "$out/gstreamer-version.txt"
ffprobe -version > "$out/ffprobe-version.txt"
sha256sum "$fixture" > "$out/input-sha256.txt"
"$out/probe" "$out/input" fragmented "$out/fragmented.mp4" > "$out/fragmented.log"
"$out/probe" "$out/input" faststart "$out/faststart.mp4" > "$out/faststart.log"
sha256sum "$out/fragmented.mp4" "$out/faststart.mp4" > "$out/output-sha256.txt"
python3 tests/linux/check-mux-comparison.py fragmented "$out" > "$out/fragmented-check.json"
python3 tests/linux/check-mux-comparison.py faststart "$out" > "$out/faststart-check.json"
