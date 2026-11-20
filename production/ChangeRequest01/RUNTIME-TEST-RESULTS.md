# PRD2 02:30 Refresh - Runtime Test Results

## 1. Executive summary

**Overall status: PASS for the exercised runtime scope; scheduling remains disabled pending customer activation approval.**

The initial normal scheduler run passed. Independent comparison against the real source confirmed **96 files and 1,180 rows** exactly in Bronze and Silver, all test-date Silver rows classified, and **40 matching Gold groups**. The normal run left unrelated records unchanged, readiness true, and no batch lock.

The first six-file correction **failed at Step 32, Rebuild Gold Summary**. All six files had reloaded, and all source/audit/Silver/unrelated-record checks before Step 32 passed. MV creation with `backfill=true` rejected historical source extents outside the existing 90-day hot-cache policy. The scheduler correctly retained its lock, left readiness false, and did not publish or release after this failure.

**Separate manual recovery passed without another Copy.** Under the retained original owner, the coordinator temporarily extended source hot-cache coverage to 365 days, rebuilt and reconciled Gold, restored the original 90-day policy, completed the original refresh checkpoint, then published readiness and released the original lock. Six new replacement child identities and 81 replacement rows reconciled, six original successes were preserved, and 96 current Success entries remained. The historical root and child jobs stay **Failed**.

The corrected native refresh, six controlled negative guards, frozen-03:00 normal repeat, and restored actual-clock normal run passed. Repeat audit/isolation checks passed after both repeat runs. Production clock conversion is restored, approval defaults remain false, scheduling remains disabled, and future-date test controls are removed. A normal batch at 03:00 is **not guaranteed**: it must wait for successful correction and a later eligible scheduler batch.

**All six controlled guard-failure scenarios passed:** false approvals, wrong lock owner, same-date refresh rerun, concurrent lock acquisition, missing source, and incomplete-refresh blocking. None changed original customer or November 19-20 data. Missing-source and incomplete-sentinel control evidence was captured before exact test-only cleanup; the audit/isolation check re-passed afterward.

After the recovered, Completed fixture was archived/reset under the test-only procedure in section 8, clean native scheduler `24ab0ed7-01ee-4d61-9b2f-013e0a4f1932` **passed** with child `391be264-d3bd-4c32-80a7-d35fe89a25e1`. The child recorded **92 succeeded activities and zero failures**; all six file-invocation intervals overlapped. Cache extension/restoration passed natively, independent comparison again matched 1,180 rows per layer and 40 Gold groups, and all 96 source ETag/size/last-modified values were unchanged.

The corrected root took approximately **11.86 minutes**, **one observed sample**, not a future 03:00 SLA. Its wall-clock run was November 20, 01:45:30-01:57:21 ICT; the decision clock was deliberately frozen at 02:30. The earlier failed attempt plus manual recovery is not a comparable clean-performance measurement.

Frozen-03:00 scheduler `8d97bb46-6eb3-44ec-9cc8-f92f384372e6` and actual-clock scheduler `3ebe2d47-fdb4-4e85-b8d3-c7f689c6f9ed` both observed `CompletedToday=1` and invoked normal discovery instead of repeating correction. Final date-scoped audit totals were **96 Success / 1,180 logged rows** and **12 Superseded / 162 logged rows** across the two legitimate test cycles.

Each repeat discovery scan listed **839 folder items**, filtered **zero new files**, and produced **zero ingestion invocations**. All four pipeline items are idle. Final control counts are one refresh run, six manifest rows, six AuditBefore rows, and zero incomplete runs; Gold is enabled/healthy, readiness is true, and source cache is 90 days.

The current `2026-11-20` checkpoint is Completed/Verified; same-date correction will not automatically repeat at the real 02:30 start. **Do not delete that checkpoint to force another replacement.** Final all-database row counts differ by the preserved legacy mismatch: Bronze 3,015, Silver 3,124; the test-date scope is exactly 1,180 in each layer.

