# Option 1 — Function (`Gold_EarlyWarning()` + reference table)

The simplest architecture: **no stored final table**. Data Activator runs the
`Gold_EarlyWarning()` function on a schedule; it recomputes today's rows fresh each time. The
function is **self-contained** — it reads Silver directly and joins the `EWI_AlertThreshold`
reference table to assign `Alert_Level`. Parent: [Gold EWI README](README.md).

## Flow

```
Silver: DepositMovementClassified → Gold_EarlyWarning()  ◄── EWI_AlertThreshold
      → KQL Query → Data Activator (watches Alert_Level)
```

No materialized view — window functions (cumulative / velocity / jump) run inside the function.

## Objects

| Object | Script |
| --- | --- |
| `EWI_AlertThreshold` (reference table) | [kql/16-create-EWI_AlertThreshold.kql](kql/16-create-EWI_AlertThreshold.kql) · [kql/17-load-EWI_AlertThreshold.kql](kql/17-load-EWI_AlertThreshold.kql) |
| `Gold_EarlyWarning()` (function) | [kql/11-create-fn_Gold_EarlyWarning.kql](kql/11-create-fn_Gold_EarlyWarning.kql) |
| Verification | [kql/12-verify-EarlyWarning.kql](kql/12-verify-EarlyWarning.kql) |

No persisted table, no scheduler.

## Deployment

1. Run [kql/16](kql/16-create-EWI_AlertThreshold.kql) + [kql/17](kql/17-load-EWI_AlertThreshold.kql) — create + load the 288-row threshold table.
2. Run [kql/11](kql/11-create-fn_Gold_EarlyWarning.kql) — the self-contained function.
3. Run [kql/12](kql/12-verify-EarlyWarning.kql) — verify.
4. Wire Activator to the **function query** — see [../09-activator-alerts/option-1-function.md](../09-activator-alerts/option-1-function.md).

## Pros / cons

- ✅ Fewest objects; nothing extra to run; always fresh.
- ✅ Thresholds live in `EWI_AlertThreshold` (versioned in the repo); Activator just watches `Alert_Level`.
- ❌ **No persisted history** → no Power BI time-series, backtesting, or percentile calibration
  unless you add Option 3.
- ⚠️ The function re-aggregates today's Silver on every Activator evaluation (cheap for one day,
  but repeated).

## When to choose

Alerting only, minimal footprint, no dashboard or history requirement.
