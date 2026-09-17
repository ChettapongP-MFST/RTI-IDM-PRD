# Production 03 - Silver Deposit Movement Classification

Create `DepositMovementClassified`, a row-preserving Silver table enriched with Bangkok-local business-day and operating-window classifications.

```text
Bronze DepositMovement
        |
        | update policy
        v
Silver DepositMovementClassified
        |
        v
Existing Gold summaries (unchanged)
```

## Classification contract

- Preserve every Bronze column and row; do not aggregate in Silver.
- Treat `Date` plus the start of `Time` as an Asia/Bangkok wall-clock value. No UTC conversion is applied to these source business fields.
- Require `Time` in `HH:mm-HH:mm` format.
- Apply precedence in this order: `WEEKEND`, `HOLIDAY`, `BUSINESS_DAY`.
- Set `IsBusinessDay` only when the date is neither a weekend nor a financial-institution holiday.
- Match operating windows for business days, weekends, and holidays with `[StartTime, EndTime)`: include the start and exclude the end.
- Flag calendar events per row: `IsMonthEnd` (last calendar day), `IsPayroll` (the 25th and month-end, each shifted to the previous business day when it lands on a weekend or holiday), and `IsLongWeekend` (within a run of three or more consecutive non-business days); summarise them in `EventFlag` (`NORMAL` when none apply).
- Surface malformed times and zero/multiple matches through `ClassificationStatus`; never silently discard them.

The existing Bronze table and Gold materialized view are not modified by this module.

## Prerequisites

Complete [Production 01](../01-eventhouse-kql-tables/) and verify:

- `DepositMovement` exists with its 15-column production schema.
- `ThailandFinancialInstitutionHoliday` is populated for the current business year.
- `OperatingWindowsTimes` has unique, contiguous half-open windows covering `00:00:00` through `1.00:00:00`.

Run the Production 01 reference verification scripts before enabling the Silver policy:

- [Holiday verification](../01-eventhouse-kql-tables/kql/05-verify-ThailandFinancialInstitutionHoliday.kql)
- [Operating-window verification](../01-eventhouse-kql-tables/kql/07-verify-OperatingWindowsTimes.kql)

## Deployment order

Run these scripts in the `DepositMovement` KQL database inside `eh-rti-deposit`:

1. [Create the Silver table](kql/01-create-DepositMovementClassified.kql).
2. [Create the transformation function](kql/02-create-Transform_DepositMovementClassified.kql).
3. Preview the function and confirm its row count equals Bronze.
4. [Enable the transactional update policy](kql/03-enable-update-policy.kql).
5. If Bronze already contained rows, review and run the commented one-time command in [the backfill script](kql/04-backfill-existing-bronze.kql).
6. Run [all Silver verification checks](kql/05-verify-DepositMovementClassified.kql).

For an existing deployment, script 01 must run before script 02 so the update-policy output remains schema-compatible. Adding the column does not populate historical Silver extents; follow the controlled rebuild procedure under **Reference-data or schema changes**.

The update policy uses `IsTransactional=true`: if classification fails, the corresponding Bronze ingestion fails instead of leaving Bronze and Silver inconsistent. `PropagateIngestionProperties=true` retains supported source extent properties on Silver.

The function filters the holiday reference to the current calendar year, converts it to a scalar date-keyed property bag, and applies operating windows per row. It does not use `join` or `lookup`, so Bronze streaming ingestion can remain enabled.

## How `Transform_DepositMovementClassified` works

The function reads `DepositMovement` and enriches each Bronze row without aggregating or filtering it. Processing follows these stages:

1. **Load holiday reference data.** `ThailandFinancialInstitutionHoliday` is filtered dynamically to the current calendar year, reduced to one holiday name per date, and converted with `toscalar()` into a date-keyed property bag. Each source row can then test its local date with `bag_has_key()` without using `join` or `lookup`.
2. **Load operating-window reference data.** `OperatingWindowsTimes` is ordered by `SortOrder` and converted with `toscalar()` into a dynamic list containing each window's code, name, start, end, and sort order.
3. **Construct Bangkok-local business time.** `LocalDate` is the start of the source `Date`. A regular expression extracts the first `HH:mm` value from `Time`, and that value becomes `LocalTimeOfDay`. Adding it to `LocalDate` produces `LocalDateTime`. These are Asia/Bangkok wall-clock values; the function does not perform a UTC conversion.
4. **Classify the calendar date.** Saturday and Sunday set `IsWeekend`. A matching date in the holiday property bag sets `IsFinancialInstitutionHoliday` and supplies `HolidayName`. `IsBusinessDay` is true only when both flags are false.
5. **Apply day-classification precedence.** `DayClassification` checks weekend first, then holiday, and otherwise returns business day. Therefore, a date present in the holiday reference that also falls on a weekend is classified as `WEEKEND`.
6. **Evaluate operating windows per row.** `mv-apply` evaluates every reference window inside the current source row, regardless of day classification. A window matches when its parsed start time is valid and the time is within the half-open interval `[StartTime, EndTime)`. A boundary time therefore belongs to the window that starts at that time, not the one that ends there.
7. **Return window details only for one match.** `WindowMatchCount` records how many windows matched. The code, name, boundaries, and sort order are populated only when that count is exactly one.
8. **Assign a processing status.** Status precedence is `INVALID_TIME_FORMAT`, `NO_WINDOW_MATCH`, `MULTIPLE_WINDOW_MATCHES`, then `CLASSIFIED`. The same window validation applies to business days, weekends, and holidays while preserving every source row for investigation.
9. **Derive calendar event flags.** A padded calendar of the execution year is built once from date arithmetic and the holiday reference. `IsMonthEnd` is the last calendar day of the month. `IsPayroll` covers the 25th and month-end, each shifted to the previous business day when it lands on a weekend or holiday. `IsLongWeekend` is true for every date inside a run of three or more consecutive non-business days. `EventFlag` joins the active events (`MONTH_END`, `PAYROLL`, `LONG_WEEKEND`) with a comma, or reads `NORMAL` when none apply. No additional reference table is required.
10. **Project the Silver contract.** The final `project` emits the 15 Bronze columns followed by the 19 classification columns in the exact order and types required by `DepositMovementClassified`. This exact schema match is required by the update policy.

