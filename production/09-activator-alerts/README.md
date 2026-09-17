# Production 09 — Data Activator Alerts: Early Warning Indicators (EWI)

Wire **Data Activator** to the Gold Early Warning Indicators
([Production 04](../04-gold-summary-table/)) so intraday deposit-outflow triggers fire at
**L1 Watch / L2 Warning / L3 Critical**, per **Scope × indicator**, every **30 minutes**,
plus a 30-minute net-outflow digest.

> The previous per-Product/Channel `Net_Amount` alert is preserved in
> [README_old.md](README_old.md). This document covers the **EWI** alert model.

---

## Source — two options (match the Gold architecture)

Activator consumes the Gold EWI rows — one row per **Scope × 30-min bucket** with every
dimension as a **filter** column and every indicator as a **threshold** column. There are two
ways to provide that source, matching the Gold [architecture options](../04-gold-summary-table/README.md#architecture-options):

| | Source | Page |
| --- | --- | --- |
| **Option 1** | the `Gold_EarlyWarning()` **function** (KQL Queryset, run on schedule) | [option-1-function.md](option-1-function.md) |
| **Option 3** | the `Gold_EarlyWarning_Snapshot` **table** (populated every 30 min) | [option-3-snapshot-table.md](option-3-snapshot-table.md) |

- **Option 1** — simplest; alerting only, no history.
- **Option 3** — Activator reads a stored table; also powers Power BI dashboards, backtesting,
  and percentile calibration.

---

## Alert model (both options)

- **Object identity** = `Scope` (`TOTAL_BANK` / `RETAILS` / `NON_RETAILS`) — 3 tracked objects.
- **Filter** in / out by `WindowCode`, `DayType`, `EventFlag` — Activator property filters.
- **Threshold** a numeric indicator column (`NetOutflow_MB`, `Velocity_X`, `ClusterShare_Pct`, …)
  with a value typed in the Activator UI. Because each rule is already filtered to one context,
  its threshold is a single editable constant.
- **Tier** a metric with L1/L2/L3 as three conditions, or three rules with a `Changes` guard.
- **30-min digest** — a scheduled message using `NetOutflow_Bn` (periodic) and
  `AccumNetOutflow_Bn` (cumulative from 00:00).

### Example rule
> Object `TOTAL_BANK` · filter `WindowCode = MORNING_WORKING_HOUR` and `DayType = BUSINESS_DAY`
> · when `NetOutflow_MB <= -5500` → **L3 Critical**.

To retune, edit the number in the Activator UI. To ignore holidays, drop the `DayType` filter.

---

## Indicators & thresholds

Formulas, units, and directions for all 8 indicators are in the
[Gold EWI README](../04-gold-summary-table/README.md):

| # | Indicator | Column | Unit | Breach |
| --- | --- | --- | --- | --- |
| 1 | Gross Outflow | `GrossOutflow_MB` | MB | ≥ |
| 2 | Net Outflow | `NetOutflow_MB` | MB | ≤ (neg) |
| 3 | Accum Net Outflow | `AccumNetOutflow_MB` | MB | ≤ (neg) |
| 4 | Debit Txn Count | `DebitTxnCount_M` | Million | ≥ |
| 5 | Transaction Velocity | `Velocity_X` | X | ≥ |
| 6 | Average Debit Amount | `AvgDebitAmount_KThb` | K THB | ≥ |
| 7 | Cluster Share | `ClusterShare_Pct` | % | ≥ *(threshold pending)* |
| 8 | Sudden Share Jump | `ShareJump_Pct` | pp | ≥ *(threshold pending)* |

#7 Cluster Share (`%`) and #8 Sudden Share Jump (`pp`) emit values now; their **alert
thresholds are pending** the customer's numbers.

---

## Deployment

1. Deploy the Gold layer — [Production 04](../04-gold-summary-table/) (core + your chosen option).
2. Wire Activator for that option:
   - Option 1 → [option-1-function.md](option-1-function.md)
   - Option 3 → [option-3-snapshot-table.md](option-3-snapshot-table.md)
3. Add the 30-minute digest rule.
