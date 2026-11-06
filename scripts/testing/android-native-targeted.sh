#!/usr/bin/env bash
# Fixed targeted cases; separate evidence for each case and each owned profile.
set -euo pipefail
serial="$1"
dir="$2"
revision="$3"
profile="$4"
ownership="$5"
pid="$6"
avd="$7"
port="$8"
sdk="$9"
started="${10}"
# These fixed controls have no capture. Refuse any unexpected host codec call,
# including one whose caller might otherwise ignore its exit status.
guard_dir="$dir/targeted-media-guard"
mkdir -p "$guard_dir"
export KELPIE_TARGETED_MEDIA_ATTEMPT="$guard_dir/attempted"
cat > "$guard_dir/ffmpeg" <<'GUARD'
#!/bin/sh
printf '%s\n' unexpected > "$KELPIE_TARGETED_MEDIA_ATTEMPT"
exit 97
GUARD
cp "$guard_dir/ffmpeg" "$guard_dir/ffprobe"
chmod +x "$guard_dir/ffmpeg" "$guard_dir/ffprobe"
export PATH="$guard_dir:$PATH"
cases=(
  'navigation-stop=com.kelpie.browser.automation.ScriptNavigationStopTest#nativeStopDuringIssuedNavigationPreservesUncertaintyAndRecovers'
  'chrome-input=com.kelpie.browser.automation.ScriptChromeInputFlowTest#activeNoMovieRunBlocksChromeButNativeStopStillWorks'
  'renderer-system-key=com.kelpie.browser.ui.ScriptRendererKeyFrameTest#rendererKeysAreBlockedOnlyDuringPlaybackAndSystemKeysAreDelegated'
)
result=0
for entry in "${cases[@]}"; do
  node "$ownership" verify "$pid" "$avd" "$port" "$sdk" "$started"
  actual_avd="$(timeout 3s adb -s "$serial" emu avd name 2>/dev/null | head -1 | tr -d '\r')"
  [[ "$actual_avd" == "$avd" ]] || { echo EMULATOR_DEVICE_IDENTITY_MISMATCH >&2; exit 1; }
  name="${entry%%=*}"
  test_class="${entry#*=}"
  case_dir="$dir/targeted/$name"
  mkdir -p "$case_dir"
  printf '%s\n' "$test_class" > "$case_dir/case.txt"
  set +e
  timeout 5m adb -s "$serial" shell am instrument -w -r \
    -e class "$test_class" -e sourceRevision "$revision" -e deviceClass "$profile" \
    com.kelpie.browser.test/androidx.test.runner.AndroidJUnitRunner \
    > "$case_dir/instrumentation.log" 2>&1
  status=$?
  set -e
  printf '%s\n' "$status" > "$case_dir/exit.txt"
  # Each pull is a cumulative fixture snapshot, not exclusive per-case provenance.
  adb -s "$serial" pull /sdcard/Android/data/com.kelpie.browser/files/script-acceptance "$case_dir/" \
    > "$case_dir/pull.log" 2>&1 || true
  if [[ -e "$KELPIE_TARGETED_MEDIA_ATTEMPT" ]]; then
    echo UNEXPECTED_TARGETED_MEDIA_REQUEST >&2
    result=1
  fi
  if [[ "$status" -ne 0 ]] || ! grep -Eq '^OK \(1 test\)' "$case_dir/instrumentation.log" ||
    grep -Eq 'FAILURES!!!|INSTRUMENTATION_FAILED|Process crashed' "$case_dir/instrumentation.log"; then
    result=1
  fi
done
exit "$result"
