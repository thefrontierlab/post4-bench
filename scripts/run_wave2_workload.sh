#!/bin/bash
# Wave 2 — workload-type, 2 models × 1 n_max (sweet-spot) × 5 prompts × 5 runs = 50 runs.
# Sweet-spots: moe=n=2, dense=n=3.

set -uo pipefail
HERE="$(dirname "$(realpath "$0")")"
source "$HERE/lib/bench-helpers.sh"
source "$HERE/lib/mtp-server.sh"

cd /home/eh/post4-bench
mkdir -p logs results

RESULTS_CSV="results/wave2-workload-$(date +%Y%m%d-%H%M%S).csv"
echo "cell_id,model,n_max,workload,run,elapsed_ms,prompt_ms,predicted_ms,prompt_tps,predicted_tps,prompt_n,predicted_n,draft_n,draft_n_accepted,mtp_pct,vram_peak_gb,temp_max_c,thermal_flag" > "$RESULTS_CSV"

declare -A SWEET_NMAX=( [moe]=2 [dense]=3 )
WORKLOADS=(code structured technical creative dialog)
RUNS=5
PENALTY=1.5

echo "=== Wave 2 pre-flight ==="
preflight || exit 1

for model in moe dense; do
    n_max="${SWEET_NMAX[$model]}"
    echo ""
    echo "=== Starting server: model=$model n_max=$n_max (sweet-spot) ==="
    if ! start_mtp_server "$model" "$n_max" "$PENALTY"; then
        echo "FAIL: server start for $model n=$n_max" >&2
        continue
    fi

    for wl in "${WORKLOADS[@]}"; do
        cell_id="wave2-${model}-n${n_max}-wl${wl}"
        echo "--- cell: $cell_id ---"
        for run in $(seq 1 $RUNS); do
            wait_for_temp 60
            prefix="/tmp/$cell_id-r${run}"
            row=$(run_mtp_test "payloads/payload-wl-${wl}.json" "$prefix")
            echo "${cell_id},${model},${n_max},${wl},${run},${row}" >> "$RESULTS_CSV"
            echo "  run ${run}: ${row}"
        done
    done

    stop_server
done

echo ""
echo "=== Wave 2 complete. Results: $RESULTS_CSV ==="
