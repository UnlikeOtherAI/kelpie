#!/bin/bash
# Exercise the shipped portable installer without touching a real installation.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
scratch="$(mktemp -d "$root/.cache/update-install-test-XXXXXX")"
mkdir -p "$scratch/bin"
cat > "$scratch/bin/curl" <<'CURL'
#!/bin/bash
set -euo pipefail
while [ "$#" -gt 0 ]; do
  if [ "$1" = --output ]; then cp -- "$KELPIE_TEST_ARCHIVE" "$2"; exit 0; fi
  shift
done
exit 1
CURL
chmod 755 "$scratch/bin/curl"
export PATH="$scratch/bin:$PATH"

run_case() {
  local name="$1" mode="$2"
  local work="$scratch/$name"
  mkdir -p "$work/installed/profile" "$work/package/kelpie-linux" "$work/operation"
  printf 'saved browser data\n' > "$work/installed/profile/preferences"
  cat > "$work/installed/kelpie-linux" <<'OLD'
#!/bin/bash
printf 'old\n' > "$1"
printf '%s\n' "$$" > "$1.pid"
sleep 15
OLD
  chmod 755 "$work/installed/kelpie-linux"
  if [ "$mode" = restart-failure ]; then
    printf '#!/bin/bash\nexit 1\n' > "$work/package/kelpie-linux/kelpie-linux"
  else
    cat > "$work/package/kelpie-linux/kelpie-linux" <<'NEW'
#!/bin/bash
printf 'new\n' > "$1"
printf '%s\n' "$$" > "$1.pid"
sleep 15
NEW
  fi
  chmod 755 "$work/package/kelpie-linux/kelpie-linux"
  touch "$work/package/kelpie-linux/libcef.so" "$work/package/kelpie-linux/install-update.sh"
  tar -czf "$work/package.tar.gz" -C "$work/package" kelpie-linux
  export KELPIE_TEST_ARCHIVE="$work/package.tar.gz"
  local hash
  hash="$(sha256sum "$KELPIE_TEST_ARCHIVE" | cut -d ' ' -f 1)"
  if [ "$mode" = checksum-failure ]; then hash="$(printf '%064d' 0)"; fi
  local result=0
  /bin/bash "$root/apps/updates/install-linux.sh" "$work/operation" 99999999 \
    'https://github.com/UnlikeOtherAI/kelpie/releases/download/test/package.tar.gz' \
    "$hash" 0.2.1 "$work/installed/kelpie-linux" tar "$work/installed/profile" "$work/restarted" || result=$?
  if [ "$mode" = success ]; then
    [ "$result" = 0 ]
    [ "$(cat "$work/operation/status")" = installed ]
    [ "$(cat "$work/restarted")" = new ]
  elif [ "$mode" = checksum-failure ]; then
    [ "$result" != 0 ]
    [ "$(cat "$work/operation/status")" = error ]
    [ ! -e "$work/restarted" ]
    grep -q "printf 'old" "$work/installed/kelpie-linux"
  else
    [ "$result" != 0 ]
    [ "$(cat "$work/operation/status")" = error ]
    [ "$(cat "$work/restarted")" = old ]
  fi
  [ "$(cat "$work/installed/profile/preferences")" = 'saved browser data' ]
  if [ -f "$work/restarted.pid" ]; then
    # Only the fixture's known child is stopped, never a Kelpie process.
    kill "$(cat "$work/restarted.pid")" 2>/dev/null || true
  fi
  printf 'PASS: %s\n' "$mode"
}
run_case valid success
run_case corrupt checksum-failure
run_case rollback restart-failure
if [ "$(id -u)" != 0 ]; then
  if bash "$root/apps/updates/install-linux.sh" --apply-managed \
    'https://github.com/UnlikeOtherAI/kelpie/releases/download/test/package.deb' "$(printf '%064d' 0)" deb; then
    echo 'The privileged installer accepted an unprivileged caller.' >&2
    exit 1
  fi
  printf 'PASS: managed install requires system authorization\n'
fi
printf 'Installer test evidence: %s\n' "$scratch"
