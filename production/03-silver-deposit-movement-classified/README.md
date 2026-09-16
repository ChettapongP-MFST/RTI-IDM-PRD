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
- Match business-day windows with `[StartTime, EndTime)`: include the start and exclude the end.
- Keep non-business-day window fields empty. They are classified by day, not by operating window.
- Surface malformed times and zero/multiple matches through `ClassificationStatus`; never silently discard them.

The existing Bronze table and Gold materialized view are not modified by this module.

## Prerequisites

Complete [Production 01](../01-eventhouse-kql-tables/) and verify:

- `DepositMovement` exists with its 15-column production schema.
- `ThailandFinancialInstitutionHoliday` is populated for every required business year.
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

The function converts the holiday reference to a scalar date-keyed property bag and applies operating windows per row. It does not use `join` or `lookup`, so Bronze streaming ingestion can remain enabled.

## Silver schema

The first 15 columns are unchanged from Bronze. Silver appends:

| Column | Type | Meaning |
|---|---|---|
| `LocalDate` | `datetime` | Local business date at midnight |
| `LocalDateTime` | `datetime` | Local date plus interval start |
| `LocalTimeOfDay` | `timespan` | Parsed interval start |
| `IsWeekend` | `bool` | Saturday or Sunday |
| `IsFinancialInstitutionHoliday` | `bool` | Date exists in the holiday reference |
| `IsBusinessDay` | `bool` | Neither a weekend nor a financial-institution holiday |
| `DayClassification` | `string` | `WEEKEND`, `HOLIDAY`, or `BUSINESS_DAY` |
| `HolidayName` | `string` | Holiday name(s), empty when not a holiday |
| `OperatingWindowCode` | `string` | Matched window code on a business day |
| `OperatingWindowName` | `string` | Matched window display name |
| `OperatingWindowStartTime` | `timespan` | Inclusive lower boundary |
| `OperatingWindowEndTime` | `timespan` | Exclusive upper boundary |
| `OperatingWindowSortOrder` | `int` | Display order from the reference table |
| `WindowMatchCount` | `long` | Number of matching reference windows |
| `ClassificationStatus` | `string` | `CLASSIFIED` or an actionable exception |

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
- Every business-day row has exactly one operating-window match.
- Weekend dates win over holiday dates.
- Post-backfill counts reconcile by pipeline load identity.
