"""
Generate a full-day mock deposit movement dataset for a single date (default: today).

Reuses the intraday alert-tier design from generate_alert_mockup.py so the day
crosses all three cumulative net tiers within a single intraday:
  🟡 Low    ≤  -5,000 M Baht
  🟠 Medium ≤ -10,000 M Baht
  🔴 High   ≤ -15,000 M Baht

Output: 48 half-hour CSVs (YYYY_MM_DD_mock_HHMM_HHMM.csv) in extra-mock-up/.
Each CSV = 24 rows (3 Products × 4 Channels × 2 Transaction Types).

Usage:
  python generate_today_mock.py            # uses today's date
  python generate_today_mock.py 2026-09-17 # uses an explicit date (YYYY-MM-DD)
"""

import csv
import os
import random
import sys
from datetime import date

random.seed(2026)

OUT_DIR = os.path.join(os.path.dirname(__file__), "extra-mock-up")

TIME_SLOTS = [
    f"{h:02d}:{m:02d}-{(h + (m + 30) // 60):02d}:{(m + 30) % 60:02d}"
    for h in range(24) for m in (0, 30)
]
TIME_SLOTS[-1] = "23:30-24:00"

PRODUCTS = ["Fixed", "Saving", "Current"]
CHANNELS = [
    ("ATM", "Offline"),
    ("BCMS", "Online"),
    ("ENET", "Online"),
    ("TELL", "Offline"),
]
TXN_TYPES = ["On-Us", "Off-Us"]

COMBOS = [
    (prod, ch, cg, tt)
    for prod in PRODUCTS
    for ch, cg in CHANNELS
    for tt in TXN_TYPES
]

# Breach design for the day: low @ 09:00, medium @ 13:30, high @ 17:30.
# (low_slot, med_slot, high_slot, overnight_M, end_M)
BREACH = (18, 27, 35, -1000, -17000)
LOW_VAL, MED_VAL, HIGH_VAL = -5000, -10000, -15000
OVERNIGHT_SLOT = 8


def build_anchors():
    low_s, med_s, high_s, overnight, end_m = BREACH
    return [
        (0, 0),
        (OVERNIGHT_SLOT, overnight),
        (low_s, LOW_VAL),
        (med_s, MED_VAL),
        (high_s, HIGH_VAL),
        (47, end_m),
    ]


def interpolate_cumulative(anchors, n_slots=48):
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


def generate_rows_for_slot(date_str, time_label, target_net_m):
    target_net_baht = target_net_m * 1_000_000
    n = len(COMBOS)

    base_net = target_net_baht / n
    raw_nets = [base_net * (1 + random.uniform(-0.4, 0.4)) for _ in range(n)]
    raw_sum = sum(raw_nets)
    if abs(raw_sum) > 0:
        scale = target_net_baht / raw_sum
        row_nets = [r * scale for r in raw_nets]
    else:
        row_nets = [target_net_baht / n] * n

    rows = []
    for idx, (prod, ch, cg, tt) in enumerate(COMBOS):
        net = round(row_nets[idx])
        credit = round(random.uniform(200_000_000, 800_000_000))
        debit = credit - net
        if debit < 0:
            credit = abs(net) + round(random.uniform(50_000_000, 200_000_000))
            debit = credit - net

        credit_txn = random.randint(800, 5000)
        debit_txn = random.randint(800, 5000)
        total_txn = credit_txn + debit_txn

        rows.append({
            "Date": date_str,
            "Time": time_label,
            "Product": prod,
            "Channel": ch,
            "Channel_Group": cg,
            "Transaction_Type": tt,
            "Credit_Amount": credit,
            "Debit_Amount": debit,
            "Net_Amount": credit - debit,
            "Credit_Txn": credit_txn,
            "Debit_Txn": debit_txn,
            "Total_Txn": total_txn,
        })

    return rows


def slot_index_to_file_times(idx):
    h = idx // 2
    m = (idx % 2) * 30
    h2 = h + (m + 30) // 60
    m2 = (m + 30) % 60
    if h2 == 24:
        return f"{h:02d}{m:02d}", "2400"
    return f"{h:02d}{m:02d}", f"{h2:02d}{m2:02d}"


def main():
    if len(sys.argv) > 1:
        target = date.fromisoformat(sys.argv[1])
    else:
        target = date.today()

    date_str = target.isoformat()
    date_prefix = date_str.replace("-", "_")
    os.makedirs(OUT_DIR, exist_ok=True)

    cum = interpolate_cumulative(build_anchors())
    slot_nets = cum_to_slot_nets(cum)

    actual_cum = 0
    print(f"{'=' * 70}")
    print(f"  {date_str}  —  Alert Timeline")
    print(f"{'=' * 70}")
    print(f"  {'Slot':<6} {'Time':<14} {'Slot Net (M)':>14} {'Cum Net (M)':>14}  Alert")
    print(f"  {'-' * 6} {'-' * 14} {'-' * 14} {'-' * 14}  {'-' * 20}")

    for i in range(48):
        t_start, t_end = slot_index_to_file_times(i)
        time_label = TIME_SLOTS[i]
        rows = generate_rows_for_slot(date_str, time_label, slot_nets[i])

        fname = f"{date_prefix}_mock_{t_start}_{t_end}.csv"
        fpath = os.path.join(OUT_DIR, fname)
        with open(fpath, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=[
                "Date", "Time", "Product", "Channel", "Channel_Group",
                "Transaction_Type", "Credit_Amount", "Debit_Amount",
                "Net_Amount", "Credit_Txn", "Debit_Txn", "Total_Txn",
            ])
            writer.writeheader()
            writer.writerows(rows)

        slot_actual = sum(r["Net_Amount"] for r in rows)
        actual_cum += slot_actual
        actual_cum_m = actual_cum / 1_000_000

        if actual_cum_m <= -15000:
            alert = "HIGH"
        elif actual_cum_m <= -10000:
            alert = "MEDIUM"
        elif actual_cum_m <= -5000:
            alert = "LOW"
        else:
            alert = "Normal"

        if i % 4 == 0 or i == 47:
            print(f"  {i:<6} {time_label:<14} {slot_actual / 1_000_000:>14,.1f} {actual_cum_m:>14,.1f}  {alert}")

    print(f"\n  Final cumulative: {actual_cum / 1_000_000:,.1f} M Baht")
    print(f"  Files generated: 48 -> {OUT_DIR}")


if __name__ == "__main__":
    main()
