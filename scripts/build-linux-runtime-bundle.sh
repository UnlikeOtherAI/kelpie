#!/bin/bash
set -euo pipefail

BUILD_DIR="apps/linux/build"
MANIFEST="packaging/linux/runtime-files.txt"
OUTPUT_DIR=""
VERSION=""
BUILD_LABEL=""

usage() {
  cat <<'EOF'
Usage: scripts/build-linux-runtime-bundle.sh --version <version> --output-dir <dir> [--build-label <label>]
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --build-label)
      BUILD_LABEL="$2"
      shift 2
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "${VERSION}" ] || [ -z "${OUTPUT_DIR}" ]; then
  usage >&2
  exit 1
fi

if [ ! -d "${BUILD_DIR}" ]; then
  echo "Linux build output not found at ${BUILD_DIR}" >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"
rm -rf "${OUTPUT_DIR}/kelpie-linux"
mkdir -p "${OUTPUT_DIR}/kelpie-linux"

while IFS= read -r runtime_file; do
  [ -n "${runtime_file}" ] || continue

  if [ ! -e "${BUILD_DIR}/${runtime_file}" ]; then
    echo "Missing runtime file: ${BUILD_DIR}/${runtime_file}" >&2
    exit 1
  fi

  cp -a "${BUILD_DIR}/${runtime_file}" "${OUTPUT_DIR}/kelpie-linux/"
done < "${MANIFEST}"

chmod 755 "${OUTPUT_DIR}/kelpie-linux/kelpie-linux"
chmod 755 "${OUTPUT_DIR}/kelpie-linux/chrome-sandbox"

cat > "${OUTPUT_DIR}/kelpie-linux/README.txt" <<EOF
Kelpie Linux release bundle
Version: ${VERSION}
Build: ${BUILD_LABEL:-generic}

Run:
  ./kelpie-linux

Notes:
- This bundle includes the Chromium Embedded Framework runtime.
- It still depends on common system libraries such as GTK3, NSS, NSPR, Pango,
  Fontconfig, Avahi, and ALSA.
- Native distro packages and package repositories are generated from this same
  runtime bundle during release automation.
EOF
