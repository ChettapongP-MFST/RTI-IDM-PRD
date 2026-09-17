"""
Generate alert-test INTRADAY_SUMMARY CSVs for today's ICT date: 2026-07-20.

Purpose
-------
Create 9 production-format files (09:45 -> 12:00, 15-min intervals) that push
three Product/Channel combinations into each Activator alert tier so that
Production 08 (Data Activator) can be validated end-to-end.

Alert design — cumulative Net_Amount per (Product, Channel) across 9 intervals:
  High   : C  / ENET  -> 9 x (-1,750,000,000) = -15,750,000,000  (<= -15,000 M)
  Medium : S  / BCMS  -> 9 x (-1,200,000,000) = -10,800,000,000  (<= -10,000 M)
  Low    : L  / TELL  -> 9 x (  -600,000,000) =  -5,400,000,000  (<=  -5,000 M)
  Normal : all others  -> small positive Net_Amount

File format (pipe-delimited, NO header, 11 columns):
  Date|Time|Product|Channel|Channel_Group|Credit_Amount|Debit_Amount|Net_Amount
  |Credit_Transaction|Debit_Transaction|Total_Transaction

Invariants (match existing resources/prd_datasets/*.CSV):
  * Amounts: right-aligned to width 18 with 2 decimal places.
  * Channel: left-justified, space-padded to 4 chars (e.g. "BC  ", "ENET").
  * Net_Amount = Credit_Amount - Debit_Amount  (must hold exactly per row).
  * Total_Transaction = Credit_Transaction + Debit_Transaction.
  * Rows sorted by (Product, Channel).
  * File name: INTRADAY_SUMMARY_20260720_HHMM_HHMM.CSV  (uppercase .CSV).

Output  -> resources/prd_datasets/   (same folder as existing sample files)
Upload  -> ADLS Gen2: mockadlsidimdprd001 / inflowoutflow / inbound/statement/
"""

import os
import random
from datetime import date

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SEED     = 20260720
TODAY    = date(2026, 7, 20)
DATE_STR = TODAY.isoformat()          # "2026-07-20"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT  = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", ".."))
OUTPUT_DIR = os.path.join(REPO_ROOT, "resources", "prd_datasets")

# 9 x 15-minute intervals (09:45 -> 12:00)
INTERVALS = [
    ("09:45-10:00", "0945_1000"),
    ("10:00-10:15", "1000_1015"),
    ("10:15-10:30", "1015_1030"),
    ("10:30-10:45", "1030_1045"),
    ("10:45-11:00", "1045_1100"),
    ("11:00-11:15", "1100_1115"),
    ("11:15-11:30", "1115_1130"),
    ("11:30-11:45", "1130_1145"),
    ("11:45-12:00", "1145_1200"),
]

OFFLINE_CHANNELS = {"ATM", "POS", "TELL"}


def channel_group(ch):
    return "Offline" if ch.strip() in OFFLINE_CHANNELS else "Online"


def fmt_amt(v):
    """Right-align amount to width 18 with 2 decimal places (matches prd_datasets)."""
    return f"{v:18.2f}"


def fmt_ch(ch):
    """Left-justify channel code, space-padded to 4 chars."""
    return f"{ch:<4}"


# ---------------------------------------------------------------------------
# Row definitions
# ---------------------------------------------------------------------------
# Alert-tier rows — fixed amounts every interval so cumulative hits each tier.
#   (product, channel, credit, debit, cr_txn, db_txn)
#   Net_Amount = credit - debit   (large negative to breach threshold)
ALERT_ROWS = [
    # High:   C/ENET  net = -1,750,000,000 / interval -> cumulative -15,750,000,000
    ("C", "ENET",  250_000_000.00, 2_000_000_000.00, 120, 480),
    # Medium: S/BCMS  net = -1,200,000,000 / interval -> cumulative -10,800,000,000
    ("S", "BCMS",  200_000_000.00, 1_400_000_000.00,  90, 360),
    # Low:    L/TELL  net =   -600,000,000 / interval -> cumulative  -5,400,000,000
    ("L", "TELL",   50_000_000.00,   650_000_000.00,  30, 120),
]

