# Activator Option 3 — source = `Gold_EarlyWarning_Snapshot` table

Activator reads the persisted snapshot table (populated every 30 min). The rules are identical
to Option 1; only the **source** differs. Parent: [EWI Activator README](README.md).

## Prerequisite

Gold **Option 3** deployed — base MV + function + snapshot table + 30-min scheduled append:
[../04-gold-summary-table/option-3-snapshot-table.md](../04-gold-summary-table/option-3-snapshot-table.md).

## Wire it up

1. Open a **KQL Queryset** on the `DepositMovement` database.
2. Source query reads the **latest bucket per scope** from the stored table:
   ```kql
   let _today = startofday(now() + 7h);
   Gold_EarlyWarning_Snapshot
   | where Bucket_Start >= _today
   | summarize arg_max(Bucket_Start, *) by Scope
   ```
3. Toolbar → **Add alert** (Set alert) → save into an Activator item, e.g. `act-ewi-alerts`.
4. Build rules exactly as in Option 1 — filter `WindowCode` / `DayType` / `EventFlag`, threshold
   the indicator columns, tier L1/L2/L3, add Email / Teams actions.

## Why the table

- Activator reads a **stable stored table** instead of recomputing the function each cycle.
- The same table feeds **Power BI dashboards**, **backtesting**, and **percentile calibration**.

## 30-minute digest

Same as Option 1, reading `NetOutflow_Bn` / `AccumNetOutflow_Bn` from the table.

## Notes

- The append job — [../04-gold-summary-table/kql/15-append-Gold_EarlyWarning_Snapshot.kql](../04-gold-summary-table/kql/15-append-Gold_EarlyWarning_Snapshot.kql) — is idempotent, so Activator always sees at most one row per `(Scope, bucket)`.
- Indicator formulas, units, and directions: [Gold EWI README](../04-gold-summary-table/README.md).
