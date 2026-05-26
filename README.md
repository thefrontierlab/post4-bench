# post4-bench

Controlled-measurement data and bench harness for "MTP Defaults Are a Trap: What 260 Runs Showed About Speculative Decoding on Qwen3" — [The Frontier Lab, May 2026](https://thefrontierlab.ai/mtp-defaults-are-a-trap).

260 benchmark runs measuring Multi-Token Prediction (MTP) speculative-decoding behavior on Qwen3 (dense + MoE) on AMD Strix Halo (Bosgame M5, gfx1151), Vulkan/RADV, llama.cpp b9295.

## Key findings

- The pre-PR-#23269 default `--spec-draft-n-max=16` is catastrophic on Qwen3's single MTP head: **−75% throughput on 35B-A3B MoE**, **−39% on 27B Dense** (plus thermal throttling).
- Sweet spots are architecture-specific: **n=2 for MoE A3B** (+10%), **n=3 for Dense** (+61%). The new upstream default of 3 is correct for Dense, leaves ~10% on the table for MoE.
- Sweet spots held stable across four build generations (b9199 → b9295) while absolute speedups climbed — evidence the optimum is architectural, not code-path-incidental.
- Code-generation workloads get the largest lift: **+129% on Dense, +37% on MoE** — far above prose.
- Aggressive `presence-penalty` taxes MTP speedup more on Dense (−7.2%) than MoE (−2.0%) — sampler and draft path are coupled.
- Multi-spec-type chaining (MTP + ngram drafters, PR #23269) gives no net gain on single-GPU Vulkan: Dense +1-2% (noise), MoE −5%. Compute competition on one Vulkan queue dominates.

## Hardware + software

| Component | Value |
|---|---|
| System | Bosgame M5 / Sixunited AXB35-02 |
| CPU/GPU | AMD Ryzen AI MAX+ 395, gfx1151 (Radeon 8060S) |
| Memory | 128 GB LPDDR5X unified, 96 GB UMA carveout |
| Backend | Vulkan/RADV (Mesa), ROCm not usable on this board (Issue #6182) |
| llama.cpp | b9295 (95405ac65) |
| Models | Qwen3.6-35B-A3B-MTP + Qwen3.6-27B-MTP, both UD-Q5_K_XL |

## Methodology

- n=5 runs per cell, run 1 dropped as warmup, n=4 measurements aggregated
- Median + IQR (primary), Mean + Stdev (secondary), CV>5% flagged
- Thermal cooldown to <60°C edge between runs; temp_max flagged at >85°C
- Bench server on isolated port 9091, production stack (8080/8081/8082) untouched throughout
- Acceptance rate from HTTP `timings.draft_n` / `draft_n_accepted`

## Waves

| Wave | What | Cells | Runs |
|---|---|---|---|
| 1 | n_max sweep (0,1,2,3,4,6,8,16 × 2 models × 2 prompt lengths) | 32 | 160 |
| 2 | Workload type (5 types × 2 models, at sweet-spot n_max) | 10 | 50 |
| 3 | Sampler coupling (presence-penalty 0.0 vs 1.5 × 2 models) | 4 | 20 |
| 4 | Multi-spec-type chaining (3 chains × 2 models) | 6 | 30 |
| **Total** | | **52** | **260** |

A harness pilot of 2 sanity runs ran before Wave 1 — not included in the 260 measurement runs.

## Files

| Path | Contents |
|---|---|
| `tldr.md` | Headline findings + all four wave tables + mechanism summary |
| `methodology.md` | Full bench methodology |
| `anomalies.log` | Observed issues during bench |
| `results/wave{1,2,3,4}-*.csv` | Raw per-run data, 260 rows |
| `results/summary.csv` | 52 aggregated cells (median/IQR/mean/stdev/CV) |
| `results/plots/wave{1,2,3,4}-*.png` | Charts |
| `results/preliminary/` | Day-1/2/3 production-side bench (n=1) — build-trajectory reference |
| `prompts/` | 5 workload prompts (~600 tok) + medium (461) + long (3799) |
| `scripts/` | bench runners + aggregate.py + plot.py |

## Mechanism in brief

The draft-depth optimum is set by the trade-off between more parallel tokens (favoring more drafts) and bigger, more expensive verification batches (favoring fewer). Three pillars:

1. **Leviathan speedup model** frames why a sweet spot exists. With measured α ≈ 0.63 on Dense, a fitted cost ratio c ≈ 0.12 puts the optimum near n=3 (a one-parameter fit, not a first-principles prediction).
2. **Single-head autoregressive decay**: Qwen3's lone MTP head compounds errors across draft positions, so acceptance falls geometrically — explaining the sharp collapse past the peak.
3. **MoE verify-batch expert-union growth** (own observation, not found formalized in the 2026 literature): for MoE targets, the union of activated experts grows super-linearly with draft count, raising effective verify cost with γ and shifting the optimum left — why MoE peaks at n=2 while Dense peaks at n=3.

## Scope

`--spec-type draft-mtp` is fully wired only for the Qwen3 family (`qwen35` + `qwen35moe`) on stock llama.cpp b9295. DeepSeek-V3, GLM-4, EXAONE-MoE, Ling/Bailing, MiMo-2 carry MTP metadata but no decoder graph upstream. Llama, Gemma, Mistral have no MTP heads. Single-head only (`GGML_ASSERT(nextn_predict_layers == 1)`).

## Not covered here (see follow-ups)

- Full-context decode behavior (>30k tokens) — separate post
- Quantization-depth sweep (Q4 vs Q5 vs Q8)
- ROCm backend (blocked by Issue #6182 on this board)
- Per-position acceptance rates (not exposed in stock master)

## License

- Scripts and methodology text: **MIT**
- Raw measurement data (`results/*.csv`, `results/preliminary/*`): **CC0** — factual data, no copyright reserved

## Related

- [Post 1 — What 96 GB of VRAM Actually Gets You](https://thefrontierlab.ai/what-96gb-of-vram-on-unified-memory-hardware-actually-gets-you-for-local-llm-inference)
- [Post 2 — Vulkan/RADV vs ROCm 6.4 on Strix Halo](https://thefrontierlab.ai/vulkan-radv-vs-rocm-6-4-on-strix-halo-what-128-benchmark-runs-actually-showed)
- [Post 3 — ROCm 7.x on the Bosgame M5: 14 Configurations, 14 Failures](https://thefrontierlab.ai/rocm-7-x-on-the-bosgame-m5-14-configurations-14-failures)
- [post3-bench](https://github.com/thefrontierlab/post3-bench)
- [llama.cpp PR #22673 (MTP merge)](https://github.com/ggml-org/llama.cpp/pull/22673) · [PR #23269 (default 16→3 + chaining)](https://github.com/ggml-org/llama.cpp/pull/23269)
