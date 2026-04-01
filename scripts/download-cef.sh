#!/bin/bash
set -euo pipefail

TARGET_PLATFORM="${1:-$(uname -s | tr '[:upper:]' '[:lower:]')}"
TMP_ROOT="/tmp/mollotov-cef"
mkdir -p "${TMP_ROOT}"

download_and_extract() {
    local url="$1"
    local tarball="$2"
    local extract_root="$3"

    echo "Downloading CEF from ${url}..."
    curl -L --fail -o "${tarball}" "${url}"

    echo "Extracting..."
    mkdir -p "${extract_root}"
    tar -xjf "${tarball}" -C "${extract_root}"
}

install_macos_arm64() {
    local cef_version="146.0.9+g3ca6a87+chromium-146.0.7680.165"
    local cef_platform="macosarm64"
    local outdir="apps/macos/Frameworks"
    local tarball="${TMP_ROOT}/cef-${cef_platform}.tar.bz2"
    local extract_root="${TMP_ROOT}/extract-macos"
    local url="https://cef-builds.spotifycdn.com/cef_binary_${cef_version}_${cef_platform}_minimal.tar.bz2"

    rm -rf "${extract_root}"
    download_and_extract "${url}" "${tarball}" "${extract_root}"

    local extracted
    extracted=$(find "${extract_root}" -maxdepth 1 -type d -name "cef_binary_*_${cef_platform}_minimal" | head -1)
    if [ -z "${extracted}" ]; then
        echo "ERROR: macOS extraction failed"
        exit 1
    fi

    mkdir -p "${outdir}"
    rm -rf "${outdir}/Chromium Embedded Framework.framework" "${outdir}/cef_include"
    cp -R "${extracted}/Release/Chromium Embedded Framework.framework" "${outdir}/"
    cp -R "${extracted}/include" "${outdir}/cef_include"

    ln -sfn "${outdir}/cef_include" "${outdir}/cef_include/include"

    local cef_fw="${outdir}/Chromium Embedded Framework.framework"
    if [ -f "${cef_fw}/Resources/Info.plist" ] && [ ! -e "${cef_fw}/Info.plist" ]; then
        ln -sf Resources/Info.plist "${cef_fw}/Info.plist"
    fi

    rm -rf "${extract_root}" "${tarball}"
    echo "CEF framework installed at ${outdir}/Chromium Embedded Framework.framework"
    echo "CEF headers installed at ${outdir}/cef_include/"
}

install_linux_x64() {
    local cef_version="120.2.7+g4bc6a59+chromium-120.0.6099.234"
    local cef_platform="linux64_minimal"
    local cache_root="${HOME}/.cache/mollotov/cef"
    local version_root="${cache_root}/cef_binary_${cef_version}_${cef_platform}"
    local current_link="${cache_root}/linux64-current"
    local tarball="${TMP_ROOT}/cef-${cef_platform}.tar.bz2"
    local extract_root="${TMP_ROOT}/extract-linux"
    local url="https://cef-builds.spotifycdn.com/cef_binary_${cef_version}_${cef_platform}.tar.bz2"

    rm -rf "${extract_root}"
    download_and_extract "${url}" "${tarball}" "${extract_root}"

    local extracted
    extracted=$(find "${extract_root}" -maxdepth 1 -type d -name "cef_binary_*_${cef_platform}" | head -1)
    if [ -z "${extracted}" ]; then
        echo "ERROR: Linux extraction failed"
        exit 1
    fi

    mkdir -p "${cache_root}"
    rm -rf "${version_root}"
    mv "${extracted}" "${version_root}"

    if [ -f "${version_root}/CMakeLists.txt" ]; then
        cmake -S "${version_root}" -B "${version_root}/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DUSE_SANDBOX=OFF
        cmake --build "${version_root}/build" --target libcef_dll_wrapper
    fi

    ln -sfn "${version_root}" "${current_link}"
    rm -rf "${extract_root}" "${tarball}"
    echo "Linux CEF SDK installed at ${version_root}"
    echo "Stable symlink updated at ${current_link}"
}

case "${TARGET_PLATFORM}" in
    macos|darwin)
        install_macos_arm64
        ;;
    linux)
        install_linux_x64
        ;;
    *)
        echo "Unsupported platform: ${TARGET_PLATFORM}"
        echo "Usage: $0 [linux|macos]"
        exit 1
        ;;
esac
