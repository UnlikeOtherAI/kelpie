#!/usr/bin/env bash
set -euo pipefail
umask 077
: "${GITHUB_WORKSPACE:?}" "${RUNNER_TEMP:?}" "${GITHUB_SHA:?}" "${GITHUB_RUN_ID:?}"
isolation_only="${KELPIE_AB_ISOLATION_ONLY:-false}"
[[ "$isolation_only" == true || "$isolation_only" == false ]]
[[ "$GITHUB_SHA" =~ ^[a-f0-9]{40}$ && "$GITHUB_RUN_ID" =~ ^[0-9]+$ && "${GITHUB_RUN_ATTEMPT:-1}" =~ ^[0-9]+$ ]]
if [[ "$isolation_only" == false ]]; then
 : "${CHROMIUM_ARCHIVE_SHA256:?}" "${CHROMIUM_BINARY_SHA256:?}"
 [[ "$CHROMIUM_ARCHIVE_SHA256" =~ ^[a-f0-9]{64}$ && "$CHROMIUM_BINARY_SHA256" =~ ^[a-f0-9]{64}$ ]]
fi
[[ "$(id -u)" != 0 ]]
sudo -n true
root="$GITHUB_WORKSPACE"
out="$RUNNER_TEMP/worker-ab-evidence"
assets="$RUNNER_TEMP/worker-ab-assets"
node="$(command -v node)"
uid="$(id -u)"; gid="$(id -g)"
mkdir -m 700 "$out"
comparison_id="$(openssl rand -hex 32)"
host_ip="$(hostname -I | awk '{print $1}')"
[[ "$host_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ && "$host_ip" != 127.* ]]
"$node" "$root/tests/linux/worker-comparison-canary.mjs" serve "$out/canary.json" >"$out/canary.log" 2>&1 &
canary_pid=$!
cleanup() {
  if kill -0 "$canary_pid" 2>/dev/null; then kill -TERM "$canary_pid"; fi
  wait "$canary_pid" 2>/dev/null || true
}
trap cleanup EXIT
for _ in $(seq 1 100); do [[ -s "$out/canary.json" ]] && break; sleep 0.1; done
[[ -s "$out/canary.json" ]]
port="$("$node" -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(process.argv[1]));if(!Number.isInteger(x.port)||x.port<1||x.port>65535)process.exit(1);process.stdout.write(String(x.port))' "$out/canary.json")"
"$node" "$root/tests/linux/worker-comparison-canary.mjs" outside "$host_ip" "$port" >"$out/outside-probe.json"
printf '%s\n' "$comparison_id" >"$out/comparison-id.txt"
failed=0
arm_retired=0
run_arm() {
 arm_retired=0
 local backend="$1" executable="$2" expected="$3" dir="$out/$1"
 local unit="kelpie-worker-ab-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT:-1}-$backend"
 mkdir -m 700 "$dir"
 local -a command
 if [[ "$backend" == probe ]]; then
  command=("$node" "$root/tests/linux/worker-isolation-probe.mjs" "$dir")
 else
  command=("$node" "$root/tests/linux/worker-comparison.mjs" "$backend" "$executable" "$expected" "$dir")
 fi
 sudo -n systemd-run --quiet --wait --pipe --unit="$unit" --uid="$uid" --gid="$gid" \
  --property="WorkingDirectory=$root" --property=CPUQuota=100% --property=MemoryMax=2G \
  --property=TasksMax=256 --property=RuntimeMaxSec=120 --property=NoNewPrivileges=yes --property=KillMode=control-group \
  --property=IPAddressDeny=any --property=IPAddressAllow=localhost \
  --setenv="PATH=$PATH" --setenv="KELPIE_TEST_REVISION=$GITHUB_SHA" \
  --setenv="KELPIE_COMPARISON_ID=$comparison_id" --setenv="KELPIE_AB_CANARY_HOST=$host_ip" \
  --setenv="KELPIE_AB_CANARY_PORT=$port" --setenv="KELPIE_CHROMIUM_ARCHIVE=$assets/chrome.zip" \
  --setenv="KELPIE_CHROMIUM_ARCHIVE_SHA256=${CHROMIUM_ARCHIVE_SHA256:-}" \
  "${command[@]}" >"$dir/unit.log" 2>&1 &
 local launcher=$! active=0
 for _ in $(seq 1 100); do
  sudo -n systemctl show "$unit" --no-pager --property=User --property=ActiveState \
   --property=ExecMainPID --property=ControlGroup --property=NoNewPrivileges --property=KillMode --property=MemoryMax --property=TasksMax \
   --property=CPUQuotaPerSecUSec --property=IPAddressAllow --property=IPAddressDeny >"$dir/policy.txt" 2>/dev/null || true
  if grep -qx 'ActiveState=active' "$dir/policy.txt" && grep -Eq '^ExecMainPID=[1-9][0-9]*$' "$dir/policy.txt"; then active=1; break; fi
  if ! kill -0 "$launcher" 2>/dev/null; then break; fi
  sleep 0.1
 done
 local group
 group="$(sed -n 's/^ControlGroup=//p' "$dir/policy.txt")"
 if [[ "$active" == 1 && "$group" == "/system.slice/${unit}.service" ]] && command -v bpftool >/dev/null; then
  if timeout 3s sudo -n bpftool -j cgroup show "/sys/fs/cgroup$group" effective >"$dir/bpf-effective.json" 2>/dev/null; then
   printf '%s\n' available >"$dir/bpf-status.txt"
  else printf '%s\n' query-failed >"$dir/bpf-status.txt"; fi
 else printf '%s\n' unavailable >"$dir/bpf-status.txt"; fi
 local status=0
 wait "$launcher" || status=$?
 printf '%s\n' "$status" >"$dir/launcher-exit.txt"
 sudo -n systemctl show "$unit" --no-pager --property=LoadState --property=ActiveState \
  --property=ControlGroup --property=Result --property=ExecMainStatus >"$dir/unit-final.txt" 2>&1 || true
 grep -Eq '^ActiveState=(inactive|failed)$' "$dir/unit-final.txt" || return 1
 [[ "$group" == "/system.slice/${unit}.service" ]] || return 1
 local procs="" events="" cgpath="/sys/fs/cgroup$group"
 if [[ -d "$cgpath" ]]; then
  [[ -r "$cgpath/cgroup.procs" ]] || return 1
  procs="$(cat "$cgpath/cgroup.procs")" || return 1
  [[ -z "$procs" ]] || return 1
  [[ -r "$cgpath/cgroup.events" ]] || return 1
  events="$(cat "$cgpath/cgroup.events")" || return 1
  [[ "$(printf '%s\n' "$events" | grep -cx 'populated 0')" == 1 ]] || return 1
 fi
 arm_retired=1
 local observation_status=1
 if [[ "$active" == 1 && -s "$dir/network-observation.json" ]]; then
  observation_status=0
  "$node" "$root/tests/linux/worker-observation-policy-check.mjs" \
   "$dir/policy.txt" "$uid" "$dir/network-observation.json" "$dir/policy-observed.json" || observation_status=$?
 fi
 if [[ "$active" != 1 || "$status" != 0 || "$observation_status" != 0 || ! -s "$dir/report.json" ]]; then return 1; fi
 "$node" "$root/tests/linux/worker-comparison-policy-check.mjs" \
  "$dir/policy.txt" "$uid" "$dir/report.json" "$dir/policy-verified.json"
}
if [[ "$isolation_only" == true ]]; then
 run_arm probe "" "" || failed=1
 exit "$failed"
fi
run_arm lightpanda "$assets/lightpanda" ae7d01d261efb9e480e18ce3424533332883863bcf70b12a4321b5733f37e19e || failed=1
if [[ "$arm_retired" == 1 && "$failed" == 0 ]]; then
 run_arm playwright "$assets/chrome/chrome-linux64/chrome" "$CHROMIUM_BINARY_SHA256" || failed=1
else
 failed=1
fi
if [[ "$failed" == 0 ]]; then
 "$node" "$root/tests/linux/worker-comparison-report.mjs" "$out/lightpanda/report.json" "$out/playwright/report.json" >"$out/comparison.json"
fi
exit "$failed"
