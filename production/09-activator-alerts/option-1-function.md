# Activator Option 1 — source = `Gold_EarlyWarning()` function

Activator runs the function query on a schedule (the same "Add alert from a KQL Queryset"
pattern as the legacy alert in [README_old.md](README_old.md)). No stored table. Parent:
[EWI Activator README](README.md).

## Prerequisite

Gold **Option 1** deployed — base MV + function:
[../04-gold-summary-table/option-1-function.md](../04-gold-summary-table/option-1-function.md).

## Wire it up

1. Open a **KQL Queryset** on the `DepositMovement` database.
2. Paste the source query (Activator tracks state per `Object_Id = Scope`):
   ```kql
   Gold_EarlyWarning()
   // all 3 scopes; filter/threshold columns arrive with each row
   ```
3. Toolbar → **Add alert** (Set alert) → save into an Activator item, e.g. `act-ewi-alerts`.
4. Open the Activator item and build rules:
   - **Filter**: `WindowCode`, `DayType`, `EventFlag` as needed.
   - **Condition**: numeric threshold on an indicator column (e.g. `NetOutflow_MB <= -5500`).
   - **Tier** with L1/L2/L3 (three conditions, or three rules with a `Changes` guard on the tier).
5. Add actions (Email / Teams) per tier.

## 30-minute digest

Add a scheduled rule that formats `NetOutflow_Bn` (periodic) and `AccumNetOutflow_Bn`
(cumulative from 00:00) into the message:

```
Periodic net outflow of {WindowStart}-{WindowEnd} = {NetOutflow_Bn} bn,
Cumulative net outflow from 00:00 until {BucketEnd} = {AccumNetOutflow_Bn} bn
```

## Notes

- Set the Queryset / alert cadence to **30 minutes** to match the bucket grain.
- The function recomputes today's rows on each evaluation — fine for a single day.
- Indicator formulas, units, and directions: [Gold EWI README](../04-gold-summary-table/README.md).
