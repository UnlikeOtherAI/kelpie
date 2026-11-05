#!/bin/bash
set -euo pipefail
# Disposable CI container only: diagnostic tracing can perturb Chromium.
[[ $# == 2 && $EUID == 0 ]] || { echo "Expected distro and candidate directory as container root" >&2; exit 1; }
distro="$1"
package_root="$(realpath "$2")"
[[ "$package_root" == /workspace/dist/release/* && -d "$package_root" ]] || exit 1
output="$package_root/namespace-diagnostic"
mkdir "$output"
printf '%s\n' 'ptrace diagnostic; sandbox/profile/NNP/limits unchanged; untraced replay required' > "$output/scope.txt"
stage=install
trap 'code=$?; printf "{\"stage\":\"%s\",\"exitCode\":%s}\n" "$stage" "$code" > "$output/outcome.json"' EXIT
case "$distro" in
  ubuntu-22.04)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates util-linux strace
    mapfile -d '' candidates < <(find "$package_root" -maxdepth 1 -type f -name '*.deb' -print0)
    [[ ${#candidates[@]} == 1 ]]
    apt-get install -y --no-install-recommends "${candidates[0]}"
    ;;
  fedora-44)
    dnf install -y ca-certificates util-linux shadow-utils strace
    mapfile -d '' candidates < <(find "$package_root" -maxdepth 1 -type f -name '*.rpm' -print0)
    [[ ${#candidates[@]} == 1 ]]
    dnf install -y "${candidates[0]}"
    ;;
  *) echo "Unsupported diagnostic distro" >&2; exit 1 ;;
esac
stage=identity
sha256sum "${candidates[0]}" /usr/bin/kelpie-linux /opt/kelpie/libcef.so > "$output/installed-sha256.txt"
expected="$(awk '$2 == "apps/linux/build/kelpie-linux" { print $1 }' "$package_root/binary-sha256.txt")"
[[ "$expected" =~ ^[a-f0-9]{64}$ && "$(sha256sum /usr/bin/kelpie-linux | cut -d ' ' -f1)" == "$expected" ]]
expected_cef="$(awk '$2 == "apps/linux/build/libcef.so" { print $1 }' "$package_root/binary-sha256.txt")"
[[ "$expected_cef" =~ ^[a-f0-9]{64}$ && "$(sha256sum /opt/kelpie/libcef.so | cut -d ' ' -f1)" == "$expected_cef" ]]
useradd --uid 10001 --create-home --home-dir /tmp/kelpie-trace-home kelpie-trace
home=/tmp/kelpie-trace-home
mkdir "$home/runtime"
chmod 700 "$home" "$home/runtime"
chown -R kelpie-trace:kelpie-trace "$home" "$output"
stage=namespace-preflight
runuser -u kelpie-trace -- timeout 10 unshare --user --map-root-user --net --pid --fork true > "$output/preflight.txt" 2>&1
stage=ptrace-diagnostic
# One combined trace is file-size bounded, rather than one unbounded file per child.
# No execve, payload, profile contents or HTTP bearer tokens are traced.
set +e
(
  ulimit -f 16384
  timeout --signal=TERM --kill-after=5 20 runuser -u kelpie-trace -- env \
    HOME="$home" XDG_RUNTIME_DIR="$home/runtime" TMPDIR="$home/runtime" \
    strace -f -tt -s 64 -e trace=clone,clone3,unshare,setns \
      -o "$output/namespace-syscalls.txt" /usr/bin/kelpie-linux --headless --port 0 \
      --profile-dir "$home/profile" --readiness-file "$home/runtime/readiness.json" --url about:blank
) > "$output/app.log" 2>&1
result=$?
set -e
printf '%s\n' "$result" > "$output/traced-exit.txt"
stage=complete
# Timeout or ptrace denial is evidence, not a passing installed verification.
