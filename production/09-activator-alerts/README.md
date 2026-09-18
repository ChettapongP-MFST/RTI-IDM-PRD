# Production 09 — Data Activator Alerts: Early Warning Indicators (EWI)

Wire **Data Activator** to the Gold Early Warning Indicators
([Production 04](../04-gold-summary-table/)) so intraday deposit-outflow triggers fire at
**L1 Watch / L2 Warning / L3 Critical**, per **Scope × indicator**, every **30 minutes**,
plus a 30-minute net-outflow digest.

> The previous per-Product/Channel `Net_Amount` alert is preserved in
> [README_old.md](README_old.md). This document covers the **EWI** alert model.

---

## Source — two options (match the Gold architecture)

Activator consumes the Gold EWI rows — one row per **Scope × 30-min bucket × indicator**, each
carrying its `Value` and an assigned **`Alert_Level`** (L0–L3) from the `EWI_AlertThreshold`
reference table. There are two ways to provide that source, matching the Gold
[architecture options](../04-gold-summary-table/README.md#architecture-options):

| | Source | Page |
| --- | --- | --- |
| **Option 1** | the `Gold_EarlyWarning()` **function** (KQL Queryset, run on schedule) | [option-1-function.md](option-1-function.md) |
| **Option 3** | the `DepositMovementEarlyWarning` **table** (populated every 30 min) | [option-3-snapshot-table.md](option-3-snapshot-table.md) |

- **Option 1** — simplest; alerting only, no history.
- **Option 3** — Activator reads a stored table; also powers Power BI dashboards, backtesting,
  and percentile calibration.

---

## Alert model (both options)

- **Object identity** = `Object_Id` = `Scope|IndicatorKey` (e.g. `TOTAL_BANK|NetOutflow_MB`) —
  each scope-indicator is tracked independently.
- **Watch `Alert_Level`** — the level is already computed per row from `EWI_AlertThreshold`
  (per `Window × DayType`), so a rule is a single condition: `Alert_Level in ('L2','L3')`
  (or `Alert_Rank >= 2`). No thresholds typed in Activator.
- **Filter** (optional) by `WindowCode`, `DayType`, `EventFlag`, or a specific `IndicatorKey`.
- **Retune** by editing [../04-gold-summary-table/data/ewi-alert-threshold.csv](../04-gold-summary-table/data/ewi-alert-threshold.csv)
  and reloading `EWI_AlertThreshold` — no rule change.
- **30-min digest** — a scheduled message from the `NetOutflow_MB` / `AccumNetOutflow_MB` rows
  (billions = `Value / 1000`).

### Example rule
> Object `TOTAL_BANK|NetOutflow_MB` · when `Alert_Level in ('L2','L3')` → alert.
>
> The level already encodes the morning/business-day threshold; to change it, edit the reference
> CSV and reload. To watch a different indicator, point the object at another `Scope|IndicatorKey`.

---

## Indicators & thresholds

Formulas, units, and directions for all 8 indicators are in the
[Gold EWI README](../04-gold-summary-table/README.md):

| # | Indicator | `IndicatorKey` | Unit | Breach |
| --- | --- | --- | --- | --- |
| 1 | Gross Outflow | `GrossOutflow_MB` | MB | ≥ |
| 2 | Net Outflow | `NetOutflow_MB` | MB | ≤ (neg) |
| 3 | Accum Net Outflow | `AccumNetOutflow_MB` | MB | ≤ (neg) |
| 4 | Debit Txn Count | `DebitTxnCount_M` | Million | ≥ |
| 5 | Transaction Velocity | `Velocity_X` | X | ≥ |
| 6 | Average Debit Amount | `AvgDebitAmount_MB` | MB | ≥ |
| 7 | Cluster Share | `ClusterShare_Pct` | % | ≥ *(threshold pending)* |
| 8 | Sudden Share Jump | `ShareJump_Pct` | pp | ≥ *(threshold pending)* |

Each indicator is a **row** (`IndicatorKey`) with its `Value` and `Alert_Level`. #7 Cluster Share
and #8 Sudden Share Jump emit values now; their thresholds are blank in `EWI_AlertThreshold` and
stay `L0` until the customer supplies numbers.

---

## Deployment

1. Deploy the Gold layer — [Production 04](../04-gold-summary-table/) (core + your chosen option).
2. Wire Activator for that option:
   - Option 1 → [option-1-function.md](option-1-function.md)
   - Option 3 → [option-3-snapshot-table.md](option-3-snapshot-table.md)
3. Add the 30-minute digest rule.
