#!/bin/bash
# Wave 4 — multi-spec-type chaining, 2 models × 3 chains × 1 prompt × 5 runs = 30 runs.
# Chains: draft-mtp only, draft-mtp + ngram-mod, draft-mtp + ngram-mod + ngram-map-k4v.

set -uo pipefail
HERE="$(dirname "$(realpath "$0")")"
source "$HERE/lib/bench-helpers.sh"
source "$HERE/lib/mtp-server.sh"

cd /home/eh/post4-bench
mkdir -p logs results

RESULTS_CSV="results/wave4-chaining-$(date +%Y%m%d-%H%M%S).csv"
echo "cell_id,model,n_max,chain,prompt,run,elapsed_ms,prompt_ms,predicted_ms,prompt_tps,predicted_tps,prompt_n,predicted_n,draft_n,draft_n_accepted,mtp_pct,vram_peak_gb,temp_max_c,thermal_flag" > "$RESULTS_CSV"

declare -A SWEET_NMAX=( [moe]=2 [dense]=3 )
declare -A CHAINS=(
    [mtp]="draft-mtp"
    [mtp-ng]="draft-mtp,ngram-mod"
    [mtp-ng-k4v]="draft-mtp,ngram-mod,ngram-map-k4v"
)
RUNS=5
PENALTY=1.5

echo "=== Wave 4 pre-flight ==="
preflight || exit 1

for model in moe dense; do
    n_max="${SWEET_NMAX[$model]}"
    for chain_id in mtp mtp-ng mtp-ng-k4v; do
        spec_type="${CHAINS[$chain_id]}"
        echo ""
        echo "=== Starting server: model=$model n_max=$n_max chain=$chain_id ($spec_type) ==="
        if ! start_mtp_server "$model" "$n_max" "$PENALTY" "$spec_type"; then
            echo "FAIL: server start" >&2
            continue
        fi

        cell_id="wave4-${model}-${chain_id}"
        echo "--- cell: $cell_id ---"
        for run in $(seq 1 $RUNS); do
            wait_for_temp 60
            prefix="/tmp/$cell_id-r${run}"
            row=$(run_mtp_test payloads/payload-medium.json "$prefix")
            echo "${cell_id},${model},${n_max},${chain_id},medium,${run},${row}" >> "$RESULTS_CSV"
            echo "  run ${run}: ${row}"
        done

        stop_server
    done
done

echo ""
echo "=== Wave 4 complete. Results: $RESULTS_CSV ==="
