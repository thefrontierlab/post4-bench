# MTP-server-launch helpers for Post 4 bench.
# Source after bench-helpers.sh — extends with MTP-specific server starts.

# Default paths
BENCH_BIN="${BENCH_BIN:-/usr/local/bin/llama-server}"
BENCH_PORT="${BENCH_PORT:-9091}"
MODEL_MOE="/home/eh/models/Qwen3.6-35B-A3B-MTP/Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf"
MODEL_DENSE="/home/eh/models/Qwen3.6-27B-MTP/Qwen3.6-27B-UD-Q5_K_XL.gguf"
CTX_MOE=131072
CTX_DENSE=65536

# Start llama-server on $BENCH_PORT with MTP config.
# Args:
#   $1 = model alias (moe|dense)
#   $2 = n_max (0 = no MTP, baseline)
#   $3 = presence-penalty (e.g. 1.5)
#   $4 = spec-type-str (e.g. "draft-mtp" or "draft-mtp,ngram-mod") — only used if n_max>0
#
# Sets BENCH_SERVER_PID and BENCH_SERVER_LOG.
# Returns 0 when server is ready, 1 on timeout.
start_mtp_server() {
    local model_key="$1"
    local n_max="$2"
    local pen="${3:-1.5}"
    local spec_type="${4:-draft-mtp}"

    local model ctx
    case "$model_key" in
        moe)   model="$MODEL_MOE"   ; ctx="$CTX_MOE"   ;;
        dense) model="$MODEL_DENSE" ; ctx="$CTX_DENSE" ;;
        *) echo "unknown model: $model_key" >&2; return 1 ;;
    esac

    local ts=$(date +%s)
    BENCH_SERVER_LOG="/home/eh/post4-bench/logs/server-${model_key}-n${n_max}-p${pen/./}-${ts}.log"

    local extra_args=()
    if [ "$n_max" -gt 0 ]; then
        extra_args+=( --spec-type "$spec_type"
                      --spec-draft-n-max "$n_max"
                      --spec-draft-n-min 0
                      --spec-draft-p-min 0.0 )
    fi

    "$BENCH_BIN" \
        --model "$model" \
        --host 127.0.0.1 --port "$BENCH_PORT" \
        --ctx-size "$ctx" \
        --batch-size 4096 --ubatch-size 512 \
        --flash-attn on \
        --no-mmap \
        --parallel 1 \
        --temperature 0.7 --top-p 0.8 --top-k 20 --min-p 0.0 \
        --presence-penalty "$pen" --repeat-penalty 1.0 \
        --chat-template-kwargs '{"enable_thinking":false}' \
        --slot-prompt-similarity 0.55 --cache-reuse 256 \
        --no-warmup \
        "${extra_args[@]}" \
        > "$BENCH_SERVER_LOG" 2>&1 &
    BENCH_SERVER_PID=$!

    # Wait up to 5 min for "server is listening"
    for i in $(seq 1 300); do
        if grep -qE "server is listening|all slots are idle" "$BENCH_SERVER_LOG" 2>/dev/null; then
            return 0
        fi
        if ! kill -0 "$BENCH_SERVER_PID" 2>/dev/null; then
            echo "server died during startup, see $BENCH_SERVER_LOG" >&2
            tail -20 "$BENCH_SERVER_LOG" >&2
            return 1
        fi
        sleep 1
    done
    echo "server didn't reach listening within 300s" >&2
    return 1
}

# Run a single chat-completion and emit one CSV-row to stdout:
#   ttft_ms,prompt_ms,predicted_ms,prompt_tps,predicted_tps,prompt_n,predicted_n,draft_n,draft_n_accepted,mtp_acc_pct,vram_peak_gb,temp_max_c,thermal_flag
#
# Args:
#   $1 = path to payload JSON (e.g. payloads/payload-medium.json)
#   $2 = output-prefix for run artifacts (e.g. /tmp/run-cell-r1)
run_mtp_test() {
    local payload="$1"
    local prefix="$2"
    local port="${BENCH_PORT:-9091}"

    local stream_out="${prefix}.stream"
    local ttft_file="${prefix}.ttft"
    local vram_log="${prefix}.vram"
    local temp_log="${prefix}.temp"

    # Polling pollers
    ( while : ; do gpu_vram_used_gb >> "$vram_log"; sleep 0.5; done ) &
    local vram_pid=$!
    ( while : ; do gpu_temp_c >> "$temp_log"; sleep 1; done ) &
    local temp_pid=$!

    local t_start=$(date +%s.%N)
    curl -sN -X POST "http://127.0.0.1:${port}/v1/chat/completions" \
        -H 'Content-Type: application/json' \
        --data-binary "@${payload}" \
        > "$stream_out"
    local t_end=$(date +%s.%N)

    kill "$vram_pid" "$temp_pid" 2>/dev/null
    wait "$vram_pid" "$temp_pid" 2>/dev/null

    # Compute TTFT proxy from elapsed time? — payloads are non-streaming for simplicity
    # We treat total elapsed - prompt_ms - predicted_ms as effective TTFT overhead.
    local elapsed_ms=$(awk -v s="$t_start" -v e="$t_end" 'BEGIN{printf "%.0f", (e-s)*1000}')

    local final_json="$stream_out"
    local timings_json=$(jq '.timings' "$final_json" 2>/dev/null)
    if [ -z "$timings_json" ] || [ "$timings_json" = "null" ]; then
        echo ",,,,,,,,,,,,no-timings"
        return 1
    fi

    local prompt_ms=$(echo "$timings_json" | jq -r '.prompt_ms // empty')
    local predicted_ms=$(echo "$timings_json" | jq -r '.predicted_ms // empty')
    local prompt_tps=$(echo "$timings_json" | jq -r '.prompt_per_second // empty')
    local predicted_tps=$(echo "$timings_json" | jq -r '.predicted_per_second // empty')
    local prompt_n=$(echo "$timings_json" | jq -r '.prompt_n // empty')
    local predicted_n=$(echo "$timings_json" | jq -r '.predicted_n // empty')
    local draft_n=$(echo "$timings_json" | jq -r '.draft_n // 0')
    local draft_acc=$(echo "$timings_json" | jq -r '.draft_n_accepted // 0')

    # Compute %MTP_of_out = accepted / predicted_n
    local mtp_pct="0"
    if [ "${predicted_n:-0}" -gt 0 ] && [ "${draft_acc:-0}" -gt 0 ]; then
        mtp_pct=$(awk -v a="$draft_acc" -v p="$predicted_n" 'BEGIN{printf "%.1f", (a/p)*100}')
    fi

    local vram_peak="0"
    [ -s "$vram_log" ] && vram_peak=$(sort -n "$vram_log" | tail -1)
    local temp_max="0"
    [ -s "$temp_log" ] && temp_max=$(sort -n "$temp_log" | tail -1)
    local thermal_flag="false"
    if [ -n "$temp_max" ] && [ "$temp_max" -gt 85 ] 2>/dev/null; then
        thermal_flag="true"
    fi

    echo "${elapsed_ms},${prompt_ms},${predicted_ms},${prompt_tps},${predicted_tps},${prompt_n},${predicted_n},${draft_n},${draft_acc},${mtp_pct},${vram_peak},${temp_max},${thermal_flag}"
    return 0
}
