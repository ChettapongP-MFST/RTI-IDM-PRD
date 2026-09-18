#!/usr/bin/env python3
"""Melt the 3 wide customer trigger-threshold matrices into one tidy EWI CSV.

Source (local, gitignored): input/Trigger Requirement_<date>_<scope>.csv
  - each file = 8 indicator blocks x (L1/L2/L3) x (4 windows) x (3 day types)
Output (committed): production/04-gold-summary-table/data/ewi-alert-threshold.csv
  - one row per Scope x IndicatorKey x WindowCode x DayType with L1/L2/L3.

Re-run whenever the customer resends thresholds. `xx` / blank cells -> empty (null).
"""
from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
INPUT_DIR = REPO / "input"
OUT = REPO / "production" / "04-gold-summary-table" / "data" / "ewi-alert-threshold.csv"

DATE_TAG = "15Sep2026"
SCOPE_FILES = {
    "TOTAL_BANK": f"Trigger Requirement_{DATE_TAG}_Total Bank.csv",
    "RETAILS": f"Trigger Requirement_{DATE_TAG}_Retails.csv",
    "NON_RETAILS": f"Trigger Requirement_{DATE_TAG}_Non-Retails.csv",
}

# IndicatorId -> (IndicatorKey matching Gold_EarlyWarning output column, Direction)
INDICATORS = {
    1: ("GrossOutflow_MB", "HIGH_IS_BAD"),
    2: ("NetOutflow_MB", "LOW_IS_BAD"),
    3: ("AccumNetOutflow_MB", "LOW_IS_BAD"),
    4: ("DebitTxnCount_M", "HIGH_IS_BAD"),
    5: ("Velocity_X", "HIGH_IS_BAD"),
    6: ("AvgDebitAmount_MB", "HIGH_IS_BAD"),
    7: ("ClusterShare_Pct", "HIGH_IS_BAD"),
    8: ("ShareJump_Pct", "HIGH_IS_BAD"),
}

WINDOWS = [
    "BEFORE_WORKING_HOUR",
    "MORNING_WORKING_HOUR",
    "AFTERNOON_WORKING_HOUR",
    "AFTER_WORKING_HOUR",
]
WIN_BASECOL = [2, 6, 10, 14]          # first data column of each window block
DAYTYPES = ["BUSINESS_DAY", "WEEKEND", "HOLIDAY"]  # offsets 0,1,2 within a window

BLOCK_RE = re.compile(r"^\s*(\d+)\.\s")


def clean(v: str) -> str:
    v = (v or "").strip()
    return "" if v.lower() in ("", "xx") else v


def parse_scope(path: Path) -> dict:
    """Return {(indicatorId, window, daytype): {L1,L2,L3}}."""
    rows = list(csv.reader(path.open(newline="", encoding="utf-8-sig")))
    out: dict = {}
    current = None  # active indicatorId
    for r in rows:
        col0 = r[0].strip() if r else ""
        m = BLOCK_RE.match(col0)
        if m:
            current = int(m.group(1))
            continue
        if current is None or len(r) < 2:
            continue
        label = r[1].strip()
        lvl = None
        if label.startswith("L1"):
            lvl = "L1"
        elif label.startswith("L2"):
            lvl = "L2"
        elif label.startswith("L3"):
            lvl = "L3"
        if lvl is None:
            continue
        for w, base in zip(WINDOWS, WIN_BASECOL):
            for d, off in zip(DAYTYPES, range(3)):
                col = base + off
                val = clean(r[col]) if col < len(r) else ""
                out.setdefault((current, w, d), {})[lvl] = val
    return out


def main() -> int:
    missing = [f for f in SCOPE_FILES.values() if not (INPUT_DIR / f).exists()]
    if missing:
        print("Missing input files:\n  " + "\n  ".join(missing), file=sys.stderr)
        return 1

    OUT.parent.mkdir(parents=True, exist_ok=True)
    n = 0
    with OUT.open("w", newline="", encoding="utf-8") as fh:
        wr = csv.writer(fh)
        wr.writerow(
            ["Scope", "IndicatorId", "IndicatorKey", "WindowCode", "DayType",
             "Direction", "L1", "L2", "L3"]
        )
        for scope, fname in SCOPE_FILES.items():
            parsed = parse_scope(INPUT_DIR / fname)
            for ind_id in sorted(INDICATORS):
                key, direction = INDICATORS[ind_id]
                for w in WINDOWS:
                    for d in DAYTYPES:
                        cell = parsed.get((ind_id, w, d), {})
                        wr.writerow([
                            scope, ind_id, key, w, d, direction,
                            cell.get("L1", ""), cell.get("L2", ""), cell.get("L3", ""),
                        ])
                        n += 1
    print(f"Wrote {n} rows -> {OUT.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
