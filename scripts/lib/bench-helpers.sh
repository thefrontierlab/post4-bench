# Shared functions for the Vulkan-vs-ROCm bench
# Source this from run-bench.sh / pilot.sh.

set -uo pipefail

# ─── Backend-aware GPU sensors ──────────────────────────────────────────────

# GPU edge temperature in degrees Celsius (integer).
# We use the amdgpu hwmon temp1_input (edge temp) — junction temp is also
# available but edge is the conservative chassis-warming signal we want.
gpu_temp_c() {
    cat /sys/class/drm/card1/device/hwmon/hwmon*/temp1_input 2>/dev/null \
        | head -1 \
        | awk '{printf "%d\n", $1/1000}'
}

# Currently used VRAM in gigabytes (float, 2 decimals).
# Sysfs path is identical for both backends — ROCm and Vulkan both go through
# the amdgpu kernel driver, so the kernel-side accounting is the same.
gpu_vram_used_gb() {
    awk '{printf "%.2f\n", $1/1024/1024/1024}' \
        /sys/class/drm/card1/device/mem_info_vram_used
}

# Currently used GTT (system RAM backing GPU allocations) in gigabytes.
gpu_gtt_used_gb() {
    awk '{printf "%.2f\n", $1/1024/1024/1024}' \
        /sys/class/drm/card1/device/mem_info_gtt_used
}

# ─── Cooldown / state-clear gates ───────────────────────────────────────────

# Block until GPU edge temp is below threshold (default 60°C).
# Strix Halo throttles aggressively when chassis warms, so this matters more
# than a fixed sleep would.
wait_for_temp() {
    local threshold="${1:-60}"
    local poll_s="${2:-5}"
    local t
    while : ; do
        t=$(gpu_temp_c)
        if [ "${t:-99}" -lt "$threshold" ]; then
            return 0
        fi
        sleep "$poll_s"
    done
}

# Block until VRAM-used is below threshold (GB, default 5).
# Vulkan drivers sometimes hold buffer objects in their cache after process
# exit; this prevents the next server from starting in a warm-cache state.
wait_for_vram_clear() {
    local target_gb="${1:-5.0}"
    local timeout_s="${2:-60}"
    local used
    for i in $(seq 1 $((timeout_s / 2))); do
        used=$(gpu_vram_used_gb)
        # bash arithmetic doesn't do floats; use awk
        if awk -v u="$used" -v t="$target_gb" 'BEGIN{exit !(u < t)}'; then
            return 0
        fi
        sleep 2
    done
    echo "WARN: VRAM didn't clear below ${target_gb} GB within ${timeout_s}s, current ${used} GB" >&2
    return 1
}

# ─── Pre-flight check ───────────────────────────────────────────────────────

preflight() {
    echo "=== Pre-flight checks ==="
    local issues=0

    # Production llama-server processes (exact match on executable name,
    # not full cmdline — that would match grep filters mentioning "llama-server")
    if pgrep -ax 'llama-server' >/dev/null 2>&1; then
        echo "  FAIL: llama-server processes still running:"
        pgrep -ax 'llama-server' | sed 's/^/    /'
        issues=$((issues+1))
    else
        echo "  OK:   no llama-server processes"
    fi

    # llama-monitor Python dashboard — exact script name
    if pgrep -fa 'llama-monitor/server\.py' >/dev/null 2>&1; then
        echo "  FAIL: llama-monitor still running:"
        pgrep -fa 'llama-monitor/server\.py' | sed 's/^/    /'
        issues=$((issues+1))
    else
        echo "  OK:   no llama-monitor"
    fi

    # GPU temp baseline
    local t=$(gpu_temp_c)
    echo "  GPU edge temp: ${t}°C"

    # VRAM baseline
    local v=$(gpu_vram_used_gb)
    echo "  VRAM in use: ${v} GB (idle baseline)"
    if awk -v u="$v" 'BEGIN{exit !(u > 5.0)}'; then
        echo "  WARN: VRAM baseline > 5 GB — something is holding memory"
    fi

    # GPU device access — actual permission check, not group-membership check
    # (the smoke tests showed GPU works fine without render group active in shell)
    if [ -r /dev/dri/renderD128 ] && [ -w /dev/dri/renderD128 ]; then
        echo "  OK:   /dev/dri/renderD128 accessible"
    else
        echo "  WARN: /dev/dri/renderD128 not accessible — runs may fail"
        # Not blocking — let llama-server itself fail if it can't init GPU
    fi

    if [ "$issues" -gt 0 ]; then
        echo "FAIL: $issues issue(s) — abort"
        return 1
    fi
    echo "PASS"
    return 0
}

