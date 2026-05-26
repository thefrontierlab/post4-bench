#!/bin/bash
# Wave 3 — sampler-coupling A/B, 2 models × 2 penalties × 1 prompt × 5 runs = 20 runs.

set -uo pipefail
HERE="$(dirname "$(realpath "$0")")"
source "$HERE/lib/bench-helpers.sh"
source "$HERE/lib/mtp-server.sh"

cd /home/eh/post4-bench
mkdir -p logs results

RESULTS_CSV="results/wave3-sampler-$(date +%Y%m%d-%H%M%S).csv"
echo "cell_id,model,n_max,penalty,prompt,run,elapsed_ms,prompt_ms,predicted_ms,prompt_tps,predicted_tps,prompt_n,predicted_n,draft_n,draft_n_accepted,mtp_pct,vram_peak_gb,temp_max_c,thermal_flag" > "$RESULTS_CSV"

declare -A SWEET_NMAX=( [moe]=2 [dense]=3 )
PENALTIES=(0.0 1.5)
RUNS=5

echo "=== Wave 3 pre-flight ==="
preflight || exit 1

for model in moe dense; do
    n_max="${SWEET_NMAX[$model]}"
    for pen in "${PENALTIES[@]}"; do
        echo ""
        echo "=== Starting server: model=$model n_max=$n_max penalty=$pen ==="
        if ! start_mtp_server "$model" "$n_max" "$pen"; then
            echo "FAIL: server start" >&2
            continue
        fi

        cell_id="wave3-${model}-n${n_max}-p${pen/./}"
        echo "--- cell: $cell_id ---"
        for run in $(seq 1 $RUNS); do
            wait_for_temp 60
            prefix="/tmp/$cell_id-r${run}"
            row=$(run_mtp_test payloads/payload-medium.json "$prefix")
            echo "${cell_id},${model},${n_max},${pen},medium,${run},${row}" >> "$RESULTS_CSV"
            echo "  run ${run}: ${row}"
        done

        stop_server
    done
done

echo ""
echo "=== Wave 3 complete. Results: $RESULTS_CSV ==="
