#!/usr/bin/env python3
"""Aggregates RESULT lines from Scripts/eval/run.sh into one table with a
verdict per metric. Thresholds are per run (every run must clear them), so a
flaky case fails the harness rather than hiding in a mean."""
import sys
from collections import defaultdict
from pathlib import Path

# metric: (comparison, bound). "min" means value >= bound on every run;
# "max" means value <= bound on every run. Missing metrics fail.
THRESHOLDS = {
    "understanding": {"category": ("min", 24), "gist": ("min", 23), "title_language": ("min", 28), "no_answer": ("max", 0)},
    "snap":          {"missed": ("max", 0), "false_merges": ("max", 0), "no_answer": ("max", 0)},
    "ask":           {"answered": ("min", 11), "sources": ("min", 10), "language": ("min", 10), "translate_echo": ("max", 0), "no_tool": ("max", 1)},
    "memory":        {"kept": ("min", 1), "overstated": ("max", 0), "ungrounded_kept": ("max", 0),
                      "summary_first_person": ("max", 0), "summary_defines_name": ("max", 0), "summary_echo": ("max", 0), "summary_missing": ("max", 1)},
}

results_path, runs, out_dir = sys.argv[1], int(sys.argv[2]), sys.argv[3]
by_eval = defaultdict(list)
for line in Path(results_path).read_text().splitlines():
    parts = line.split()
    if len(parts) < 2 or parts[0] != "RESULT":
        continue
    metrics = {}
    for kv in parts[2:]:
        k, _, v = kv.partition("=")
        try:
            metrics[k] = float(v)
        except ValueError:
            pass
    by_eval[parts[1]].append(metrics)

failed = False
for name, rows in by_eval.items():
    print(f"\n== {name}  ({len(rows)} run{'s' if len(rows) != 1 else ''})")
    keys = sorted({k for r in rows for k in r})
    for k in keys:
        values = [r.get(k) for r in rows]
        present = [v for v in values if v is not None]
        worst = mean = None
        if present:
            mean = sum(present) / len(present)
        rule = THRESHOLDS.get(name, {}).get(k)
        verdict = ""
        if rule:
            kind, bound = rule
            if len(present) != len(rows):
                verdict, ok = "FAIL (missing)", False
            elif kind == "min":
                worst = min(present); ok = worst >= bound
                verdict = f"{'PASS' if ok else 'FAIL'}  (>= {bound})"
            else:
                worst = max(present); ok = worst <= bound
                verdict = f"{'PASS' if ok else 'FAIL'}  (<= {bound})"
            failed |= not ok
        else:
            worst = min(present) if present else None
        fmt = lambda v: "-" if v is None else (f"{v:.2f}" if k == "latency" else f"{v:g}")
        print(f"  {k:22} worst {fmt(worst):>6}  mean {fmt(mean):>6}  {verdict}")
    if any("failed" in r for r in rows):
        print("  (a run printed no RESULT line; see the logs)")
        failed = True

for name in THRESHOLDS:
    if name not in by_eval and (len(sys.argv) < 5):
        pass
print("\n" + ("FAIL" if failed else "PASS") + f"  logs: {out_dir}")
sys.exit(1 if failed else 0)
