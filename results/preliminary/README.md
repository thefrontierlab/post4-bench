# Preliminary Bench Data (n=1 per cell, indikativ)

Dieses Verzeichnis enthält Production-Bench-Runs vom 2026-05-17 bis 2026-05-23,
durchgeführt während der Day-1/2/3 llama.cpp-Upgrade-Zyklen mit den
existierenden `bench-ab-mtp.sh` / `bench-ab-mtp-27b.sh` Scripts.

**Statistical caveat**: Jeder Bench-Run hat 5 Prompts × 1 Repeat = **n=1 per cell**.
Das ist OK für **direkte Production-Decisions** (Sweet-Spots finden, Build-zu-Build
Vergleich) — aber **NICHT publication-grade**. Run-to-run-Varianz auf einzelnen
Cells kann ±10% sein (z.B. 27B Dialog-Prompt: 13.04 vs 14.18 t/s in zwei separaten
Day-2/Day-3-Runs).

Die kontrollierte Bench-Wave (n=5/Cell, run 1 dropped, 240 runs total) ist in
`scripts/run_wave{1,2,3,4}.sh` definiert und produziert Daten in `results/wave*-*.csv`.

## File-Inventory

### MoE (Qwen3.6-35B-A3B)

| File | Datum | Build | Aliases | Notes |
|---|---|---|---|---|
| `bench-20260517-173104.summary.txt` | 17.05. 17:33 | b9199 | baseline, mtp(n=4), mtp(n=8) | erstes MTP-bench, n=4/8 |
| `bench-20260517-174318.summary.txt` | 17.05. 17:46 | b9199 | baseline, mtp(n=4), mtp(n=2) | n=2 als sweet-spot identifiziert |
| `bench-20260517-175116.summary.txt` | 17.05. 17:53 | b9199 | baseline, mtp(n=2), mtp(n=4) | n=2 bestätigt vs n=4 |
| `bench-20260518-222025.summary.txt` | 18.05. 22:22 | b9219 | baseline, mtp(n=2) | post-PR #23198 logit-copy + bid-fix Quants |
| `bench-20260519-174453.summary.txt` | 19.05. 17:46 | b9235 | baseline, mtp(n=2) | post-PR #23269 MTP clean-up |
| `bench-20260519-181458.summary.txt` | 19.05. 18:17 | b9235 | baseline, mtp(n=2), mtp(n=3) | n=3 (neuer Default) getestet, n=2 bleibt sweet-spot |
| `bench-20260523-110143.summary.txt` | 23.05. 11:03 | b9295 | baseline, mtp(n=2) | post-PR #23287 backend-sampling |

### Dense (Qwen3.6-27B)

| File | Datum | Build | Aliases | Notes |
|---|---|---|---|---|
| `bench-27b-20260517-175622.summary.txt` | 17.05. 18:01 | b9199 | baseline, mtp(n=2) | erstes 27B-MTP-bench |
| `bench-27b-20260517-180258.summary.txt` | 17.05. 18:10 | b9199 | baseline, mtp(n=2), mtp(n=4) | n=4 als sweet-spot identifiziert |
| `bench-27b-20260518-222458.summary.txt` | 18.05. 22:32 | b9219 | baseline, mtp(n=2), mtp(n=4) | post-PR #23198 |
| `bench-27b-20260519-175033.summary.txt` | 19.05. 17:56 | b9235 | baseline, mtp(n=4) | post-PR #23269 |
| `bench-27b-20260519-182907.summary.txt` | 19.05. 18:36 | b9235 | baseline, mtp(n=4), mtp(n=3) | n=3 ≈ n=4, sweet-spot revised auf n=3 |
| `bench-27b-20260523-110317.summary.txt` | 23.05. 11:08 | b9295 | baseline, mtp(n=3) | post-PR #23287, MoE+Dense parallel loaded (VRAM full) |
| `bench-27b-20260523-111541.summary.txt` | 23.05. 11:20 | b9295 | baseline, mtp(n=3) | VRAM-paging-Validation: nur Dense backends loaded |

## Headline Findings aus Preliminary Data

| Build | Datum | MoE mtp(n=2) gen t/s | Dense mtp(n=3) gen t/s | vs Baseline (MoE / Dense) |
|---|---|---|---|---|
| b9199 | 17.05. | 59.06 | 17.36 (n=2) / 18.52 (n=4) | +9.7% / +69% (n=4) |
| b9219 | 18.05. | 56.87 | 16.91 (n=4) | +8.4% / +66% |
| b9235 | 19.05. | 59.77 | 17.37 | +13.8% / +71.9% |
| b9295 | 23.05. | **61.65** | **18.52** | **+17.4% / +81.3%** |

## VRAM-Paging-Validation (23.05.)

| Variante | mit VRAM-Stress (4 backends loaded) | VRAM-frei (2 backends loaded) | Δ |
|---|---|---|---|
| Dense baseline | 10.216 | 10.210 | -0.06% (Noise) |
| Dense mtp n=3 | 18.52 | 18.71 | +1.0% (Noise) |

**Schluss**: VRAM-Paging hat keinen messbaren Inferenz-Tax bei sustained-Load — nur
Backend-Switch hat eine Migrations-Cost (~5-15s).
