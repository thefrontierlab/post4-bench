#!/bin/bash
# Wave 1 — n_max sweep, 2 models × 7 n_max values × 2 prompts × 5 runs = 140 runs
# n_max=0 means baseline (no MTP).

set -uo pipefail
HERE="$(dirname "$(realpath "$0")")"
source "$HERE/lib/bench-helpers.sh"
source "$HERE/lib/mtp-server.sh"

cd /home/eh/post4-bench
mkdir -p logs results

RESULTS_CSV="results/wave1-nmax-$(date +%Y%m%d-%H%M%S).csv"
echo "cell_id,model,n_max,prompt,run,elapsed_ms,prompt_ms,predicted_ms,prompt_tps,predicted_tps,prompt_n,predicted_n,draft_n,draft_n_accepted,mtp_pct,vram_peak_gb,temp_max_c,thermal_flag" > "$RESULTS_CSV"

NMAX_VALUES=(0 1 2 3 4 6 8 16)   # 0 = baseline
PROMPTS=(medium long)
RUNS=5
PENALTY=1.5

echo "=== Wave 1 pre-flight ==="
preflight || exit 1

for model in moe dense; do
    for n_max in "${NMAX_VALUES[@]}"; do
        echo ""
        echo "=== Starting server: model=$model n_max=$n_max ==="
        if ! start_mtp_server "$model" "$n_max" "$PENALTY"; then
            echo "FAIL: server start for $model n=$n_max, skipping cell" >&2
            continue
        fi

        for prompt in "${PROMPTS[@]}"; do
            cell_id="wave1-${model}-n${n_max}-${prompt}-p${PENALTY/./}"
            echo "--- cell: $cell_id ---"
            for run in $(seq 1 $RUNS); do
                wait_for_temp 60
                prefix="/tmp/$cell_id-r${run}"
                row=$(run_mtp_test "payloads/payload-${prompt}.json" "$prefix")
                echo "${cell_id},${model},${n_max},${prompt},${run},${row}" >> "$RESULTS_CSV"
                echo "  run ${run}: ${row}"
            done
        done

        stop_server
    done
done

echo ""
echo "=== Wave 1 complete. Results: $RESULTS_CSV ==="