**Final independent verification after both repeats: PASS, exit code 0.** All 96 source versions were unchanged; both layers matched 1,180 exact business rows with zero duplicates; all 1,180 Silver rows were CLASSIFIED; 81 refreshed rows and 40 Gold groups matched. Final configuration verification confirmed the restored production clock, false approval defaults, disabled scheduling, parallelism six, 38 main/60 total activities, unchanged reused children, and no live jobs. This report is self-contained through captured excerpts and [read-only replay queries](#10-read-only-sqlkql-replay-queries-and-captured-results); evidence filenames identify retained originals and are not machine-local link targets.

This is the single runtime report for the change. Customer authoring instructions remain in [05 - Refresh child](05-data-pipeline/README.md) and [07 - Existing scheduler](07-interval-scheduler/README.md).

## 2. Scope and environment

| Item | Exact scope |
| --- | --- |
| Workspace | `RTI-IDM-PRD2` |
| KQL database | `eh-rti-deposit > DepositMovement` |
| Control Warehouse | `wh_control_framework` |
| Existing scheduler | `pl_ingest_DepositMovement_schedule` |
| Existing discovery | `pl_ingest_DepositMovement_trigger_pipeline` |
| Existing single-file ingestion | `pl_ingest_DepositMovement` |
| New refresh child | `pl_refresh_DepositMovement_0230` |
| Deployed refresh activity count | 38 main-canvas / 60 total activities; original Steps 01-36 plus 32A/35A |
| Source | ADLS Gen2 container `inflowoutflow`, directory `inbound/statement` |
| Source dates compared | `2026-11-19` and `2026-11-20`: 48 files per date |
| Data layers | Bronze `DepositMovement`, Silver `DepositMovementClassified`, Gold `mv_Summary_Product_Channel_Alert` |
| Correction date | `2026-11-20` |
| Scheduling during tests | Disabled; controlled manual runs only |
| Backups before testing | Original definitions of all four pipelines snapshotted |
| Bronze cache / retained history | Original hot-cache policy 90 days; temporary recovery coverage 365 days; oldest confirmed extent `2026-07-06` |
| Test ownership | Live-test coordinator controls execution, fault injection, recovery, and final restoration |

The independent source inspection reported immutable ETags, no bad source business rows, and no duplicate source business rows. Source files will not be modified for these tests. No broad data deletion is authorized; the replacement scope is only these six filenames, containing **81 source rows** in total:

```text
INTRADAY_SUMMARY_20261119_2300_2330.CSV
INTRADAY_SUMMARY_20261119_2330_2400.CSV
INTRADAY_SUMMARY_20261120_0000_0030.CSV
INTRADAY_SUMMARY_20261120_0030_0100.CSV
INTRADAY_SUMMARY_20261120_0100_0130.CSV
INTRADAY_SUMMARY_20261120_0130_0200.CSV
```

**Scope boundary:** a pre-existing September 17 mismatch of **109 extra Silver rows** is unrelated to this change. Final all-database counts are Bronze **3,015** and Silver **3,124**, while both test-date scopes contain exactly **1,180** rows. Unrelated records were preserved; no full-database parity or repair of that mismatch is claimed.

**Clock boundary:** correction tests temporarily froze only scheduler `vRunICT` at `2026-11-20T02:30:00`; N02 tested frozen 03:00. These were test controls, not actual wall-clock start times or customer setup instructions. Production `Freeze Run ICT` was restored exactly to `@convertFromUtc(utcNow(),'SE Asia Standard Time')` before successful actual-clock test N03. No permanent clock-override parameter was added.

## 3. Scenario matrix

N01 and C02 passed normal ingestion and corrected native refresh respectively. F01/F02/F03/F06/R01/R02 passed all six controlled guard rejections; F05 passed the actual safe-stop check; R03 passed manual derived-stage recovery. Expected failed guard jobs are not completed correction runs. C01 remains historically Failed.

| ID | Scenario | Status | Evidence / remaining check |
| --- | --- | --- | --- |
| N01 | Normal ingestion before 02:30 | PASS | Scheduler and independent source comparison completed; see section 4.1 |
| C01 | First eligible 02:30 correction | FAIL | Six reloads and pre-Step-32 checks passed; Gold backfill failed on cold source extents |
| C02 | Clean native correction with deployed cache fix and bounded six-file parallel reload | PASS | Root/child succeeded; six overlapping reload invocations; native cache restoration; data/audit/isolation and independent oracle PASS |
| N02 | 03:00 normal route after successful correction | PASS | `8d97bb46-6eb3-44ec-9cc8-f92f384372e6`: `CompletedToday=1`, normal discovery, Repeat audit/isolation PASS |
| N03 | Actual-clock scheduler after production expression restoration | PASS | `3ebe2d47-fdb4-4e85-b8d3-c7f689c6f9ed`: restored exact production expression, `CompletedToday=1`, normal discovery, Repeat audit/isolation PASS |
| F01 | Concurrent scheduler cannot acquire another owner's lock | PASS | `402c11c9-674c-4d15-b29e-9d33eba049c4`: Acquire Batch Lock rejected with `EntityAlreadyExists`; foreign lock preserved |
| F02 | False approval condition stops correction | PASS | `3375631d-80a3-4d49-87fd-f8f184a6ed73`: `R0230_NOT_APPROVED` |
| F03 | Missing source guard for future-date filenames | PASS | `2bb8b127-7e71-4ec2-bd8e-72ad6a3f17e1`: `R0230_SOURCE_MISSING`; no backup/deletion stage reached |
| F04 | Partial reload/audit/visibility/reconciliation failure injection | NOT EXECUTED | No such injection supplied; actual Gold failure/safe-stop/recovery covered separately |
| F05 | Gold rebuild failure keeps the correction safely held | PASS - safe-stop behavior only | Actual C01 failure retained lock, readiness false, Running/Reloading checkpoint before manual recovery |
| F06 | Wrong lock owner stops the refresh child | PASS | `8a6db1c6-b1ff-49f6-a540-76b5b73b2529`: `R0230_LOCK` |
| R01 | Same-date direct refresh rerun is rejected | PASS | `5b68882a-65e9-4967-88d9-ea0ba5b516ae`: Register Refresh error `2011`, existing-date message |
| R02 | Incomplete refresh blocks normal ingestion | PASS | `9e1befe6-47f5-43ca-8c19-6a0647c57429`: Lookup Refresh State error `2100`; root-owned lock retained |
| R03 | Controlled derived-stage recovery without a second Copy | PASS | Original owner/checkpoint retained; Gold reconciled; cache restored; audit/isolation passed |

## 4. Per-scenario execution details

### 4.1 N01 - Normal ingestion before 02:30

**Setup**

1. Keep the existing scheduler schedule disabled.
2. Confirm no active jobs before starting the test and snapshot the four original pipeline definitions.
3. Inspect the two source dates independently: 96 files, 1,180 rows, immutable ETags, and no bad/duplicate source business rows.
4. Use the existing source connection and set both scheduler approval parameters to Boolean true for this manual run.

**Action**

1. Execute scheduler job `5cf71d07-868e-4e9e-8245-52efc7d5fc58` before 02:30 ICT.
2. Observe the normal discovery/ingestion path using the real source connection; the observed discovery fan-out was 10.
3. Wait for the root job to finish, then compare both data layers and Gold against the independent source results.
4. Check current audit successes, refresh registration, unrelated rows, readiness, and final lock absence.

These are the coordinator-reported execution steps, not newly executed commands in this report.

**Expected**

Normal discovery runs without a refresh checkpoint. All source files appear exactly once in the test-date data, with matching business values and Gold groups. Publication succeeds, the owner lock is released, and unrelated records are preserved.

**Actual - PASS**

The root job succeeded. Independent source-to-output comparison passed with the results in section 5.2. The parent audit check found 96 current Success entries, no registered refresh, unchanged unrelated rows, readiness true, and no batch lock.

**Timing**

| Clock | Start | End |
| --- | --- | --- |
| UTC | `2026-11-19T17:23:05Z` | `2026-11-19T17:47:48Z` |
| ICT, UTC+07:00 | `2026-11-20T00:23:05+07:00` | `2026-11-20T00:47:48+07:00` |

### 4.2 C01 - Six-file correction at frozen 02:30

**Setup:** normal run N01 completed; schedule stayed disabled; both approval parameters true; only scheduler `vRunICT` temporarily frozen at `2026-11-20T02:30:00`.

**Action:** coordinator started scheduler job `1769832f-ebfc-42c1-a06d-3a046c0e3005`, invoking correction child `37da5dc4-8e67-4c65-8739-151125ba02a9`.

**Expected:** select only the six-file scope; validate source/prior visibility; back up; hold serving; delete selected rows; archive/supersede their prior audit successes; reload each file once; reconcile selected and unrelated data; rebuild/verify Gold; complete the checkpoint; publish and release through the scheduler.

**Actual - FAIL:** all six files reloaded, all source/audit/Silver/unrelated-record checks before Step 32 succeeded, and six old Success entries were archived/superseded. `Rebuild Gold Summary` failed with the exact error recorded in section 5.3. Neither the child nor its scheduler root passed.

| Execution | Start UTC | End UTC | Failed-attempt duration |
| --- | --- | --- | --- |
| Scheduler root | `2026-11-19T17:49:23Z` | `2026-11-19T18:21:17Z` | 31 minutes 54 seconds |
| Refresh child | `2026-11-19T17:50:02Z` | `2026-11-19T18:20:56Z` | 30 minutes 54 seconds |

The SQL checkpoint started at `2026-11-19T17:50:39Z`. The durations above describe the **failed attempt**, not successful correction completion.

### 4.3 F05 - Actual Gold rebuild failure and safe stop

**Setup:** C01 had completed the six scoped reloads and all pre-Step-32 checks. Historical July source data was outside the existing 90-day hot-cache policy. This was an actual runtime failure, not a deliberately changed source file.

**Action:** `Rebuild Gold Summary` attempted MV creation with `backfill=true` over the retained Bronze history.

**Expected:** failure must not mark the refresh Completed, publish readiness, release the acquired lock, or start normal ingestion.

**Actual - PASS for safe-stop behavior only:** both jobs failed; the root lock was retained, readiness was false, and the checkpoint remained Running/Reloading. No automatic publication or release occurred. This safe stop does not turn C01 into a passed correction.

**Recovery:** passed separately as R03 below. C01's historical root and child jobs remain Failed; manual completion of the original checkpoint does not change those job results.

### 4.4 R03 - Manual derived-stage recovery without another Copy

**Setup:** C01's six reloads and pre-rebuild checks had passed; its original scheduler owner still held the lock, readiness was false, and its original checkpoint was Running/Reloading.

**Action - coordinator-reported executed sequence**

1. Retain scheduler owner `1769832f-ebfc-42c1-a06d-3a046c0e3005` and refresh checkpoint RunId `37da5dc4-8e67-4c65-8739-151125ba02a9`.
2. Change only the source cache policy from 90 to 365 days using the command in section 5.4; preserve all retained historical records.
3. Resume only the derived-data work manually: create the summary with backfill, then verify its health and exact values.
4. Restore the original 90-day source cache policy.
5. Execute the original completion SQL against the **original child RunId**, rather than starting a new refresh or copying the six files again.
6. Publish readiness and release the old root lock only after verification.
7. Recheck replacement audit identities, preserved originals, selected rows, current successes, and isolation.

**Expected:** recover derived outputs and finish the original correction checkpoint without duplicating source ingestion; restore cache/readiness/ownership only after reconciliation.

**Actual - PASS:** parent audit/isolation check returned Corrected PASS: six new replacement source-child identities, six archived/superseded original successes, 81 replacement rows, 96 current Success entries, and unchanged unrelated source records. Gold was healthy and exact. Current cache was 90 days, readiness true, and no lock remained. No second Copy was performed.

The archived Warehouse checkpoint records `CompletedAtUtc="2026-11-19T18:29:14.805"`, Status `Completed`, Stage `Verified`, for original RunId `37da5dc4-8e67-4c65-8739-151125ba02a9`.

**Evidence limits:** complete manual recovery start/end timing and full reconciliation grids are not reproduced here. The completed checkpoint is preserved in `cr01-completed-test-fixture-archive.json`. This was manual derived-stage recovery, not a verified native rerun-from-failed-activity feature. Original root/child history remains Failed.

### 4.5 Executed guard and same-date rerun checks

These are coordinator-controlled executions against the existing guarded pipelines. Automatic scheduling remained disabled. Each job below failed as expected; **PASS describes the rejection behavior**, not a successful correction.

#### F02 - False approvals

1. **Setup:** supply a false approval condition to the refresh child.
2. **Action:** run child `3375631d-80a3-4d49-87fd-f8f184a6ed73`.
3. **Expected:** `Require Approval` rejects the run before destructive work.
4. **Actual - PASS:** error `R0230_NOT_APPROVED`; no deletion, reload, or publication stage reached.

#### F06 - Wrong lock owner

1. **Setup:** retain the held foreign-owner lock and supply a non-owning identity to the refresh child.
2. **Action:** run child `8a6db1c6-b1ff-49f6-a540-76b5b73b2529`.
3. **Expected:** ownership guard rejects the caller without releasing the held lock.
4. **Actual - PASS:** error `R0230_LOCK`; foreign-owner lock preserved; no deletion, reload, or publication stage reached.

#### R01 - Same-date refresh rerun

1. **Setup:** keep the already-recovered correction-date checkpoint present.
2. **Action:** run refresh child `5b68882a-65e9-4967-88d9-ea0ba5b516ae` for that same date.
3. **Expected:** `Register Refresh` rejects a second replacement rather than reloading the date.
4. **Actual - PASS:** Register Refresh error `2011` with message excerpt `This date already has a refresh record`; no deletion, reload, or publication stage reached.

#### F01 - Concurrent scheduler acquisition

1. **Setup:** retain the held foreign-owner batch lock.
2. **Action:** start scheduler `402c11c9-674c-4d15-b29e-9d33eba049c4`.
3. **Expected:** create-only `Acquire Batch Lock` fails without changing or removing the existing owner's lock.
4. **Actual - PASS:** `EntityAlreadyExists` at `Acquire Batch Lock`; held foreign-owner lock preserved; no deletion, reload, or publication stage reached.

#### F03 - Missing source without changing source files

1. **Setup:** use isolated correction date `2099-12-31`; keep all existing source files unchanged.
2. **Action:** run child `2bb8b127-7e71-4ec2-bd8e-72ad6a3f17e1`.
3. **Expected:** absent future-date source files fail preflight before backups or deletion.
4. **Actual - PASS:** `Check Source Files / Require Source Exists` failed with inner error `R0230_SOURCE_MISSING`. No backup/deletion stage was reached. The captured Warehouse state contained the six future-date manifest rows and a Running/Preparing checkpoint.
5. **Cleanup:** retain the captured evidence, then remove only this exact test-owned checkpoint/manifest state. No customer data was deleted.

#### R02 - Incomplete refresh blocks normal ingestion

1. **Setup:** inject one isolated `2098-12-31` incomplete sentinel, RunId `b03ae0d5-ae05-4e43-ac1f-dd9472edc45a`, Status `Test-Incomplete`, Stage `InjectedGuardTest`.
2. **Action:** start scheduler `9e1befe6-47f5-43ca-8c19-6a0647c57429`.
3. **Expected:** reject incomplete work at `Lookup Refresh State`, before either branch; retain the scheduler-owned lock.
4. **Actual - PASS:** Lookup error `2100` contained `An incomplete refresh blocks normal ingestion; recover it first.` The captured KQL lock owner was exactly the rejected scheduler RunId.
5. **Cleanup:** after capturing the sentinel/ownership evidence and verifying no active jobs or incomplete work remained, remove only the injected sentinel and release only the matching test owner's lock.

All six tests preserved the original customer and November 19-20 data. The coordinator's Corrected audit/isolation comparison passed again after their cleanup. Exact UTC job timestamps and raw evidence references are retained in section 5.

### 4.6 C02 - Clean corrected native acceptance run

**Setup:** all six negative guards completed and the audit/isolation check re-passed. The completed first-cycle test control fixture was archived before its exact test-only reset; `ProcessedFiles`, source files, and business data were preserved. The deployed refresh has 38 main-canvas / 60 total activities, including 32A/35A.

**Action - coordinator-reported executed sequence**

1. Start scheduler `24ab0ed7-01ee-4d61-9b2f-013e0a4f1932` with temporary frozen ICT decision time `2026-11-20T02:30:00`.
2. Invoke refresh child `391be264-d3bd-4c32-80a7-d35fe89a25e1` with approved parameters and scheduler ownership.
3. Execute preflight, backups, exact six-file deletion, audit preservation, and bounded parallel-six reload.
4. Verify that all six `Invoke File Reload` intervals overlap and the pre-rebuild source/audit/Silver/unrelated-record checks pass.
5. Execute `Warm Bronze Cache For Backfill` at 365 days, rebuild/reconcile Gold, then `Restore Bronze Cache Policy` at 90 days natively.
6. Complete the checkpoint, publish readiness, release the lock, and perform independent source/output and audit/isolation comparisons.

**Expected:** all native stages pass without manual derived-stage recovery; exactly one current Success per selected filename; source/data/audit/isolation and Gold reconcile; original cache policy is restored before completion/publication/release.

**Actual - PASS:** root and child succeeded natively. The child recorded 92 succeeded activities and zero failed activities; all six file-invocation intervals overlapped. Both cache activities succeeded. Audit/isolation Corrected PASS found six new IDs, 81 replacement rows, 96 current Success entries, 12 cumulative Superseded entries, six current AuditBefore records, unchanged unrelated Bronze/Silver, readiness true, and no lock.

Independent source comparison passed again: 1,180 exact rows per layer, 40 exact Gold groups, and all 96 source ETag/size/last-modified values unchanged. Source totals remained those in section 5.2.

| Execution | Start UTC, November 19 | End UTC, November 19 | ICT wall-clock timing, November 20 |
| --- | --- | --- | --- |
| Scheduler root | `18:45:30` | `18:57:21` | `01:45:30-01:57:21` |
| Refresh child | `18:46:03` | `18:56:41` | `01:46:03-01:56:41` |

The root's reported duration was approximately **11.86 minutes**; displayed timestamps are to whole seconds. This is one observed sample, not a future SLA, and is not comparable to the earlier failed run plus manual recovery.

This was the second legitimate test replacement cycle. The **12 measured Superseded entries across six filenames** represent both cycles, while exactly one current Success per filename remains. The new cycle's `Refresh0230AuditBefore` contains six latest originals. First-cycle control snapshots are archived and are not expected as current SQL rows. No historical failed job was relabeled as successful.

### 4.7 N02 - Frozen-03:00 normal repeat

**Setup:** C02 completed successfully; its Completed/Verified correction-date checkpoint remained present. Keep the schedule disabled and temporarily set the scheduler's decision clock to 03:00 for the controlled repeat test.

**Action**

1. Execute scheduler `8d97bb46-6eb3-44ec-9cc8-f92f384372e6`.
2. Inspect `Lookup Refresh State` and branch selection.
3. Follow normal-discovery child `6c6105d8-c262-4662-96c3-a618f858a8e7`.
4. Repeat audit/isolation comparisons after the run.

**Expected:** today's completed correction selects normal discovery, not another six-file replacement; no duplicate ingestion or unrelated-data changes.

**Actual - PASS:** scheduler completed on November 19, **18:59:38-19:01:52 UTC** (November 20, **01:59:38-02:01:52 ICT**). `CompletedToday=1` selected the normal-discovery child above. Repeat audit/isolation PASS confirmed the preserved corrected state. The decision clock was frozen 03:00, not the actual wall-clock time.

The inspected no-op export confirms discovery listed 839 items, returned `FilteredItemsCount=0` with `Value=[]`, and created zero ingestion activity instances.

### 4.8 N03 - Restored production clock and actual-clock normal run

**Setup:** after N02, restore production `Freeze Run ICT` exactly to:

```text
@convertFromUtc(utcNow(),'SE Asia Standard Time')
```

**Action**

1. Execute scheduler `3ebe2d47-fdb4-4e85-b8d3-c7f689c6f9ed` using the restored production expression.
2. Inspect the frozen clock output, today's completed count, and chosen branch.
3. Follow normal-discovery child `32bbbcab-5ec3-4843-9c4c-5d91cdd0cd04`.
4. Re-run the audit/isolation comparison and confirm the final control/configuration state.

**Expected:** use the real converted clock without an override; do not repeat today's completed correction; preserve source, audit, and unrelated data.

**Actual - PASS:** scheduler completed on November 19, **19:03:15-19:04:53 UTC** (November 20, **02:03:15-02:04:53 ICT**). The frozen ICT wall-clock value was **2026-11-20 02:03:24**; `CompletedToday=1` selected the normal-discovery child above. Repeat audit/isolation passed after both N02 and N03.

The inspected no-op export independently confirms 839 listed items, `FilteredItemsCount=0`, `Value=[]`, and zero ingestion activity instances for this second discovery run too.

**Clock serialization caution:** the service serializes the already-shifted ICT wall-clock output with `Z`. Do not treat that label as a new UTC instant or apply another seven-hour conversion; job start/end times above remain UTC.

**Final supplied Warehouse/configuration state:** 96 current Success entries logging 1,180 rows; 12 Superseded entries logging 162 rows across two replacement cycles; sole current refresh RunId `391be264-d3bd-4c32-80a7-d35fe89a25e1`, Completed/Verified, StartedAtUtc `2026-11-19T18:46:47`, CompletedAtUtc `2026-11-19T18:56:34`. Approval defaults remain false, scheduling remains disabled, and no future-date test control rows remain.

Partial Copy, audit-write, and visibility/reconciliation fault injection was not executed in the supplied evidence; see section 9 rather than interpreting these as passed tests.

## 5. Run IDs, timestamps, and Warehouse/KQL evidence

### 5.1 Run register

| Scenario | Job / run ID | Observed state | Timing supplied |
| --- | --- | --- | --- |
| N01 scheduler | `5cf71d07-868e-4e9e-8245-52efc7d5fc58` | Succeeded | `2026-11-19T17:23:05Z` to `2026-11-19T17:47:48Z` |
| C01 scheduler | `1769832f-ebfc-42c1-a06d-3a046c0e3005` | Failed | `2026-11-19T17:49:23Z` to `2026-11-19T18:21:17Z` |
| C01 refresh child | `37da5dc4-8e67-4c65-8739-151125ba02a9` | Failed at Rebuild Gold Summary | `2026-11-19T17:50:02Z` to `2026-11-19T18:20:56Z`; checkpoint start `2026-11-19T17:50:39Z` |
| R03 manual recovery | Original owner `1769832f-ebfc-42c1-a06d-3a046c0e3005`; original checkpoint `37da5dc4-8e67-4c65-8739-151125ba02a9` | Data/control recovery passed; historical jobs remain Failed | Original SQL `CompletedAtUtc=2026-11-19T18:29:14.805`; full manual recovery timing not supplied |
| F02 false approvals | `3375631d-80a3-4d49-87fd-f8f184a6ed73` | Expected failure, `R0230_NOT_APPROVED` | `2026-11-19T18:34:10.3733333Z` to `2026-11-19T18:34:47.6266667Z` |
| F06 wrong owner | `8a6db1c6-b1ff-49f6-a540-76b5b73b2529` | Expected failure, `R0230_LOCK` | `2026-11-19T18:34:59.58Z` to `2026-11-19T18:35:59.3733333Z` |
| R01 same-date rerun | `5b68882a-65e9-4967-88d9-ea0ba5b516ae` | Expected Register Refresh failure, `2011` | `2026-11-19T18:36:20.0535585Z` to `2026-11-19T18:37:20.8666667Z` |
| F01 concurrent scheduler | `402c11c9-674c-4d15-b29e-9d33eba049c4` | Expected acquisition failure, `4000` / `EntityAlreadyExistsException` | `2026-11-19T18:37:42.0366667Z` to `2026-11-19T18:38:09.5Z` |
| F03 missing source | `2bb8b127-7e71-4ec2-bd8e-72ad6a3f17e1` | Expected failure, inner `R0230_SOURCE_MISSING` | `2026-11-19T18:38:29.8855422Z` to `2026-11-19T18:40:41.4733333Z` |
| R02 incomplete sentinel | `9e1befe6-47f5-43ca-8c19-6a0647c57429` | Expected Lookup failure, `2100` | `2026-11-19T18:41:44.2166667Z` to `2026-11-19T18:42:14.9566667Z` |
| C02 clean native scheduler | `24ab0ed7-01ee-4d61-9b2f-013e0a4f1932` | Succeeded | `2026-11-19T18:45:30Z` to `2026-11-19T18:57:21Z` |
| C02 clean native child | `391be264-d3bd-4c32-80a7-d35fe89a25e1` | Succeeded; 92 succeeded activities, zero failed | `2026-11-19T18:46:03Z` to `2026-11-19T18:56:41Z` |
| N02 frozen-03:00 scheduler | `8d97bb46-6eb3-44ec-9cc8-f92f384372e6` | Completed; normal branch | `2026-11-19T18:59:38Z` to `2026-11-19T19:01:52Z` |
| N02 normal discovery | `6c6105d8-c262-4662-96c3-a618f858a8e7` | Invoked by N02 normal branch | Detailed child timing not reproduced |
| N03 actual-clock scheduler | `3ebe2d47-fdb4-4e85-b8d3-c7f689c6f9ed` | Completed; restored production clock, normal branch | `2026-11-19T19:03:15Z` to `2026-11-19T19:04:53Z` |
| N03 normal discovery | `32bbbcab-5ec3-4843-9c4c-5d91cdd0cd04` | Invoked by N03 normal branch | Detailed child timing not reproduced |

### 5.2 Received comparison results

The following are **reported verified results**, transcribed from the live-test coordinator and independent source-oracle feedback. They are not fabricated raw SQL/KQL grids; full source/output query transcripts are not reproduced here.

| N01 comparison / control check | Received result |
| --- | --- |
| November 19 source files | 48 |
| November 20 source files | 48 |
| Source / Bronze / Silver test-date rows | 1,180 / 1,180 / 1,180 |
| November 19 rows in each layer | 612 |
| November 20 rows in each layer | 568 |
| Silver test-date classification | All `CLASSIFIED` |
| Gold test-date groups | 40, exact match |
| Credit amount | `620667116563.36` |
| Debit amount | `654667116563.50` |
| Net amount | `-34000000000.14` |
| Credit transactions | `704772` |
| Debit transactions | `680414` |
| Total transactions | `1385186` |
| Current Success audit entries | 96 |
| Refresh registration after N01 | None |
| Batch lock after N01 | Absent |
| Readiness after N01 | True |
| Unrelated records after N01 | Unchanged |

### 5.3 Actual Warehouse/KQL logs and evidence references

**Actual C01 activity error, supplied by the live-test coordinator:**

- Activity: `Rebuild Gold Summary`
- Child run: `37da5dc4-8e67-4c65-8739-151125ba02a9`

```text
MaterializedViewInvalidArgumentException
Materialized view creation with backfill option is not supported for tables with extents in cold cache. Please increase the hot cache policy to cover all extents in table or create the view with no backfill.
```

The coordinator identified retained July history outside the source table's existing 90-day hot-cache policy. **The no-backfill alternative in the service error is not the approved recovery:** preserve all history and keep `backfill=true`.

Evidence provenance is explicit below: inspected raw control/activity exports are distinguished from coordinator-verified comparison results. Example queries and generated output are not substituted for executed evidence. Credentials, tokens, and personal identity fields are excluded from excerpts.

| Evidence item | Provenance / retained result |
| --- | --- |
| Source-oracle and immutable-source comparisons | Independent PASS reported by coordinator; exact counts in sections 5.2/5.7 |
| N01 per-date Bronze/Silver and Gold comparisons | Verified result summary in section 5.2 |
| N01 audit and KQL lock/readiness/unrelated-row checks | Verified control-state summary in section 5.2 |
| C01 checkpoint, manifest, archive/superseded and replacement audit | Six reloads/pre-Step-32 checks passed; original checkpoint completed manually in R03 and preserved in inspected fixture archive |
| C01 activity failure / R03 recovery | Exact Step-32 error above; verified recovery results in section 5.4 |
| C02 native cache/parallel/source/audit/isolation checks | Native PASS and six overlapping invocations reported; results in section 5.7 |
| Six controlled guard failures | Actual jobs, timestamps, errors, and two control-state exports inspected; see sections 5.5/5.6 |
| N02/N03 branch, audit/isolation, and final Warehouse rechecks | Both Repeat comparisons PASS; exact run IDs in section 5.1 and state in section 5.8 |
| N02/N03 discovery no-op proof | Inspected `cr01-repeat-noop-evidence.json`; exact zero-file/zero-ingestion output in section 5.9 |
| Final database state | Inspected `cr01-final-database-evidence.json`; exact export in section 5.10 |
| Final independent business/source/configuration verification | Inspected final oracle, source-version, and configuration exports; self-contained excerpts in section 5.11 |

### 5.4 Verified recovery commands and control results

The coordinator supplied these exact commands as executed successfully during manual recovery. They alter **cache policy**, not retained business records:

```kql
.alter table DepositMovement policy caching hot = 365d
```

After Gold was rebuilt and reconciled:

```kql
.alter table DepositMovement policy caching hot = 90d
```

| R03 reported verification | Actual result supplied |
| --- | --- |
| Gold summary | Healthy and exact |
| Replacement child identities | Six new identities |
| Original Success entries | Six archived/superseded |
| Selected replacement rows | 81 |
| Current Success audit entries | 96 |
| Unrelated source records | Unchanged |
| Original refresh checkpoint | Completion SQL executed against `37da5dc4-8e67-4c65-8739-151125ba02a9` |
| Source cache after recovery | 90 days |
| Readiness / lock after recovery | True / absent |
| Additional Copy | None |

These are supplied verification results, not reconstructed raw query grids. Full query transcripts are not reproduced here.

### 5.5 Actual guard-error evidence

The following actual error codes/message excerpts were inspected in the coordinator's session evidence `cr01-negative-scenarios.json`; diagnostic request/host metadata is omitted:

| Run ID | Failed activity / guard | Actual error supplied |
| --- | --- | --- |
| `3375631d-80a3-4d49-87fd-f8f184a6ed73` | Require Approval Failed | `R0230_NOT_APPROVED`; `Refresh requires approved maintenance and finalized source files.` |
| `8a6db1c6-b1ff-49f6-a540-76b5b73b2529` | Guard Lock Owner Failed | `R0230_LOCK`; `Refresh does not own the scheduler batch lock.` |
| `5b68882a-65e9-4967-88d9-ea0ba5b516ae` | Register Refresh | `2011`; `This date already has a refresh record. Inspect/recover it; do not start a second replacement.` |
| `402c11c9-674c-4d15-b29e-9d33eba049c4` | Acquire Batch Lock | `4000`; inner `EntityAlreadyExistsException`: `Entity 'Refresh0230_BatchLock' of kind 'Table' already exists.` |
| `2bb8b127-7e71-4ec2-bd8e-72ad6a3f17e1` | Require Source Exists Failed, inside Check Source Files | `R0230_SOURCE_MISSING`; `A selected source file is missing; stop before deletion` |
| `9e1befe6-47f5-43ca-8c19-6a0647c57429` | Lookup Refresh State | `2100`; SQL message `An incomplete refresh blocks normal ingestion; recover it first.` |

For the false-approval, wrong-owner, same-date, and concurrent-start tests, no deletion/reload/publication stage was reached and the held foreign-owner lock was preserved.

### 5.6 Actual Warehouse/KQL control-state evidence and references

The following session evidence files were inspected directly. Their names are evidence references, not additional customer implementation documents:

| Evidence file | Actual contents used |
| --- | --- |
| `cr01-negative-scenarios.json` | Six job records, failed activities/errors, timestamps, foreign-owner preservation, and isolated cleanup result |
| `cr01-missing-source-control-evidence.json` | Missing-source checkpoint, six manifest rows, null reload identities/counts, and `NoDataStageReached=true` |
| `cr01-incomplete-guard-control-evidence.json` | Injected incomplete Warehouse checkpoint and KQL lock owner matching the rejected scheduler |
| `cr01-completed-test-fixture-archive.json` | Completed first-cycle checkpoint, six manifest/six prior-audit records, test-only marker, and read-only pre-reset audit snapshot |
| `cr01-repeat-noop-evidence.json` | Both exact discovery RunIds, 839 listed items, zero filtered/new files, and zero ingestion invocations |
| `cr01-final-database-evidence.json` | Final Gold, Warehouse control counts, readiness, 90-day cache, and all/test-scope KQL row counts |
| `cr01-live-oracle-verification-final.json` | Final exact business/lineage comparison, zero duplicates, classification, Gold, both exit codes, and unchanged persisted identities after repeats |
| `cr01-source-versions-final.json` | Final read-only source listing: 96 unchanged ETag/length/last-modified versions; no final content download |
| `cr01-final-config-evidence.json` | Final production-clock/safe-default/schedule/parallelism/dependency/count/idle checks |

**Missing-source Warehouse run row - actual object excerpt:**

```json
{
  "RunId": "2bb8b127-7e71-4ec2-bd8e-72ad6a3f17e1",
  "RefreshDate": "2099-12-31T00:00:00",
  "BackupSuffix": "20991231_2bb8b1277e714ec2bd8e72ad6a3f17e1",
  "Status": "Running",
  "Stage": "Preparing",
  "StartedAtUtc": "2026-11-19T18:39:05.799",
  "CompletedAtUtc": null
}
```

The same export recorded `NoDataStageReached: true` and six `Refresh0230File` rows; all six had null `SourceBytes`, `SourceLastModified`, `ReloadRows`, and `ReloadPipelineRunId`. The registered filenames were:

```text
INTRADAY_SUMMARY_20991230_2300_2330.CSV
INTRADAY_SUMMARY_20991230_2330_2400.CSV
INTRADAY_SUMMARY_20991231_0000_0030.CSV
INTRADAY_SUMMARY_20991231_0030_0100.CSV
INTRADAY_SUMMARY_20991231_0100_0130.CSV
INTRADAY_SUMMARY_20991231_0130_0200.CSV
```

**Incomplete-sentinel Warehouse/KQL export - actual complete object:**

```json
{
  "RejectedSchedulerRun": "9e1befe6-47f5-43ca-8c19-6a0647c57429",
  "Run": [
    {
      "RunId": "b03ae0d5-ae05-4e43-ac1f-dd9472edc45a",
      "RefreshDate": "2098-12-31T00:00:00",
      "BackupSuffix": "CR01_GUARD_TEST",
      "Status": "Test-Incomplete",
      "Stage": "InjectedGuardTest",
      "StartedAtUtc": "2026-11-19T18:41:40.927",
      "CompletedAtUtc": null
    }
  ],
  "LockOwner": [
    {
      "Owner": "9e1befe6-47f5-43ca-8c19-6a0647c57429"
    }
  ]
}
```

The negative-scenarios export also recorded `CustomerDataDeleted: false` and Result `Passed` for `Isolated failed-test control cleanup`. The coordinator confirmed exact test-record cleanup, owner-safe lock release after checking active/incomplete work, and a repeated Corrected audit/isolation PASS. These future-date fixtures were not customer recovery instructions.

**Completed-fixture archive - inspected actual fields/counts:**

| Archive field / collection | Actual value |
| --- | --- |
| `CapturedUtc` | `2026-11-19T18:44:53.3109894Z` |
| `NotProductionRetry` | `true` |
| `OriginalRoot` | `1769832f-ebfc-42c1-a06d-3a046c0e3005` |
| `Run` | One row: `37da5dc4-8e67-4c65-8739-151125ba02a9`, `Completed` / `Verified` |
| Original checkpoint `CompletedAtUtc` | `2026-11-19T18:29:14.805` |
| `Manifest` / `PriorAuditSnapshot` | Six / six records |
| Read-only `ProcessedFilesBeforeReset` snapshot | 102 entries: 96 `Success`, six `Superseded-0230` |

The archive's read-only audit snapshot is evidence of retained history, **not deletion from `ProcessedFiles`**. Only the exact completed test run's three control-table record sets were reset.

### 5.7 Corrected native acceptance results

These are actual results supplied by the coordinator and independent oracle, not fabricated raw activity/query output:

| C02 native check | Verified result |
| --- | --- |
| Root / refresh child | `24ab0ed7-01ee-4d61-9b2f-013e0a4f1932` / `391be264-d3bd-4c32-80a7-d35fe89a25e1`, both Succeeded |
| Child activity records | 92 Succeeded, zero Failed |
| File invocation concurrency | All six intervals overlapped |
| Warm cache activity | Succeeded at 365 days |
| Restore cache activity | Succeeded at 90 days |
| Selected replacement rows / new child identities | 81 / six |
| Current Success entries | 96; one per selected filename |
| Cumulative Superseded entries | 12 across two legitimate test cycles |
| Current AuditBefore entries | Six latest originals; first-cycle snapshot archived |
| Unrelated Bronze/Silver | Preserved |
| Independent test-date rows / Gold groups | 1,180 exact rows per layer / 40 exact groups |
| Source immutability | All 96 ETag/size/last-modified triples unchanged |
| Readiness / lock after C02 | True / absent |

The coordinator verified overlap of all six invocation intervals; the full individual timestamp grid is not reproduced here. A native PASS is established for this run, not for unexecuted future batches.

### 5.8 Actual normal-repeat and final Warehouse results

The following values were supplied from the completed repeat runs and date-scoped Warehouse checks:

| Check | Actual supplied result |
| --- | --- |
| N02 `CompletedToday` / branch | `1` / normal discovery `6c6105d8-c262-4662-96c3-a618f858a8e7` |
| N03 restored expression | `@convertFromUtc(utcNow(),'SE Asia Standard Time')` |
| N03 frozen ICT wall-clock value | `2026-11-20 02:03:24`; vendor serializes shifted wall time with `Z` |
| N03 `CompletedToday` / branch | `1` / normal discovery `32bbbcab-5ec3-4843-9c4c-5d91cdd0cd04` |
| Repeat audit/isolation after both runs | PASS |
| Current Success audit count / logged rows | 96 / 1,180 |
| Cumulative Superseded audit count / logged rows | 12 / 162, across two legitimate test cycles |
| Sole current refresh RunId | `391be264-d3bd-4c32-80a7-d35fe89a25e1` |
| RefreshDate / Status / Stage | `2026-11-20` / `Completed` / `Verified` |
| StartedAtUtc / CompletedAtUtc | `2026-11-19T18:46:47` / `2026-11-19T18:56:34` |
| Future-date test controls | None remaining |
| Approval defaults / schedule | False / disabled |
| Final discovery results, N02 and N03 | 839 items each; zero filtered/new files; zero ingestion invocations |
| Pipeline items | All four idle; original discovery and single-file definitions unchanged by independent coordinator diff |

Audit `RowsLogged` totals are Warehouse accounting values, not additional Bronze/Silver rows. The sole current refresh row belongs to C02; C01/R03 control snapshots remain in their durable archive. Independent coordinator comparison confirmed the original discovery and single-file ingestion definitions unchanged and the scheduler's intended production clock expression restored. Per-file definition hashes are not reproduced here.

### 5.9 Actual repeat no-op evidence

The following complete payload was inspected in `cr01-repeat-noop-evidence.json`:

```json
[
  {
    "Scenario": "normal-after-correction-0300",
    "DiscoveryRunId": "6c6105d8-c262-4662-96c3-a618f858a8e7",
    "DiscoveredCandidates": 839,
    "NewFiles": 0,
    "IngestionInvocations": 0,
    "FilterOutput": {
      "ItemsCount": 839,
      "FilteredItemsCount": 0,
      "Value": []
    },
    "Result": "Passed"
  },
  {
    "Scenario": "normal-real-clock-final",
    "DiscoveryRunId": "32bbbcab-5ec3-4843-9c4c-5d91cdd0cd04",
    "DiscoveredCandidates": 839,
    "NewFiles": 0,
    "IngestionInvocations": 0,
    "FilterOutput": {
      "ItemsCount": 839,
      "FilteredItemsCount": 0,
      "Value": []
    },
    "Result": "Passed"
  }
]
```

These are real no-op normal runs, not a claim that new files were ingested. Duplicate protection is evidenced by the empty filtered arrays, zero ingestion calls, and unchanged audit/data comparisons.

### 5.10 Actual final database evidence

The following complete payload was inspected in `cr01-final-database-evidence.json`:

```json
{
  "Gold": [
    {
      "Name": "mv_Summary_Product_Channel_Alert",
      "IsEnabled": 1,
      "IsHealthy": 1
    }
  ],
  "WarehouseControl": [
    {
      "ObjectName": "RefreshRun",
      "Records": 1
    },
    {
      "ObjectName": "Manifest",
      "Records": 6
    },
    {
      "ObjectName": "AuditBefore",
      "Records": 6
    },
    {
      "ObjectName": "Incomplete",
      "Records": 0
    }
  ],
  "Readiness": [
    {
      "IsReady": true,
      "ChangedAtUtc": "2026-11-19T19:04:40.2209382Z",
      "Owner": "3ebe2d47-fdb4-4e85-b8d3-c7f689c6f9ed"
    }
  ],
  "SourceCachingPolicy": {
    "DataHotSpan": {
      "Value": "90.00:00:00"
    },
    "IndexHotSpan": {
      "Value": "90.00:00:00"
    }
  },
  "CheckedUtc": "2026-11-19T19:08:44.3209528Z",
  "KqlRows": [
    {
      "AllRows": 3124,
      "TestRows": 1180,
      "Layer": "Silver"
    },
    {
      "AllRows": 3015,
      "TestRows": 1180,
      "Layer": "Bronze"
    }
  ]
}
```

The 109-row global difference is the preserved September 17 baseline, not a new correction discrepancy. The verified reconciliation claim is exact test-date equality plus unrelated-record preservation.

### 5.11 Final independent verification after both repeats

The final independent verifier read the two authorized business dates after N02/N03. It returned **PASS, exit code 0**, with zero mismatches. Selected actual fields from the final oracle and source-version exports are reproduced below; account/identity/local-path fields are deliberately excluded.

| Final independent result | Bronze | Silver |
| --- | --- | --- |
| Files / exact business rows | 96 / 1,180 | 96 / 1,180 |
| November 19 / November 20 rows | 612 / 568 | 612 / 568 |
| Duplicate business-key excess rows | 0 | 0 |
| Duplicate current-ingest excess rows | 0 | 0 |
| Files without exactly one current identity | 0 | 0 |
| Refreshed rows / exact normalized match | 81 / true | 81 / true |
| Persisted ingestion identities unchanged after repeats | 96 of 96 | 96 of 96 |
| Business multisets unchanged after repeats | 96 of 96 | 96 of 96 |
| Classification | Not applicable | `CLASSIFIED: 1180` |

Both normalized business-row multisets had SHA-256:

```text
6f216382886899db8f1076b5635c13b071b023e47af4f55150228593f6d74c2a
```

Gold had 40 raw rows, 40 normalized groups, 40 expected groups, zero duplicate groups, and `exact_source_aggregation_match=true`. All 40 groups remained unchanged after the normal repeats.

**Final source-version export - selected actual fields:**

```json
{
  "status": "PASS",
  "read_only": true,
  "content_downloaded": false,
  "reported_final_scheduler_root": "3ebe2d47-fdb4-4e85-b8d3-c7f689c6f9ed",
  "expected_files": 96,
  "listed_files": 96,
  "unchanged_files": 96,
  "missing_files": [],
  "unexpected_files": [],
  "changed_versions": [],
  "source_versions_unchanged": true,
  "completed_at_utc": "2026-11-20T02:08:33.574814+07:00",
  "exit_code": 0
}
```

The final check compared live ETags, byte lengths, and LastModified values with the original content-hashed source oracle. It did **not** download or rehash final source content. The business and source-version verifier exit codes were both 0; its final acceptance record reported no further live queries.

**Final configuration export - actual complete payload:**

```json
{
  "WaitsSeconds": [
    5,
    5,
    5
  ],
  "CacheFixWired": true,
  "ProductionClockRestored": true,
  "ApprovalDefaultsFalse": true,
  "RefreshTotalActivities": 60,
  "RefreshMainActivities": 38,
  "ScheduleDisabled": true,
  "ReloadParallelism": 6,
  "CheckedUtc": "2026-11-19T19:11:17.7523084Z",
  "ReusedChildrenUnchanged": true,
  "NoLiveJobs": true,
  "Status": "Passed"
}
```

## 6. Data movement and integrity

| Operation | Reported scope / result | Acceptance boundary |
| --- | --- | --- |
| N01 normal ingestion | 96 files, 1,180 rows represented exactly in each layer | Source dates November 19 and 20 only |
| C01 replacement / R03 recovery | Six files, six new child identities, 81 replacement rows | Audit/isolation Corrected PASS; original native jobs remain Failed |
| C01 original audit preservation | Six prior Success entries archived/superseded; 96 current Success entries after recovery | Preserved first-cycle archive includes the original control snapshots |
| C02 second test replacement | Native PASS: six new IDs, 81 rows, 96 current Success, 12 cumulative Superseded, six current AuditBefore | Both legitimate test cycles accounted for; first-cycle control archive preserved |
| Unrelated data | N01, C01 pre-Step-32, R03, post-negative-test, C02, and N02/N03 Repeat checks passed | No full-database parity claim; unrelated records preserved |
| Gold | N01 passed; C01 failed; R03 recovered; C02 rebuilt/reconciled natively | Independent C02 oracle confirmed 40 exact groups |
| N02/N03 normal repeats | Each scanned 839 items, filtered zero new files, invoked ingestion zero times | Repeat audit/isolation PASS; no additional correction or duplicate load |
| Six controlled negative guards | Zero original customer-row changes; no source files edited | Only captured isolated control fixtures were cleaned; audit/isolation re-passed |

The 81 selected rows are part of the 1,180-row source inventory, not additional files or growth. C02's final independent comparison confirmed 1,180 rows per layer; intermediate delete/reload counts were not treated as the accepted end state.

### 6.1 Six-file before/after movement in the clean native cycle

The following actual identities were selected with **`Status='Success'`** from `cr01-before-correction-audit.json` and `cr01-after-correction-audit.json`; historical Superseded entries were excluded. The before snapshot was **after first-cycle recovery and immediately before C02**, not before the original normal ingestion. The source oracle confirmed the same expected row counts.

| FileName | Rows before -> after | Old current child ID | Final child ID |
| --- | --- | --- | --- |
| `INTRADAY_SUMMARY_20261119_2300_2330.CSV` | 14 -> 14 | `276cc92b-4879-47ce-ae55-0b526027d423` | `e9765b21-abe4-40e1-9529-dee093055c73` |
| `INTRADAY_SUMMARY_20261119_2330_2400.CSV` | 15 -> 15 | `2070a424-ff49-4993-873b-06205a9d661c` | `1d79f63b-5e24-4e7f-9f46-0af2f5dbe5b1` |
| `INTRADAY_SUMMARY_20261120_0000_0030.CSV` | 14 -> 14 | `b616da4e-4944-480a-94a7-044abfe15119` | `dcbf95df-1d48-444c-ac9e-6855a097e11e` |
| `INTRADAY_SUMMARY_20261120_0030_0100.CSV` | 11 -> 11 | `e82a05d8-8940-4830-afb0-f13ad79183ca` | `5d1aa657-5a55-485e-a981-74e311f70793` |
| `INTRADAY_SUMMARY_20261120_0100_0130.CSV` | 12 -> 12 | `4b8a28aa-02d5-43db-9427-071b028d17c2` | `808855cd-3d9b-4969-b807-a283e0ab843f` |
| `INTRADAY_SUMMARY_20261120_0130_0200.CSV` | 15 -> 15 | `491e276f-9c6c-473b-852e-6d828792bc1f` | `7b708f69-ed68-4840-ba9c-457bc2992144` |
| **Total** | **81 -> 81** | Six distinct prior identities | Six distinct replacement identities |

Unchanged row counts are expected because the source versions were immutable: this test proved **replacement lineage without duplication**, not a fabricated financial adjustment. The old current successes became the second set of Superseded entries; each file retained exactly one new current Success.

`cr01-source-oracle.json` recorded the six-file scope as November 19, 23:00 through November 20, 02:00: six files / 81 rows, credit **45016723707.05**, debit **45774223707.02**, net **-757499999.97**, and credit/debit/total transactions **48730 / 45547 / 94277**. The final independent comparison matched those scoped amounts/counts in both Bronze and Silver.

### 6.2 Actual failed-stage, recovery, and native-pass snapshots

| Snapshot | Selected Bronze / Silver | Gold | Checkpoint | Readiness / lock | Source hot cache |
| --- | --- | --- | --- | --- | --- |
| C01 failed at Step 32 | 81 / 81 already reloaded; pre-rebuild checks passed | Absent after drop; backfill creation failed | Original `37da5dc4-8e67-4c65-8739-151125ba02a9`: Running / Reloading | False / original scheduler owner retained | 90 days |
| R03 manual recovery | Same 81 / 81; **no second Copy** | Rebuilt, healthy, exact | Original checkpoint Completed / Verified | True / original owner lock released after verification | Restored to 90 days after temporary 365 |
| C02 corrected native pass | 81 / 81, six final identities above | Rebuilt/reconciled natively | `391be264-d3bd-4c32-80a7-d35fe89a25e1`: Completed / Verified | True / lock released by successful scheduler | Restored to 90 days natively |

The retained C01 lock owner was `1769832f-ebfc-42c1-a06d-3a046c0e3005`. This was a real **post-delete/reload derived-stage failure**, not an injected partial Copy. Historical C01 root/child jobs remain Failed even though R03 recovered their data/checkpoint; C02 is a separate successful native execution.

## 7. Runtime findings and fixes

| Finding | Coordinator-reported action | Verification status |
| --- | --- | --- |
| Scheduler's final activity was named `elease Owned Batch Lock` | Corrected to `Release Owned Batch Lock` after N01 | N01 succeeded despite the typo; corrected native C02 also passed |
| Scheduler activities retained default timeout settings | Aligned remaining scheduler timeouts to two-hour activity / one-hour command guidance | Corrected native C02 passed |
| Gold MV backfill rejected cold historical source extents | Added 365-day cache activity before backfill and original 90-day restoration after reconciliation, Steps 32A/35A | Manual R03 and native C02 both passed |
| Sequential first attempt failed after more than 30 minutes | Preserve ownership and wait for a later eligible normal batch; do not make a 03:00 guarantee | Failed root: 31 minutes 54 seconds, plus separate recovery; not comparable clean-performance data |
| Six-file reload latency | Set `Reload Selected Files` Sequential Off, batch count 6; no Set/Append Variable among its five inner activities | C02 proved six overlapping invocations and passed all checks; root about 11.86 minutes, one sample only |

Permanent deployed activity order: `Guard Unrelated Rows -> Warm Bronze Cache For Backfill -> Rebuild Gold Summary`, then `Guard Gold Summary Values -> Restore Bronze Cache Policy -> Mark Refresh Completed`. Both added KQL activities use Retry `0`, activity timeout `0.02:00:00`, and command timeout `01:00:00`. These fixed values require the verified original 90-day policy and all retained extents within 365 days; the oldest inspected extent was July 6. Document 05 retains Steps 01-36 and inserts 32A/35A without renumbering.

For bounded-parallel reload, each iteration uses its own `item()`, activity metadata, and SQL keyed by refresh RunId plus unique FileName. C02 verified concurrent execution and complete native reconciliation. Customer Step 24 now specifies Sequential Off and batch count 6, without an optional sequential/parallel branch.

The failed C01 correction, successful manual R03 recovery, and successful native C02 correction remain separate results. The activity-name and timeout authoring corrections were not established as causes of the cold-cache failure.

## 8. Cleanup and final end state

| Required check | Latest supplied state |
| --- | --- |
| Automatic schedule / approval defaults | Disabled / false; no production activation performed |
| Schedule configuration | 30-minute interval, SE Asia/Bangkok time zone, enabled false |
| Source files unchanged | C02 independent oracle confirmed all 96 ETag/size/last-modified values unchanged |
| Production clock expression | Restored exactly to `@convertFromUtc(utcNow(),'SE Asia Standard Time')`; actual-clock N03 passed |
| Permanent clock override parameter | None introduced |
| Refresh checkpoint and six replacement identities | First cycle completed/recovered and archived; C02 completed natively with six new identities |
| Lock / readiness immediately after C01 failure | Lock retained; readiness false; subsequently recovered separately |
| Lock absent / readiness true after R03 | Confirmed after verified manual recovery |
| Lock / readiness | Lock absent after successful scheduler chains; final readiness true, owner `3ebe2d47-fdb4-4e85-b8d3-c7f689c6f9ed`, ChangedAtUtc `2026-11-19T19:04:40.2209382Z` |
| Unrelated records preserved | Preserved through C02, all negative tests, and both Repeat comparisons |
| Source cache policy restored after MV recovery | Confirmed 90 days after R03 and natively in C02 |
| Temporary negative-test fixtures | Six guards completed; exact missing-source/sentinel records cleaned after evidence capture and owner-safe release; completed-date fixture reset is separate |
| Pipeline job state | All four pipeline items idle |
| Final current Warehouse state | One Completed/Verified run, six current AuditBefore rows, 96 current Success, 12 cumulative Superseded; no future-date test controls |
| Control counts | RefreshRun 1 / Manifest 6 / AuditBefore 6 / Incomplete 0 |
| Existing pipeline definitions | Normal discovery and single-file ingestion unchanged by independent coordinator comparison |
| Same-date behavior after testing | November 20 already Completed; no automatic same-date correction repeat; retain checkpoint |
| Customer activation approval | Not established by this report |

Keep the schedule disabled until the customer authorizes activation and accepts the stated coverage limits. Never remove an active/different owner's lock merely to resume processing.

**Executed test-fixture reset - not a production retry procedure:** after successful R03 recovery and all six negative guards, the coordinator archived the task-owned Completed run `37da5dc4-8e67-4c65-8739-151125ba02a9` in `cr01-completed-test-fixture-archive.json`, then removed only its **one Run, six File, and six AuditBefore records** to reuse the static correction-date fixture. All `ProcessedFiles` history, source files, and Bronze/Silver data were retained. The inspected archive marks `NotProductionRetry=true`. This was not a bypass of failed/incomplete work and does not authorize deleting a production checkpoint to defeat same-date protection.

## 9. Untested gaps and final verdict

- C01 remains historically Failed. R03 manual recovery and C02 corrected native execution passed separately; no historical job status was changed.
- Post-correction frozen-03:00 routing and restored actual-clock normal routing passed; both Repeat audit/isolation checks passed. A direct same-date child rerun was correctly rejected.
- All six controlled approval/ownership/rerun/concurrency/missing-source/incomplete-checkpoint guards passed. **Partial Copy, audit-write crash, source-version mutation, and visibility/reconciliation fault injection were not executed.** An unchanged-source comparison is not proof of mutation-guard rejection.
- **The actual cold-cache failure after scoped deletion/reload and its retained-owner, no-second-Copy recovery were executed and verified.** They are not untested hypothetical failure paths.
- Bounded parallel-six reload and both cache activities passed C02. Its 11.86-minute root duration is one sample, not a guaranteed future correction duration or 03:00 SLA.
- Raw negative-test Warehouse/KQL control exports and activity evidence are included/referenced above. Normal/correction/recovery/repeat results are identified as coordinator/independent-oracle verified summaries where complete query transcripts are not reproduced.
- Unattended 24/7 operation, real scheduled 02:30 dispatch, and a missed-start/later-same-day catch-up were not exercised. Production-clock restoration itself was verified by N03.
- Source mutation is not part of this test. Any changed-file guard evidence must state the actual coordinator-controlled method and its limits.
- No full-database Bronze/Silver parity claim is made; the known September 17 mismatch remains outside scope.

**Final verdict for the exercised runtime scope: PASS. N01/C02/N02/N03, all six controlled negative guards, F05 safe-stop, and R03 manual recovery passed. C01 remains historically Failed. Unexecuted injection/dispatch cases are listed above; scheduling remains disabled with false approval defaults pending customer activation approval.**

## 10. Read-only SQL/KQL replay queries and captured results

These queries are **read-only** and contain the literal dates, UTC interval, and final refresh RunId. Run the SQL in **RTI-IDM-PRD2 > wh_control_framework > New SQL query**; run the KQL in **eh-rti-deposit > DepositMovement**. Run each KQL block separately.

The SQL blocks are reusable replay statements for the captured Warehouse checks; they were not newly executed by this report's author. Their observed results come from the verified control/audit evidence above. The full KQL oracle query in section 10.2 is the actual executed query retained in the final independent export. Result tables are captured-result excerpts, not generated claims of a new execution.

**Identity distinction:** `391be264-d3bd-4c32-80a7-d35fe89a25e1` is the overall **refresh** RunId. It is not the six source-ingestion `pipeline_runid` values. Read those file-specific identities from `Refresh0230File.ReloadPipelineRunId`.

### 10.1 Warehouse SQL - completed refresh, manifest, and audit

```sql
SELECT RunId,CONVERT(CHAR(10),RefreshDate,23) AS RefreshDate,
       Status,Stage,
       CONVERT(VARCHAR(19),StartedAtUtc,126) AS StartedAtUtc,
       CONVERT(VARCHAR(19),CompletedAtUtc,126) AS CompletedAtUtc
FROM dbo.Refresh0230Run
WHERE RunId='391be264-d3bd-4c32-80a7-d35fe89a25e1'
  AND RefreshDate='2026-11-20'
  AND StartedAtUtc>='2026-11-19T18:46:00'
  AND CompletedAtUtc<'2026-11-19T18:57:00';

SELECT FileName,ReloadRows,ReloadPipelineRunId
FROM dbo.Refresh0230File
WHERE RunId='391be264-d3bd-4c32-80a7-d35fe89a25e1'
ORDER BY FileName;

SELECT COUNT(*) AS PreservedOriginals
FROM dbo.Refresh0230AuditBefore
WHERE RefreshRunId='391be264-d3bd-4c32-80a7-d35fe89a25e1';

SELECT Status,COUNT(*) AS AuditRecords,SUM(RowCount_) AS RowsLogged
FROM dbo.ProcessedFiles
WHERE (FileName LIKE 'INTRADAY[_]SUMMARY[_]20261119[_]%.CSV'
    OR FileName LIKE 'INTRADAY[_]SUMMARY[_]20261120[_]%.CSV')
  AND Status IN ('Success','Superseded-0230')
GROUP BY Status
ORDER BY Status;
```

**Captured completed-run result:**

| RunId | RefreshDate | Status | Stage | StartedAtUtc | CompletedAtUtc |
| --- | --- | --- | --- | --- | --- |
| `391be264-d3bd-4c32-80a7-d35fe89a25e1` | 2026-11-20 | Completed | Verified | 2026-11-19T18:46:47 | 2026-11-19T18:56:34 |

**Six replacement identities/row counts:** the parent audit check matched the manifest, and the final independent KQL oracle retained these same six live file identities and counts:

| FileName | ReloadRows | ReloadPipelineRunId |
| --- | --- | --- |
| `INTRADAY_SUMMARY_20261119_2300_2330.CSV` | 14 | `e9765b21-abe4-40e1-9529-dee093055c73` |
| `INTRADAY_SUMMARY_20261119_2330_2400.CSV` | 15 | `1d79f63b-5e24-4e7f-9f46-0af2f5dbe5b1` |
| `INTRADAY_SUMMARY_20261120_0000_0030.CSV` | 14 | `dcbf95df-1d48-444c-ac9e-6855a097e11e` |
| `INTRADAY_SUMMARY_20261120_0030_0100.CSV` | 11 | `5d1aa657-5a55-485e-a981-74e311f70793` |
| `INTRADAY_SUMMARY_20261120_0100_0130.CSV` | 12 | `808855cd-3d9b-4969-b807-a283e0ab843f` |
| `INTRADAY_SUMMARY_20261120_0130_0200.CSV` | 15 | `7b708f69-ed68-4840-ba9c-457bc2992144` |

`PreservedOriginals=6`; selected replacement rows total **81**.

| Status | AuditRecords | RowsLogged |
| --- | --- | --- |
| Success | 96 | 1180 |
| Superseded-0230 | 12 | 162 |

The 12 Superseded entries reflect two legitimate test cycles, not duplicate current successes. Keep the final Completed checkpoint; do not clear it to repeat the date.

### 10.2 KQL - actual executed final independent oracle query

This query returns scoped business/lineage rows plus three server-count records. It reads only November 19-20 business dates. The independent verifier compared those rows with the immutable source oracle and checked classification, duplicates, replacement rows, and Gold aggregation.

```kql
let scoped_rows = materialize(union
(DepositMovement | where Date >= datetime(2026-11-19) and Date < datetime(2026-11-21) | project Layer="Bronze", Date=tostring(Date), Time=tostring(Time), Product=tostring(Product), Channel=tostring(Channel), Channel_Group=tostring(Channel_Group), Credit_Amount=tostring(Credit_Amount), Debit_Amount=tostring(Debit_Amount), Net_Amount=tostring(Net_Amount), Credit_Transaction=tostring(Credit_Transaction), Debit_Transaction=tostring(Debit_Transaction), Total_Transaction=tostring(Total_Transaction), file_name=tostring(file_name), pipeline_name=tostring(pipeline_name), pipeline_runid=tostring(pipeline_runid), load_ts=tostring(load_ts), ClassificationStatus=""),
(DepositMovementClassified | where Date >= datetime(2026-11-19) and Date < datetime(2026-11-21) | project Layer="Silver", Date=tostring(Date), Time=tostring(Time), Product=tostring(Product), Channel=tostring(Channel), Channel_Group=tostring(Channel_Group), Credit_Amount=tostring(Credit_Amount), Debit_Amount=tostring(Debit_Amount), Net_Amount=tostring(Net_Amount), Credit_Transaction=tostring(Credit_Transaction), Debit_Transaction=tostring(Debit_Transaction), Total_Transaction=tostring(Total_Transaction), file_name=tostring(file_name), pipeline_name=tostring(pipeline_name), pipeline_runid=tostring(pipeline_runid), load_ts=tostring(load_ts), ClassificationStatus=tostring(ClassificationStatus)),
(mv_Summary_Product_Channel_Alert | where Date >= datetime(2026-11-19) and Date < datetime(2026-11-21) | project Layer="Gold", Date=tostring(Date), Time=tostring(Time), Product=tostring(Product), Channel=tostring(Channel), Channel_Group=tostring(Channel_Group), Credit_Amount=tostring(Credit_Amount), Debit_Amount=tostring(Debit_Amount), Net_Amount=tostring(Net_Amount), Credit_Transaction=tostring(Credit_Transaction), Debit_Transaction=tostring(Debit_Transaction), Total_Transaction=tostring(Total_Transaction), file_name="", pipeline_name="", pipeline_runid="", load_ts="", ClassificationStatus=""));
union (scoped_rows | extend RecordKind="row", ServerRows=""),
(print RecordKind="count", Layer="Bronze", ServerRows=tostring(toscalar(scoped_rows | where Layer=="Bronze" | count))),
(print RecordKind="count", Layer="Silver", ServerRows=tostring(toscalar(scoped_rows | where Layer=="Silver" | count))),
(print RecordKind="count", Layer="Gold", ServerRows=tostring(toscalar(scoped_rows | where Layer=="Gold" | count)))
| project RecordKind, Layer, ServerRows, Date, Time, Product, Channel, Channel_Group, Credit_Amount, Debit_Amount, Net_Amount, Credit_Transaction, Debit_Transaction, Total_Transaction, file_name, pipeline_name, pipeline_runid, load_ts, ClassificationStatus
```

**Actual server-count records:** the client received the same counts, so the verifier did not accept a silently truncated result:

| RecordKind | Layer | ServerRows |
| --- | --- | --- |
| count | Bronze | 1180 |
| count | Silver | 1180 |
| count | Gold | 40 |

Computed from those returned rows, the final verifier recorded zero mismatches, zero duplicate excess rows in each data layer, `CLASSIFIED:1180`, 81 matching refreshed rows per layer, exact Gold/source aggregation, and exit code 0. The independent source-version check separately exited 0 with all 96 versions unchanged.

### 10.3 KQL - compact read-only final-state rechecks

The following are replay queries for the captured final-state results in section 5.10:

```kql
union
    (DepositMovement
     | summarize AllRows=count(),
         TestRows=countif(Date>=datetime(2026-11-19T00:00:00)
             and Date<datetime(2026-11-21T00:00:00))
     | extend Layer="Bronze"),
    (DepositMovementClassified
     | summarize AllRows=count(),
         TestRows=countif(Date>=datetime(2026-11-19T00:00:00)
             and Date<datetime(2026-11-21T00:00:00))
     | extend Layer="Silver")
| project Layer,AllRows,TestRows
| order by Layer asc
```

| Layer | AllRows | TestRows |
| --- | --- | --- |
| Bronze | 3015 | 1180 |
| Silver | 3124 | 1180 |

Run this metadata command separately:

```kql
.show materialized-views
| where Name=="mv_Summary_Product_Channel_Alert"
| project Name,IsEnabled,IsHealthy
```

Captured export: `mv_Summary_Product_Channel_Alert`, `IsEnabled=1`, `IsHealthy=1`.

Run this query separately:

```kql
CR01_PublishState
| top 1 by ChangedAtUtc desc
| project IsReady,ChangedAtUtc,Owner
```

Captured result: `IsReady=true`, `ChangedAtUtc=2026-11-19T19:04:40.2209382Z`, `Owner=3ebe2d47-fdb4-4e85-b8d3-c7f689c6f9ed`.

Run this metadata command separately:

```kql
.show table DepositMovement policy caching
```

Captured policy fields: `DataHotSpan.Value="90.00:00:00"` and `IndexHotSpan.Value="90.00:00:00"`.

These queries do not modify data, policy, readiness, or checkpoints. Future legitimate ingestion can change counts; the tables above are the actual November 20 acceptance snapshot, not permanent expected constants.
