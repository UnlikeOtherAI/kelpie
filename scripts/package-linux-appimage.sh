#!/bin/bash
set -euo pipefail

BUNDLE_DIR=""
OUTPUT_DIR=""
VERSION=""
APPIMAGETOOL=""

usage() {
  cat <<'EOF'
Usage: scripts/package-linux-appimage.sh --version <version> --bundle-dir <dir> --output-dir <dir> --appimagetool <path>
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
    --appimagetool)
      APPIMAGETOOL="$2"
      shift 2
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "${VERSION}" ] || [ -z "${BUNDLE_DIR}" ] || [ -z "${OUTPUT_DIR}" ] || [ -z "${APPIMAGETOOL}" ]; then
  usage >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

APPDIR="${WORK_DIR}/Kelpie.AppDir"
mkdir -p "${APPDIR}/usr/lib/kelpie"
cp -a "${BUNDLE_DIR}/." "${APPDIR}/usr/lib/kelpie/"

cat > "${APPDIR}/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "${HERE}/usr/lib/kelpie/kelpie-linux" "$@"
EOF
chmod 755 "${APPDIR}/AppRun"

sed 's|^Exec=.*|Exec=kelpie-linux %u|' packaging/linux/kelpie.desktop > "${APPDIR}/kelpie.desktop"
cp "${BUNDLE_DIR}/icon-1024.png" "${APPDIR}/kelpie.png"

mkdir -p "${OUTPUT_DIR}"
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "${APPIMAGETOOL}" "${APPDIR}" "${OUTPUT_DIR}/Kelpie-${VERSION}-x86_64.AppImage"
