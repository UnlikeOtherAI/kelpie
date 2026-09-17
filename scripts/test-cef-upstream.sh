#!/bin/bash
# Stock-CEF comparison test for the macOS Chromium renderer freeze
# (UnlikeOtherAI/kelpie#74, docs/plans/2026-06-10-cef-navigation-freeze.md).
#
# Downloads the official prebuilt cefclient.app ("client" distribution) for a
# given CEF version and launches it against a test URL, with zero Kelpie code
# involved. This isolates upstream-CEF-vs-our-integration:
#
#   - cefclient renders + re-navigates fine  -> our embedding is at fault
#   - cefclient is also blank / freezes      -> upstream CEF <-> macOS bug;
#                                                try the next CEF version
#
# Must be run ON THE TARGET MAC (Apple Silicon). Usage:
#
#   scripts/test-cef-upstream.sh                     # latest pinned version
#   scripts/test-cef-upstream.sh <full-cef-version>  # e.g. the old broken pin
#
# Suggested manual checks once cefclient opens:
#   1. Does https://example.com render (not a white page)?
#   2. Navigate to a second URL via the address bar — does it commit?
#   3. Open a data: URL (data:text/html,<h1>HELLO</h1>) — does it render?
# All three must pass to clear upstream CEF on this macOS build.
set -euo pipefail

# Keep the default in sync with install_macos_arm64 in download-cef.sh.
CEF_VERSION="${1:-149.0.6+g0d0eeb6+chromium-149.0.7827.201}"
CEF_PLATFORM="macosarm64"

if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
    echo "ERROR: this test must run on an Apple Silicon Mac (the machine showing the bug)."
    exit 1
fi

TMP_ROOT="/tmp/kelpie-cef-upstream-test"
ARCHIVE_NAME="cef_binary_${CEF_VERSION}_${CEF_PLATFORM}_client"
TARBALL="${TMP_ROOT}/${ARCHIVE_NAME}.tar.bz2"
EXTRACT_ROOT="${TMP_ROOT}/${ARCHIVE_NAME}"
# The version string contains '+' which must be URL-encoded as %2B.
ENCODED_NAME="${ARCHIVE_NAME//+/%2B}"
URL="https://cef-builds.spotifycdn.com/${ENCODED_NAME}.tar.bz2"

mkdir -p "${TMP_ROOT}"

if [ ! -d "${EXTRACT_ROOT}" ]; then
    echo "Downloading stock cefclient ${CEF_VERSION}..."
    curl -L --fail -o "${TARBALL}" "${URL}"
    mkdir -p "${EXTRACT_ROOT}"
    tar -xjf "${TARBALL}" -C "${EXTRACT_ROOT}" --strip-components 1
    rm -f "${TARBALL}"
fi

CEFCLIENT_APP=$(find "${EXTRACT_ROOT}" -maxdepth 3 -type d -name "cefclient.app" | head -1)
if [ -z "${CEFCLIENT_APP}" ]; then
    echo "ERROR: cefclient.app not found under ${EXTRACT_ROOT}"
    exit 1
fi

echo "Launching stock cefclient (${CEF_VERSION})..."
echo "  ${CEFCLIENT_APP}"
echo ""
echo "Check: 1) example.com renders  2) second navigation commits  3) data: URL renders"
"${CEFCLIENT_APP}/Contents/MacOS/cefclient" \
    --use-mock-keychain \
    --url="https://example.com/"