# ─── Per-run measurement ────────────────────────────────────────────────────

# Run a single completion request against http://127.0.0.1:$PORT/completion,
# measuring streaming TTFT, gen t/s, prompt t/s, and VRAM peak.
#
# Arguments:
#   $1 = payload JSON file (must contain prompt, n_predict, etc.)
#   $2 = output prefix for temp files (e.g. /tmp/run-bench-vulkan-qwen-short-r3)
#
# Emits one CSV-friendly line to stdout with these fields, comma-separated:
#   ttft_ms,prompt_ms,predicted_ms,prompt_per_second,predicted_per_second,
#   prompt_n,predicted_n,vram_peak_gb,gpu_temp_max_c,thermal_flag,error
#
# Returns 0 on success, 1 on any error.
run_single_test() {
    local payload="$1"
    local prefix="$2"
    local port="${BENCH_PORT:-9091}"
    local response="${prefix}.response.json"
    local stream_out="${prefix}.stream.txt"
    local ttft_file="${prefix}.ttft"
    local vram_log="${prefix}.vram.log"
    local temp_log="${prefix}.temp.log"

    rm -f "$response" "$stream_out" "$ttft_file" "$vram_log" "$temp_log"

    # Start VRAM-peak poller in background
    (
        while : ; do
            gpu_vram_used_gb >> "$vram_log" 2>/dev/null
            sleep 0.5
        done
    ) &
    local vram_pid=$!

    # Start temperature poller in background
    (
        while : ; do
            gpu_temp_c >> "$temp_log" 2>/dev/null
            sleep 1
        done
    ) &
    local temp_pid=$!

    # Streaming request with client-side stopwatch for real TTFT.
    # We use --no-buffer + read line-by-line, watch for the first SSE event
    # with non-empty content, then capture wall-clock delta.
    local start_ns=$(date +%s%N)
    local first_done=""
    curl -sS -N --no-buffer --max-time 600 \
        -X POST "http://127.0.0.1:${port}/completion" \
        -H "Content-Type: application/json" \
        -d "@${payload}" 2>>"${prefix}.curl-err" \
        | while IFS= read -r line; do
            if [ -z "$first_done" ] && [[ "$line" == *'"content":"'* ]] \
                && [[ "$line" != *'"content":""'* ]]; then
                local end_ns=$(date +%s%N)
                echo "$(( (end_ns - start_ns) / 1000000 ))" > "$ttft_file"
                first_done=1
            fi
            echo "$line"
        done > "$stream_out"

    # Stop pollers
    kill "$vram_pid" "$temp_pid" 2>/dev/null
    wait "$vram_pid" "$temp_pid" 2>/dev/null

    # Parse the final SSE 'data:' line for the timings block
    local final_data=$(grep '"timings"' "$stream_out" | tail -1 | sed 's/^data: //')
    if [ -z "$final_data" ]; then
        echo ",,,,,,,,,,no-timings-block"
        return 1
    fi

    # Extract metrics with jq
    local ttft_ms=$(cat "$ttft_file" 2>/dev/null || echo "")
    local prompt_ms=$(echo "$final_data" | jq -r '.timings.prompt_ms // empty')
    local predicted_ms=$(echo "$final_data" | jq -r '.timings.predicted_ms // empty')
    local prompt_tps=$(echo "$final_data" | jq -r '.timings.prompt_per_second // empty')
    local predicted_tps=$(echo "$final_data" | jq -r '.timings.predicted_per_second // empty')
    local prompt_n=$(echo "$final_data" | jq -r '.timings.prompt_n // .tokens_evaluated // empty')
    local predicted_n=$(echo "$final_data" | jq -r '.tokens_predicted // .timings.predicted_n // empty')

    # VRAM peak from log
    local vram_peak="0"
    if [ -s "$vram_log" ]; then
        vram_peak=$(sort -n "$vram_log" | tail -1)
    fi

    # Max temp during run
    local temp_max="0"
    if [ -s "$temp_log" ]; then
        temp_max=$(sort -n "$temp_log" | tail -1)
    fi

    # Thermal flag: did edge temp exceed 85°C at any point?
    local thermal_flag="false"
    if [ -n "$temp_max" ] && [ "$temp_max" -gt 85 ] 2>/dev/null; then
        thermal_flag="true"
    fi

    echo "${ttft_ms},${prompt_ms},${predicted_ms},${prompt_tps},${predicted_tps},${prompt_n},${predicted_n},${vram_peak},${temp_max},${thermal_flag},"
    return 0
}

