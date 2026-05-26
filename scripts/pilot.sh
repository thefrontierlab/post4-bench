#!/bin/bash
# Pilot — 1 cell smoke: baseline MoE on medium prompt, 2 runs (warmup + 1).
# Verifies whole harness works before running the 240-run wave.

set -uo pipefail
HERE="$(dirname "$(realpath "$0")")"
source "$HERE/lib/bench-helpers.sh"
source "$HERE/lib/mtp-server.sh"

cd /home/eh/post4-bench
mkdir -p logs results

echo "=== Pilot pre-flight ==="
preflight || exit 1

echo ""
echo "=== Start MoE server, no MTP (baseline), penalty=1.5 ==="
start_mtp_server moe 0 1.5 || { echo "FAIL: server start"; exit 1; }
echo "Server PID $BENCH_SERVER_PID, log: $BENCH_SERVER_LOG"

echo ""
echo "=== 2 runs (warmup + measurement) on medium prompt ==="
for run in 1 2; do
    wait_for_temp 60
    prefix="/tmp/pilot-r${run}"
    row=$(run_mtp_test payloads/payload-medium.json "$prefix")
    echo "run $run: $row"
done

echo ""
stop_server
echo "=== Pilot complete ==="
echo "If row shows non-empty predicted_tps, harness works."
