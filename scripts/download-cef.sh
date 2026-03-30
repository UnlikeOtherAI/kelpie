#!/bin/bash
# Downloads CEF binary distribution for macOS ARM64.
# Run this once before building the macOS app.
set -euo pipefail

CEF_VERSION="146.0.9+g3ca6a87+chromium-146.0.7680.165"
ARCH="macosarm64"
OUTDIR="apps/macos/Frameworks"

URL="https://cef-builds.spotifycdn.com/cef_binary_${CEF_VERSION}_${ARCH}_minimal.tar.bz2"
TARBALL="/tmp/cef-${ARCH}.tar.bz2"

echo "Downloading CEF ${CEF_VERSION} for ${ARCH}..."
curl -L -o "${TARBALL}" "${URL}"

echo "Extracting..."
mkdir -p "${OUTDIR}"
tar -xjf "${TARBALL}" -C /tmp/
EXTRACTED=$(ls -d /tmp/cef_binary_*_${ARCH}_minimal 2>/dev/null | head -1)

if [ -z "$EXTRACTED" ]; then
    echo "ERROR: Extraction failed"
    exit 1
fi

cp -R "${EXTRACTED}/Release/Chromium Embedded Framework.framework" "${OUTDIR}/"
cp -R "${EXTRACTED}/include" "${OUTDIR}/cef_include"

# Create symlink so CEF internal #include "include/..." paths resolve
ln -sfn "${OUTDIR}/cef_include" "${OUTDIR}/cef_include/include"

# Create Info.plist symlink at framework root for Xcode validation
CEF_FW="${OUTDIR}/Chromium Embedded Framework.framework"
if [ -f "${CEF_FW}/Resources/Info.plist" ] && [ ! -e "${CEF_FW}/Info.plist" ]; then
    ln -sf Resources/Info.plist "${CEF_FW}/Info.plist"
fi

rm -rf "${EXTRACTED}" "${TARBALL}"
echo "CEF framework installed at ${OUTDIR}/Chromium Embedded Framework.framework"
echo "CEF headers installed at ${OUTDIR}/cef_include/"
