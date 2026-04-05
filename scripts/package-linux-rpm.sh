#!/bin/bash
set -euo pipefail

BUNDLE_DIR=""
OUTPUT_DIR=""
VERSION=""
RELEASE="1"
ARCH="x86_64"

usage() {
  cat <<'EOF'
Usage: scripts/package-linux-rpm.sh --version <version> --bundle-dir <dir> --output-dir <dir>
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

TOPDIR="${WORK_DIR}/rpmbuild"
BUILDROOT="${WORK_DIR}/buildroot"
mkdir -p \
  "${TOPDIR}/BUILD" \
  "${TOPDIR}/BUILDROOT" \
  "${TOPDIR}/RPMS" \
  "${TOPDIR}/SOURCES" \
  "${TOPDIR}/SPECS" \
  "${TOPDIR}/SRPMS" \
  "${BUILDROOT}/opt/kelpie" \
  "${BUILDROOT}/usr/bin" \
  "${BUILDROOT}/usr/share/applications" \
  "${BUILDROOT}/usr/share/icons/hicolor/1024x1024/apps"

cp -a "${BUNDLE_DIR}/." "${BUILDROOT}/opt/kelpie/"
install -m 644 packaging/linux/kelpie.desktop "${BUILDROOT}/usr/share/applications/kelpie.desktop"
install -m 644 "${BUNDLE_DIR}/icon-1024.png" "${BUILDROOT}/usr/share/icons/hicolor/1024x1024/apps/kelpie.png"
ln -s /opt/kelpie/kelpie-linux "${BUILDROOT}/usr/bin/kelpie-linux"
chmod 755 "${BUILDROOT}/opt/kelpie/kelpie-linux"
chmod 755 "${BUILDROOT}/opt/kelpie/chrome-sandbox"

cat > "${TOPDIR}/SPECS/kelpie.spec" <<EOF
Name:           kelpie
Version:        ${VERSION}
Release:        ${RELEASE}%{?dist}
Summary:        Kelpie LLM-first browser for Linux
License:        MIT
BuildArch:      ${ARCH}
AutoReqProv:    no
Requires:       alsa-lib
Requires:       at-spi2-atk
Requires:       atk
Requires:       avahi-libs
Requires:       cups-libs
Requires:       dbus-libs
Requires:       fontconfig
Requires:       gtk3
Requires:       libX11
Requires:       libXcomposite
Requires:       libXdamage
Requires:       libXext
Requires:       libXfixes
Requires:       libXrandr
Requires:       libdrm
Requires:       mesa-libgbm
Requires:       nspr
Requires:       nss
Requires:       pango
Requires:       zlib

%description
Linux desktop browser shell for Kelpie with embedded Chromium runtime,
local HTTP/MCP control surface, and mDNS discovery.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a ${BUILDROOT}/. %{buildroot}/

%files
/opt/kelpie
/usr/bin/kelpie-linux
/usr/share/applications/kelpie.desktop
/usr/share/icons/hicolor/1024x1024/apps/kelpie.png
EOF

mkdir -p "${OUTPUT_DIR}"
rpmbuild --define "_topdir ${TOPDIR}" -bb "${TOPDIR}/SPECS/kelpie.spec"
find "${TOPDIR}/RPMS" -name '*.rpm' -exec cp -a {} "${OUTPUT_DIR}/kelpie-${VERSION}-${RELEASE}.${ARCH}.rpm" \;
