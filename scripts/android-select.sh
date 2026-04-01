#!/usr/bin/env bash
# Android device / emulator / AVD picker for `make android`.
#
# Usage:
#   android-select.sh                  → interactive picker (auto-selects if only one)
#   android-select.sh list             → print numbered list and exit
#   android-select.sh non-interactive  → auto-select without prompting
#   android-select.sh <serial|avd>     → use that target directly
#
# On success (non-list mode) outputs one line to stdout: "<serial_or_avd>\t<type>"
#   type = "running"  (already-connected device or emulator — use serial with adb -s)
#          "avd"      (AVD not yet running — caller must boot it first)
#
# Remembers last selection in .cache/android-device.

set -euo pipefail

ANDROID_SDK="${ANDROID_SDK:-$HOME/Library/Android/sdk}"
ADB="$ANDROID_SDK/platform-tools/adb"
EMULATOR_BIN="$ANDROID_SDK/emulator/emulator"

CACHE_FILE="$(git rev-parse --show-toplevel 2>/dev/null || echo '.')/.cache/android-device"
mkdir -p "$(dirname "$CACHE_FILE")"

ARG="${1:-}"

# ── collect entries ────────────────────────────────────────────────────────────
# Format per entry: "LABEL|ID|TYPE"

entries=()

# 1. Currently connected devices and emulators (adb devices)
if [[ -x "$ADB" ]]; then
  while IFS=$'\t' read -r serial state; do
    serial="${serial%%[[:space:]]*}"
    [[ "$state" != "device" ]] && continue
    if [[ "$serial" == emulator-* ]]; then
      avd_name=$("$ADB" -s "$serial" emu avd name 2>/dev/null | head -1 | tr -d '\r\n' || echo "")
      [[ -z "$avd_name" ]] && avd_name="$serial"
      entries+=("emulator: ${avd_name} [${serial}]|${serial}|running")
    else
      model=$("$ADB" -s "$serial" shell getprop ro.product.model 2>/dev/null | tr -d '\r\n' || echo "$serial")
      entries+=("${model} [${serial}]|${serial}|running")
    fi
  done < <("$ADB" devices 2>/dev/null | tail -n +2 | grep -v '^[[:space:]]*$' | grep $'\tdevice$')
fi

# 2. Available AVDs not already running
if [[ -x "$EMULATOR_BIN" ]]; then
  # collect serials of running emulators to filter AVD list
  running_avds=()
  for entry in "${entries[@]+"${entries[@]}"}"; do
    type_field=$(echo "$entry" | cut -d'|' -f3)
    [[ "$type_field" != "running" ]] && continue
    label=$(echo "$entry" | cut -d'|' -f1)
    if [[ "$label" == emulator:* ]]; then
      avd=$(echo "$label" | sed 's/emulator: //' | sed 's/ \[.*//')
      running_avds+=("$avd")
    fi
  done

  while IFS= read -r avd_name; do
    [[ -z "$avd_name" ]] && continue
    # skip if already in running list
    already=false
    for ra in "${running_avds[@]+"${running_avds[@]}"}"; do
      [[ "$ra" == "$avd_name" ]] && { already=true; break; }
    done
    $already && continue
    entries+=("AVD: ${avd_name} [not running]|${avd_name}|avd")
  done < <("$EMULATOR_BIN" -list-avds 2>/dev/null)
fi

if [[ ${#entries[@]} -eq 0 ]]; then
  echo "ERROR: No Android devices, emulators, or AVDs found." >&2
  echo "       Connect a device or create an AVD with Android Studio." >&2
  exit 1
fi

# ── list mode ─────────────────────────────────────────────────────────────────
if [[ "$ARG" == "list" ]]; then
  printf "\n  Available Android targets:\n\n"
  for i in "${!entries[@]}"; do
    label=$(echo "${entries[$i]}" | cut -d'|' -f1)
    id=$(echo "${entries[$i]}" | cut -d'|' -f2)
    type=$(echo "${entries[$i]}" | cut -d'|' -f3)
    printf "  %d. %s\n     %s  [%s]\n\n" "$((i+1))" "$label" "$id" "$type"
  done
  exit 0
fi

# ── direct serial/AVD mode ────────────────────────────────────────────────────
if [[ -n "$ARG" && "$ARG" != "non-interactive" ]]; then
  for entry in "${entries[@]}"; do
    id_field=$(echo "$entry" | cut -d'|' -f2)
    type_field=$(echo "$entry" | cut -d'|' -f3)
    if [[ "$id_field" == "$ARG" ]]; then
      echo "$id_field" > "$CACHE_FILE"
      printf "%s\t%s\n" "$id_field" "$type_field"
      exit 0
    fi
  done
  echo "ERROR: '$ARG' not found. Run 'make android list' to see options." >&2
  exit 1
fi

# ── load last selection ────────────────────────────────────────────────────────
last_id=""
[[ -f "$CACHE_FILE" ]] && last_id=$(cat "$CACHE_FILE")

# ── auto-select if only one option or non-interactive ────────────────────────
auto_select() {
  local idx=$1
  local id_field type_field label_field
  id_field=$(echo "${entries[$idx]}" | cut -d'|' -f2)
  type_field=$(echo "${entries[$idx]}" | cut -d'|' -f3)
  label_field=$(echo "${entries[$idx]}" | cut -d'|' -f1)
  echo "$id_field" > "$CACHE_FILE"
  printf "  Auto-selected: %s\n\n" "$label_field" >&2
  printf "%s\t%s\n" "$id_field" "$type_field"
}

if [[ ${#entries[@]} -eq 1 ]]; then
  auto_select 0; exit 0
fi

if [[ "$ARG" == "non-interactive" ]]; then
  # prefer last used if still present
  for i in "${!entries[@]}"; do
    if [[ "$(echo "${entries[$i]}" | cut -d'|' -f2)" == "$last_id" ]]; then
      auto_select "$i"; exit 0
    fi
  done
  # otherwise prefer a running device/emulator over an unbooted AVD
  for i in "${!entries[@]}"; do
    if [[ "$(echo "${entries[$i]}" | cut -d'|' -f3)" == "running" ]]; then
      auto_select "$i"; exit 0
    fi
  done
  auto_select 0; exit 0
fi

# ── interactive picker ─────────────────────────────────────────────────────────
default=0
for i in "${!entries[@]}"; do
  if [[ "$(echo "${entries[$i]}" | cut -d'|' -f2)" == "$last_id" ]]; then
    default=$i; break
  fi
done

selected=$default
count=${#entries[@]}

draw_menu() {
  tput rc 2>/dev/null || true
  printf "\n  Select Android target  (↑↓ or number, Enter to confirm)\n\n" >&2
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
