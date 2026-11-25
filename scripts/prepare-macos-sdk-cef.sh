#!/bin/bash
# Prepare an architecture-specific, checksum-verified SDK in an isolated build directory.
set -euo pipefail
arch="${1:?architecture}"
destination="${2:?SDK directory}"
case "$arch" in
    arm64) platform=macosarm64; digest=eb4877f894615c0f1b806b699c74d19c476696f7716daee22811b883a9e8441f ;;
    x86_64) platform=macosx64; digest=38e5264c72ab4bdc7e3c0889faed8a30496344a7a76a81e2ad6557006d3e24d7 ;;
    *) exit 2 ;;
esac
if [ -f "$destination/archive.sha256" ] && [ "$(cat "$destination/archive.sha256")" = "$digest" ]; then exit 0; fi
test ! -e "$destination"
scratch="$(mktemp -d "$(dirname "$destination")/cef.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT
version='158.0.3+g8c29be2+chromium-158.0.8127.18'
name="cef_binary_${version}_${platform}_minimal"
curl --fail --location --retry 3 -o "$scratch/archive" "https://cef-builds.spotifycdn.com/$name.tar.bz2"
printf '%s  %s\n' "$digest" "$scratch/archive" | shasum -a 256 --check --status
tar -xjf "$scratch/archive" -C "$scratch" "$name/Release" "$name/include"
mkdir "$scratch/sdk"
mv "$scratch/$name/Release/Chromium Embedded Framework.framework" "$scratch/sdk/"
mv "$scratch/$name/include" "$scratch/sdk/cef_include"
ln -s . "$scratch/sdk/cef_include/include"
framework="$scratch/sdk/Chromium Embedded Framework.framework"
[ -e "$framework/Info.plist" ] || ln -s Resources/Info.plist "$framework/Info.plist"
printf '%s\n' "$digest" > "$scratch/sdk/archive.sha256"
mv "$scratch/sdk" "$destination"
