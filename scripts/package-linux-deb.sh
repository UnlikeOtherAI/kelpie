#!/bin/bash
set -euo pipefail

BUNDLE_DIR=""
OUTPUT_DIR=""
VERSION=""
ARCH="amd64"
MAINTAINER="${KELPIE_PACKAGE_MAINTAINER:-Kelpie <hello@unlikeother.ai>}"

usage() {
  cat <<'EOF'
Usage: scripts/package-linux-deb.sh --version <version> --bundle-dir <dir> --output-dir <dir>
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --bundle-dir)
      BUNDLE_DIR="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "${VERSION}" ] || [ -z "${BUNDLE_DIR}" ] || [ -z "${OUTPUT_DIR}" ]; then
  usage >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

PKG_ROOT="${WORK_DIR}/pkg"
mkdir -p \
  "${PKG_ROOT}/DEBIAN" \
  "${PKG_ROOT}/opt/kelpie" \
  "${PKG_ROOT}/usr/bin" \
  "${PKG_ROOT}/usr/share/applications" \
  "${PKG_ROOT}/usr/share/icons/hicolor/1024x1024/apps"

cp -a "${BUNDLE_DIR}/." "${PKG_ROOT}/opt/kelpie/"
install -m 644 packaging/linux/kelpie.desktop "${PKG_ROOT}/usr/share/applications/kelpie.desktop"
install -m 644 "${BUNDLE_DIR}/icon-1024.png" "${PKG_ROOT}/usr/share/icons/hicolor/1024x1024/apps/kelpie.png"
ln -s /opt/kelpie/kelpie-linux "${PKG_ROOT}/usr/bin/kelpie-linux"

cat > "${PKG_ROOT}/DEBIAN/control" <<EOF
Package: kelpie
Version: ${VERSION}
Section: net
Priority: optional
Architecture: ${ARCH}
Maintainer: ${MAINTAINER}
Depends: libasound2, libatk-bridge2.0-0, libatk1.0-0, libavahi-client3, libc6, libcups2, libdbus-1-3, libdrm2, libfontconfig1, libgbm1, libglib2.0-0, libgtk-3-0, libnspr4, libnss3, libpango-1.0-0, libstdc++6, libx11-6, libxcomposite1, libxdamage1, libxext6, libxfixes3, libxrandr2, zlib1g
Description: Kelpie LLM-first browser for Linux
 Linux desktop browser shell for Kelpie with embedded Chromium runtime,
 local HTTP/MCP control surface, and mDNS discovery.
EOF

chmod 755 "${PKG_ROOT}/opt/kelpie/kelpie-linux"
chmod 755 "${PKG_ROOT}/opt/kelpie/chrome-sandbox"

mkdir -p "${OUTPUT_DIR}"
dpkg-deb --build "${PKG_ROOT}" "${OUTPUT_DIR}/kelpie_${VERSION}_${ARCH}.deb"