# Normal-tier rows — (product, channel, credit_range, debit_range, txn_range)
# Credit > Debit -> small positive Net -> "Normal" alert flag.
NORMAL_ROWS = [
    ("C", "BC",   (1_500_000,  12_000_000), (1_200_000,  10_000_000), (20, 150)),
    ("C", "BCMS", (2_000_000,  18_000_000), (1_600_000,  15_000_000), (25, 180)),
    ("C", "FAAT", (  500_000,   4_000_000), (  400_000,   3_500_000), (10,  80)),
    ("C", "PMKF", (  800_000,   6_000_000), (  600_000,   5_000_000), (12, 100)),
    ("C", "SIPI", (  300_000,   3_000_000), (  240_000,   2_500_000), ( 8,  60)),
    ("C", "SYSG", (  600_000,   5_000_000), (  480_000,   4_200_000), (11,  90)),
    ("C", "TFS",  (  400_000,   3_500_000), (  320_000,   2_900_000), ( 9,  70)),
    ("S", "ATM",  (  300_000,   4_100_000), (  240_000,   3_500_000), (15, 120)),
    ("S", "CCAP", (  500_000,   4_000_000), (  400_000,   3_400_000), (10,  80)),
    ("S", "ENET", (90_000_000, 162_000_000),(72_000_000, 135_000_000),(300, 500)),
    ("S", "OEFS", (  200_000,   2_000_000), (  160_000,   1_700_000), ( 8,  60)),
    ("S", "PMKF", (  700_000,   5_500_000), (  560_000,   4_600_000), (12,  95)),
    ("S", "POS",  (1_000_000,   3_000_000), (  800_000,   2_500_000), (14, 110)),
    ("S", "SCF",  (  400_000,   3_200_000), (  320_000,   2_700_000), ( 9,  72)),
    ("S", "SYSG", (  550_000,   4_500_000), (  440_000,   3_800_000), (10,  82)),
    ("S", "TELL", (  400_000,   3_800_000), (  320_000,   3_200_000), (11,  85)),
    ("S", "TFS",  (  350_000,   3_000_000), (  280_000,   2_500_000), ( 8,  65)),
]


# ---------------------------------------------------------------------------
# Main generator
# ---------------------------------------------------------------------------
def build_line(date_s, interval, product, channel, credit, debit, cr_txn, db_txn):
    """Return one pipe-delimited data line."""
    net = round(credit - debit, 2)
    return (
        f"{date_s}|{interval}|{product}|{fmt_ch(channel)}|{channel_group(channel)}"
        f"|{fmt_amt(credit)}|{fmt_amt(debit)}|{fmt_amt(net)}"
        f"|{cr_txn}|{db_txn}|{cr_txn + db_txn}"
    )


def main():
    random.seed(SEED)
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print(f"\nGenerating alert-test data for {DATE_STR} (ICT / UTC+7)")
    print(f"Output: {OUTPUT_DIR}")
    print()

    for interval_label, interval_tag in INTERVALS:
        rows = []  # (product_key, channel_key, line)

        # -- Alert-tier rows (deterministic) --
        for product, channel, credit, debit, cr_txn, db_txn in ALERT_ROWS:
            line = build_line(DATE_STR, interval_label, product, channel,
                              credit, debit, cr_txn, db_txn)
            rows.append((product, channel.strip(), line))

        # -- Normal-tier rows (seeded random) --
        for product, channel, (cr_lo, cr_hi), (db_lo, db_hi), (cnt_lo, cnt_hi) in NORMAL_ROWS:
            # Generate credit first, then debit independently (credit > debit on average)
            credit = round(random.uniform(cr_lo, cr_hi), 2)
            debit  = round(random.uniform(db_lo, db_hi), 2)
            cr_txn = random.randint(cnt_lo, cnt_hi)
            db_txn = random.randint(cnt_lo, cnt_hi)
            line   = build_line(DATE_STR, interval_label, product, channel,
                                credit, debit, cr_txn, db_txn)
            rows.append((product, channel.strip(), line))

        # Sort by (Product, Channel) ascending
        rows.sort(key=lambda r: (r[0], r[1]))

        fname = f"INTRADAY_SUMMARY_{DATE_STR.replace('-', '')}_{interval_tag}.CSV"
        fpath = os.path.join(OUTPUT_DIR, fname)
        with open(fpath, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(line for _, _, line in rows) + "\n")

        print(f"  ✓  {fname}  ({len(rows)} rows)")

    # ----------------------------------------------------------------
    print()
    print("=" * 60)
    print(f"Done — {len(INTERVALS)} files written.")
    print()
    print("Expected cumulative Net_Amount after ingestion (today ICT):")
    print(f"  High   C / ENET  : {9 * (-1_750_000_000) / 1_000_000:>12,.0f} M Baht  (<= -15,000 M)  [HIGH]")
    print(f"  Medium S / BCMS  : {9 * (-1_200_000_000) / 1_000_000:>12,.0f} M Baht  (<= -10,000 M)  [MEDIUM]")
    print(f"  Low    L / TELL  : {9 *   (-600_000_000) / 1_000_000:>12,.0f} M Baht  (<=  -5,000 M)  [LOW]")
    print()
    print("Next steps:")
    print("  1. Upload all INTRADAY_SUMMARY_20260720_*.CSV to ADLS Gen2:")
    print("       mockadlsidimdprd001 / inflowoutflow / inbound/statement/")
    print("  2. Wait for ingestion (event trigger P05 or scheduler P06)")
    print("  3. Verify: run the P8.3 KQL quick-check query")
    print("  4. Proceed with P8.2 -> P8.7 (Activator setup)")


if __name__ == "__main__":
    main()
