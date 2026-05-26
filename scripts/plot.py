#!/usr/bin/env python3
"""
Generate Post 4 plots from results/summary.csv.

Plots:
  (a) n_max-sweep curve per (model, prompt) — Wave 1
  (b) workload-type bar chart per model — Wave 2
  (c) sampler-penalty A/B per model — Wave 3
  (d) chain-config comparison per model — Wave 4

Output: results/plots/*.png

Usage:
    python3 scripts/plot.py
"""

from __future__ import annotations
import csv
import os
import sys
from collections import defaultdict
from pathlib import Path

try:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
except ImportError:
    print("matplotlib not installed. pip install matplotlib", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parent.parent
RESULTS_DIR = ROOT / "results"
PLOTS_DIR = RESULTS_DIR / "plots"
PLOTS_DIR.mkdir(exist_ok=True)
SUMMARY = RESULTS_DIR / "summary.csv"

if not SUMMARY.exists():
    print(f"Missing {SUMMARY}. Run aggregate.py first.", file=sys.stderr)
    sys.exit(1)

rows = []
with SUMMARY.open() as f:
    rdr = csv.DictReader(f)
    for r in rdr:
        rows.append(r)


def fnum(v, default=None):
    try:
        return float(v)
    except (ValueError, TypeError):
        return default


# ─── (a) n_max sweep ───────────────────────────────────────────────────────
wave1 = [r for r in rows if r.get("source_csv", "").startswith("wave1-")]
if wave1:
    fig, axes = plt.subplots(1, 2, figsize=(13, 5), sharey=False)
    for ax, model in zip(axes, ("moe", "dense")):
        prompts = sorted({r["prompt"] for r in wave1 if r.get("model") == model})
        for prompt in prompts:
            cells = [
                r
                for r in wave1
                if r.get("model") == model and r.get("prompt") == prompt
            ]
            cells.sort(key=lambda r: fnum(r.get("n_max"), 0))
            xs = [fnum(r.get("n_max"), 0) for r in cells]
            ys = [fnum(r.get("predicted_tps_median")) for r in cells]
            iqrs = [fnum(r.get("predicted_tps_iqr"), 0) for r in cells]
            ax.errorbar(xs, ys, yerr=iqrs, marker="o", label=prompt, capsize=3)
        ax.set_xlabel("--spec-draft-n-max")
        ax.set_ylabel("generation t/s (median, IQR errorbar)")
        ax.set_title(f"{'Qwen3.6-35B-A3B (MoE)' if model == 'moe' else 'Qwen3.6-27B (Dense)'}")
        ax.grid(True, alpha=0.3)
        ax.legend()
    fig.suptitle(
        "n_max sweep — sweet-spots stable across builds, defaults are catastrophic",
        y=1.02,
    )
    fig.tight_layout()
    out = PLOTS_DIR / "wave1-nmax-sweep.png"
    fig.savefig(out, dpi=120, bbox_inches="tight")
    plt.close(fig)
    print(f"  wrote {out}")

# ─── (b) workload-type bar ─────────────────────────────────────────────────
wave2 = [r for r in rows if r.get("source_csv", "").startswith("wave2-")]
if wave2:
    fig, axes = plt.subplots(1, 2, figsize=(13, 5))
    for ax, model in zip(axes, ("moe", "dense")):
        cells = [r for r in wave2 if r.get("model") == model]
        cells.sort(key=lambda r: r.get("workload", ""))
        wls = [r.get("workload", "?") for r in cells]
        ys = [fnum(r.get("predicted_tps_median")) for r in cells]
        iqrs = [fnum(r.get("predicted_tps_iqr"), 0) for r in cells]
        ax.bar(wls, ys, yerr=iqrs, capsize=3, color="steelblue")
        ax.set_ylabel("generation t/s (median, IQR errorbar)")
        ax.set_title(f"{'MoE n=2' if model == 'moe' else 'Dense n=3'}")
        ax.tick_params(axis="x", rotation=45)
        ax.grid(True, axis="y", alpha=0.3)
    fig.suptitle("Workload-type variance — code wins most, creative least", y=1.02)
    fig.tight_layout()
    out = PLOTS_DIR / "wave2-workload.png"
    fig.savefig(out, dpi=120, bbox_inches="tight")
    plt.close(fig)
    print(f"  wrote {out}")

# ─── (c) sampler A/B ───────────────────────────────────────────────────────
wave3 = [r for r in rows if r.get("source_csv", "").startswith("wave3-")]
if wave3:
    fig, ax = plt.subplots(figsize=(8, 5))
    models = sorted({r["model"] for r in wave3})
    width = 0.35
    pens = ["0.0", "1.5"]
    for i, pen in enumerate(pens):
        ys = []
        for m in models:
            match = [
                r for r in wave3 if r.get("model") == m and r.get("penalty") == pen
            ]
            ys.append(fnum(match[0].get("predicted_tps_median")) if match else 0)
        xs = [j + i * width for j in range(len(models))]
        ax.bar(xs, ys, width=width, label=f"presence-penalty={pen}")
    ax.set_xticks([j + width / 2 for j in range(len(models))])
    ax.set_xticklabels(models)
    ax.set_ylabel("generation t/s (median)")
    ax.set_title("Sampler-MTP coupling — penalty=1.5 reduces dense MTP-speedup more")
    ax.legend()
    ax.grid(True, axis="y", alpha=0.3)
    fig.tight_layout()
    out = PLOTS_DIR / "wave3-sampler.png"
    fig.savefig(out, dpi=120, bbox_inches="tight")
    plt.close(fig)
    print(f"  wrote {out}")

# ─── (d) chain configs ─────────────────────────────────────────────────────
wave4 = [r for r in rows if r.get("source_csv", "").startswith("wave4-")]
if wave4:
    fig, ax = plt.subplots(figsize=(9, 5))
    models = sorted({r["model"] for r in wave4})
    chains = ["mtp", "mtp-ng", "mtp-ng-k4v"]
    width = 0.25
    for i, ch in enumerate(chains):
        ys = []
        for m in models:
            match = [r for r in wave4 if r.get("model") == m and r.get("chain") == ch]
            ys.append(fnum(match[0].get("predicted_tps_median")) if match else 0)
        xs = [j + i * width for j in range(len(models))]
        ax.bar(xs, ys, width=width, label=ch)
    ax.set_xticks([j + width for j in range(len(models))])
    ax.set_xticklabels(models)
    ax.set_ylabel("generation t/s (median)")
    ax.set_title("Multi-spec-type chaining — does adding ngram drafters help?")
    ax.legend()
    ax.grid(True, axis="y", alpha=0.3)
    fig.tight_layout()
    out = PLOTS_DIR / "wave4-chaining.png"
    fig.savefig(out, dpi=120, bbox_inches="tight")
    plt.close(fig)
    print(f"  wrote {out}")

print(f"\n=== Plots in {PLOTS_DIR} ===")
