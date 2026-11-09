#!/bin/bash
set -euo pipefail
# Managed installs use the existing root-owned helper. The privileged process
# downloads into its own private directory rather than installing a mutable
# user-owned file after a checksum check in another process.
if [ "${1:-}" = --apply-managed ]; then
  [[ "$(id -u)" = 0 && "$#" = 4 ]]
  export PATH=/usr/sbin:/usr/bin:/sbin:/bin
  root_url="$2"; root_hash="$3"; root_format="$4"
  [[ "$root_url" == https://github.com/UnlikeOtherAI/kelpie/releases/download/* &&
     "$root_url" != *..* && "$root_url" != *'%'* && "$root_url" != *'?'* && "$root_url" != *'#'* &&
     "$root_hash" =~ ^[a-f0-9]{64}$ ]]
  [[ "$root_format" == deb || "$root_format" == rpm ]]
  [[ "$root_url" == *."$root_format" ]]
  root_scratch="$(mktemp -d /var/tmp/kelpie-managed-update-XXXXXX)"
  case "$root_scratch" in /var/tmp/kelpie-managed-update-*) ;; *) exit 1;; esac
  trap 'rm -rf -- "$root_scratch"' EXIT
  root_archive="$root_scratch/package.$root_format"
  curl --fail --location --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 300 --output "$root_archive" "$root_url"
  [[ "$(sha256sum "$root_archive" | cut -d ' ' -f 1)" == "$root_hash" ]]
  if [ "$root_format" = deb ]; then
    [[ "$(dpkg-deb -f "$root_archive" Package)" == kelpie && "$(dpkg-deb -f "$root_archive" Architecture)" == amd64 ]]
    apt-get install -y --allow-downgrades "$root_archive"
  else
    [[ "$(rpm -qp --queryformat '%{NAME} %{ARCH}' "$root_archive")" == 'kelpie x86_64' ]]
    dnf install -y "$root_archive"
  fi
  exit 0
fi
operation="$1"; parent="$2"; url="$3"; expected_hash="$4"; version="$5"; executable="$6"; format="$7"
profile="$8"
shift 8
profile="$(realpath "$profile")"
restart_args=("$@")
closed=false; moved=false; installed=false
backup=""; destination=""; staged=""
restart() { "$executable" "${restart_args[@]}" > "$operation/restart.log" 2>&1 & }
fail() {
  local code=$?
  trap - ERR
  printf '%s\n' 'The update could not be downloaded, verified or installed. Restart Kelpie to try again.' > "$operation/error"
  printf 'error\n' > "$operation/status"
  if $moved; then
    if $installed; then mv -- "$destination" "${destination}.failed-$(date +%s)-$$"; fi
    mv -- "$backup" "$destination"
  fi
  if $closed; then restart; fi
  exit "${code:-1}"
}
trap fail ERR
[[ "$parent" =~ ^[0-9]+$ && "$expected_hash" =~ ^[a-f0-9]{64}$ && "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$url" == https://github.com/UnlikeOtherAI/kelpie/releases/download/* && "$url" != *..* && "$url" != *'%'* && "$url" != *'?'* && "$url" != *'#'* ]]
[[ "$executable" == /* && -x "$executable" && ! -L "$executable" ]]
case "$format" in
  appimage) extension=AppImage; destination="$executable";;
  tar) extension=tar.gz; destination="$(dirname "$executable")";;
  deb) extension=deb; command -v pkexec; command -v apt-get; [[ "$executable" == /opt/kelpie/kelpie-linux ]];;
  rpm) extension=rpm; command -v pkexec; command -v dnf; [[ "$executable" == /opt/kelpie/kelpie-linux ]];;
  *) false;;
esac
if [[ "$format" == deb || "$format" == rpm ]]; then
  [[ ! -L /opt/kelpie && ! -L /opt/kelpie/install-update.sh ]]
  [[ "$(stat -c %u /opt/kelpie)" = 0 && "$(stat -c %u /opt/kelpie/install-update.sh)" = 0 ]]
  for path in /opt/kelpie /opt/kelpie/install-update.sh; do
    mode="$(stat -c %a "$path")"
    (( (8#$mode & 022) == 0 ))
  done
fi
[[ "$url" == *."$extension" ]]
archive="$operation/package.$extension"
printf 'downloading\n' > "$operation/status"
curl --fail --location --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 300 --output "$archive" "$url"
[[ "$(sha256sum "$archive" | cut -d ' ' -f 1)" == "$expected_hash" ]]
printf 'verifying\n' > "$operation/status"
case "$format" in
  appimage)
    [[ -w "$(dirname "$destination")" ]]
    staged="${destination}.update-$$"; cp -- "$archive" "$staged"; chmod 755 "$staged"
    ;;
  tar)
    [[ -w "$(dirname "$destination")" && "$destination" != / && ! -L "$destination" ]]
    [[ "$(realpath "$profile")" != "$(realpath "$destination")" ]]
    ! tar -tzf "$archive" | grep -Eq '(^/|(^|/)\.\.(/|$))'
    staged="${destination}.update-$$"; mkdir -- "$staged"
    tar -xzf "$archive" -C "$staged" --strip-components=1 --no-same-owner
    [[ -x "$staged/kelpie-linux" && -f "$staged/libcef.so" && -f "$staged/install-update.sh" ]]
    ;;
  deb) [[ "$(dpkg-deb -f "$archive" Package)" == kelpie && "$(dpkg-deb -f "$archive" Architecture)" == amd64 ]];;
  rpm) [[ "$(rpm -qp --queryformat '%{NAME} %{ARCH}' "$archive")" == 'kelpie x86_64' ]];;
esac
printf 'ready\n' > "$operation/status"
for ((attempt=0; attempt<600; attempt++)); do
  if ! kill -0 "$parent" 2>/dev/null; then closed=true; break; fi
  sleep 0.5
done
$closed
# CEF subprocesses may still be flushing the profile after their parent exits.
# Wait for the exact executable, without matching or stopping unrelated apps.
for ((attempt=0; attempt<300; attempt++)); do
  remaining=false
  for process in /proc/[0-9]*/exe; do
    if [[ "$(readlink "$process" 2>/dev/null || true)" == "$executable" ]]; then remaining=true; break; fi
  done
  if ! $remaining; then break; fi
  sleep 0.1
done
! $remaining
if [[ "$format" == tar && "$(realpath "$profile")" == "$(realpath "$destination")/"* ]]; then
  relative="${profile#"$destination/"}"
  [[ ! -e "$staged/$relative" ]]
  mkdir -p -- "$(dirname "$staged/$relative")"
  cp -a -- "$profile" "$staged/$relative"
fi
case "$format" in
  appimage|tar)
    backup="${destination}.previous-$(date +%s)-$$"
    mv -- "$destination" "$backup"; moved=true
    mv -- "$staged" "$destination"; installed=true
    ;;
  deb|rpm) pkexec /bin/bash /opt/kelpie/install-update.sh --apply-managed "$url" "$expected_hash" "$format";;
esac
restart
child=$!
sleep 5
kill -0 "$child"
printf 'installed\n' > "$operation/status"
# Keep portable-install backups; native packages remain owned by apt/dnf.
