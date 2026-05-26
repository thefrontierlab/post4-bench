#!/bin/bash
# Top-level orchestrator: pilot → wave 1 → wave 2 → wave 3 → wave 4.

set -uo pipefail
HERE="$(dirname "$(realpath "$0")")"
cd /home/eh/post4-bench

echo "=== Pilot first ==="
bash "$HERE/pilot.sh" || { echo "Pilot failed, abort"; exit 1; }

echo ""
echo "=== Wave 1: n_max sweep ==="
bash "$HERE/run_wave1_nmax.sh" || echo "WARN: Wave 1 partial"

echo ""
echo "=== Wave 2: workload-type ==="
bash "$HERE/run_wave2_workload.sh" || echo "WARN: Wave 2 partial"

echo ""
echo "=== Wave 3: sampler A/B ==="
bash "$HERE/run_wave3_sampler.sh" || echo "WARN: Wave 3 partial"

echo ""
echo "=== Wave 4: chaining ==="
bash "$HERE/run_wave4_chaining.sh" || echo "WARN: Wave 4 partial"

echo ""
echo "=== All waves complete. Run aggregate.py + plot.py for summary. ==="
ls -la results/
