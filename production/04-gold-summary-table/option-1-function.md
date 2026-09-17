# Option 1 — Function (base MV + `Gold_EarlyWarning()`)

The simplest architecture: **no stored final table**. Data Activator (and Power BI, if used)
run the `Gold_EarlyWarning()` function on a schedule; it recomputes today's rows fresh each
time. Parent: [Gold EWI README](README.md).

## Flow

```
Silver → mv_EarlyWarning_Base → Gold_EarlyWarning()  ──►  Data Activator (runs the function)
```

## Objects

| Object | Script |
| --- | --- |
| `mv_EarlyWarning_Base` (base MV) | [kql/10-create-mv_EarlyWarning_Base.kql](kql/10-create-mv_EarlyWarning_Base.kql) |
| `Gold_EarlyWarning()` (function) | [kql/11-create-fn_Gold_EarlyWarning.kql](kql/11-create-fn_Gold_EarlyWarning.kql) |
| Verification | [kql/12-verify-EarlyWarning.kql](kql/12-verify-EarlyWarning.kql) · [kql/13-backfill-verify-mv_EarlyWarning_Base.kql](kql/13-backfill-verify-mv_EarlyWarning_Base.kql) |

No snapshot table, no scheduler.

## Deployment

1. Run [kql/10](kql/10-create-mv_EarlyWarning_Base.kql) — base MV (auto-backfills from Silver via `backfill=true`).
2. Run [kql/11](kql/11-create-fn_Gold_EarlyWarning.kql) — the function.
3. Run [kql/12](kql/12-verify-EarlyWarning.kql) — verify.
4. Wire Activator to the **function query** — see [../09-activator-alerts/option-1-function.md](../09-activator-alerts/option-1-function.md).

## Pros / cons

- ✅ Fewest objects; nothing extra to run; always fresh.
- ✅ Thresholds and filters live entirely in Activator.
- ❌ **No persisted history** → no Power BI time-series, backtesting, or percentile calibration
  unless you add Option 3.
- ⚠️ The function recomputes today's window math on every Activator evaluation (cheap for one
  day, but repeated).

## When to choose

Alerting only, minimal footprint, no dashboard or history requirement.