The update policy invokes `Transform_DepositMovementClassified()` for newly ingested Bronze data. Because the policy is transactional, a transformation failure also fails the corresponding Bronze ingestion rather than allowing Bronze and Silver to diverge. Updating the function or its reference tables does not reprocess existing extents; historical rows require the controlled backfill or rebuild described under **Reference-data or schema changes**.

## Silver schema

The first 15 columns are unchanged from Bronze. Silver appends:

| Column | Type | Meaning |
| --- | --- | --- |
| `LocalDate` | `datetime` | Local business date at midnight |
| `LocalDateTime` | `datetime` | Local date plus interval start |
| `LocalTimeOfDay` | `timespan` | Parsed interval start |
| `IsWeekend` | `bool` | Saturday or Sunday |
| `IsFinancialInstitutionHoliday` | `bool` | Date exists in the holiday reference |
| `IsBusinessDay` | `bool` | Neither a weekend nor a financial-institution holiday |
| `DayClassification` | `string` | `WEEKEND`, `HOLIDAY`, or `BUSINESS_DAY` |
| `HolidayName` | `string` | Holiday name(s), empty when not a holiday |
| `OperatingWindowCode` | `string` | Matched window code for any day classification |
| `OperatingWindowName` | `string` | Matched window display name |
| `OperatingWindowStartTime` | `timespan` | Inclusive lower boundary |
| `OperatingWindowEndTime` | `timespan` | Exclusive upper boundary |
| `OperatingWindowSortOrder` | `int` | Display order from the reference table |
| `WindowMatchCount` | `long` | Number of matching reference windows |
| `ClassificationStatus` | `string` | `CLASSIFIED` or an actionable exception |
| `IsMonthEnd` | `bool` | Local date is the last calendar day of the month |
| `IsPayroll` | `bool` | Payday — the 25th or month-end, shifted to the previous business day off weekends/holidays |
| `IsLongWeekend` | `bool` | Date lies within a run of three or more consecutive non-business days |
| `EventFlag` | `string` | Comma-joined active events (`MONTH_END`, `PAYROLL`, `LONG_WEEKEND`), or `NORMAL` |

## Operations

### Backfill safety

The backfill is append-only. Run it once and only when `DepositMovementClassified` is empty. Keep the update policy enabled during backfill so newly arriving Bronze rows are not missed. Reconcile by the four pipeline load identity columns after completion.

### Reference-data or schema changes

Update policies process new source extents; changing a holiday or window reference does not reclassify historical Silver rows automatically. Similarly, `.create-merge` adds `IsBusinessDay` to an existing table but leaves the field unpopulated on historical rows.

For a historical correction or this schema upgrade, pause Bronze ingestion, disable the update policy, clear Silver, run scripts 01 and 02, re-enable the policy with script 03, and run the one-time backfill in script 04. Then run every verification check before resuming ingestion. Schedule this as a controlled maintenance operation because clearing Silver is destructive.

### Monitoring

Alert on either condition:

```kql
DepositMovementClassified
| where ClassificationStatus != "CLASSIFIED"
```

```kql
DepositMovementClassified
| summarize SilverRows = count() by pipeline_runid
| join kind=fullouter (
    DepositMovement
    | summarize BronzeRows = count() by pipeline_runid
) on pipeline_runid
| where coalesce(SilverRows, 0) != coalesce(BronzeRows, 0)
```

## Exit criteria

- The table is in the `Silver` folder and the function is in the `Silver` function folder.
- The update policy is enabled, transactional, and sourced from `DepositMovement`.
- Transformation preview count equals Bronze count.
- All rows have `ClassificationStatus == "CLASSIFIED"`.
- `IsBusinessDay` is populated and agrees with `DayClassification == "BUSINESS_DAY"`.
- Every row with a valid `Time` has exactly one operating-window match, including business days, weekends, and holidays.
- Weekend dates win over holiday dates.
- Event flags are consistent: `EventFlag` reads `NORMAL` only when no individual flag is set, and each set flag appears as a token in `EventFlag` (verification checks 13–14 return no rows).
- Post-backfill counts reconcile by pipeline load identity.
