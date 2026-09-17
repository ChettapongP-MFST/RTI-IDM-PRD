# Option 3 — Snapshot table (base MV + function + scheduler)

Persists the enriched rows in a physical Gold table so **Activator and Power BI read a stored
table**, and history is retained for dashboards, backtesting, and Trigger-Amount percentile
calibration. Parent: [Gold EWI README](README.md).

## Flow

```
Silver → mv_EarlyWarning_Base → Gold_EarlyWarning()
      → [30-min scheduled .set-or-append] → Gold_EarlyWarning_Snapshot (table)
      → Data Activator  +  Power BI
```

## Why a scheduler (not a materialized view)

A materialized view **cannot** compute the cross-row indicators — cumulative (#3), velocity
(#5), and sudden jump (#8) need window functions (`row_cumsum`, `prev`). So the enriched table
is filled by a **scheduled job** that runs the function and appends new buckets — the same
pattern as [Production 07 — Interval Scheduler](../07-interval-scheduler/).

## Objects

| Object | Script |
| --- | --- |
| `mv_EarlyWarning_Base` (base MV) | [kql/10-create-mv_EarlyWarning_Base.kql](kql/10-create-mv_EarlyWarning_Base.kql) |
| `Gold_EarlyWarning()` (function) | [kql/11-create-fn_Gold_EarlyWarning.kql](kql/11-create-fn_Gold_EarlyWarning.kql) |
| `Gold_EarlyWarning_Snapshot` (table) | [kql/14-create-Gold_EarlyWarning_Snapshot.kql](kql/14-create-Gold_EarlyWarning_Snapshot.kql) |
| Idempotent 30-min append | [kql/15-append-Gold_EarlyWarning_Snapshot.kql](kql/15-append-Gold_EarlyWarning_Snapshot.kql) |
| Verification | [kql/12-verify-EarlyWarning.kql](kql/12-verify-EarlyWarning.kql) · [kql/13-backfill-verify-mv_EarlyWarning_Base.kql](kql/13-backfill-verify-mv_EarlyWarning_Base.kql) |

## Deployment

1. Run [kql/10](kql/10-create-mv_EarlyWarning_Base.kql), [kql/11](kql/11-create-fn_Gold_EarlyWarning.kql) — base MV + function.
2. Run [kql/14](kql/14-create-Gold_EarlyWarning_Snapshot.kql) — create the snapshot table.
3. Schedule [kql/15](kql/15-append-Gold_EarlyWarning_Snapshot.kql) **every 30 minutes** via a
   Fabric Data Pipeline + Notebook (module-07 pattern). The append is **idempotent** — re-running
   a cycle adds nothing; a late bucket is picked up on the next run.
4. (Optional) Backfill a past date using the commented block in [kql/15](kql/15-append-Gold_EarlyWarning_Snapshot.kql).
5. Wire Activator to the **snapshot table** — see [../09-activator-alerts/option-3-snapshot-table.md](../09-activator-alerts/option-3-snapshot-table.md).

## Idempotency

The append builds a `Scope|Bucket_Start` set for today and inserts only rows not already
present, so overlapping or repeated runs never duplicate a bucket.

## Retention

The snapshot keeps **730 days** (softdelete, recoverable) and **90 days hot** cache — see
[kql/14](kql/14-create-Gold_EarlyWarning_Snapshot.kql).

## Pros / cons

- ✅ Persisted history → Power BI dashboards (like the customer mockups), backtesting, and
  percentile calibration all read the table.
- ✅ Activator reads a stable table instead of recomputing the function.
- ❌ Extra moving parts: a 30-min Fabric pipeline + notebook, plus the idempotency guard.

## When to choose

You need a **dashboard**, **history**, or **percentile calibration** — not just alerts.
