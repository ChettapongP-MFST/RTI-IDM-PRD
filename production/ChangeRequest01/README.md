# Change Request 01 - 24/7 Ingestion and 02:30 Correction

Use these documents to update the existing deposit-ingestion solution through the **Microsoft Fabric UI**.

## Follow these two guides in order

| Order | Guide | What to do |
| --- | --- | --- |
| 1 | [05 - Create the refresh child](05-data-pipeline/README.md) | Prepare the Warehouse tracking tables and serving objects, then create `pl_refresh_DepositMovement_0230`. Follow the numbered activity steps, including source checks, backups, reload, and Gold-summary verification. |
| 2 | [07 - Modify the existing scheduler](07-interval-scheduler/README.md) | Update `pl_ingest_DepositMovement_schedule` to run every 30 minutes, all day. Add the shared lock and correction/normal routing, validate the complete flow, then activate after approval. |

**Keep scheduling disabled during setup and testing. Do not run the refresh child directly:** it requires the scheduler's lock and owning RunId.

No separate controller pipeline, CLI script, or pipeline JSON import is required.

## What the change does

| Requirement | Behavior |
| --- | --- |
| Normal ingestion | Every **30 minutes, 24/7**, using Bangkok / ICT time |
| Daily correction | The first eligible batch at or after **02:30 ICT**, if today's correction has not completed |
| Correction scope | The six agreed files below, selected by their filename business intervals |
| After correction | Resume normal discovery on the next eligible batch only after correction succeeds |
| Failure | Retain ownership and block continuation until recovery is completed |

For correction date **2026-11-20**, the six files are:

```text
INTRADAY_SUMMARY_20261119_2300_2330.CSV
INTRADAY_SUMMARY_20261119_2330_2400.CSV
INTRADAY_SUMMARY_20261120_0000_0030.CSV
INTRADAY_SUMMARY_20261120_0030_0100.CSV
INTRADAY_SUMMARY_20261120_0100_0130.CSV
INTRADAY_SUMMARY_20261120_0130_0200.CSV
```

The late-evening files use the previous calendar date; after-midnight files use the correction date. `2400` means midnight at the end of the previous date. The correction does **not** include `2230_2300` or `0200_0230`.

**03:00 is not an unconditional restart time.** If correction is still running or has failed, normal ingestion must wait.

## Existing components and required changes

| Component | Action |
| --- | --- |
| `pl_ingest_DepositMovement_schedule` | Modify the existing scheduler as described in guide 07 |
| `pl_refresh_DepositMovement_0230` | Create the new correction child as described in guide 05 |
| `pl_ingest_DepositMovement_trigger_pipeline` | Reuse the existing normal-discovery pipeline unchanged |
| `pl_ingest_DepositMovement` | Reuse the existing single-file ingestion pipeline unchanged |
| `dbo.ProcessedFiles` | Keep its schema; preserve old audit entries and record replacement successes |
| Bronze, Silver, and the Gold summary | Keep the source schemas; replace only selected source rows and rebuild/reconcile the existing summary |

The required supporting SQL and KQL are included in guide 05. This workflow does not require an EWI table, EWI function, or EWI base materialized view.

## Flow diagram

[Open the 02:30 setup and execution diagram](05-data-pipeline/END-TO-END-0230.svg).

## Testing and activation

Guide 07 contains the acceptance checks, recorded live-test results, and recovery instructions. Review its coverage limits before sharing the instructions or enabling scheduled operation.

Customer approval must cover source-file finalization, competing writers, consumer maintenance, recovery, and the tested data volume. Successful controlled tests do not automatically authorize production activation.

## Retained historical report

[TEST-RESULTS.md](TEST-RESULTS.md) records the **earlier 03:30 design in RTI-IDM-PRD**. It is retained for history, not as installation instructions or acceptance evidence for this revised 02:30 workflow in RTI-IDM-PRD2.

The earlier design's supporting folders and alternate guides have been removed. Follow only guides **05, then 07** above.
