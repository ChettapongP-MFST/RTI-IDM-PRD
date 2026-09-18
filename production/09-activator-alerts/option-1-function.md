# Activator — source = `Gold_EarlyWarning()` function

Activator runs the function query **every 30 minutes** (the same "Add alert from a KQL Queryset"
pattern as the legacy alert in [README_old.md](README_old.md)). The function reads the
auto-refreshing base MV `mv_DepositMovementEarlyWarning`, so there is no stored table and nothing
to schedule beyond the alert cadence. Parent: [EWI Activator README](README.md).

## Prerequisite

Gold layer deployed — reference table + base MV + function:
[../04-gold-summary-table/README.md#deployment-kql-scripts](../04-gold-summary-table/README.md).

## Wire it up

1. Open a **KQL Queryset** on the `DepositMovement` database.
2. Paste the source query (Activator tracks state per `Object_Id = Scope|IndicatorKey`):
   ```kql
   Gold_EarlyWarning()
   // long: one row per Scope x bucket x indicator, each with Value + Alert_Level
   ```
3. Toolbar → **Add alert** (Set alert) → save into an Activator item, e.g. `act-deposit-ewi`.
4. Open the Activator item and build rules:
   - **Object**: `Object_Id` (e.g. `TOTAL_BANK|NetOutflow_MB`).
   - **Condition**: `Alert_Level` is one of `L2`, `L3` (or `Alert_Rank >= 2`).
   - **Filter** (optional): a specific `IndicatorKey`, `WindowCode`, `DayType`, or `EventFlag`.
5. Add actions (Email / Teams) with `Value` / `WindowCode` / `DayType` / `Alert_Level` as content.

## Examples

### Example 1 — Net Outflow, Total Bank (latest bucket)

Full script: [kql/10-ewi-example1-NetOutflow-TotalBank.kql](kql/10-ewi-example1-NetOutflow-TotalBank.kql).

**Source query** — the latest 30-min bucket for **Total Bank**, Net Outflow, with its level:

```kql
Gold_EarlyWarning()
| where Scope == "TOTAL_BANK" and IndicatorKey == "NetOutflow_MB"
| summarize arg_max(Bucket_Start, *) by Object_Id   // latest 30-min bucket
| project Object_Id, Scope, Date_ICT, Bucket_Label, WindowCode, DayType,
          Value, L1, L2, L3, Alert_Level, Alert_Rank
```

**Activator rule** — item `act-deposit-ewi`, rule `rule_NetOutflow_MB_alert`:
- **Object**: `Object_Id` (here `TOTAL_BANK|NetOutflow_MB`).
- **Condition**: `Alert_Level` **is one of** `L2`, `L3` (or `Alert_Rank >= 2`).
- **Actions**: Email / Teams with `Value` / `WindowCode` / `DayType` / `Alert_Level` as content.

> **Window × day-type thresholds are already applied.** The level comes from `EWI_AlertThreshold`
> (per `Window × DayType`), so one rule covers every context. To retune, edit
> [../04-gold-summary-table/data/ewi-alert-threshold.csv](../04-gold-summary-table/data/ewi-alert-threshold.csv),
> re-run the melt script, and reload the table — no rule change.

### Example 2 — *(pending customer spec)*

## 30-minute digest

Add a scheduled rule that formats the Net Outflow rows into the message (billions = `Value / 1000`):

```kql
Gold_EarlyWarning()
| where Scope == "TOTAL_BANK" and IndicatorKey in ("NetOutflow_MB", "AccumNetOutflow_MB")
| summarize arg_max(Bucket_Start, *) by Object_Id
| extend Bn = round(Value / 1000.0, 2)   // MB -> billions
```

```
Periodic net outflow of {WindowStart}-{WindowEnd} = {NetOutflow Bn} bn,
Cumulative net outflow from 00:00 until {BucketEnd} = {AccumNetOutflow Bn} bn
```

## Notes

- Set the Queryset / alert cadence to **30 minutes** to match the bucket grain.
- The function recomputes today's rows on each evaluation — fine for a single day.
- Indicator formulas, units, and directions: [Gold EWI README](../04-gold-summary-table/README.md).

## Appendix — Can Activator do `if / then / else`?

**No.** An Activator rule is *one condition → one action*. The **Operation** dropdown
(`On every value`, `Becomes greater than`, `Enters/Exits range`, `Changes`, …) plus any extra
conditions are **AND-combined filters** — there is no `else` branch and no multiple action paths
inside a single rule. To get tiered (L1/L2/L3) behaviour, use one of the three patterns below.

### A. One rule per tier (simple, but rules overlap)

Three rules on the same event, each with its own threshold and action:

| Rule | Condition | Action |
|------|-----------|--------|
| `rule_NetOutflow_L1_watch`    | `NetOutflow_MB` becomes ≤ **-3000** | Teams/email "Watch" |
| `rule_NetOutflow_L2_warning`  | `NetOutflow_MB` becomes ≤ **-4000** | "Warning" + more recipients |
| `rule_NetOutflow_L3_critical` | `NetOutflow_MB` becomes ≤ **-5500** | "Critical" + escalate |

A value of −6000 trips all three. Mitigate with **band** conditions (L2 = *enters range*
−4000…−5000) or resolve the tier in KQL (pattern **B**).

### B. Compute the tier in KQL with `case()` (recommended)

Move the `if/then/else` upstream into the query. The `case(...)` **is** the branch; Activator
just reacts to the resulting label:

```kql
Gold_EarlyWarning()
| where Scope == "TOTAL_BANK"
| summarize arg_max(Bucket_Start, *) by Scope
| extend Alert_Level = case(
    NetOutflow_MB <= -5500, "L3_CRITICAL",
    NetOutflow_MB <= -4000, "L2_WARNING",
    NetOutflow_MB <= -3000, "L1_WATCH",
                            "L0_NORMAL")
| project Scope, Date_ICT, Bucket_Label, WindowCode, DayType, NetOutflow_MB, Alert_Level
```

Then one rule watches `Alert_Level`: **Operation = `Changes`** (or `On every value` filtered to
`Alert_Level <> "L0_NORMAL"`). To vary the value by `WindowCode` / `DayType`, replace the fixed
constants with the threshold **`datatable`** join from the optional block in
[kql/10-ewi-example1-NetOutflow-TotalBank.kql](kql/10-ewi-example1-NetOutflow-TotalBank.kql).

### C. Multiple conditions in one rule (AND only)

Add conditions to narrow *when* the single action fires
(e.g. `NetOutflow_MB ≤ -4000` **AND** `WindowCode == "MORNING_WORKING_HOUR"`) — still no `else`.

**Guidance:** prefer **B**. Keep one Activator rule bound to `Alert_Level` (or a numeric
threshold), and let the KQL `case()` own the tiering — cleaner, versioned in the repo, and no
overlapping-rule noise. Whichever pattern you pick, keep the **Object** column (`Scope`) and the
watched column (`NetOutflow_MB` / `Alert_Level`) names stable so the rule binding survives edits.
