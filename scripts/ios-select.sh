#!/usr/bin/env bash
# iOS device / simulator picker for `make ios`.
#
# Usage:
#   ios-select.sh              → interactive picker (auto-selects if only one option)
#   ios-select.sh list         → print numbered list to stdout and exit
#   ios-select.sh <udid>       → validate + use that identifier directly
#
# On success (non-list mode) outputs one line to stdout: "<udid>\t<type>"
#   type = "simulator" | "device"
#
# Remembers last selection in .cache/ios-device.

set -euo pipefail

CACHE_FILE="$(git rev-parse --show-toplevel 2>/dev/null || echo '.')/.cache/ios-device"
mkdir -p "$(dirname "$CACHE_FILE")"

ARG="${1:-}"

# ── collect entries ────────────────────────────────────────────────────────────
# Format per entry: "LABEL|ID|TYPE"

entries=()

# 1. Connected physical iPhones/iPads via devicectl.
# Extract UUID with grep to avoid fighting with space-padded columns.
while IFS= read -r line; do
  identifier=$(echo "$line" | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' | head -1)
  [[ -z "$identifier" ]] && continue
  echo "$line" | grep -qi "available" || continue
  echo "$line" | grep -qiE "iPhone|iPad" || continue
  name=$(echo "$line" | sed 's/  .*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  entries+=("${name} [device]|${identifier}|device")
done < <(xcrun devicectl list devices 2>/dev/null | tail -n +3)

# 2. Available simulators (iPhone / iPad only)
while IFS='|' read -r simname udid rt; do
  simname="$(echo "$simname" | sed 's/[[:space:]]*$//')"
  udid="$(echo "$udid" | sed 's/[[:space:]]*//')"
  rt_short="$(echo "$rt" \
    | sed 's/com\.apple\.CoreSimulator\.SimRuntime\.//' \
    | sed 's/iOS-/iOS /' \
    | sed 's/-[0-9]*$//' \
    | sed 's/-/./g')"
  entries+=("${simname} (${rt_short} Simulator)|${udid}|simulator")
done < <(
  python3 -c "
import json, subprocess
data = json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']).decode())
for rt, devs in data['devices'].items():
    for dev in devs:
        n = dev['name']; u = dev['udid']
        if 'iPhone' in n or 'iPad' in n:
            print(n + '|' + u + '|' + rt)
"
)

if [[ ${#entries[@]} -eq 0 ]]; then
  echo "ERROR: No iOS devices or simulators found." >&2
  exit 1
fi

# ── list mode ─────────────────────────────────────────────────────────────────
if [[ "$ARG" == "list" ]]; then
  printf "\n  Available iOS targets:\n\n"
  for i in "${!entries[@]}"; do
    label=$(echo "${entries[$i]}" | cut -d'|' -f1)
    id=$(echo "${entries[$i]}" | cut -d'|' -f2)
    printf "  %d. %s\n     %s\n\n" "$((i+1))" "$label" "$id"
  done
  exit 0
fi

# ── direct identifier mode ─────────────────────────────────────────────────────
if [[ -n "$ARG" ]]; then
  for entry in "${entries[@]}"; do
    id_field=$(echo "$entry" | cut -d'|' -f2)
    type_field=$(echo "$entry" | cut -d'|' -f3)
    if [[ "$id_field" == "$ARG" ]]; then
      echo "$id_field" > "$CACHE_FILE"
      printf "%s\t%s\n" "$id_field" "$type_field"
      exit 0
    fi
  done
  echo "ERROR: '$ARG' not found in available devices/simulators. Run 'make ios list' to see options." >&2
  exit 1
fi

# ── load last selection ────────────────────────────────────────────────────────
last_id=""
[[ -f "$CACHE_FILE" ]] && last_id=$(cat "$CACHE_FILE")

# ── auto-select if only one option ────────────────────────────────────────────
if [[ ${#entries[@]} -eq 1 ]]; then
  id_field=$(echo "${entries[0]}" | cut -d'|' -f2)
  type_field=$(echo "${entries[0]}" | cut -d'|' -f3)
  label_field=$(echo "${entries[0]}" | cut -d'|' -f1)
  echo "$id_field" > "$CACHE_FILE"
  printf "  Auto-selected: %s\n\n" "$label_field" >&2
  printf "%s\t%s\n" "$id_field" "$type_field"
  exit 0
fi

# ── interactive picker ─────────────────────────────────────────────────────────
default=0
for i in "${!entries[@]}"; do
  if [[ "$(echo "${entries[$i]}" | cut -d'|' -f2)" == "$last_id" ]]; then
    default=$i
    break
  fi
done

selected=$default
count=${#entries[@]}

draw_menu() {
  tput rc 2>/dev/null || true
  printf "\n  Select iOS target  (↑↓ or number, Enter to confirm)\n\n" >&2
  for i in "${!entries[@]}"; do
    label=$(echo "${entries[$i]}" | cut -d'|' -f1)
    id_field=$(echo "${entries[$i]}" | cut -d'|' -f2)
    [[ $i -eq $selected ]] && prefix=" ▶ " || prefix="   "
    suffix=""; [[ "$id_field" == "$last_id" ]] && suffix="  (last)"
    printf "  %s%d. %s%s\n" "$prefix" "$((i+1))" "$label" "$suffix" >&2
  done
  printf "\n" >&2
}

tput sc 2>/dev/null || true
draw_menu

old_stty=$(stty -g)
stty raw -echo

while true; do
  k=$(dd bs=1 count=1 2>/dev/null)
  if [[ "$k" == $'\x1b' ]]; then
    k2=$(dd bs=1 count=1 2>/dev/null)
    if [[ "$k2" == "[" ]]; then
      k3=$(dd bs=1 count=1 2>/dev/null)
      case "$k3" in
        A) selected=$(( (selected - 1 + count) % count )); draw_menu ;;
        B) selected=$(( (selected + 1) % count ));         draw_menu ;;
      esac
    fi
  elif [[ "$k" == $'\r' || "$k" == $'\n' ]]; then
    break
  elif [[ "$k" =~ ^[1-9]$ ]]; then
    n=$(( k - 1 ))
    if [[ $n -lt $count ]]; then
      selected=$n; draw_menu; break
    fi
  elif [[ "$k" == "q" || "$k" == $'\x03' ]]; then
    stty "$old_stty"
    printf "\nCancelled.\n" >&2
    exit 1
  fi
done

stty "$old_stty"

id_field=$(echo "${entries[$selected]}" | cut -d'|' -f2)
type_field=$(echo "${entries[$selected]}" | cut -d'|' -f3)
label_field=$(echo "${entries[$selected]}" | cut -d'|' -f1)

echo "$id_field" > "$CACHE_FILE"
printf "\n  ✓ Selected: %s\n\n" "$label_field" >&2
printf "%s\t%s\n" "$id_field" "$type_field"
