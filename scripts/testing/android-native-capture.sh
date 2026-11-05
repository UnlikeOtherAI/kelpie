#!/usr/bin/env bash
# Dedicated hosted runner only: sequential native phone/tablet acceptance.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
out="$(realpath -m "$1")"
app="$(realpath "$2")"
tests="$(realpath "$3")"
mkdir -p "$out"
export ANDROID_AVD_HOME="$out/avd"
mkdir -p "$ANDROID_AVD_HOME"
sdk="$ANDROID_HOME"
export PATH="$sdk/platform-tools:$sdk/emulator:$sdk/cmdline-tools/latest/bin:$PATH"
[[ -c /dev/kvm && -r /dev/kvm && -w /dev/kvm ]] || {
  echo 'KVM_UNAVAILABLE: hosted native execution cannot run' | tee "$out/blocker.txt"
  exit 1
}
revision="$(git -C "$root" rev-parse HEAD)"
printf '%s\n' "$revision" > "$out/source-revision.txt"
sha256sum "$app" "$tests" "$root/packages/cli/dist/index.js" > "$out/build-sha256.txt"
unzip -p "$app" lib/x86_64/libkelpie_jni.so | sha256sum > "$out/packaged-native-sha256.txt"
sdkmanager 'platform-tools' 'emulator' 'system-images;android-35;google_apis;x86_64' > "$out/sdk-install.log" 2>&1
adb start-server >/dev/null
serial=''
pid=''
cleanup() {
  if [[ -n "$serial" ]]; then adb -s "$serial" emu kill >/dev/null 2>&1 || true; fi
  if [[ -n "$pid" ]]; then
    for _ in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    if kill -0 "$pid" 2>/dev/null; then kill "$pid"; fi
    wait "$pid" 2>/dev/null || true
  fi
  serial=''
  pid=''
}
trap cleanup EXIT INT TERM
result=0
for profile in phone tablet; do
  case "$profile" in phone) device=pixel_7; port=5584;; tablet) device=pixel_tablet; port=5586;; esac
  dir="$out/$profile"
  mkdir -p "$dir"
  name="kelpie-capture-$profile"
  printf 'no\n' | avdmanager create avd --name "$name" --package 'system-images;android-35;google_apis;x86_64' --device "$device" > "$dir/avd-create.log" 2>&1
  serial="emulator-$port"
  emulator -avd "$name" -port "$port" -no-window -no-audio -no-boot-anim \
    -no-snapshot -gpu swiftshader_indirect -cores 2 -memory 3072 \
    > "$dir/emulator.log" 2>&1 &
  pid=$!
  booted=false
  for _ in $(seq 1 180); do
    kill -0 "$pid" 2>/dev/null || break
    if [[ "$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then booted=true; break; fi
    sleep 2
  done
  if [[ "$booted" != true ]]; then
    echo BOOT_FAILED > "$dir/blocker.txt"
    result=1
    cleanup
    continue
  fi
  adb -s "$serial" shell getprop ro.build.fingerprint > "$dir/image-fingerprint.txt"
  adb -s "$serial" shell wm size > "$dir/display.txt"
  adb -s "$serial" shell wm density >> "$dir/display.txt"
  cp "$ANDROID_AVD_HOME/$name.avd/config.ini" "$dir/avd-config.ini"
  adb -s "$serial" install -t --no-streaming "$app" > "$dir/install-app.log"
  adb -s "$serial" install -t --no-streaming "$tests" > "$dir/install-tests.log"
  installed="$(adb -s "$serial" shell pm path com.kelpie.browser | head -1 | tr -d '\r' | cut -d: -f2-)"
  adb -s "$serial" shell sha256sum "$installed" > "$dir/installed-apk-sha256.txt"
  [[ "$(cut -d ' ' -f1 "$dir/installed-apk-sha256.txt")" == "$(sha256sum "$app" | cut -d ' ' -f1)" ]] || {
    echo INSTALLED_APK_HASH_MISMATCH > "$dir/blocker.txt"
    exit 1
  }
  adb -s "$serial" shell dumpsys package com.kelpie.browser | grep -E 'versionCode=|versionName=' > "$dir/installed-version.txt"
  # Supported AndroidX instrumentation performs pairing/native UI assertions.
  # No adb input, desktop input or screen-control service is used.
  set +e
  timeout 20m adb -s "$serial" shell am instrument -w -r \
    -e package com.kelpie.browser.automation -e notClass com.kelpie.browser.automation.ScriptCliBridgeTest -e sourceRevision "$revision" \
    -e deviceClass "$profile" \
    com.kelpie.browser.test/androidx.test.runner.AndroidJUnitRunner \
    > "$dir/instrumentation.log" 2>&1
  instrument_exit=$?
  set -e
  printf '%s\n' "$instrument_exit" > "$dir/instrumentation-exit.txt"

  # Start a fresh native fixture; the real CLI requests its own persistent grant.
  timeout 5m adb -s "$serial" shell am instrument -w -r \
    -e class com.kelpie.browser.automation.ScriptCliBridgeTest \
    -e sourceRevision "$revision" -e deviceClass "$profile" \
    com.kelpie.browser.test/androidx.test.runner.AndroidJUnitRunner \
    > "$dir/cli-instrumentation.log" 2>&1 &
  bridge_pid=$!
  bridge_ready=false
  for _ in $(seq 1 60); do
    if adb -s "$serial" pull /sdcard/Android/data/com.kelpie.browser/files/script-acceptance/cli-bridge.json "$dir/cli-bridge.json" >/dev/null 2>&1; then bridge_ready=true; break; fi
    kill -0 "$bridge_pid" 2>/dev/null || break
    sleep 1
  done
  cli_exit=1
  if [[ "$bridge_ready" == true ]]; then
    adb -s "$serial" forward tcp:18420 tcp:8420
    set +e
    node "$root/scripts/testing/android-native-cli.mjs" "$root" "$dir" 18420 > "$dir/cli-driver.log" 2>&1
    cli_exit=$?
    set -e
    # Test coordination only: never a credential or product-state repair.
    printf 'complete\n' > "$dir/cli-finish.txt"
    adb -s "$serial" push "$dir/cli-finish.txt" /sdcard/Android/data/com.kelpie.browser/files/script-acceptance/cli-finish.txt > /dev/null
    adb -s "$serial" forward --remove tcp:18420
  fi
  set +e
  wait "$bridge_pid"
  bridge_exit=$?
  set -e
  if [[ "$cli_exit" -ne 0 || "$bridge_exit" -ne 0 ]] || ! grep -Eq '^OK \(1 test\)' "$dir/cli-instrumentation.log"; then result=1; fi
  printf '%s\n' "$cli_exit" > "$dir/cli-exit.txt"

  # Only curated fixture exports, never pairing stores, endpoint credentials,
  # unrestricted logcat or application-private databases.
  adb -s "$serial" pull /sdcard/Android/data/com.kelpie.browser/files/script-acceptance "$dir/" > "$dir/pull-capture.log" 2>&1 || true
  adb -s "$serial" pull /sdcard/Android/data/com.kelpie.browser/files/script-codec-acceptance "$dir/" > "$dir/pull-codecs.log" 2>&1 || true
  if [[ "$instrument_exit" -ne 0 ]] || ! grep -Eq '^OK \([0-9]+ tests?\)' "$dir/instrumentation.log" ||
    grep -Eq 'FAILURES!!!|INSTRUMENTATION_FAILED|Process crashed' "$dir/instrumentation.log"; then result=1; fi
  cleanup
done
node "$root/scripts/testing/android-native-report.mjs" "$out"
exit "$result"