#!/bin/bash
set -euo pipefail
# Run only inside the fresh, disposable distro test container, after packaging.
[[ $# == 2 && $EUID == 0 ]] || { echo "Expected distro and candidate directory as container root" >&2; exit 1; }
distro="$1"
package_root="$(realpath "$2")"
[[ "$package_root" == /workspace/dist/release/* && -d "$package_root" ]] || exit 1
output="$package_root/installed-smoke"
mkdir "$output"
stage=install
trap 'code=$?; printf "{\"stage\":\"%s\",\"exitCode\":%s}\n" "$stage" "$code" > "$output/outcome.json"' EXIT

case "$distro" in
  ubuntu-22.04)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates curl xz-utils util-linux binutils ffmpeg
    mapfile -d '' candidates < <(find "$package_root" -maxdepth 1 -type f -name '*.deb' -print0)
    [[ ${#candidates[@]} == 1 ]]
    candidate="${candidates[0]}"
    apt-get install -y --no-install-recommends "$candidate"
    dpkg-query -W > "$output/runtime-system-packages.txt"
    dpkg-query -W kelpie > "$output/installed-package.txt"
    dpkg-deb -f "$candidate" > "$output/candidate-metadata.txt"
    ;;
  fedora-44)
    dnf install -y ca-certificates curl xz util-linux binutils shadow-utils ffmpeg-free
    mapfile -d '' candidates < <(find "$package_root" -maxdepth 1 -type f -name '*.rpm' -print0)
    [[ ${#candidates[@]} == 1 ]]
    candidate="${candidates[0]}"
    dnf install -y "$candidate"
    rpm -qa > "$output/runtime-system-packages.txt"
    rpm -q kelpie > "$output/installed-package.txt"
    rpm -qip "$candidate" > "$output/candidate-metadata.txt"
    ;;
  *) echo "Unsupported installed test distro" >&2; exit 1 ;;
esac
stage=verify-installed-hashes
sha256sum "$candidate" /usr/bin/kelpie-linux /opt/kelpie/libcef.so > "$output/installed-sha256.txt"
expected="$(awk '$2 == "apps/linux/build/kelpie-linux" { print $1 }' "$package_root/binary-sha256.txt")"
[[ "$expected" =~ ^[a-f0-9]{64}$ ]]
[[ "$(sha256sum /usr/bin/kelpie-linux | cut -d ' ' -f1)" == "$expected" ]] || { echo "Installed executable differs from tested build" >&2; exit 1; }
expected_cef="$(awk '$2 == "apps/linux/build/libcef.so" { print $1 }' "$package_root/binary-sha256.txt")"
[[ "$expected_cef" =~ ^[a-f0-9]{64}$ ]]
[[ "$(sha256sum /opt/kelpie/libcef.so | cut -d ' ' -f1)" == "$expected_cef" ]] || { echo "Installed CEF differs from tested build" >&2; exit 1; }
stat -c '%a %U %G %n' /opt/kelpie/chrome-sandbox > "$output/sandbox-helper.txt"
# Never install a new privileged helper as a test workaround.
[[ "$(stat -c %a /opt/kelpie/chrome-sandbox)" == 755 ]]
readelf -d /usr/bin/kelpie-linux > "$output/installed-elf.txt"
ldd /usr/bin/kelpie-linux > "$output/installed-linker.txt"
! grep -q 'not found' "$output/installed-linker.txt"
cp /opt/kelpie/README.txt "$output/installed-bundle.txt"
cp /etc/os-release "$output/os-release.txt"
source_revision="$(cat "$package_root/source-revision.txt")"
[[ "$source_revision" =~ ^[a-f0-9]{40}$ ]]
printf '%s\n' "$source_revision" > "$output/source-revision.txt"
[[ "$(cat /opt/kelpie/source-revision.txt)" == "$source_revision" ]]
sha256sum /opt/kelpie/source-revision.txt > "$output/embedded-source-sha256.txt"

stage=client
# A test runtime, never part of the native package. Verify the upstream archive.
node_name=node-v22.14.0-linux-x64.tar.xz
curl -fsSL "https://nodejs.org/dist/v22.14.0/$node_name" -o "/tmp/$node_name"
curl -fsSL https://nodejs.org/dist/v22.14.0/SHASUMS256.txt -o /tmp/kelpie-node-shasums.txt
grep "  $node_name$" /tmp/kelpie-node-shasums.txt > "$output/node-runtime-sha256.txt"
(cd /tmp && sha256sum -c "$output/node-runtime-sha256.txt")
tar -xJf "/tmp/$node_name" -C /opt
node=/opt/node-v22.14.0-linux-x64/bin/node
mapfile -d '' clients < <(find "$package_root" -maxdepth 1 -type f -name '*.tgz' -print0)
[[ ${#clients[@]} == 1 ]]
sha256sum "${clients[0]}" > "$output/client-package-sha256.txt"
useradd --uid 10001 --create-home --home-dir /tmp/kelpie-installed-home kelpie-smoke
home=/tmp/kelpie-installed-home
mkdir "$home/client" "$home/runtime"
chmod 700 "$home" "$home/runtime"
tar -xzf "${clients[0]}" -C "$home/client"
# Use the already frozen build's external JS dependencies; no fresh resolver.
ln -s /workspace/packages/cli/node_modules "$home/client/package/node_modules"
chown -R kelpie-smoke:kelpie-smoke "$home" "$output"
export PATH="/opt/node-v22.14.0-linux-x64/bin:$PATH"

stage=sandbox-preflight
# Actual namespace policy, not an assumption from command-line flags.
# Failure is a runtime-host blocker; do not weaken the container or Chromium.
runuser -u kelpie-smoke -- timeout 10 unshare --user --map-root-user --net --pid --fork true \
  > "$output/namespace-preflight.txt" 2>&1
run() {
  runuser -u kelpie-smoke -- env HOME="$home" XDG_RUNTIME_DIR="$home/runtime" \
    TMPDIR="$home/runtime" NODE_OPTIONS=--max-old-space-size=2048 \
    KELPIE_CAPTURE_SOURCE="$source_revision" KELPIE_TEST_REVISION="$source_revision" \
    KELPIE_CLI_BUILD_REVISION="$source_revision" \
    KELPIE_LINUX_FINALIZE_FAULT=1 KELPIE_LINUX_PREINPUT_REPLACEMENT=1 \
    timeout --signal=TERM --kill-after=10 300 "$node" "$@"
}
stage=native-http-mcp
run tests/linux/run-native-capture-acceptance.mjs /usr/bin/kelpie-linux "$output/capture" \
  > "$output/native-corpus.log" 2>&1
stage=independent-media
run tests/linux/verify-native-replay.mjs "$output/capture" > "$output/native-media.log" 2>&1
stage=public-cli
run tests/linux/run-native-alias-acceptance.mjs /usr/bin/kelpie-linux \
  "$home/client/package/bin/kelpie.js" "$output/alias" offscreen > "$output/public-cli.log" 2>&1
stage=complete
