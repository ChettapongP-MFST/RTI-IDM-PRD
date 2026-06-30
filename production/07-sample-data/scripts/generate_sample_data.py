"""Generate production-format INTRADAY_SUMMARY sample CSVs.

Format (pipe-delimited, NO header, one file per 15-minute interval):
    Date|Interval|Product|Channel|Status|TotalAmt|InflowAmt|OutflowAmt|InflowCnt|OutflowCnt|TotalCnt

Invariants (match resources/prd_datasets/*.CSV):
    * Amounts are right-aligned to width 18 with 2 decimals.
    * TotalAmt  == InflowAmt + OutflowAmt   (Inflow is the larger share).
    * TotalCnt  == InflowCnt + OutflowCnt   (Inflow count >= Outflow count).
    * Channel is left-justified, space-padded to 4 chars (e.g. "BC  ", "SCF ").
    * Rows are sorted by (Product, Channel).
    * File name: INTRADAY_SUMMARY_YYYYMMDD_HHMM_HHMM.CSV  (uppercase .CSV).

Default run produces 2026-07-01 .. 2026-07-10, intervals 09:45 -> 12:00 (9 per day).
"""

import os
import random
from datetime import date, timedelta

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SEED = 20260701
START_DATE = date(2026, 7, 1)
END_DATE = date(2026, 7, 10)

# Interval window covered each day (matches the existing 0615 / 0630 sample sets).
DAY_START_HHMM = (9, 45)
DAY_END_HHMM = (12, 0)

ROWS_MIN = 4
ROWS_MAX = 12

# Valid product -> channel universe (derived from existing prd_datasets samples).
PRODUCT_CHANNELS = {
    "C": ["BC", "BCMS", "ENET", "FAAT", "PMKF", "SIPI", "SYSG", "TFS"],
    "L": ["TELL"],
    "S": ["ATM", "BCMS", "CCAP", "ENET", "OEFS", "PMKF", "POS", "SCF", "SYSG", "TELL", "TFS"],
}
OFFLINE_CHANNELS = {"ATM", "POS", "TELL"}

# Per-channel total-amount range (THB); everything else uses the default band.
AMOUNT_RANGE = {
    "ENET": (90_000_000, 162_000_000),
    "TELL": (400_000, 3_800_000),
    "ATM": (300_000, 4_100_000),
    "POS": (1_000_000, 3_000_000),
}
DEFAULT_AMOUNT_RANGE = (1_300_000, 28_000_000)

# ---------------------------------------------------------------------------
# Derived paths
# ---------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", ".."))
OUTPUT_DIR = os.path.join(REPO_ROOT, "resources", "prd_datasets")


def build_intervals():
    """Return list of (label, tag) 15-minute windows for the configured day."""
    intervals = []
    start = DAY_START_HHMM[0] * 60 + DAY_START_HHMM[1]
    end = DAY_END_HHMM[0] * 60 + DAY_END_HHMM[1]
    m = start
    while m < end:
        nxt = m + 15
        sh, sm = divmod(m, 60)
        eh, em = divmod(nxt, 60)
        label = f"{sh:02d}:{sm:02d}-{eh:02d}:{em:02d}"
        tag = f"{sh:02d}{sm:02d}_{eh:02d}{em:02d}"
        intervals.append((label, tag))
        m = nxt
    return intervals


def all_combos():
    """Flatten product->channel map into a sorted list of (product, channel)."""
    combos = []
    for product, channels in PRODUCT_CHANNELS.items():
        for ch in channels:
            combos.append((product, ch))
    return combos


def make_amounts(channel):
    lo, hi = AMOUNT_RANGE.get(channel, DEFAULT_AMOUNT_RANGE)
    inflow = round(random.uniform(lo, hi) * random.uniform(0.55, 0.92), 2)
    outflow = round(random.uniform(lo, hi) * random.uniform(0.05, 0.45), 2)
    total = round(inflow + outflow, 2)
    return total, inflow, outflow


def make_counts():
    inflow_cnt = random.randint(12, 916)
    outflow_cnt = random.randint(int(inflow_cnt * 0.4), inflow_cnt)
    return inflow_cnt, outflow_cnt, inflow_cnt + outflow_cnt


def format_row(date_str, label, product, channel, status):
    total, inflow, outflow = make_amounts(channel)
    in_cnt, out_cnt, tot_cnt = make_counts()
    return "|".join([
        date_str,
        label,
        product,
        f"{channel:<4}",
        status,
        f"{total:>18.2f}",
        f"{inflow:>18.2f}",
        f"{outflow:>18.2f}",
        str(in_cnt),
        str(out_cnt),
        str(tot_cnt),
    ])


def main():
    random.seed(SEED)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    intervals = build_intervals()
    combos = all_combos()

    file_count = 0
    row_count = 0
    current = START_DATE
    while current <= END_DATE:
        date_str = current.isoformat()
        ymd = current.strftime("%Y%m%d")
        for label, tag in intervals:
            k = random.randint(ROWS_MIN, min(ROWS_MAX, len(combos)))
            chosen = sorted(random.sample(combos, k))
            lines = []
            for product, channel in chosen:
                status = "Offline" if channel in OFFLINE_CHANNELS else "Online"
                lines.append(format_row(date_str, label, product, channel, status))
            filename = f"INTRADAY_SUMMARY_{ymd}_{tag}.CSV"
            path = os.path.join(OUTPUT_DIR, filename)
            with open(path, "w", newline="", encoding="utf-8") as f:
                f.write("\n".join(lines) + "\n")
            file_count += 1
            row_count += len(lines)
        current += timedelta(days=1)

    print(f"Generated {file_count} files, {row_count} rows in {OUTPUT_DIR}")
    print(f"Date range: {START_DATE} .. {END_DATE}")
    print(f"Intervals/day: {len(intervals)}  ({intervals[0][0]} .. {intervals[-1][0]})")


if __name__ == "__main__":
    main()
