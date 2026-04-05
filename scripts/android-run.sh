#!/usr/bin/env bash
# Boot (if needed), install, and launch the Kelpie app on an Android target.
#
# Usage: android-run.sh <target> <type> <apk>
#   target  — ADB serial (type=running) or AVD name (type=avd)
#   type    — "running" | "avd"
#   apk     — path to the .apk file

set -euo pipefail

TARGET="$1"
TYPE="$2"
APK="$3"

ANDROID_SDK="${ANDROID_SDK:-$HOME/Library/Android/sdk}"
ADB="$ANDROID_SDK/platform-tools/adb"
EMULATOR_BIN="$ANDROID_SDK/emulator/emulator"
AVDMANAGER="$ANDROID_SDK/cmdline-tools/latest/bin/avdmanager"
SDKMANAGER="$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager"

SERIAL="$TARGET"

# ── boot AVD if not running ────────────────────────────────────────────────────
if [[ "$TYPE" == "avd" ]]; then
  # ensure AVD exists; create if not
  if ! "$AVDMANAGER" list avd -c 2>/dev/null | grep -qx "$TARGET"; then
    echo "→ AVD '$TARGET' not found — creating it..."
    "$SDKMANAGER" --install "system-images;android-34;google_apis;arm64-v8a" 2>&1 | grep -v '^\[='
    echo no | "$AVDMANAGER" create avd \
      --name "$TARGET" \
      --package "system-images;android-34;google_apis;arm64-v8a" \
      --device "pixel_7" \
      --force
    echo "✓ AVD '$TARGET' created"
  fi

  # snapshot existing emulator serials before boot
  old_serials=$("$ADB" devices 2>/dev/null | grep "^emulator-" | awk '{print $1}' || true)

  echo "→ Starting emulator $TARGET..."
  "$EMULATOR_BIN" -avd "$TARGET" -no-snapshot-save &>/dev/null &

  # wait for a new emulator serial to appear
  echo "→ Waiting for emulator to appear..."
  SERIAL=""
  while [[ -z "$SERIAL" ]]; do
    sleep 1
    for s in $("$ADB" devices 2>/dev/null | grep "^emulator-" | awk '{print $1}'); do
      if ! echo "$old_serials" | grep -qx "$s"; then
        SERIAL="$s"
        break
      fi
    done
  done

  echo "→ Emulator online at $SERIAL — waiting for full boot..."
  "$ADB" -s "$SERIAL" wait-for-device
  "$ADB" -s "$SERIAL" shell 'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done'
  echo "✓ Emulator ready"
fi

# ── install and launch ─────────────────────────────────────────────────────────
echo "→ Installing $APK on $SERIAL..."
"$ADB" -s "$SERIAL" install -r "$APK"

echo "→ Launching..."
"$ADB" -s "$SERIAL" shell am start -n com.kelpie.browser/.MainActivity
echo "✓ App launched on $SERIAL"