# ─── Server lifecycle ───────────────────────────────────────────────────────

# Start a llama-server in background for the given backend/model/cache config.
# Globals set:
#   BENCH_SERVER_PID — server's process ID (for cleanup)
#   BENCH_SERVER_LOG — path to server log
#
# Arguments:
#   $1 = backend ("vulkan" or "rocm")
#   $2 = model file path
#   $3 = cache_type_k value ("f16" or "q8_0")
#   $4 = ctx_size (default 65536)
#
# Returns 0 if server reached "starting the main loop" within timeout, else 1.
start_server() {
    local backend="$1"
    local model="$2"
    local cache_k="${3:-f16}"
    local ctx="${4:-65536}"
    local port="${BENCH_PORT:-9091}"

    local bin
    case "$backend" in
        vulkan) bin="/opt/llamacpp/vulkan/bin/llama-server-vulkan" ;;
        rocm)   bin="/opt/llamacpp/rocm/bin/llama-server-rocm" ;;
        *) echo "unknown backend: $backend" >&2; return 1 ;;
    esac

    BENCH_SERVER_LOG="/home/eh/post2-bench/logs/server-${backend}-$(date +%s).log"

    "$bin" \
        --model "$model" \
        --host 127.0.0.1 --port "$port" \
        --ctx-size "$ctx" \
        --batch-size 4096 --ubatch-size 512 \
        --flash-attn on \
        --cache-type-k "$cache_k" \
        --no-mmap \
        --parallel 1 \
        > "$BENCH_SERVER_LOG" 2>&1 &
    BENCH_SERVER_PID=$!

    # Wait up to 5 min for server to reach main loop
    for i in $(seq 1 300); do
        if grep -q "starting the main loop" "$BENCH_SERVER_LOG" 2>/dev/null; then
            return 0
        fi
        if ! kill -0 "$BENCH_SERVER_PID" 2>/dev/null; then
            echo "server died during startup, see $BENCH_SERVER_LOG" >&2
            return 1
        fi
        sleep 1
    done
    echo "server didn't reach main loop within 300s" >&2
    return 1
}

stop_server() {
    if [ -n "${BENCH_SERVER_PID:-}" ]; then
        kill "$BENCH_SERVER_PID" 2>/dev/null
        # Give it 10s to shut down cleanly
        for i in $(seq 1 10); do
            if ! kill -0 "$BENCH_SERVER_PID" 2>/dev/null; then
                break
            fi
            sleep 1
        done
        # Force-kill if still alive
        if kill -0 "$BENCH_SERVER_PID" 2>/dev/null; then
            kill -9 "$BENCH_SERVER_PID" 2>/dev/null
        fi
        wait "$BENCH_SERVER_PID" 2>/dev/null
        BENCH_SERVER_PID=""
    fi
    # Wait for VRAM to clear before next server start
    wait_for_vram_clear 5.0 30
}
