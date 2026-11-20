# CR01 - Latest Live Validation Results

**Retest date:** 2026-11-20. **Target:** `RTI-IDM-PRD2`. **Latest configuration/data check:** 11:33:10 ICT.

This report replaces the earlier blocked status with the verified **lock recovery and supervised scheduler run** for the current 02:30, six-file workflow. It also retains the earlier same-day source-access evidence. The earlier full-day ingestion and destructive correction acceptance runs are identified separately; they were not rerun during this recovery.

For implementation, follow [05 - Create the refresh child](05-data-pipeline/README.md), then [07 - Modify the existing scheduler](07-interval-scheduler/README.md).

## Executive summary

| Check | Latest result |
| --- | --- |
| Release the verified stale lock - Step 6 | **PASS** - only the failed owner's lock table was dropped |
| Confirm unlocked - Step 7 | **PASS** - lock table absent before the supervised run |
| Supervised scheduler - Step 8 | **PASS** - Completed; 7 successful scheduler activities and 6 successful discovery activities |
| Real Fabric source discovery | **PASS** - 887 items listed, zero new files, zero ingestion invocations |
| Source CSV content sample | **PASS at 09:20 ICT** - nonempty 11-column row; not reread during this recovery |
| Warehouse recovery/audit checks | **PASS** - zero incomplete refreshes; audit/control totals unchanged before and after the run |
| November 19-20 KQL counts | **PASS** - unchanged at 1,180 Bronze rows, 1,180 Silver rows, 40 Gold groups |
| Final publication/lock/serving state | **PASS** - readiness true under the new run, lock absent, Gold healthy/enabled, cache 90 days |
| Unattended scheduled operation | **NOT RETESTED** - the new run was Manual; scheduling remains disabled |

**Overall: PASS for the requested Steps 6-8.** The stale-lock blocker is resolved, and the real scheduler successfully reacquired and released a new lock. The recovery, supervised-run, discovery-verification, and post-run verification commands exited **0**.

The `AuthorizationFailure` / `Forbidden` source-access blocker remains cleared for the tested connection/path. No production pipeline definitions, saved approval defaults, or schedule settings were changed by this recovery. Normal discovery was a **no-op**: no Copy or six-file correction occurred. The scheduler appended a readiness record and removed its own lock as intended.

This is not unattended-service or production activation sign-off. The schedule was disabled by the user before recovery and was left disabled.

## 1. Latest lock recovery and supervised scheduler test

### Preconditions - verified before release

- Current schedule `c0b76c56-b622-4e20-8f47-d100f70033e0`: **disabled**.
- All four production pipeline job lists checked: **zero active writers**.
- Lock Owner exactly `c94e2556-627e-4f20-9a68-99555d8f3c5d`; the owning scheduler job was **Failed**.
- Original discovery child `f0cb8fb3-96dd-497e-b397-c1e47691d0d4` failed at source Get Metadata, including its retries. No ingestion invocation or Copy activity ran.
- Fresh read-only Warehouse Lookup: **IncompleteRefreshes=0**, **CompletedToday=1**, **ManifestFiles=6**, **ArchivedAuditRows=6**.
- Serving readiness true; Gold healthy/enabled.

The Warehouse preflight ran in the test-only, unscheduled `pl_CR01_LockRecoveryPreflight_20261120T042655Z`, item `a4448e9d-bbed-4f27-9e8c-e31bfa61ab55`. Before-run job `9a0181f4-cfd6-4dbe-97f1-024439e9910b` and after-run job `c870614e-7d2d-4c68-b4c6-e5436fcc668a` both completed with a successful read-only Lookup. This helper is not a production controller.

### Steps executed and outcomes

| Step | Action and captured evidence | Result |
| --- | --- | --- |
| 6 | Rechecked disabled scheduling, idle writers, and exact failed Owner; executed `.drop table Refresh0230_BatchLock` at **11:28:53 ICT** | PASS |
| 7 | Queried `.show tables` for the exact lock name; **zero rows** at **11:29:00 ICT** | PASS |
| 8 | Started the existing scheduler once with both manual approval parameters **false**; today's completed refresh selected normal discovery | PASS |
| Post-run | Independently checked lock absence, readiness Owner, idle writer jobs, unchanged audit/control totals and test-date KQL counts | PASS |

### Supervised scheduler run

| Field | Value |
| --- | --- |
| Pipeline | `pl_ingest_DepositMovement_schedule` |
| Pipeline ID | `4034e996-d163-4682-a7d0-d3375769a381` |
| Run ID | `c0758ff6-d82e-4632-af63-c15440af16d0` |
| Invocation / status | **Manual / Completed** |
| UTC start / end | `2026-11-20 04:29:43` / `04:31:31` |
| ICT start / end | `2026-11-20 11:29:43` / `11:31:31` |
| Observed duration | About **1 minute 49 seconds**, not an SLA |
| Normal-discovery child Run ID | `1cd99fb5-4b88-45a9-a74c-b5848f50b76b` |

