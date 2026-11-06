#!/usr/bin/env bash
# Dedicated hosted runner only: sequential native phone/tablet acceptance.
set -euo pipefail
script_dir="$(cd -- "$(dirname "$0")" && pwd)"
ownership="$script_dir/android-native-ownership.mjs"
node "$ownership" hosted
root="$(git rev-parse --show-toplevel)"
out="$(realpath -m "$1")"
app="$(realpath "$2")"
tests="$(realpath "$3")"
mode="${4:-full}"
[[ "$mode" == full || "$mode" == targeted || "$mode" == api29-smoke ]] || { echo INVALID_NATIVE_TEST_MODE >&2; exit 1; }
image='system-images;android-35;google_apis;x86_64'
profiles=(phone tablet)
if [[ "$mode" == api29-smoke ]]; then
  image='system-images;android-29;google_apis;x86_64'
  profiles=(phone)
fi
mkdir -p "$out"
printf 'GITHUB_ACTIONS=%s\nRUNNER_ENVIRONMENT=%s\nRUNNER_OS=%s\n' "$(printenv GITHUB_ACTIONS)" "$(printenv RUNNER_ENVIRONMENT)" "$(printenv RUNNER_OS)" > "$out/runner-environment.txt"
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
sdkmanager 'platform-tools' 'emulator' "$image" > "$out/sdk-install.log" 2>&1
adb start-server >/dev/null
serial=''
pid=''
owned_started=''
owned_avd=''
owned_port=''

cleanup() {
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    if ! node "$ownership" verify "$pid" "$owned_avd" "$owned_port" "$sdk" "$owned_started"; then
      echo EMULATOR_OWNERSHIP_UNVERIFIED >&2
      return 1
    fi
    actual_avd="$(timeout 3s adb -s "$serial" emu avd name 2>/dev/null | head -1 | tr -d '\r' || true)"
    if [[ "$actual_avd" == "$owned_avd" ]]; then
      adb -s "$serial" emu kill >/dev/null 2>&1 || true
    fi
    for _ in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    if kill -0 "$pid" 2>/dev/null &&
      node "$ownership" verify "$pid" "$owned_avd" "$owned_port" "$sdk" "$owned_started"; then
      kill "$pid"
      for _ in $(seq 1 10); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
      if kill -0 "$pid" 2>/dev/null &&
        node "$ownership" verify "$pid" "$owned_avd" "$owned_port" "$sdk" "$owned_started"; then kill -KILL "$pid"; fi
    fi
  fi
  if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then wait "$pid" 2>/dev/null || true; fi
  serial=''
  pid=''
  owned_started=''
  owned_avd=''
  owned_port=''
}

