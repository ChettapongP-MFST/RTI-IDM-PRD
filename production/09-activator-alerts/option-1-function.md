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

## Examples

### Example 1 — Net Outflow, Total Bank (latest bucket)

Full script: [kql/10-ewi-example1-NetOutflow-TotalBank.kql](kql/10-ewi-example1-NetOutflow-TotalBank.kql).

**Source query** — the latest 30-min bucket for **Total Bank**, exposing `NetOutflow_MB`:

```kql
Gold_EarlyWarning()
| where Scope == "TOTAL_BANK"
| summarize arg_max(Bucket_Start, *) by Scope   // latest 30-min bucket
| project Scope, Date_ICT, Bucket_Label, WindowCode, DayType, NetOutflow_MB
```

**Activator rule** — item `act-deposit-ewi`, rule `rule_NetOutflow_MB_alert`; threshold
`NetOutflow_MB` directly (single editable constant):
- **Object**: `Scope` (here `TOTAL_BANK`).
- **Condition**: `NetOutflow_MB` **≤** `<value>` (e.g. `-5500` for −5500 MB; more negative = worse).
- **Tier (optional)**: add L1/L2/L3 as three rules with different values.
- **Actions**: Email / Teams with `NetOutflow_MB` / `WindowCode` / `DayType` as dynamic content.

> **Window × day-type thresholds:** a single numeric condition can't vary the value by
> `WindowCode` / `DayType`. When those matter (e.g. −3500 morning vs −3000 before-hours), use
> the **optional tiered block** in the same script — a small threshold `datatable` resolves the
> value per row and emits an `Alert_Flag` (L0–L3) that one rule watches (`Changes` +
> `Alert_Flag != "L0_NORMAL"`). Edit a cell to retune; no rule change.

### Example 2 — *(pending customer spec)*

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
