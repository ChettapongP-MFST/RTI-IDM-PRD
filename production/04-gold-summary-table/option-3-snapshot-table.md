# Option 3 — Persisted table (`DepositMovementEarlyWarning`)

Persists the enriched rows in a physical Gold table so **Activator and Power BI read a stored
table**, and history is retained for dashboards, backtesting, and Trigger-Amount percentile
calibration. Parent: [Gold EWI README](README.md).

## Flow

```
Silver: DepositMovementClassified → Gold_EarlyWarning()  ◄── EWI_AlertThreshold
      → [30-min scheduled .set-or-append] → DepositMovementEarlyWarning (table)
      → Data Activator  +  Power BI
```

## Why a scheduler (not a materialized view)

A materialized view **cannot** compute the cross-row indicators — cumulative (#3), velocity
(#5), and sudden jump (#8) need window functions (`row_cumsum`, `prev`). So `Gold_EarlyWarning()`
is a **function**, and the enriched table is filled by a **scheduled job** that runs it and
appends new rows — the same pattern as [Production 07 — Interval Scheduler](../07-interval-scheduler/).

## Objects

| Object | Script |
| --- | --- |
| `EWI_AlertThreshold` (reference table) | [kql/16-create-EWI_AlertThreshold.kql](kql/16-create-EWI_AlertThreshold.kql) · [kql/17-load-EWI_AlertThreshold.kql](kql/17-load-EWI_AlertThreshold.kql) |
| `Gold_EarlyWarning()` (function) | [kql/11-create-fn_Gold_EarlyWarning.kql](kql/11-create-fn_Gold_EarlyWarning.kql) |
| `DepositMovementEarlyWarning` (table) | [kql/14-create-DepositMovementEarlyWarning.kql](kql/14-create-DepositMovementEarlyWarning.kql) |
| Idempotent 30-min append | [kql/15-append-DepositMovementEarlyWarning.kql](kql/15-append-DepositMovementEarlyWarning.kql) |
| Verification | [kql/12-verify-EarlyWarning.kql](kql/12-verify-EarlyWarning.kql) |

## Deployment

1. Run [kql/16](kql/16-create-EWI_AlertThreshold.kql) + [kql/17](kql/17-load-EWI_AlertThreshold.kql) — threshold table; then [kql/11](kql/11-create-fn_Gold_EarlyWarning.kql) — the function.
2. Run [kql/14](kql/14-create-DepositMovementEarlyWarning.kql) — create the persisted table.
3. Schedule [kql/15](kql/15-append-DepositMovementEarlyWarning.kql) **every 30 minutes** via a
   Fabric Data Pipeline + Notebook (module-07 pattern). The append is **idempotent** — re-running
   a cycle adds nothing; a late bucket is picked up on the next run.
4. (Optional) Backfill a past date using the commented block in [kql/15](kql/15-append-DepositMovementEarlyWarning.kql).
5. Wire Activator to the **table** — see [../09-activator-alerts/option-3-snapshot-table.md](../09-activator-alerts/option-3-snapshot-table.md).

## Idempotency

The append builds an `Object_Id|Bucket_Start` set for today (grain = Scope × bucket × indicator)
and inserts only rows not already present, so overlapping or repeated runs never duplicate a row.

## Retention

The table keeps **730 days** (softdelete, recoverable) and **90 days hot** cache — see
[kql/14](kql/14-create-DepositMovementEarlyWarning.kql).

## Pros / cons

- ✅ Persisted history → Power BI dashboards (like the customer mockups), backtesting, and
  percentile calibration all read the table.
- ✅ Activator reads a stable table instead of recomputing the function.
- ❌ Extra moving parts: a 30-min Fabric pipeline + notebook, plus the idempotency guard.

## When to choose

You need a **dashboard**, **history**, or **percentile calibration** — not just alerts.
