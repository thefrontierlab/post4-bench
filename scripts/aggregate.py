#!/usr/bin/env python3
"""
Aggregate per-cell stats from wave1-4 CSVs.

Reads results/wave*-*.csv (one row per (cell_id, run)), drops run=1 as warmup,
computes median + IQR + mean + stdev per cell on the n=4 measurement runs.
Emits results/summary.csv plus per-cell CV-warnings.

Usage:
    python3 scripts/aggregate.py
    python3 scripts/aggregate.py results/wave1-nmax-20260524-103000.csv
"""

from __future__ import annotations
import csv
import glob
import os
import statistics
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESULTS_DIR = ROOT / "results"

METRIC_COLS = [
    "predicted_tps",
    "prompt_tps",
    "draft_n",
    "draft_n_accepted",
    "mtp_pct",
    "vram_peak_gb",
    "temp_max_c",
]


def quartiles(values):
    if not values:
        return None, None, None
    s = sorted(values)
    n = len(s)
    if n == 1:
        v = s[0]
        return v, v, v
    q1 = statistics.quantiles(s, n=4, method="inclusive")[0]
    med = statistics.median(s)
    q3 = statistics.quantiles(s, n=4, method="inclusive")[2]
    return q1, med, q3


def cv_pct(values):
    if not values or len(values) < 2:
        return None
    m = statistics.mean(values)
    if m == 0:
        return None
    s = statistics.stdev(values)
    return (s / m) * 100.0


def aggregate_csv(path: Path) -> list[dict]:
    """Group rows by cell_id, drop run=1, aggregate runs 2-5."""
    cells: dict[str, list[dict]] = defaultdict(list)
    with path.open() as f:
        rdr = csv.DictReader(f)
        for row in rdr:
            cell = row.get("cell_id", "?")
            try:
                run = int(row.get("run", "0"))
            except ValueError:
                continue
            if run == 1:
                continue  # warmup drop
            cells[cell].append(row)

    out = []
    for cell_id, rows in sorted(cells.items()):
        sample_row = rows[0]
        agg = {
            "cell_id": cell_id,
            "n_runs": len(rows),
        }
        # Preserve grouping cols from first row
        for col in ("model", "n_max", "prompt", "workload", "penalty", "chain"):
            if col in sample_row and sample_row[col]:
                agg[col] = sample_row[col]

        for m in METRIC_COLS:
            vals = []
            for r in rows:
                v = r.get(m, "")
                if v in ("", "no-timings", None):
                    continue
                try:
                    vals.append(float(v))
                except ValueError:
                    continue
            if not vals:
                continue
            q1, med, q3 = quartiles(vals)
            agg[f"{m}_median"] = round(med, 3) if med is not None else None
            agg[f"{m}_iqr"] = round(q3 - q1, 3) if (q1 is not None and q3 is not None) else None
            agg[f"{m}_mean"] = round(statistics.mean(vals), 3)
            agg[f"{m}_stdev"] = round(statistics.stdev(vals), 3) if len(vals) >= 2 else 0
            cv = cv_pct(vals)
            agg[f"{m}_cv_pct"] = round(cv, 2) if cv is not None else None
            # CV-flag at 5%
            if cv is not None and cv > 5.0:
                agg.setdefault("cv_flags", []).append(f"{m}={cv:.1f}%")
        if "cv_flags" in agg:
            agg["cv_flags"] = ";".join(agg["cv_flags"])
        out.append(agg)
    return out


def main(args):
    if args:
        paths = [Path(p) for p in args]
    else:
        paths = sorted(RESULTS_DIR.glob("wave*-*.csv"))

    if not paths:
        print("No wave*-*.csv files found in results/", file=sys.stderr)
        return 1

    all_rows = []
    for p in paths:
        print(f"=== Aggregating {p.name} ===")
        rows = aggregate_csv(p)
        for r in rows:
            r["source_csv"] = p.name
        all_rows.extend(rows)
        for r in rows:
            cv_msg = f" CV-WARN: {r['cv_flags']}" if r.get("cv_flags") else ""
            print(
                f"  {r['cell_id']:42s} n={r['n_runs']:1d}"
                f" gen_tps median={r.get('predicted_tps_median', 'n/a')}"
                f" iqr={r.get('predicted_tps_iqr', 'n/a')}"
                f" mean={r.get('predicted_tps_mean', 'n/a')}"
                f"{cv_msg}"
            )

    # Write summary CSV
    if not all_rows:
        print("No aggregated rows.")
        return 1

    summary_path = RESULTS_DIR / "summary.csv"
    keys = sorted({k for r in all_rows for k in r.keys()})
    # Reorder for readability
    front = ["cell_id", "model", "n_max", "prompt", "workload", "penalty", "chain", "n_runs"]
    other = [k for k in keys if k not in front]
    cols = [k for k in front if k in keys] + other

    with summary_path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        for r in all_rows:
            w.writerow({k: r.get(k, "") for k in cols})
    print(f"\n=== Summary written: {summary_path} ({len(all_rows)} cells) ===")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
