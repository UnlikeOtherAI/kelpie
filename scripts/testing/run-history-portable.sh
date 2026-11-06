#!/usr/bin/env bash
# Runs inside the already bounded non-root systemd unit; stdout is not retained.
set -euo pipefail
: "${HISTORY_RECEIPT_DIR:?}" "${HISTORY_LOG_DIR:?}"
[[ "$(id -u)" != 0 ]]
group="$(sed -n 's/^0:://p' /proc/self/cgroup)"
[[ "$group" == /system.slice/kelpie-history-portable-*.service ]]
cg="/sys/fs/cgroup$group"
memory="$(cat "$cg/memory.max")"; cpu="$(cat "$cg/cpu.max")"; tasks="$(cat "$cg/pids.max")"
[[ "$memory" == 2147483648 && "$tasks" == 256 ]]
read -r quota period <<<"$cpu"; [[ "$quota" =~ ^[0-9]+$ && "$quota" == "$period" ]]
grep -qx "$$" "$cg/cgroup.procs"
mkdir -p "$HISTORY_LOG_DIR" "$HISTORY_RECEIPT_DIR"
lint=not-run; build=not-run; test=not-run; code=0
pnpm lint >"$HISTORY_LOG_DIR/lint.log" 2>&1 || code=$?
lint="$code"
if [[ "$code" != 0 ]]; then
 node "$(dirname "$0")/lint-receipt.mjs" "$HISTORY_LOG_DIR/lint.log" "$HISTORY_RECEIPT_DIR/lint-diagnostic.json"
fi
if [[ "$code" == 0 ]]; then
 pnpm build >"$HISTORY_LOG_DIR/build.log" 2>&1 || code=$?
 build="$code"
fi
if [[ "$code" == 0 ]]; then
 pnpm test >"$HISTORY_LOG_DIR/test.log" 2>&1 || code=$?
 test="$code"
fi
printf '{"version":1,"memoryBytes":%s,"cpuQuota":"%s","tasks":%s,"lint":"%s","build":"%s","test":"%s","exitCode":%s}\n' \
 "$memory" "$cpu" "$tasks" "$lint" "$build" "$test" "$code" >"$HISTORY_RECEIPT_DIR/suite.json"
exit "$code"
