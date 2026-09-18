# Activator Option 3 — source = `DepositMovementEarlyWarning` table

Activator reads the persisted table (populated every 30 min). The rules are identical to
Option 1; only the **source** differs. Parent: [EWI Activator README](README.md).

## Prerequisite

Gold **Option 3** deployed — reference table + function + `DepositMovementEarlyWarning` + 30-min
scheduled append:
[../04-gold-summary-table/option-3-snapshot-table.md](../04-gold-summary-table/option-3-snapshot-table.md).

## Wire it up

1. Open a **KQL Queryset** on the `DepositMovement` database.
2. Source query reads the **latest bucket per Scope × indicator** from the stored table:
   ```kql
   let _today = startofday(now() + 7h);
   DepositMovementEarlyWarning
   | where Bucket_Start >= _today
   | summarize arg_max(Bucket_Start, *) by Object_Id   // Object_Id = Scope|IndicatorKey
   ```
3. Toolbar → **Add alert** (Set alert) → save into an Activator item, e.g. `act-deposit-ewi`.
4. Build rules: **Object** = `Object_Id`, **Condition** = `Alert_Level in ('L2','L3')`
   (or `Alert_Rank >= 2`); optionally filter a specific `IndicatorKey` / `WindowCode` / `DayType`;
   add Email / Teams actions.

## Why the table

- Activator reads a **stable stored table** instead of recomputing the function each cycle.
- The same table feeds **Power BI dashboards**, **backtesting**, and **percentile calibration**.

## 30-minute digest

Same as Option 1, reading the `NetOutflow_MB` / `AccumNetOutflow_MB` rows from the table
(billions = `Value / 1000`).

## Notes

- The append job — [../04-gold-summary-table/kql/15-append-DepositMovementEarlyWarning.kql](../04-gold-summary-table/kql/15-append-DepositMovementEarlyWarning.kql) — is idempotent, so Activator always sees at most one row per `(Object_Id, bucket)`.
- Indicator formulas, units, and directions: [Gold EWI README](../04-gold-summary-table/README.md).
