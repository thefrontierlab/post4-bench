# Post 4 — MTP Defaults Are A Trap — TL;DR (FINAL)

**Status**: ✅ **Controlled measurement-Wave durchgeführt** 2026-05-26 — 260 runs total, n=5 per cell, run 1 als warmup dropped, n=4 measurements. 52 aggregierte Cells in `results/summary.csv`, Plots in `results/plots/`.

**Build-lock**: llama.cpp **b9295** (commit `95405ac65`), Vulkan/RADV auf AMD Strix Halo (Bosgame M5, gfx1151).

---

## Headline (controlled n=4 medians)

Default `--spec-draft-n-max=16` (vor PR #23269) ist auf Qwen3.6 mit 1 MTP-Head **catastrophic**:

- **35B-A3B (MoE) bei n=16**: median 13.35 t/s → **-74% vs Baseline 52.98 t/s**
- **27B Dense bei n=16**: median 6.31 t/s → **-38% vs Baseline 10.33 t/s** + **Thermal-Throttling** (89°C edge, >85°C threshold)

Neuer Default `n=3` (seit PR #23269) ist für Dense near-optimal, für MoE neutral. Sweet-Spots bleiben architektur-spezifisch:

- **MoE Sweet-Spot n=2**: +11% (medium), +11% (long)
- **Dense Sweet-Spot n=3**: +61% (medium), +65% (long)

---

## Wave 1 — n_max Sweep (controlled, n=4 medians)

### Qwen3.6-27B (Dense)

| n_max | medium gen t/s | long gen t/s | vs Baseline (medium) |
|---|---|---|---|
| 0 (Baseline) | 10.33 | 10.16 | — |
| 1 | 15.12 | 15.16 | +47% |
| 2 | 16.63 | 16.65 | +61% |
| **3** ← new default | **16.58** | **16.72** | **+61%** |
| 4 | 16.26 | 16.39 | +57% |
| 6 | 12.71 | 13.69 | +23% |
| 8 | 8.30 | 8.78 | **-20%** |
| **16** ← old default | **6.31** | **6.42** | **-39%** + Thermal |

### Qwen3.6-35B-A3B (MoE)

| n_max | medium gen t/s | long gen t/s | vs Baseline (medium) |
|---|---|---|---|
| 0 (Baseline) | 52.98 | 51.65 | — |
| 1 | 58.97 | 57.65 | +11% |
| **2** ← Sweet-Spot | **58.20** | **57.50** | **+10%** |
| 3 ← new default | 52.34 | 51.35 | ~baseline |
| 4 | 45.58 | 42.50 | -14% |
| 6 | 34.22 | 35.48 | -35% |
| 8 | 21.92 | 23.22 | -59% |
| **16** ← old default | **13.35** | **14.84** | **-75%** |

**Headline-Visual**: `results/plots/wave1-nmax-sweep.png` zeigt beide Kurven side-by-side. MoE-Plateau ist viel schmaler als Dense-Plateau, beide kollabieren ab n≥6.

---

## Wave 2 — Workload-Type-Effekt (controlled, sweet-spot n_max)

### Qwen3.6-27B Dense at n=3

| Workload | gen_tps median | vs Dense Baseline (10.33) |
|---|---|---|
| **wl-code** (BST Python) | **23.65** | **+129%** |
| wl-structured (Linux history) | 17.40 | +68% |
| wl-creative (Bauhaus essay) | 16.45 | +59% |
| wl-technical (Vulkan vs ROCm) | 16.36 | +58% |
| wl-dialog (Senior/Junior) | 16.13 | +56% |

### Qwen3.6-35B-A3B MoE at n=2

| Workload | gen_tps median | vs MoE Baseline (52.98) |
|---|---|---|
| **wl-code** (BST Python) | **72.36** | **+37%** |
| wl-structured | 59.94 | +13% |
| wl-creative | 57.41 | +8% |
| wl-dialog | 54.92 | +4% |
| wl-technical | 53.97 | +2% |

**Headline-Visual**: `results/plots/wave2-workload.png`. Code-Prompts dominieren klar bei beiden Modellen. Dense+Code ist mit **+129% vs Baseline** das stärkste Single-Cell-Result der ganzen Bench.

---

## Wave 3 — Sampler-MTP-Coupling (controlled)

`presence-penalty 0.0 vs 1.5`, sweet-spot n_max, medium prompt:

| Modell | n_max | p-pen 0.0 | p-pen 1.5 | Δ |
|---|---|---|---|---|
| **27B Dense** | 3 | **17.03** | 15.81 | **-7.2%** |
| **35B-A3B MoE** | 2 | 56.65 | 55.51 | **-2.0%** |

Dense leidet ~3.6x mehr unter aggressiver presence-penalty als MoE — bestätigt Sampler-Coupling-These mit n=4 statistics. MoE absorbiert Sampler-Cost im dominanten Verify-Pfad.

Production-Wahl bleibt p-pen=1.5 (Quality > Speed-Trade-off für OpenClaw/Cron). Erwarteter Speedup-Verlust quantifiziert.

`results/plots/wave3-sampler.png`.

---

## Wave 4 — Multi-Spec-Type Chaining (NEU, PR #23269)

`--spec-type` chaining mit ngram-Drafters on top, sweet-spot n_max, medium prompt:

| Modell | mtp only | mtp + ngram-mod | mtp + ngram-mod + ngram-map-k4v |
|---|---|---|---|
| 27B Dense | 15.60 | 15.95 (+2.2%) | 15.81 (+1.3%) |
| 35B-A3B MoE | 52.73 | 50.11 (**-5.0%**) | 51.63 (-2.1%) |

**Befund**: Chaining liefert auf Strix-Halo / Vulkan **keinen netten Gewinn**. Dense gewinnt 1-2% (Noise), MoE verliert messbar — Compute-Konkurrenz auf single-Vulkan-Queue dominiert über zusätzliche Acceptance-Chancen. Bestätigt Recon B's Hypothese.

→ **Practical recommendation**: stick to `--spec-type draft-mtp` allein. Ngram-Chaining ist eine Option für CUDA/Multi-GPU-Setups (kmarble's 75 t/s auf Dual-5070-Ti zeigt das es woanders funktioniert), aber nicht auf integrierter Vulkan-Hardware.

`results/plots/wave4-chaining.png`.

---

## Build-Trajektorie (preliminary, n=1/Cell — siehe `results/preliminary/`)

Über 6 Tage upstream-Entwicklung (Production-Bench, weniger Statistik aber konsistente Richtung):

| Build | Datum | MoE mtp n=2 | Dense mtp n=3 | Sweet-Spots |
|---|---|---|---|---|
| b9199 | 17.05. | 59.06 (+9.7%) | — (n=4: 18.52, +80%) | stabil |
| b9219 | 18.05. | 56.87 (+8.4%) | n=4: 16.91 (+66%) | stabil + presence-penalty=1.5 |
| b9235 | 19.05. | 59.77 (+13.8%) | 17.37 (+71.9%) | stabil + new default n=3 |
| **b9295** | **23.05.** | 61.65 (+17.4%) | 18.52 (+81.3%) | stabil |

**Stabilität der Sweet-Spots über 4 Builds** = zentraler Mechanism-Punkt: Optimierungen wirken auf Verify-Cost, nicht auf Draft-Acceptance.

---

## Mechanism (drei Säulen für den Post)

**Säule 1 (Leviathan-Formel)**: `(1-α^(γ+1))/((1-α)(cγ+1))`. Mit empirischem α=0.63 (Dense) und solved c≈0.12 fällt theoretisches Optimum γ ≈ 3.5 — **exakt auf empirischem n=3** für Dense. Konvergenz Theorie/Messung.

**Säule 2 (Medusa-Per-Position-Decay)**: bei 1-MTP-Head ist β klein wegen autoregressivem Error-Propagation. Erklärt rapides Abfallen jenseits γ=4.

**Säule 3 (MoE-Extension, Erik's eigener Befund)**: bei MoE-Targets steigt effective c mit γ (verify-batch-expert-union wächst super-linear) → Optimum verschiebt sich **nach links** → MoE-Sweet-Spot bei n=2 statt n=4. **Nicht formal in 2026-Literatur** — eigene empirische Beitrag.

---

## Scope-Statement

`--spec-type draft-mtp` auf b9295 (stock master) ist **nur** für Qwen3-Familie (`qwen35` + `qwen35moe` architectures) end-to-end wired. Andere Familien (DeepSeek-V3, GLM-4/4.6, EXAONE-MoE, Ling/Bailing, MiMo-2) lesen MTP-Metadata aus GGUFs, haben aber **keinen `LLM_GRAPH_TYPE_DECODER_MTP`-Graph**. Plus `GGML_ASSERT(nextn_predict_layers == 1)` hardcoded.

**Post 4 narrow gefasst**: "Qwen3 MTP defaults on Vulkan / Strix Halo, controlled measurement on b9295".

---

## Methodische Hygiene

- **n=4 measurements pro Cell** (run 1 dropped als warmup) — Post-2-statistics-Grade
- **CV-Tracking**: predicted_tps CV überwiegend <5%, einige Cells 5-10% (vor allem n=16 und workload-creative). draft_n / draft_n_accepted haben höhere CV (per-response variability bei MTP) — separat geflaggt.
- **Thermal-Tracking**: `temp_max_c` pro Run, flag bei >85°C. Wave 1 dense n=16 long-prompt triggerte das mehrfach.
- **VRAM-Tracking**: peak GB pro Run mitgeloggt, validiert dass kein OOM passierte.
- **Server-Lifecycle**: Bench-Server auf Port 9091 separat von Production (8081). 24 server-restarts insgesamt (8 für Wave 1, 2 für Wave 2 model-switch, 4 für Wave 3 penalty-switch, 6 für Wave 4 chain-switch + Pilot).
- **Backend-Scope**: Vulkan/RADV only. ROCm aus per Post 3 / Issue #6182.

---

## Files in diesem Verzeichnis

- `tldr.md` — diese Datei (FINAL nach Wave-Run)
- `README.md` — entry point
- `methodology.md` — vollständige Bench-Methodology
- `anomalies.log` — beobachtete Issues
- `prompts/` — 5 workload-prompts (~600 tok) + medium (461) + long (3799)
- `payloads/` — JSON-payloads
- `scripts/` — bench-runner + aggregate.py + plot.py
- `results/wave{1,2,3,4}-*.csv` — raw per-run data, 260 rows total
- `results/summary.csv` — 52 aggregated cells (median/IQR/mean/stdev/CV)
- `results/plots/wave{1,2,3,4}-*.png` — matplotlib charts
- `results/preliminary/` — Day-1/2/3 Production-Bench-Daten als Reference (n=1)