verify_device() {
  node "$ownership" verify "$pid" "$owned_avd" "$owned_port" "$sdk" "$owned_started" || return 1
  actual_avd="$(timeout 3s adb -s "$serial" emu avd name 2>/dev/null | head -1 | tr -d '\r' || true)"
  [[ "$actual_avd" == "$owned_avd" ]] || { echo EMULATOR_DEVICE_IDENTITY_MISMATCH >&2; return 1; }
}
trap cleanup EXIT INT TERM
result=0
for profile in "${profiles[@]}"; do
  case "$profile" in phone) device=pixel_7; port=5584;; tablet) device=pixel_tablet; port=5586;; esac
  printf 'profile=%s phase=prepare source=%s\n' "$profile" "$revision"
  dir="$out/$profile"
  mkdir -p "$dir"
  name="kelpie-capture-$profile"
  printf 'no\n' | avdmanager create avd --name "$name" --package "$image" --device "$device" > "$dir/avd-create.log" 2>&1
  candidate="emulator-$port"
  if adb devices | awk 'NR > 1 {print $1}' | grep -Fxq "$candidate"; then
    echo PROPOSED_EMULATOR_SERIAL_IN_USE > "$dir/blocker.txt"
    exit 1
  fi
  if ! node "$ownership" ports "$port" "$((port + 1))"; then
    echo PROPOSED_EMULATOR_PORT_IN_USE > "$dir/blocker.txt"
    exit 1
  fi
  emulator -avd "$name" -port "$port" -no-window -no-audio -no-boot-anim \
    -no-snapshot -gpu swiftshader_indirect -cores 2 -memory 3072 \
    > "$dir/emulator.log" 2>&1 &
  pid=$!
  printf 'spawnedPid=%s\ncandidate=%s\navd=%s\n' "$pid" "$candidate" "$name" > "$dir/spawn-process.txt"
  owned_avd="$name"
  owned_port="$port"
  owned_started="$(node "$ownership" capture "$pid" "$name" "$port" "$sdk")"
  serial="$candidate"
  printf 'pid=%s\nstart=%s\navd=%s\nport=%s\n' "$pid" "$owned_started" "$name" "$port" > "$dir/owned-process.txt"
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
  verify_device
  adb -s "$serial" shell getprop ro.build.fingerprint > "$dir/image-fingerprint.txt"
  adb -s "$serial" shell dumpsys webviewupdate | grep -E 'Current WebView package|Preferred WebView package' > "$dir/webview-provider.txt" || true
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
  if [[ "$mode" == api29-smoke ]]; then
    printf 'api29-smoke\n' > "$out/scope.txt"
    sdk_level="$(adb -s "$serial" shell getprop ro.build.version.sdk | tr -d '\r')"
    printf '%s\n' "$sdk_level" > "$dir/api-level.txt"
    [[ "$sdk_level" == 29 ]] || { echo API_LEVEL_MISMATCH > "$dir/blocker.txt"; exit 1; }
    installed_test="$(adb -s "$serial" shell pm path com.kelpie.browser.test | head -1 | tr -d '\r' | cut -d: -f2-)"
    adb -s "$serial" shell sha256sum "$installed_test" > "$dir/installed-test-apk-sha256.txt"
    [[ "$(cut -d ' ' -f1 "$dir/installed-test-apk-sha256.txt")" == "$(sha256sum "$tests" | cut -d ' ' -f1)" ]] || {
      echo INSTALLED_TEST_APK_HASH_MISMATCH > "$dir/blocker.txt"; exit 1;
    }
    if ! bash "$script_dir/android-native-api29-smoke.sh" "$serial" "$dir" "$revision" "$profile" \
      "$ownership" "$pid" "$owned_avd" "$owned_port" "$sdk" "$owned_started"; then result=1; fi
    verify_device
    finished_pid="$pid"
    finished_serial="$serial"
    cleanup
    if kill -0 "$finished_pid" 2>/dev/null || ! node "$ownership" ports "$port" "$((port + 1))" ||
      adb devices | awk 'NR > 1 {print $1}' | grep -Fxq "$finished_serial"; then
      echo CLEANUP_UNVERIFIED > "$dir/cleanup.txt"
      result=1
    else
      echo CLEANUP_CONFIRMED > "$dir/cleanup.txt"
    fi
    continue
  fi

  if [[ "$mode" == targeted ]]; then
    printf 'targeted\n' > "$out/scope.txt"
    installed_test="$(adb -s "$serial" shell pm path com.kelpie.browser.test | head -1 | tr -d '\r' | cut -d: -f2-)"
    adb -s "$serial" shell sha256sum "$installed_test" > "$dir/installed-test-apk-sha256.txt"
    [[ "$(cut -d ' ' -f1 "$dir/installed-test-apk-sha256.txt")" == "$(sha256sum "$tests" | cut -d ' ' -f1)" ]] || {
      echo INSTALLED_TEST_APK_HASH_MISMATCH > "$dir/blocker.txt"
      exit 1
    }
    if ! bash "$script_dir/android-native-targeted.sh" "$serial" "$dir" "$revision" "$profile" \
      "$ownership" "$pid" "$owned_avd" "$owned_port" "$sdk" "$owned_started"; then result=1; fi
    verify_device
    finished_pid="$pid"
    cleanup
    if kill -0 "$finished_pid" 2>/dev/null || ! node "$ownership" ports "$port" "$((port + 1))"; then
      echo CLEANUP_UNVERIFIED > "$dir/cleanup.txt"
      result=1
    else
      echo CLEANUP_CONFIRMED > "$dir/cleanup.txt"
    fi
    continue
  fi

  # Supported AndroidX instrumentation performs pairing/native UI assertions.
  # No adb input, desktop input or screen-control service is used.
  printf 'profile=%s phase=corpus\n' "$profile"
  set +e
  timeout 20m adb -s "$serial" shell am instrument -w -r \
    -e package com.kelpie.browser.automation -e notClass com.kelpie.browser.automation.ScriptCliBridgeTest,com.kelpie.browser.automation.ScriptApi29SmokeTest -e sourceRevision "$revision" \
    -e deviceClass "$profile" \
    com.kelpie.browser.test/androidx.test.runner.AndroidJUnitRunner \
    > "$dir/instrumentation.log" 2>&1
  instrument_exit=$?
  set -e
  printf '%s\n' "$instrument_exit" > "$dir/instrumentation-exit.txt"

  verify_device
  printf 'profile=%s phase=cli\n' "$profile"
  # Give each run a unique fixture mailbox; preserve earlier evidence.
  bridge_id="${profile}-$(cat /proc/sys/kernel/random/uuid)"
  # Start a fresh native fixture; the real CLI requests its own persistent grant.
  timeout 15m adb -s "$serial" shell am instrument -w -r \
    -e class com.kelpie.browser.automation.ScriptCliBridgeTest -e bridgeId "$bridge_id" \
    -e sourceRevision "$revision" -e deviceClass "$profile" \
    com.kelpie.browser.test/androidx.test.runner.AndroidJUnitRunner \
    > "$dir/cli-instrumentation.log" 2>&1 &
  bridge_pid=$!
  bridge_ready=false
  for _ in $(seq 1 60); do
    if adb -s "$serial" pull /sdcard/Android/data/com.kelpie.browser/files/script-acceptance/cli-bridge-$bridge_id.json "$dir/cli-bridge.json" >/dev/null 2>&1; then bridge_ready=true; break; fi
    kill -0 "$bridge_pid" 2>/dev/null || break
    sleep 1
  done
  cli_exit=1
  if [[ "$bridge_ready" == true ]]; then
    adb -s "$serial" forward tcp:18420 tcp:8420
    set +e
    node "$root/scripts/testing/android-native-cli.mjs" "$root" "$dir" 18420 "$profile" "$revision" "$(sha256sum "$app" | cut -d ' ' -f1)" > "$dir/cli-driver.log" 2>&1
    cli_exit=$?
    set -e
    # Test coordination only: never a credential or product-state repair.
    printf 'complete:%s\n' "$cli_exit" > "$dir/cli-finish.txt"
    adb -s "$serial" push "$dir/cli-finish.txt" /sdcard/Android/data/com.kelpie.browser/files/script-acceptance/cli-finish-$bridge_id.txt > /dev/null
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
if [[ "$mode" == full ]]; then node "$root/scripts/testing/android-native-report.mjs" "$out"; fi
exit "$result"
