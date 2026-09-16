"""
Generate full-day mock intraday deposit-movement data in the production
INTRADAY_SUMMARY file format.

Output matches resources/prd_datasets/ exactly:
  - Filename : INTRADAY_SUMMARY_YYYYMMDD_HHMM_HHMM.CSV
  - Content  : pipe-delimited, no header
               Date|Time|Product|Channel|OnOff|Credit|Debit|Net|CrCnt|DrCnt|TotCnt
  - Coverage : full 24-hour day, 15-minute intervals (96 files/day)
  - Amounts  : right-aligned to width 18 with 2 decimals; Net = Credit - Debit
  - Channels : left-padded to width 4 (e.g. "SCF ", "BC  ")

The day is engineered so the intraday cumulative Net crosses all three alert
tiers within a single business day:
  Low    <=  -5,000 M Baht   (~09:00)
  Medium <= -10,000 M Baht   (~13:30)
  High   <= -15,000 M Baht   (~17:30)
Closing cumulative ~ -17,000 M Baht.

Usage:
  python generate_prd_mock.py 2026-09-17 2026-09-18
  python generate_prd_mock.py 20260917
  python generate_prd_mock.py            # uses today's date
"""

import os
import random
import sys
from datetime import date

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "prd_datasets")

# 96 quarter-hour slots. Last label closes the day at 24:00.
TIME_SLOTS = []
for _h in range(24):
    for _m in (0, 15, 30, 45):
        _h2 = _h + (_m + 15) // 60
        _m2 = (_m + 15) % 60
        TIME_SLOTS.append(f"{_h:02d}:{_m:02d}-{_h2:02d}:{_m2:02d}")

# Real Product | Channel | Online/Offline combinations observed in prd_datasets.
COMBOS = [
    ("C", "BC", "Online"),
    ("C", "BCMS", "Online"),
    ("C", "ENET", "Online"),
    ("C", "FAAT", "Online"),
    ("C", "PMKF", "Online"),
    ("C", "SIPI", "Online"),
    ("C", "SYSG", "Online"),
    ("C", "TFS", "Online"),
    ("L", "TELL", "Offline"),
    ("S", "ATM", "Offline"),
    ("S", "BCMS", "Online"),
    ("S", "CCAP", "Online"),
    ("S", "ENET", "Online"),
    ("S", "OEFS", "Online"),
    ("S", "PMKF", "Online"),
    ("S", "POS", "Offline"),
    ("S", "SCF", "Online"),
    ("S", "SYSG", "Online"),
    ("S", "TELL", "Offline"),
    ("S", "TFS", "Online"),
]

N_SLOTS = 96
# Anchors scaled to 96 slots: (slot, cumulative net in M Baht).
ANCHORS = [
    (0, 0),
    (16, -1000),   # overnight drift ~04:00
    (36, -5000),   # Low tier ~09:00
    (54, -10000),  # Medium tier ~13:30
    (70, -15000),  # High tier ~17:30
    (95, -17000),  # close of day
]


def interpolate_cumulative(anchors, n_slots=N_SLOTS):
    cum = [0.0] * n_slots
    for i in range(len(anchors) - 1):
        s0, c0 = anchors[i]
        s1, c1 = anchors[i + 1]
        for s in range(s0, s1 + 1):
            frac = (s - s0) / (s1 - s0) if s1 != s0 else 1.0
            cum[s] = c0 + frac * (c1 - c0)
    return cum


def cum_to_slot_nets(cum):
    nets = [cum[0]]
    for i in range(1, len(cum)):
        nets.append(cum[i] - cum[i - 1])
    return nets


def slot_to_file_times(idx):
    h, m = divmod(idx * 15, 60)
    h2 = h + (m + 15) // 60
    m2 = (m + 15) % 60
    return f"{h:02d}{m:02d}", f"{h2:02d}{m2:02d}"


def generate_rows(date_str, time_label, target_net_m):
    target_net_baht = target_net_m * 1_000_000
    k = random.randint(3, 12)
    chosen = random.sample(COMBOS, k)

    base = target_net_baht / k
    raw = [base * (1 + random.uniform(-0.4, 0.4)) for _ in range(k)]
    raw_sum = sum(raw)
    if abs(raw_sum) > 0:
        scale = target_net_baht / raw_sum
        nets = [r * scale for r in raw]
    else:
        nets = [target_net_baht / k] * k

    lines = []
    for (prod, ch, onoff), net in zip(chosen, nets):
        credit = random.uniform(50_000_000, 800_000_000)
        debit = credit - net
        if debit < 0:
            credit = abs(net) + random.uniform(50_000_000, 200_000_000)
            debit = credit - net

        credit_cnt = random.randint(50, 900)
        debit_cnt = random.randint(50, 900)
        total_cnt = credit_cnt + debit_cnt

        lines.append("|".join([
            date_str,
            time_label,
            prod,
            f"{ch:<4}",
            onoff,
            f"{credit:>18.2f}",
            f"{debit:>18.2f}",
            f"{credit - debit:>18.2f}",
            str(credit_cnt),
            str(debit_cnt),
            str(total_cnt),
        ]))
    return lines, credit_net_sum(lines)


def credit_net_sum(lines):
    total = 0.0
    for ln in lines:
        total += float(ln.split("|")[7])
    return total


def build_day(target):
    date_str = target.isoformat()
    ymd = target.strftime("%Y%m%d")
    random.seed(int(ymd))

    os.makedirs(OUT_DIR, exist_ok=True)
    cum = interpolate_cumulative(ANCHORS)
    slot_nets = cum_to_slot_nets(cum)

    print("=" * 74)
    print(f"  {date_str}  ->  INTRADAY_SUMMARY_{ymd}_*.CSV  (PRD format)")
    print("=" * 74)
    print(f"  {'Slot':<5} {'Time':<13} {'Slot Net (M)':>13} {'Cum Net (M)':>13}  Alert")
    print(f"  {'-' * 5} {'-' * 13} {'-' * 13} {'-' * 13}  {'-' * 8}")

    actual_cum = 0.0
    for i in range(N_SLOTS):
        t_start, t_end = slot_to_file_times(i)
        time_label = TIME_SLOTS[i]
        lines, slot_actual = generate_rows(date_str, time_label, slot_nets[i])

        fname = f"INTRADAY_SUMMARY_{ymd}_{t_start}_{t_end}.CSV"
        with open(os.path.join(OUT_DIR, fname), "w", newline="", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")

        actual_cum += slot_actual
        cum_m = actual_cum / 1_000_000
        if cum_m <= -15000:
            alert = "HIGH"
        elif cum_m <= -10000:
            alert = "MEDIUM"
        elif cum_m <= -5000:
            alert = "LOW"
        else:
            alert = "Normal"

        if i % 8 == 0 or i == N_SLOTS - 1:
            print(f"  {i:<5} {time_label:<13} {slot_actual / 1_000_000:>13,.1f} {cum_m:>13,.1f}  {alert}")

    print(f"\n  Final cumulative: {actual_cum / 1_000_000:,.1f} M Baht")
    print(f"  Files generated : {N_SLOTS} -> {os.path.normpath(OUT_DIR)}\n")


def main():
    args = sys.argv[1:]
    if not args:
        targets = [date.today()]
    else:
        targets = []
        for a in args:
            a = a.strip()
            if "-" in a:
                targets.append(date.fromisoformat(a))
            else:
                targets.append(date(int(a[:4]), int(a[4:6]), int(a[6:8])))

    for t in targets:
        build_day(t)


if __name__ == "__main__":
    main()