[Open the scheduler in Fabric](https://app.fabric.microsoft.com/groups/e450f2e3-d905-4264-bbdc-48f662460504/pipelines/4034e996-d163-4682-a7d0-d3375769a381?experience=fabric-developer). Select the Run ID above in its run history, then open the child-run link and each activity's Input/Output/Error.

| Scheduler activity | Actual outcome |
| --- | --- |
| `Freeze Run ICT` | Succeeded; current ICT date November 20 |
| `Acquire Batch Lock` | Succeeded; one lock row created for the new run |
| `Lookup Refresh State` | Succeeded; `CompletedToday=1`; incomplete-refresh guard did not reject |
| `Is Refresh Due` | Succeeded; normal branch selected |
| `Invoke Normal Discovery` | Succeeded; child Completed |
| `Publish Verified Results` | Succeeded; readiness appended for the new run |
| `Release Owned Batch Lock` | Succeeded; independent metadata query confirmed absence |

No `Invoke 0230 Refresh` activity ran. Today's completed refresh checkpoint was preserved.

### Discovery and data movement

All six child activities succeeded: `Set vToday`, `Set vYesterday`, `Get Metadata - List Files`, `Lookup Processed Files`, `Filter New Files`, and `ForEach New Files`.

```text
Source folder items listed: 887
Filtered/new files:         0
Ingestion invocations:      0
New Copy operations:       0
New refresh invocations:   0
```

All eligible filenames were already processed. This proves the normal rerun skipped them without duplicate ingestion; it does not exercise a new-file Copy.

### Final state and remaining validation

At **11:33:10 ICT**: lock absent, readiness true under Owner `c0758ff6-d82e-4632-af63-c15440af16d0`, Gold enabled/healthy, source cache 90 days, zero active production writer jobs, and scheduler definition unchanged.

Scheduling remains **disabled**. The earlier failed jobs remain Failed historically; their retained-lock incident is now recovered.

For unattended validation, enable the schedule only under activation approval and observe a new **Scheduled** run through successful publication and lock release. Review saved maintenance/source-finalization approvals before a future 02:30 correction; this normal-only test did not change or approve them. Also review the configured schedule end `2026-11-21T23:00:00` for the intended operating period.

## 2. Earlier same-day source-access preflight

| Field | Value |
| --- | --- |
| Workspace ID | `e450f2e3-d905-4264-bbdc-48f662460504` |
| Test pipeline | `pl_CR01_ReadOnlyAccessRetest_20261120T022041Z` |
| Test pipeline ID | `31dfdb72-4b9c-46bc-8986-b2fa74175f87` |
| Run ID | `5b84c3e2-93a8-4b9c-b0f4-c30d188c99f1` |
| Job status | **Completed** |
| UTC start / end | `2026-11-20 02:20:54` / `02:21:30` |
| ICT start / end | `2026-11-20 09:20:54` / `09:21:30` |
| Activities | **4 Succeeded, 0 Failed** |

[Open the read-only test pipeline in Fabric](https://app.fabric.microsoft.com/groups/e450f2e3-d905-4264-bbdc-48f662460504/pipelines/31dfdb72-4b9c-46bc-8986-b2fa74175f87?experience=fabric-developer). Open its run history and select the Run ID above to inspect each activity's Input, Output, and Error.

This is a test-only pipeline with **no schedule**, not a new production controller. Its saved definition contains only Get Metadata, Lookup, and read-only KQL activities. It reuses the current production connections without invoking their production pipelines.

### Activity evidence

| Activity | Type | Result | Captured output |
| --- | --- | --- | --- |
| `List Source Files Read Only` | Get Metadata | Succeeded | `ListedItems=887`, `Files=887`, November 19 files `48`, November 20 files `48` |
| `Read Source CSV Without Ingestion` | Lookup | Succeeded | `NonemptyFirstRow=true`, `ColumnCount=11` |
| `Read Audit Baseline` | Lookup | Succeeded | `SuccessfulFiles=315`, `LoggedRows=3004` across the complete audit table |
| `Read KQL Inventory` | KQL | Succeeded | `count=13` |

All four activity error codes/messages were empty. The CSV read used:

- Account: `mockadlsidimdprd001`.
- Container: `inflowoutflow`; directory: `inbound/statement`.
- Existing Fabric connection: `52065620-a202-4b92-8215-c348e25a8c2c`.
- File: `INTRADAY_SUMMARY_20261120_0000_0030.CSV`.
- Existing parsing: pipe delimiter, no header, 11 business columns.

The actual source row is omitted from this report. The successful content read is stronger evidence than listing alone, but it does not test a new Copy into Eventhouse.

## 3. Production blockers - latest status

### 3.1 Source storage access - PASS

The earlier `AuthorizationFailure` / `Forbidden` result is replaced by the successful 09:20 Fabric listing/CSV read and the **11:30 normal-discovery listing**. Both were tested from Fabric's runtime, not inferred from a local Azure CLI storage listing.

No firewall, credentials, RBAC, or network-access settings were changed by this retest. The successful result applies to the current PRD2 connection/path at the recorded time; it is not a guarantee for every identity or future network configuration.

The old PRD preflight item `e5fc7d7e-bfbf-4a66-9094-13918e88dde3` no longer exists. The new read-only test therefore uses the current PRD2 pipeline connection settings instead of restoring that deleted item.

### 3.2 Retained batch lock - RESOLVED

At **09:23:39 ICT**, the scheduler still had the failed run's lock:

```text
Table: Refresh0230_BatchLock
Owner: c94e2556-627e-4f20-9a68-99555d8f3c5d
```

| Observed scheduler run | Time, ICT | Actual result |
| --- | --- | --- |
| `c94e2556-627e-4f20-9a68-99555d8f3c5d` | 08:49:02-08:51:31 | Failed in normal discovery because source Get Metadata returned Forbidden; its lock was retained |
| `bc74f284-4fe3-40ed-90d1-92f4631eae28` | 09:00:18-09:00:54 | Failed at `Acquire Batch Lock`: `EntityAlreadyExistsException`, because the retained table already exists |

These earlier jobs remain Failed. The approved recovery removed only the verified stale lock, and the new supervised scheduler acquired and released its own lock successfully. This resolves the lock blocker without rewriting failed job history.

Current verified observations:

- Current schedule `c0b76c56-b622-4e20-8f47-d100f70033e0` is **disabled**, interval **30 minutes**, time zone `SE Asia Standard Time`.
- Zero active jobs across the four production ingestion pipeline items; lock table absent.
- November 20 refresh `391be264-d3bd-4c32-80a7-d35fe89a25e1` is **Completed / Verified**.
- There are **zero incomplete refresh checkpoints**.
- Serving readiness is **true**, now owned by `c0758ff6-d82e-4632-af63-c15440af16d0`.

No further lock deletion is needed. Do not delete the completed refresh checkpoint or force another November 20 correction. Future failures still require [reviewed recovery](07-interval-scheduler/README.md#11-failure-recovery-and-configuration-rollback), not automatic repeated lock deletion.

## 4. Warehouse and KQL evidence

Fresh before/after recovery checks verified unchanged aggregate audit/control values. The date-scoped audit breakdown below was captured at approximately **09:22 ICT**; it was not separately queried again during recovery. No ingestion or correction invocation occurred in the new run.

### `wh_control_framework`

| Measure | Before recovery | After supervised run |
| --- | --- | --- |
| Current Success entries, all dates | 315 | 315 |
| Current Success logged rows, all dates | 3,004 | 3,004 |
| Superseded-0230 entries, all dates | 12 | 12 |
| Superseded-0230 logged rows | 162 | 162 |
| Completed/Verified November 20 refreshes | 1 | 1 |
| Incomplete refreshes | 0 | 0 |
| Current refresh manifest / archived audit rows | 6 / 6 | 6 / 6 |

| Filename date | Audit status | Entries | Logged rows |
| --- | --- | --- | --- |
| 2026-11-19 | Success | 48 | 612 |
| 2026-11-20 | Success | 48 | 568 |
| 2026-11-19 | Superseded-0230 | 4 | 58 |
| 2026-11-20 | Superseded-0230 | 8 | 104 |

For the completed refresh RunId `391be264-d3bd-4c32-80a7-d35fe89a25e1`:

```text
Refresh status/stage: Completed / Verified
Manifest files:       6
Archived audit rows:  6
Incomplete refreshes: 0
```

The 12 superseded entries / 162 rows reflect the two earlier supervised replacement cycles, not this recovery. The new normal rerun introduced no audit entries.

### `DepositMovement` KQL database

| Object / condition | Fresh result |
| --- | --- |
| Bronze `DepositMovement`, November 19-20 | 1,180 before and after |
| Silver `DepositMovementClassified`, November 19-20 | 1,180 before and after |
| `mv_Summary_Product_Channel_Alert`, November 19-20 | 40 groups before and after |
| Summary MV | Enabled `1`, healthy `1`, source `DepositMovement` |
| Bronze cache policy | Data/index hot span `90.00:00:00` |

These are date-scoped count/control checks, not a new exact row-by-row or amount reconciliation. They do not assert full-database Bronze/Silver parity.

## 5. Earlier 02:30 acceptance - not repeated during recovery

The existing PRD2 end-to-end results remain documented in [guide 07, section 9.6](07-interval-scheduler/README.md#96-verified-live-test). They are context, not fresh tests performed on November 20 morning.

| Earlier scenario | Recorded run ID | Recorded outcome |
| --- | --- | --- |
| Normal full-day ingestion | `5cf71d07-868e-4e9e-8245-52efc7d5fc58` | Completed; 96 files / 1,180 exact business rows |
| First correction attempt | `1769832f-ebfc-42c1-a06d-3a046c0e3005`; child `37da5dc4-8e67-4c65-8739-151125ba02a9` | Failed at cold-cache Gold backfill; protected hold retained; separate derived-only recovery completed without another Copy |
| Corrected native correction | `24ab0ed7-01ee-4d61-9b2f-013e0a4f1932`; child `391be264-d3bd-4c32-80a7-d35fe89a25e1` | Completed; six parallel reloads, 81 selected rows, cache warm/restore; about 11.86 minutes |
| Frozen-03:00 normal rerun | `8d97bb46-6eb3-44ec-9cc8-f92f384372e6` | Completed; zero new files / ingestion invocations |
| Restored actual-clock normal rerun | `3ebe2d47-fdb4-4e85-b8d3-c7f689c6f9ed` | Completed; zero new files / ingestion invocations |

The earlier six expected-failure tests covered unapproved refresh, wrong owner, duplicate refresh date, concurrent lock acquisition, missing source, and an incomplete checkpoint. Those guards were not fault-injected again during this recovery.

## 6. Coverage limits

- The new scheduler test exercised normal discovery and duplicate prevention, not a new-file Copy or destructive six-file correction.
- Only one source CSV content sample was read in the earlier same-day preflight; all source contents/versions were not rehashed during recovery.
- Count/control checks do not replace the earlier exact source, amounts, classification, and unrelated-row reconciliation.
- Partial-Copy failure, failed audit writes, and concurrent source modification were not injected today.
- The retained lock is resolved, but a Manual run does not prove subsequent unattended scheduled or overnight operation. Scheduling was left disabled.
- No new performance SLA, alert-delivery, production approval, or annual-reference compatibility claim is made.

## Read-only replay queries

### Warehouse

Run against `RTI-IDM-PRD2 / wh_control_framework`:

```sql
SELECT SUBSTRING(FileName,18,8) AS FileDate,
       Status, COUNT_BIG(*) AS AuditRows, SUM(RowCount_) AS LoggedRows
FROM dbo.ProcessedFiles
WHERE FileName LIKE 'INTRADAY_SUMMARY_20261119[_]%'
   OR FileName LIKE 'INTRADAY_SUMMARY_20261120[_]%'
GROUP BY SUBSTRING(FileName,18,8), Status
ORDER BY FileDate, Status;

SELECT RefreshDate, RunId, Status, Stage
FROM dbo.Refresh0230Run
ORDER BY RefreshDate;

SELECT COUNT_BIG(*) AS IncompleteRefreshes
FROM dbo.Refresh0230Run
WHERE Status <> 'Completed';

SELECT COUNT_BIG(*) AS ManifestFiles
FROM dbo.Refresh0230File
WHERE RunId = '391be264-d3bd-4c32-80a7-d35fe89a25e1';

SELECT COUNT_BIG(*) AS ArchivedAuditRows
FROM dbo.Refresh0230AuditBefore
WHERE RefreshRunId = '391be264-d3bd-4c32-80a7-d35fe89a25e1';
```

### KQL

Run against `RTI-IDM-PRD2 / DepositMovement`, one query/management command at a time:

```kql
union
    (DepositMovement
     | where Date >= datetime(2026-11-19) and Date < datetime(2026-11-21)
     | summarize Rows=count() | extend Object="DepositMovement"),
    (DepositMovementClassified
     | where Date >= datetime(2026-11-19) and Date < datetime(2026-11-21)
     | summarize Rows=count() | extend Object="DepositMovementClassified"),
    (mv_Summary_Product_Channel_Alert
     | where Date >= datetime(2026-11-19) and Date < datetime(2026-11-21)
     | summarize Rows=count() | extend Object="mv_Summary_Product_Channel_Alert")
| project Object, Rows
```

```kql
Refresh0230_BatchLock | project Owner
```

```kql
CR01_PublishState | order by ChangedAtUtc desc | take 1
```

```kql
.show tables | project TableName
```

```kql
.show materialized-views | project Name, IsHealthy, IsEnabled, SourceTable
```

```kql
.show table DepositMovement policy caching
```

Replay results reflect state at replay time. If the lock has since been reviewed and released, query table existence first; an absent lock table is not a reason to create one.
