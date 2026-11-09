#!/bin/bash
set -euo pipefail
operation="$1"; parent="$2"; url="$3"; expected_hash="$4"; version="$5"; destination="$6"
shift 6
restart_args=("$@")
closed=false; moved=false; installed=false
backup="${destination}.previous-$(/usr/bin/uuidgen)"
staged="$(/usr/bin/dirname "$destination")/.kelpie-update-$(/usr/bin/uuidgen)"
fail() {
  local code=$?
  trap - ERR
  printf '%s\n' 'The update could not be downloaded, verified or installed. Your previous Kelpie has been kept.' > "$operation/error"
  printf 'error\n' > "$operation/status"
  if $moved; then
    if $installed; then /bin/mv "$destination" "${destination}.failed-$(/usr/bin/uuidgen)"; fi
    /bin/mv "$backup" "$destination"
  fi
  if $closed; then /usr/bin/open "$destination" --args "${restart_args[@]}"; fi
  exit "${code:-1}"
}
trap fail ERR
[[ "$parent" =~ ^[0-9]+$ && "$expected_hash" =~ ^[a-f0-9]{64}$ && "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$url" == https://github.com/UnlikeOtherAI/kelpie/releases/download/*.zip && "$url" != *..* && "$url" != *'%'* && "$url" != *'?'* && "$url" != *'#'* ]]
[[ "$destination" == /*.app && -d "$destination" && ! -L "$destination" ]]
[[ -w "$(/usr/bin/dirname "$destination")" ]]
team=$(/usr/bin/codesign -dv --verbose=4 "$destination" 2>&1 | /usr/bin/sed -n 's/^TeamIdentifier=//p')
[[ "$team" =~ ^[A-Z0-9]{10}$ ]]
printf 'downloading\n' > "$operation/status"
/usr/bin/curl --fail --location --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 300 \
  --output "$operation/package.zip" "$url"
actual_hash=$(/usr/bin/shasum -a 256 "$operation/package.zip" | /usr/bin/cut -d ' ' -f 1)
[[ "$actual_hash" == "$expected_hash" ]]
printf 'verifying\n' > "$operation/status"
/bin/mkdir "$staged"
# Reject traversal before extraction. Symlinks inside a signed app framework are
# required, so signature validation, rather than stripping links, seals its tree.
! /usr/bin/unzip -Z1 "$operation/package.zip" | /usr/bin/grep -Eq '(^/|(^|/)\.\.(/|$))'
# libarchive's default extraction refuses writes through symlink directories.
# Preserve legitimate framework links without letting an unverified ZIP write
# outside staging before its Developer ID signature has been checked.
/usr/bin/tar -xf "$operation/package.zip" -C "$staged"
app="$staged/Kelpie.app"
[[ -d "$app" && ! -L "$app" ]]
/usr/bin/codesign --verify --deep --strict "$app"
new_team=$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1 | /usr/bin/sed -n 's/^TeamIdentifier=//p')
[[ "$new_team" == "$team" ]]
/usr/sbin/spctl --assess --type execute "$app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$version" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == \
   "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")" ]]
printf 'ready\n' > "$operation/status"
for ((attempt=0; attempt<600; attempt++)); do
  if ! /bin/kill -0 "$parent" 2>/dev/null; then closed=true; break; fi
  /bin/sleep 0.5
done
$closed
/bin/mv "$destination" "$backup"; moved=true
/bin/mv "$app" "$destination"; installed=true
/usr/bin/open "$destination" --args "${restart_args[@]}"
/bin/sleep 5
/usr/bin/pgrep -f "${destination}/Contents/MacOS/Kelpie" >/dev/null
printf 'installed\n' > "$operation/status"
# The previous bundle stays beside the installation for recovery.
