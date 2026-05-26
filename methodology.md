# Recon B — Post 4 Bench Methodology

**Datum**: 2026-05-18, **Wave-4-Update**: 2026-05-19 (post PR #23269 merge), **Day-3-Update**: 2026-05-23 (post b9295, paging-test, sampler-coupling-quantification)
**Time-Budget genutzt**: ~50 Min initial + ~25 Min Wave 4 + ~30 Min Day-3 updates
**Status**: ready für Brief V1 (Wave 1–4 final, b9295-Build-Lock, alle Day-3-Befunde eingearbeitet)
**Build-lock**: **b9295 (95405ac65)** — post PR #23287 backend-sampling + #23433 logit-skip + #23461 VRAM-leak fix, Production hot-swapped 2026-05-23 10:58
**Bench-Backbone**: Post-2 statistical handling (n=5, run 1 = warmup, runs 2–5 = n=4 measurements) + Post-4-spezifische Cell-Matrix mit 4 Waves

> **Day-3 changelog (siehe §12 unten)**: Build b9235 → b9295 brachte +3.1% MoE / +6.6% Dense mean. Dense-Sweet-Spot von n=4 → **n=3** verschoben (matched neuen upstream-Default seit PR #23269). VRAM-Paging-Validation 2026-05-23 zeigte: keine messbare Inferenz-Penalty bei sustained inference, nur switch-cost. Presence-Penalty-Coupling jetzt quantifiziert: 1.5 vs 0.0 = -15pp Dense-MTP-Speedup. Sweet-Spots stabil über alle 4 Build-Generationen — Optimierungen wirken auf Verify-Cost, nicht Acceptance.

---

## 1. Scope + Why

Post 4 misst die **MTP-Konfigurations-Trap** auf llama.cpp b9235 (Vulkan/RADV, Strix Halo): warum der `--spec-draft-n-max=16`-Default (vor PR #23269) für 1-MTP-Head-Modelle deterministisch schlechter ist als Baseline, wo die Sweet-Spots liegen, wie stark Workload-Type und Sampler-Settings den Speedup modulieren, und ob das **Chaining multipler Speculation-Methoden** (PR #23269, gemerged 2026-05-19) nochmals zusätzlichen Gewinn bringt. Das ist eine **controlled-measurement-Wave**, nicht eine Production-Bestätigung — Erik's Day-1/Day-2-Bench (`/home/eh/llamacpp-upgrade-2026-05-17/bench-results/`) hat n=1/Cell mit warmup, was für Production-Decisions reicht, aber für einen Blog-Post mit publizierten Kurven zu rauschig ist. Post 4 nutzt **Post-2-grade statistics** auf neuem Mess-Datensatz.

**Story-Frame-Punch durch PR #23269**: Erik's empirisch gefundene Sweet-Spots (n=2 MoE, n=4 Dense) wurden ~3 Tage später durch upstream-default-Reduktion 16 → 3 indirekt validiert. Post 4 kann diese Konvergenz als Story-Hook nutzen: "Wir benchen jetzt gegen den neuen Default 3 statt den alten 16; das alte Trap-Maximum n=16 bleibt im Sweep als historischer Datenpunkt."

Out of Scope (gehört in Post 5): Full-Context-Behavior (>32k Tokens), Multi-User Concurrency, Quant-Tiefen-Sweep (Q4_K_XL vs Q5_K_XL), Heretic-Quant-Vergleich, Gemma-MTP (Upstream nicht verfügbar, siehe final-state.md §9.1).

---

## 2. Decisions Validated

### 2.1 Model scope — **Stick with Erik's two models**

Empfehlung: **Qwen3.6-35B-A3B-MTP (MoE) + Qwen3.6-27B-MTP (Dense), UD-Q5_K_XL only**. Keine Tiefen-Variation.

Begründung:
- Die Post-4-These ist *architektur-bedingt* (MoE batched-verify super-linear vs. Dense flat) — Q4_K_XL würde dieselbe These mit verschobenen absoluten Zahlen reproduzieren. Das ist Post-5-Material ("Quant depth × MTP coupling").
- Time-Budget: Q4-Sweep würde Bench verdoppeln (alle 210 Runs × 2 Quants = 420 Runs ≈ 11–12 h Wall-Clock). Kein Mehrwert für die Trap-Story.
- Beide MTP-Quants liegen bereits lokal (`~/models/Qwen3.6-{35B-A3B,27B}-MTP/`), neu hochgeladen post-PR #23237 (verifizierte SHA256 in final-state.md §11.2).

**Trade-off ausgewiesen** in der Limitations-Section von Post 4: "Quant-Tiefen-Effekt ist Post 5."

### 2.2 n_max sweep granularity — **Empfehlung: 1, 2, 3, 4, 6, 8, 16 (7 values, Erik's Vorschlag)**

Vergleich der drei Optionen:

| Option | Values | Cells (×2 models ×2 prompts ×5 runs) | Kurven-Qualität |
|---|---|---|---|
| **Coarse Erik** | 1, 2, 3, 4, 6, 8, 16 (7) | 140 | gut — dichter bei Sweet-Spot (1–4), spart bei 8/16 |
| Coarser | 1, 2, 4, 8, 16 (5) | 100 | Sweet-Spot-Region zu dünn — Dense (n=4 Peak) hätte keinen n=3-Punkt zum Visualisieren |
| Finer | 1, 2, 3, 4, 5, 6, 8, 12, 16 (9) | 180 | nice-to-have, aber +40 Runs (~1.5 h) für marginalen Gewinn |

**Pick: Erik's 7-Wert-Sweep.** Hat n=3 zwischen Dense-Peak (4) und Crossover (6), reicht für saubere Kurve. n=16 ist Pflicht weil es der Default-Trap-Punkt ist. n=1 ("single-token MTP") als Lower-Bound zur Validierung, dass MTP-Overhead bei minimalem Draft positiv bleibt (oder eben nicht).

### 2.3 Prompt set selection — **Re-use Post-2 medium + long**

Existierende Prompts in `/home/eh/post2-bench/prompts/` mit verifizierten Qwen-Tokenizer-Counts:

| ID | File | Token-Count | Inhalt |
|---|---|---|---|
| medium | `prompt-medium.txt` | 461 | Code-Review (Python Token-Estimator) — code-heavy, hohe MTP-Acceptance erwartet |
| long | `prompt-long.txt` | 3799 | Multi-Section technical doc — mixed Content, moderate Acceptance |

Beide in `/home/eh/post2-bench/prompts/` schon vorhanden, byte-identisch wiederverwendbar (auch in Post-4-Repo committen wegen Reproduzierbarkeit). **No full-context** (very-long mit 11205 Tokens kommt in Post 5).

Begründung der Auswahl:
- **medium** liefert den "common case" (~chat-typische Länge) → Headline-Number-Source für Post 4.
- **long** prüft, ob MTP-Speedup mit Context-Length stabil bleibt oder degradiert (wichtig für die These "MTP-Sweet-Spot hängt mehr von Content-Type als Prompt-Length ab").
- Code-Review-Prompt (medium) ist konsistent mit Post-2-Headlines und mit Production-Bench-Workloads — Reader können Cross-Reference machen.

### 2.4 Workload-type bench — **Erweitere Erik's Production-Prompts auf 500–800 Tokens**

Erik's existing 5 Prompts in `bench-ab-mtp.sh` sind 30–60 Tokens kurz — bei <100-Token-Prompts dominiert TTFT die Wall-Clock, was Gen-Speed-Vergleiche verzerrt. Sie geben aber gute *Themen-Templates*. Erweiterung pro Type (gespeichert in `~/post4-bench/prompts/wl-{type}.txt`):

| ID | Type | Erweiterung |
|---|---|---|
| `wl-code` | Code | Erik's BST + rebalancing/serialize/equality/pytest/JSON-roundtrip → ~600 tok |
| `wl-structured` | Strukturiert | Erik's Linux-Kernel + 5 Bullets/Phase (Event, Charakter, Repo, HW, Impact) → ~550 tok |
| `wl-technical` | Technical | Erik's Vulkan-vs-ROCm + Tabelle (API/Kernel/Multi-GPU/Stability/Coherence/Tooling) + 3 ggml-Code-Beispiele → ~700 tok |
| `wl-creative` | Creative | Erik's Bauhaus + 3 Absätze (Gropius 1919, Weimar→Dessau→Berlin, 21st-century-Einfluss) → ~600 tok |
| `wl-dialog` | Dialog | Erik's Senior/Junior + 8–10 Wechsel, BST-Code als Objekt, Klärungs-Konflikt → ~550 tok |

Token-Counts vor Bench mit `llama-tokenize ... --no-bos | wc -l` exakt erfasst, in `prompts/prompt-token-counts.csv` eingetragen.

### 2.5 Sampler A/B — **Bestätigt: 2×2 = 4 Cells, medium-prompt only**

| Cell | Model | presence-penalty | Erwartung |
|---|---|---|---|
| sp-moe-p0 | 35B-A3B-MTP | 0.0 | Mean-Speedup höher als Production (+9.7% wie Day-1 statt +8.4% Day-2) |
| sp-moe-p15 | 35B-A3B-MTP | 1.5 | Production-Baseline-Ergebnis |
| sp-dense-p0 | 27B-MTP | 0.0 | Mean +80% wie Day-1 |
| sp-dense-p15 | 27B-MTP | 1.5 | Mean +65.6% wie Day-2 |

Sweet-Spot-n_max pro Model wird *fixiert* (MoE n=2, Dense n=4) — diese Cells testen *nur* die Sampler-Penalty. Acceptance-Rate-Delta ist hier die Headline-Number: zeigt klar, dass aggressive penalty den Draft-Generator den gleichen Filter sehen lässt → niedrigere Acceptance.

### 2.6 Statistical handling — **Wie Post 2: n=5 pro Cell, run 1 dropped als Warmup, runs 2–5 = n=4 statistische Measurements**

Per Cell aggregation:
- **Median + IQR** (primary, robust gegen Outlier — vor allem für TTFT, wo gelegentliche RADV-Cache-Warmup-Spikes vorkommen)
- **Mean + Stdev** (secondary, vergleichbar zu Post-2-Tables)
- **CV-Flag**: stddev/mean > 5% triggert manuelle Inspection (Post-2-Konvention)
- **Per-Cell Metriken**: `gen_tps`, `prompt_tps`, `ttft_ms`, `predicted_n`, `draft_n`, `draft_n_accepted`, `vram_peak_gb`, `gpu_temp_max_c`

n=4 ist statistisch grenzwertig (Wilcoxon-Power gering), aber für Speedup-Vergleiche **Within-Cell**-Variabilität typisch < 3% CV bei Strix Halo Vulkan — das hat Post 2 empirisch gezeigt. n=5 mit warmup-drop ist daher die richtige Cost-Power-Balance.

### 2.7 Acceptance-rate methodology — **Per-Cell-Mean von `%MTP_of_out`**

Berechnung folgt Erik's Production-Bench-Script (`bench-ab-mtp.sh` Zeilen 67–82):
```
%MTP_of_out = draft_n_accepted / predicted_n × 100
```
Quelle: server-side `timings` block im non-streaming response JSON (oder im finalen SSE-Event bei stream=true).

**Per-Cell aggregation**: arithmetisches Mittel von runs 2–5 (warmup dropped). Median nicht nötig — das Feld ist über die n=4 measurements im Cell sehr stabil (typische Streuung <2pp).

**Per-Position acceptance** (Optional, Stretch-Goal für Post 4 falls Time-Budget reicht):
- llama.cpp emittiert seit b9199 `draft_n_accepted` aber NICHT per-position-counts. Wären wertvoll für die Visualisierung "wie weit kommen die N-Drafts im Average", aber Server-Patch nötig. **Nicht im V1-Scope.**
- Fallback: implizit über `draft_n / (predicted_n / n_max)` ableitbar, falls jeder Verify alle n_max Drafts macht. Dokumentieren als Heuristik in methodology.md.

### 2.8 Thermal protocol — **Edge-Sensor bestätigt, Threshold 60°C wie Post 2**

Sensor confirmed:
```
/sys/class/drm/card1/device/hwmon/hwmon2/temp1_input   # mC, label="edge"
```

(Bestätigt via `cat /sys/class/drm/card1/device/hwmon/hwmon2/temp1_label` → `edge`. Junction-Temp gibt es auf Strix Halo *nicht* — RDNA 3.5 amdgpu-Treiber exposed nur edge auf gfx1151 in Fedora 43 kernel 7.0.8.)

**Helper bereits in Post-2-Lib** (`/home/eh/post2-bench/scripts/lib/bench-helpers.sh`):
```bash
gpu_temp_c() { cat /sys/class/drm/card1/device/hwmon/hwmon*/temp1_input | head -1 | awk '{printf "%d\n", $1/1000}'; }
wait_for_temp() { local threshold="${1:-60}"; ... }
```

→ Wiederverwenden 1:1 in Post-4-Bench. Threshold 60°C ist konservativ (Strix-Halo throttle-edge ist ~85°C, aber chassis-warming reduziert sustained-TPS schon ab ~70°C — gemessen Post 2).

**Threshold-Begründung dokumentieren**: "60°C ist below Strix Halo's first throttle-tier; gibt deterministische cold-start-Bedingungen pro Run."

### 2.9 Server lifecycle — **Separater llama-server auf Port 9091, NICHT preset-frontend**

Bench läuft parallel zur Production via separat gestartetem llama-server auf Port **9091** (wie Phase C smoke-test, siehe final-state.md §11). Production auf 8081 bleibt unangetastet.

Gründe gegen preset-frontend: (1) `spec-draft-n-max` wird beim Server-Start gelesen, kein Hot-Reload; (2) Production-Restart riskiert OpenClaw-Downtime. Bench-Server via direkter binary-call mit expliziten CLI-flags (analog Post-2-Approach).

**Restart cadence**: n_max sweep 14 restarts (2 models × 7 n_max), workload 2 restarts (1/model, prompt-swap braucht nichts), sampler 4 restarts (2 models × 2 penalties). Pro Restart: stop + wait_for_vram_clear + start + wait_for_loop ≈ 30–45 s. **Total: 20 restarts × ~40 s ≈ 13 min Overhead**.

Bench-Server-Cmdline NICHT via preset-system. Erik's presets bleiben Production-untouched. Bench-config in `scripts/lib/start_mtp_server` als CLI-flag-array.

### 2.10 Backend scope — **Vulkan only, ROCm explizit als out-of-scope dokumentiert**

ROCm 6.4/7.x ist auf Bosgame M5 / gfx1151 blocked durch ROCm Issue #6182 (Post 3 publication, 14/14 configs reproduced). Post 4 dokumentiert das explicit:

> Backend: Vulkan/RADV via Mesa 25.3.6, identisch zu Post 2 und Production. ROCm-Bench für MTP nicht möglich — siehe Post 3 für die 14-Workaround-Matrix. ROCm-MTP-Numbers sind ein offenes Follow-up sobald HSA-Scratch-Bug upstream gefixt.

llama.cpp commit lock: **b9235 / d14ce3dab** (post PR #23269 clean-up, identisch zu Production seit 2026-05-19 17:30, static build, `BUILD_SHARED_LIBS=OFF`). Binary-Pfad `/usr/local/bin/llama-server`.

### 2.11 Multi-Spec-Type Chaining (Wave 4) — **PR #23269 ermöglicht Chaining mehrerer Speculation-Methoden gleichzeitig**

Seit PR #23269 (b9235) akzeptiert llama-server `--spec-type` mehrfach (oder als comma-separated list). Wenn MTP zusammen mit ngram-basierten Methoden geketted wird, sehen alle Implementations die accepted tokens (`#23269` Bugfix: "all speculative implementations now see accepted tokens"). Drei Chain-Configs werden gebenched:

| Chain-ID | `--spec-type` | Drafter | Begründung |
|---|---|---|---|
| `chain-mtp` | `draft-mtp` | nur MTP | Baseline (= Wave-3 Sweet-Spot Cell, hier reproduziert mit fresh n=5 series) |
| `chain-mtp-ng` | `draft-mtp,ngram-mod` | MTP + ngram-mod | Erik nutzt `ngram-mod` schon für `gemma-4-31b-unc`, `qwen36-27b-unc`, `qwen36-27b-aeon-unc` — bekannt funktionierend für repetitive/structured content |
| `chain-mtp-ng-k4v` | `draft-mtp,ngram-mod,ngram-map-k4v` | MTP + 2× ngram | Community demoed `+ngram-map-k4v` als third drafter; testet ob threefold chaining auf single-GPU Strix Halo skaliert oder OOM-Headroom-Issues entstehen |

**Fixed parameters für Wave 4** (alle Cells):
- Sweet-Spot `spec-draft-n-max`: MoE=2, Dense=4
- `spec-draft-p-min=0.0` (neuer Default seit #23269, explizit gesetzt zur Klarheit — Community-Warnung: 0.75 → -14.1% TG)
- Medium prompt only (461 tok) — zweimal long bringt für die Chaining-These keinen marginalen Erkenntnis, spart 50% Wave-Time
- `presence-penalty=1.5` (Production-Setting)
- ngram-mod defaults: `spec-ngram-mod-n-min=8 spec-ngram-mod-n-max=32 spec-ngram-mod-n-match=24` (analog zu Erik's Production-Presets)
- ngram-map-k4v defaults: keine custom flags, default-config

**Erwartungswert / Hypothesen**:
- Chain-2 (mtp+ngram-mod): bei structured content (medium-prompt = Code-Review) potentiell +5–15% on top vs mtp alone, da Code-Repetitions vom ngram-Drafter aufgegriffen werden
- Chain-3: mögliche Decline durch Compute-Konkurrenz auf single-Vulkan-Queue
- Negative Cases (chain < mtp alone): wäre Bench-Befund "chaining auf Single-GPU strix halo lohnt nicht"

**Acceptance-Aggregation für Wave 4**: zusätzlich zu `draft_n_accepted/predicted_n` interessieren die per-Drafter-Counters in `timings`-Block. Aggregate-Script muss prüfen, ob das HTTP-Response-JSON `draft_n_per_impl` / `draft_n_accepted_per_impl` field hat (war pre-#23269 nur scalar) — falls verfügbar pro Chain-Method auswerten, sonst nur Gesamtzahl.

---

## 3. Bench-Matrix (one page)

Cell-ID-Schema: `{wave}-{model}-{nmax}-{prompt}-{penalty}`. Wave-Codes: `nm` (n_max-sweep), `wl` (workload-type), `sp` (sampler-penalty A/B).

### Wave 1 — n_max sweep (28 cells, 140 runs)

Pattern: `nm-{model}-{n_max}-{prompt}-p15`, alle mit penalty=1.5, 5 runs/cell.

| Model | Ctx | Prompt | n_max-Werte | Time/Run (s) | Cells × Runs |
|---|---|---|---|---|---|
| MoE-35B-A3B | 131072 | medium (461 tok) | 1, 2, 3, 4, 6, 8, 16 | 10–24 | 7 × 5 = 35 |
| MoE-35B-A3B | 131072 | long (3799 tok) | 1, 2, 3, 4, 6, 8, 16 | 33–50 | 7 × 5 = 35 |
| Dense-27B | 65536 | medium | 1, 2, 3, 4, 6, 8, 16 | 16–32 | 7 × 5 = 35 |
| Dense-27B | 65536 | long | 1, 2, 3, 4, 6, 8, 16 | 40–60 | 7 × 5 = 35 |

Time/Run-Range pro Cell reflektiert die n_max-Spreizung (höchste Werte bei n=16-Trap, niedrigste am Sweet-Spot). Cell-IDs zum Beispiel: `nm-moe-2-medium-p15`, `nm-dense-16-long-p15`.

**Wave 1 subtotal**: 28 cells × 5 runs = **140 runs**, ~84 min run-time + 14 server-restarts × 40 s ≈ **~93 min**.

### Wave 2 — Workload-type bench (10 cells, 50 runs)

Sweet-Spot n_max fixiert, presence-penalty=1.5, 5 workload prompts per Modell.

| Cell-ID | Model | n_max | Prompt | Runs | Time/Run | Cell Time |
|---|---|---|---|---|---|---|
| wl-moe-code | MoE | 2 | wl-code (~600 tok) | 5 | ~14 s | ~1.7 min |
| wl-moe-structured | MoE | 2 | wl-structured (~550 tok) | 5 | ~13 s | ~1.6 min |
| wl-moe-technical | MoE | 2 | wl-technical (~700 tok) | 5 | ~16 s | ~1.9 min |
| wl-moe-creative | MoE | 2 | wl-creative (~600 tok) | 5 | ~14 s | ~1.7 min |
| wl-moe-dialog | MoE | 2 | wl-dialog (~550 tok) | 5 | ~13 s | ~1.6 min |
| wl-dense-code | Dense | 4 | wl-code | 5 | ~20 s | ~2.0 min |
| wl-dense-structured | Dense | 4 | wl-structured | 5 | ~19 s | ~1.9 min |
| wl-dense-technical | Dense | 4 | wl-technical | 5 | ~22 s | ~2.2 min |
| wl-dense-creative | Dense | 4 | wl-creative | 5 | ~21 s | ~2.1 min |
| wl-dense-dialog | Dense | 4 | wl-dialog | 5 | ~19 s | ~1.9 min |

**Wave 2 subtotal**: 10 cells × 5 runs = **50 runs**, ~19 min run-time + 2 server-restarts × 40 s ≈ **~21 min**.

### Wave 3 — Sampler-penalty A/B (4 cells, 20 runs)

Sweet-Spot n_max, medium-prompt, 2 penalties.

| Cell-ID | Model | n_max | Penalty | Runs | Time/Run | Cell Time |
|---|---|---|---|---|---|---|
| sp-moe-p0 | MoE | 2 | 0.0 | 5 | ~10 s | ~1.2 min |
| sp-moe-p15 | MoE | 2 | 1.5 | 5 | ~10 s | ~1.2 min |
| sp-dense-p0 | Dense | 4 | 0.0 | 5 | ~16 s | ~1.6 min |
| sp-dense-p15 | Dense | 4 | 1.5 | 5 | ~16 s | ~1.6 min |

**Wave 3 subtotal**: 4 cells × 5 runs = **20 runs**, ~5.5 min run-time + 4 server-restarts × 40 s ≈ **~9 min**.

### Wave 4 — Multi-spec-type chaining (6 cells, 30 runs)

Sweet-Spot n_max, medium-prompt, penalty=1.5. Variiert die Speculation-Pipeline-Tiefe.

| Cell-ID | Model | n_max | `--spec-type` | Runs | Time/Run | Cell Time |
|---|---|---|---|---|---|---|
| chain-moe-mtp | MoE | 2 | `draft-mtp` | 5 | ~10 s | ~1.2 min |
| chain-moe-mtp-ng | MoE | 2 | `draft-mtp,ngram-mod` | 5 | ~10–14 s | ~1.5 min |
| chain-moe-mtp-ng-k4v | MoE | 2 | `draft-mtp,ngram-mod,ngram-map-k4v` | 5 | ~10–16 s | ~1.7 min |
| chain-dense-mtp | Dense | 4 | `draft-mtp` | 5 | ~16 s | ~1.6 min |
| chain-dense-mtp-ng | Dense | 4 | `draft-mtp,ngram-mod` | 5 | ~16–20 s | ~1.9 min |
| chain-dense-mtp-ng-k4v | Dense | 4 | `draft-mtp,ngram-mod,ngram-map-k4v` | 5 | ~16–22 s | ~2.1 min |

Time/Run-Range reflects Unbekanntheit: chained Drafters könnten entweder schneller (höhere acceptance) oder langsamer (Compute-Konkurrenz) sein. Konservativ kalkuliert.

**Wave 4 subtotal**: 6 cells × 5 runs = **30 runs**, ~10 min run-time + 6 server-restarts × 40 s ≈ **~14 min**.

**Wave 4 ist Stretch falls Time-Budget tight** — Mininum-Sweep (Cells 1 + 4: chain-moe-mtp und chain-dense-mtp) ist redundant mit Wave 3 sp-{moe,dense}-p15, können bei Bedarf droppen → reduziert Wave 4 auf 4 cells / 20 runs / ~10 min total.

### Plus: Cooldown overhead

Thermal cooldown zwischen runs ist meist 0 s (Strix Halo cooled passive während prompt-eval), aber bei long-prompt-cells gelegentlich 5–15 s. Konservativ kalkuliert: **avg 5 s pro Run × 240 Runs = ~20 min** Cooldown total über die ganze Wave.

### Grand Total

| Wave | Cells | Runs | Run-Time | Server-Restarts | Subtotal |
|---|---|---|---|---|---|
| 1 n_max sweep | 28 | 140 | ~84 min | ~9 min | ~93 min |
| 2 Workload-type | 10 | 50 | ~19 min | ~1 min | ~21 min |
| 3 Sampler A/B | 4 | 20 | ~5.5 min | ~3 min | ~9 min |
| 4 Multi-spec chaining | 6 | 30 | ~10 min | ~4 min | ~14 min |
| Cooldown overhead | — | — | ~20 min | — | ~20 min |
| **TOTAL** | **48** | **240** | — | — | **~157 min = ~2.6 h** |

**Bench wall-clock estimate: 2.75–4 h** (mit 30% safety margin für Anomaly-Investigation und unexpected thermal stalls). Wave 4 fügt nur ~16 min zu, akzeptabel.

Erik's V1-Brief schätzte 5–6 h — das war zu konservativ. Strix-Halo-Generation-Zeiten sind schnell genug, dass die 240 Runs in ≤4 h durch sind. **Falls aber bei der Pilot-Phase irgendein Cell >2× erwartet braucht, ist Re-Estimate fällig.**

---

## 4. Total Time Estimate — Detail-Rechnung

**Annahmen** (validiert gegen final-state.md §11.4):
- MoE gen-speed range: 19–59 t/s (n=16 → Sweet-Spot n=2). Dense: 10–18.5 t/s.
- Generation: 400 Tokens/Run (max_tokens=400 wie Production-Bench).
- Prompt-eval-rate ~250 t/s (Vulkan/RADV): medium ≈ 2 s, long ≈ 15 s.

**Korrektur zu Erik's V1**: Erik kalkulierte "30 s prompt + 10–30 s gen". Tatsächlich medium ≈ 10–27 s/Run, long ≈ 22–40 s/Run. Model-Load ist 30–45 s (35B in GTT ~30 s, 27B ~22 s), nicht 15–20 s. → Wall-Clock konservativ 3–4 h, **plan für 4 h**, hoffe auf 2.5 h.

**Empfehlung**: Bench im Background via tmux/systemd. **Pilot mit 1 Cell vor Full-Sweep** (10 min sanity-check).

---

## 5. `~/post4-bench/` Directory Scaffold

Analog Post-2/Post-3-Convention. Pfade absolut:

```
/home/eh/post4-bench/
├── README.md                          # Entry point — was misst Post 4
├── methodology.md                     # Deep reference — diese recon-B-Datei als Vorlage, erweitert
├── tldr.md                            # One-page Key Findings für Post-Draft
├── anomalies.log                      # Append-only: observed Probleme during Bench
├── results.csv                        # Raw per-run CSV (analog Post 2)
├── summary.csv                        # Per-Cell aggregates aus aggregate.py
├── prompts/
│   ├── prompt-medium.txt              # Symlink/copy aus /home/eh/post2-bench/
│   ├── prompt-long.txt                # Symlink/copy aus /home/eh/post2-bench/
│   ├── wl-code.txt                    # ~600 tok, erweitert aus Erik's BST-Prompt
│   ├── wl-structured.txt              # ~550 tok, erweitert aus Erik's Linux-Kernel-Prompt
│   ├── wl-technical.txt               # ~700 tok, erweitert aus Erik's Vulkan-vs-ROCm-Prompt
│   ├── wl-creative.txt                # ~600 tok, erweitert aus Erik's Bauhaus-Prompt
│   ├── wl-dialog.txt                  # ~550 tok, erweitert aus Erik's Senior/Junior-Prompt
│   └── prompt-token-counts.csv        # Qwen-tokenizer-counts per prompt
├── payloads/                          # Generated per prompt — JSON payload für curl
│   ├── payload-medium.json
│   ├── payload-long.json
│   └── payload-wl-{code,structured,technical,creative,dialog}.json
├── logs/                              # Per-run server logs + temp/vram polling
│   ├── server-{wave}-{cell}-{run}.log
│   └── poll-{wave}-{cell}-{run}.{temp,vram}.tsv
├── scripts/
│   ├── lib/
│   │   └── bench-helpers.sh           # Copy aus /home/eh/post2-bench/scripts/lib/
│   ├── pilot.sh                       # 1-Cell-Probelauf für Harness-Sanity (~10 min)
│   ├── run_wave1_nmax.sh              # Wave 1 orchestrator (140 runs)
│   ├── run_wave2_workload.sh          # Wave 2 (50 runs)
│   ├── run_wave3_sampler.sh           # Wave 3 (20 runs)
│   ├── run_wave4_chaining.sh          # Wave 4 (30 runs) — multi-spec-type chaining (PR #23269)
│   ├── run_all.sh                     # Calls all four waves sequentially
│   ├── aggregate.py                   # Adapted aus Post-2; adds draft_n_accepted + per-impl chain breakdown
│   └── plot.py                        # New: matplotlib für (a) n_max sweep curve, (b) workload-bar, (c) sampler-A/B, (d) chain-stack-bar
└── .gitignore                         # logs/, payloads/, __pycache__/
```

**Skeleton der wichtigsten neuen Files**:

`scripts/run_wave1_nmax.sh` — Pseudocode:
```bash
#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/lib/bench-helpers.sh"
export BENCH_PORT=9091
declare -A MODELS=(
    [moe]="/home/eh/models/Qwen3.6-35B-A3B-MTP/Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf"
    [dense]="/home/eh/models/Qwen3.6-27B-MTP/Qwen3.6-27B-UD-Q5_K_XL.gguf"
)
declare -A CTX=( [moe]=131072 [dense]=65536 )
NMAX_VALUES=(1 2 3 4 6 8 16); PROMPTS=(medium long); RUNS=5; PENALTY=1.5
for model in moe dense; do
    for n_max in "${NMAX_VALUES[@]}"; do
        start_mtp_server "${MODELS[$model]}" "${CTX[$model]}" "$n_max" "$PENALTY"
        for prompt in "${PROMPTS[@]}"; do
            for run in $(seq 1 $RUNS); do
                row=$(run_single_test "payloads/payload-${prompt}.json" "/tmp/run-${model}-${n_max}-${prompt}-r${run}")
                append_to_csv "nm-${model}-${n_max}-${prompt}-p${PENALTY/./}" "$run" "$row"
                wait_for_temp 60
            done
        done
        stop_server && wait_for_vram_clear 5.0
    done
done
```

`scripts/aggregate.py` Erweiterungen ggü. Post-2:
- Extra-Spalten: `draft_n_mean`, `draft_n_accepted_mean`, `mtp_acceptance_pct_mean`
- Median + IQR zusätzlich zu Mean + Stdev
- Group-by: `(wave, model, n_max, prompt_id, penalty, chain_id)`
- Wave-4-spezifisch: parse `draft_n_per_impl` / `draft_n_accepted_per_impl` aus `timings`-Block, falls vorhanden (b9235+); fallback auf scalar wenn nicht exposed → flag in anomalies.log

`scripts/run_wave4_chaining.sh` — Pseudocode:
```bash
#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/lib/bench-helpers.sh"
export BENCH_PORT=9091
declare -A MODELS=(
    [moe]="/home/eh/models/Qwen3.6-35B-A3B-MTP/Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf"
    [dense]="/home/eh/models/Qwen3.6-27B-MTP/Qwen3.6-27B-UD-Q5_K_XL.gguf"
)
declare -A CTX=( [moe]=131072 [dense]=65536 )
declare -A NMAX=( [moe]=2 [dense]=4 )
CHAINS=(
    "mtp:draft-mtp"
    "mtp-ng:draft-mtp,ngram-mod"
    "mtp-ng-k4v:draft-mtp,ngram-mod,ngram-map-k4v"
)
RUNS=5; PENALTY=1.5
for model in moe dense; do
    for chain in "${CHAINS[@]}"; do
        chain_id="${chain%%:*}"; spec_type="${chain##*:}"
        start_chained_server "${MODELS[$model]}" "${CTX[$model]}" "${NMAX[$model]}" \
            "$PENALTY" "$spec_type"
        for run in $(seq 1 $RUNS); do
            row=$(run_single_test "payloads/payload-medium.json" \
                "/tmp/run-chain-${model}-${chain_id}-r${run}")
            append_to_csv "chain-${model}-${chain_id}" "$run" "$row"
            wait_for_temp 60
        done
        stop_server && wait_for_vram_clear 5.0
    done
done
```

`tldr.md` schema: Headline (Sweet-Spots + Workload + Sampler + Chaining), Verification-Table (n_max × {MoE,Dense} median gen t/s + Chain-Vergleich), Files-Liste.

---

## 6. Recommendation Summary (Brief V1)

1. **2 Modelle, 1 Quant-Depth** (Q5_K_XL). Q4-Sweep ist Post 5.
2. **7-Wert n_max-Sweep** (1, 2, 3, 4, 6, 8, 16) — Erik's Vorschlag bestätigt. **Story-Hook**: PR #23269 hat default 16 → 3 gesenkt am 2026-05-19; n=16 bleibt als historischer Trap-Datenpunkt im Sweep, n=3 ist der neue Default-Vergleichspunkt.
3. **n_max-Sweep Prompts**: medium + long aus Post-2 wiederverwenden, byte-identisch.
4. **5 Workload-Prompts erweitert** auf 500–800 Tokens. Erik's Production-Prompts als Templates.
5. **Stats**: n=5/Cell, run 1 Warmup, runs 2–5 = n=4. Median + IQR primary, Mean + Stdev secondary, CV>5% flagged.
6. **Bench-Server** auf Port 9091, separat von Production (8081). 22 restarts total (incl. Wave 4).
7. **Thermal**: edge-sensor `temp1_input`, wait_for_temp 60°C. Post-2-helper 1:1 wiederverwenden.
8. **Wall-clock**: 2.75–4 h, plan 4 h. Pilot mit 1 Cell vor Full-Sweep.
9. **48 Cells / 240 Runs**: Wave 1 (28/140), Wave 2 (10/50), Wave 3 (4/20), Wave 4 (6/30).
10. **Wave 4 (NEU, post PR #23269)**: Multi-spec-type chaining — `draft-mtp` alone vs `draft-mtp,ngram-mod` vs `draft-mtp,ngram-mod,ngram-map-k4v`, beide Modelle, medium prompt, Sweet-Spot n_max. Test ob Chaining +X% on top liefert oder durch Compute-Konkurrenz auf single-Vulkan-Queue degradiert.
11. **Build-Lock**: **b9295 / 95405ac65** (post PR #23287 backend-sampling, #23433 logit-skip, #23461 VRAM-leak-fix; Production hot-swapped 2026-05-23 10:58). p-min explizit 0.0 setzen für Klarheit auch wenn das jetzt der Default ist.
12. **Output** in `~/post4-bench/` analog Post-2; scripts: pilot.sh, run_wave{1,2,3,4}.sh, aggregate.py (+ per-impl chain breakdown), plot.py (+ chain-stack-bar).
13. **Backend**: Vulkan only. ROCm out-of-scope per Post 3 / Issue #6182.
14. **Dense Sweet-Spot revised** (Day-3-Befund): n=**3** statt n=4 — matched neuen upstream-Default seit PR #23269, gleichauf mit n=4 in production-bench, simpler config. Recon-B-original schrieb noch n=4; Wave 2 + Wave 3 sollten Dense-mtp-Cell mit n=3 fahren.

---

## 12. Day-3-Updates (2026-05-23) — eingearbeitet in Sections 1, 2.6, 2.10, 6 oben

### 12.1 Build-Trajektorie b9235 → b9295

Drei MTP-relevante upstream-PRs in 4 Tagen:

| Commit | PR | Was | Day-3-Produktions-Δ |
|---|---|---|---|
| `ad2775726` | #23287 | Backend-sampling für MTP draft-path (CPU→GPU sampling, eliminiert Roundtrip pro Draft) | dominanter Hebel, default=enabled |
| `12e5d9907` | #23433 | `inp_out_ids`-Logit-Skip (analog zu #23198) | incremental ~+1-2pp |
| `52fb93a2b` | #23461 | VRAM-leak-Fix bei sleep | nicht messbar, hygiene |

**Production-Bench-Result (n=5 pro alias, run 1 dropped as warmup)**:

| Modell | b9235 mean | b9295 mean | Δ | vs baseline |
|---|---|---|---|---|
| 35B-A3B (MoE) baseline | 52.50 | 52.51 | 0% | — |
| 35B-A3B (MoE) mtp n=2 | 59.77 | **61.65** | **+3.1%** | **+17.4%** |
| 27B (Dense) baseline | 10.21 | 10.22 | 0% | — |
| 27B (Dense) mtp n=3 | 17.37 | **18.52** | **+6.6%** | **+81.3%** |

Dense profitiert systematisch stärker: bei dense ist Sampler-Roundtrip relativ größerer Anteil der per-Token-Zeit als bei MoE (wo Verify-Cost dominiert). PR #23287's CPU↔GPU-Sync-Eliminierung trifft genau dort.

### 12.2 Dense Sweet-Spot Revision n=4 → n=3

Day-3-Bench mit explicit n=3 vs n=4 cell auf 27B Dense:

| Variante | Mean gen t/s | %MTP_of_out |
|---|---|---|
| mtp n=4 (Day-1-Sweet-Spot) | 17.27 | 61.0% |
| **mtp n=3** | **17.37** | 58.8% |

Differenz +1pp innerhalb run-to-run-Varianz (5 prompts, n=1 each). n=3 matched neuen upstream-Default (seit PR #23269), production-config kann auf n=3 gehen — explizit gesetzt für Reproduzierbarkeit, aber gleichbedeutend mit "trust the default".

MoE-Sweet-Spot bleibt n=2 (n=3 verliert ~10pp wegen super-linearem MoE-Verify-Cost).

### 12.3 VRAM-Paging-Validation

**Befund 2026-05-23**: 4 Backends gleichzeitig loaded → Vulkan0-Claims summieren auf ~105 GB vs 96 GB VRAM-Carveout → Driver paged während Backend-Wechsel.

Controlled A/B (Dense baseline + mtp n=3, je mit 4 vs 2 Backends loaded):

| Variante | mit VRAM-Stress (4 backends) | VRAM-frei (2 backends) | Δ |
|---|---|---|---|
| baseline mean | 10.216 | 10.210 | -0.06% (Noise) |
| mtp n=3 mean | 18.52 | 18.71 | +1.0% (Noise) |

**Schlussfolgerung**: Paging hat **keine messbare Inferenz-Penalty** für sustained-load. Switch-Cost (Backend-Wechsel) ist die einzige reale Penalty. Production-Setup mit `models-max=3` ist OK.

### 12.4 Sampler-Coupling quantifiziert (presence-penalty 0.0 vs 1.5)

| Modell | n_max | p-pen 0.0 | p-pen 1.5 | Δ Speedup |
|---|---|---|---|---|
| 35B-A3B MoE | 2 | +9.7% vs baseline | +8.4% | **-1.3pp** |
| 27B Dense | 4 | +80% vs baseline | +65.6% | **-14.4pp** |

Mechanismus: Draft-Generator und Target-Sampler teilen denselben Penalty-Filter → bei aggressiver Penalty werden Drafts häufiger sub-optimal → Acceptance-Rate fällt (Dense: 63.7% → 60.7%). Bei MoE überwiegt Verify-Cost so dominant, dass Sampler-Cost vernachlässigbar bleibt.

**Production-Wahl**: presence-penalty=1.5 bleibt für alle Aliases (Quality-Anforderung von OpenClaw / Cron-Jobs überwiegt). ~10pp MTP-Speedup-Verlust akzeptiert.

### 12.5 Workload-Type-Effekt verstärkt sich mit Build-Trajektorie

Code-Prompt (Python class) gen_t/s bei mtp:

| Build | 35B MoE | 27B Dense |
|---|---|---|
| b9199 (Day-1) | 67.35 | 21.59 |
| b9219 (Day-2) | 67.35 | 19.79 |
| b9295 (Day-3) | **72.89** | **25.70** |
| Δ b9199→b9295 | +8% | **+19%** |
| Speedup vs baseline (b9295) | **+39%** | **+152%** |

Code-Workloads sind die headline-source für Post-4-Number; Dense+Code-Prompt allein liefert >150% vs baseline. Wave 2 (workload-type) wird das systematisch validieren.

### 12.6 Architektur-Insight (zu erwähnen in Mechanism-Section)

Über alle 4 Build-Generationen (b9199, b9219, b9235, b9295) bleiben die Sweet-Spots **stabil**:
- MoE: n=2 in jedem Build
- Dense: n=3-4 (innerhalb Bench-Varianz identisch)

Build-zu-Build-Speedups wirken auf **Verify-Cost / Sample-Cost**, nicht auf **Draft-Acceptance** (die bleibt bei ~54% MoE / ~60% Dense konstant). Das bestätigt: Sweet-Spot-Lokalisation ist **architektur-bedingt** (Modell × Backend), nicht code-path-Artefakt.

→ Headline für Post 4 Mechanism-Section: *"Über drei aufeinanderfolgende upstream-Optimierungen haben sich die Sweet-Spots nicht verschoben, weil sie nicht Code-Detail-Artefakte sind, sondern strukturelle Eigenschaften der Modell-Architektur × Backend-Mechanik."*
