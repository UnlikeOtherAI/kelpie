#!/usr/bin/env bash
# Fixed API 29 cases; keep each native result and evidence snapshot separately.
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
# No host media tool is needed: the device decodes these fixed movie cases.
# Fail the run if any caller unexpectedly invokes a host codec tool.
guard_dir="$dir/api29-media-guard"
mkdir -p "$guard_dir"
export KELPIE_API29_MEDIA_ATTEMPT="$guard_dir/attempted"
cat > "$guard_dir/ffmpeg" <<'GUARD'
#!/bin/sh
printf '%s\n' unexpected > "$KELPIE_API29_MEDIA_ATTEMPT"
exit 97
GUARD
cp "$guard_dir/ffmpeg" "$guard_dir/ffprobe"
chmod +x "$guard_dir/ffmpeg" "$guard_dir/ffprobe"
export PATH="$guard_dir:$PATH"
cases=(
  'one-step-png=com.kelpie.browser.automation.ScriptApi29SmokeTest#oneSemanticClickShowsNativeMarkerAndReturnsOneDecodablePng'
  'movie-stop=com.kelpie.browser.automation.ScriptSecurityFlowTest#visibleStopFinalizesPartialMoviesAndNextRunRecovers'
)
result=0
for entry in "${cases[@]}"; do
  node "$ownership" verify "$pid" "$avd" "$port" "$sdk" "$started"
  actual_avd="$(timeout 3s adb -s "$serial" emu avd name 2>/dev/null | head -1 | tr -d '\r')"
  [[ "$actual_avd" == "$avd" ]] || { echo EMULATOR_DEVICE_IDENTITY_MISMATCH >&2; exit 1; }
  name="${entry%%=*}"
  test_class="${entry#*=}"
  case_dir="$dir/api29-smoke/$name"
  mkdir -p "$case_dir"
  printf '%s\n' "$test_class" > "$case_dir/case.txt"
  set +e
  timeout 5m adb -s "$serial" shell am instrument -w -r \
    -e class "$test_class" -e sourceRevision "$revision" -e deviceClass "$profile" -e api29Smoke true -e api29Case "$name" \
    com.kelpie.browser.test/androidx.test.runner.AndroidJUnitRunner \
    > "$case_dir/instrumentation.log" 2>&1
  status=$?
  set -e
  printf '%s\n' "$status" > "$case_dir/exit.txt"
  adb -s "$serial" pull /sdcard/Android/data/com.kelpie.browser/files/script-acceptance "$case_dir/" \
    > "$case_dir/pull.log" 2>&1 || true
  if [[ -e "$KELPIE_API29_MEDIA_ATTEMPT" ]]; then
    echo UNEXPECTED_API29_HOST_MEDIA_REQUEST >&2
    result=1
  fi
  case "$name" in
    one-step-png)
      for required in api29-one-step-result.json api29-native-marker.png api29-step.png native-marker-evidence.json; do
        [[ -s "$case_dir/script-acceptance/$required" ]] || { echo "MISSING_EVIDENCE:$required" >&2; result=1; }
      done
      ;;
    movie-stop)
      for required in before-native-stop-status.json stopped-manifest.json api29-partial.gif api29-partial.mp4; do
        [[ -s "$case_dir/script-acceptance/$required" ]] || { echo "MISSING_EVIDENCE:$required" >&2; result=1; }
      done
      ;;
  esac
  if [[ "$status" -ne 0 ]] || ! grep -Eq '^OK \(1 test\)' "$case_dir/instrumentation.log" ||
    grep -Eq 'FAILURES!!!|INSTRUMENTATION_FAILED|Process crashed' "$case_dir/instrumentation.log"; then
    result=1
  fi
done
exit "$result"
