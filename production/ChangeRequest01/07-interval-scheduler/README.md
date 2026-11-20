# Modify the Existing Scheduler - Click-by-Click Fabric UI Guide

**Complete [05 - Create the refresh child](../05-data-pipeline/README.md) first. Then follow this document.**

| Item | Setting |
| --- | --- |
| Workspace | `RTI-IDM-PRD2` |
| Existing pipeline to modify | `pl_ingest_DepositMovement_schedule` |
| Existing normal-discovery child, unchanged | `pl_ingest_DepositMovement_trigger_pipeline` |
| Existing single-file ingestion, unchanged | `pl_ingest_DepositMovement` |
| New correction child prepared in document 05 | `pl_refresh_DepositMovement_0230` |
| Scheduled interval | Every 30 minutes, all hours, every day |
| Time zone | Bangkok / ICT, UTC+07:00 |
| Daily correction | First eligible batch at or after 02:30, once for today's correction date |

This document edits the **existing scheduler**, not a new controller. It does not change the internals of normal discovery or one-file ingestion.

> **Before running:** a manual scheduler run can ingest real files or invoke destructive correction. In particular, a run after 02:30 selects correction if today's refresh is not Completed. Keep the schedule disabled until the complete change and supervised tests are approved.
>
> The corrected native refresh, 03:00 normal repeat, and restored actual-clock run passed live tests in PRD2. See section 9.6 and the [single runtime test report](../RUNTIME-TEST-RESULTS.md) for evidence and coverage limits. Production clock conversion is restored; approval defaults remain false and scheduling disabled. Controlled tests do not prove unattended scheduled operation or authorize activation.

### What does "record the original name and expression" mean?

It means **copy the current values into your approved change record or a backup text file before editing**. There is no Fabric button called "Record." You are making a note so you can restore the old configuration if needed.

- **Name:** the selected activity's **General > Name**, not the pipeline name at the top of the page.
- **Expression:** the formula in the If condition's **Activities > Expression** field.
- If the formula starts with `@and(...)` and checks `330` and `2230`, it is the old **03:30-22:30** operating-hours check.
- If the formula is `@equals(1,1)`, it is the earlier **always-True, 24/7-only** change.
- Either is a possible **starting value**. Copy whichever is actually present. Do not paste both, and do not change it during the backup step.
- Later, section 5 replaces that starting formula with the **02:30 correction-routing expression**. `@equals(1,1)` is not the final formula for this document.

### UI navigation used below

| Instruction | What to click |
| --- | --- |
| Main canvas | The outer pipeline canvas showing the scheduler's top-level activities |
| Select an activity | Click the activity card once; its properties open below or beside the canvas |
| General / Settings / Activities | Tabs in the selected activity's properties, not necessarily the top ribbon |
| Open a branch | Click the pencil/edit control on the If condition's True or False branch |
| Return to main canvas | Click the parent pipeline in the canvas breadcrumb/back navigation |
| Add dynamic content | Click the value field, then its Add dynamic content link; enter the formula in the expression builder and click OK |
| On success connection | Hover over the preceding card and drag its green check/success connector to the next card |

Fabric layouts can place a property panel at the bottom or on the right. Use the field names below rather than assuming a fixed pixel position.

## 1. Understand the final flow

```text
Every 30 minutes, 24/7
    |
    v
Freeze Run ICT
    -> Acquire Batch Lock
    -> Lookup Refresh State
    -> Is Refresh Due
          |
          +-- True: Invoke 0230 Refresh
          |           -> new pl_refresh_DepositMovement_0230
          |           -> reload the six files and verify all outputs
          |
          +-- False: Invoke Normal Discovery
                      -> existing discovery
                      -> existing single-file ingestion
    |
    v
Publish Verified Results
    -> Release Owned Batch Lock
```

Every connection is **On success**. Publication and release are connected to the main If activity's success output, not separately inside its branches.

| At the frozen ICT time | Today's correction state | Selected branch |
| --- | --- | --- |
| Before 02:30 | No incomplete refresh | Normal discovery |
| At or after 02:30 | No Completed entry today | 02:30 correction child |
| At or after 02:30 | Completed today | Normal discovery |
| Any time | An incomplete refresh exists | Stop before either branch |
| Any time | Another run holds the lock | Stop at lock acquisition |

The correction branch replaces normal discovery for that batch. **03:00 is a normal batch only if correction has completed successfully.** If correction runs longer, overlapping starts fail to acquire the lock; normal processing waits for a later eligible batch.

## 2. Open the correct item, preserve settings, and pause starts

### 2.1 Open the existing scheduler

1. Open [Microsoft Fabric](https://app.fabric.microsoft.com/) in your browser and sign in with the approved account.
2. Click **Workspaces** in the left navigation.
3. Click **RTI-IDM-PRD2**.
4. Click the workspace search/filter box.
5. Enter `pl_ingest_DepositMovement_schedule`.
6. Click the matching **Data pipeline** item.
7. Check the pipeline name at the top of the editor. It must be `pl_ingest_DepositMovement_schedule`.
8. Do not click **Run**.

If that item is missing, stop and confirm the correct workspace/item with its owner. Do not rename a different pipeline to match.

### 2.2 Copy the current schedule settings, then disable starts

1. On the pipeline's **Home** toolbar, click **Schedule**.
2. If a list of schedules opens, select the existing scheduler schedule and click its **Edit** control.
3. Before changing anything, copy these values into your approved change record:
   - Whether the schedule is currently enabled.
   - Interval/frequency.
   - Time zone.
   - Start and end dates/times.
   - Any day-of-week or daily-hours restrictions.
4. Set **Scheduled run / Enabled** to **Off**. If it is already Off, leave it Off.
5. Click **Apply** or **Save**, whichever the panel displays.
6. Close the Schedule panel and return to the pipeline canvas.

Retain an approved backup of the current definition/settings. If your tenant exposes **Export / Download** for the pipeline, use that existing option; otherwise obtain the owner-approved backup before proceeding. The value-copy steps below explain how to preserve the settings being edited, not a substitute for your required backup policy.

### 2.3 Copy the original If condition's activity name

1. On the main canvas, click the existing **If condition** card once. Its displayed name might be **If In Execution Window**, **If In Execution Window (ICT)**, or an already-renamed equivalent.
2. In that selected activity's properties, click **General**.
3. Find the **Name** field.
4. Click inside the Name field.
5. Press **Ctrl+A**, then **Ctrl+C**. This selects and copies the name; do not type a replacement yet.
6. Open your approved change record or a blank Notepad document.
7. Type `Original If activity name: ` and paste the copied name.
8. Leave the notes open and return to Fabric.

**Checkpoint:** you have copied the name somewhere safe. The name in Fabric is still unchanged.

### 2.4 Copy the original If condition expression

1. Keep the same If condition selected.
2. Click its **Activities** tab.
3. Find the field labelled **Expression**.
4. Click the current formula in that field to open **Pipeline expression builder**.
5. Click inside the expression text box on the right.
6. Press **Ctrl+A**, then **Ctrl+C** to copy the entire formula.
7. Return to the same backup notes.
8. Add a line labelled `Original If expression:` and paste the complete formula below it.
9. Return to Fabric and click **Cancel** in the expression builder. You are only copying the value at this point.
10. Save the backup notes in your approved location. For a new Notepad document, press **Ctrl+S**, choose that location, enter a name such as `scheduler-before-change.txt`, and click **Save**.

Do not clear the expression, click Delete on the activity, or replace its formula during this recording step.

### 2.5 Copy the existing discovery invocation settings

1. On the If condition card, find the **True** branch.
2. Click that branch's **pencil/edit** control to open its inner canvas.
3. Click the existing discovery invocation activity, commonly named **Invoke Trigger Pipeline**.
4. Click **General** and copy its activity name, timeout, and retry settings into the same backup notes.
5. Click **Settings**.
6. Copy the following displayed values into the notes:

   | Field | What to retain |
   | --- | --- |
   | Connection, if shown | Existing approved pipeline-invocation connection name |
   | Workspace | `RTI-IDM-PRD2` |
   | Invoked pipeline | `pl_ingest_DepositMovement_trigger_pipeline` |
   | Wait on completion | Whether it is checked; the final configuration requires On |
   | Parameters | Every parameter name and its exact literal/expression value; record "none" if no parameters are defined |

7. Do not copy passwords, tokens, or connection secrets.
8. Save your notes.
9. Click the parent pipeline in the canvas breadcrumb/back navigation to return to the **main canvas**.

This is a backup of an **invocation activity's settings**. You are not modifying the existing discovery pipeline or its ingestion child.

### 2.6 Let in-flight work finish and coordinate other writers

1. Click **Monitor** in the Fabric left navigation.
2. Open **Pipeline runs**, or the equivalent pipeline-run list in your layout.
3. Filter to this workspace and inspect the scheduler, discovery, and single-file ingestion runs.
4. Confirm existing runs have reached a terminal state before the change proceeds.
5. Have the responsible ingestion operator confirm already-submitted queued ingestion has drained. A terminal pipeline row or stable count alone is not proof that no queued ingestion remains.
6. Coordinate the owners of other schedules, event triggers, manual dispatch, and independent EWI jobs so they cannot bypass this scheduler's lock.
7. Return through **Workspaces > RTI-IDM-PRD2 > pl_ingest_DepositMovement_schedule**.
8. Confirm the schedule is still disabled.

Do not cancel another operator's run or disable unrelated triggers without approval.

## 3. Add the scheduler inputs and frozen-time variable

### 3.1 Add the two approval parameters

1. Click an **empty area** of the main pipeline canvas, not an activity card.
2. In the pipeline properties pane, click **Parameters**.
3. Click **+ New**.
4. Set **Name** to `pMaintenanceApproved`.
5. Set **Type** to **Bool / Boolean**.
6. Set **Default value** to **false**.
7. Click **+ New** again.
8. Set **Name** to `pSourceFinalized`.
9. Set **Type** to **Bool / Boolean**.
10. Set **Default value** to **false**.

If a parameter already exists, verify its name/type/default instead of creating a duplicate. Do not create String parameters containing the word `false`.

### 3.2 Add the frozen-time variable

1. With the blank canvas selected, click **Variables**.
2. Click **+ New**.
3. Set **Name** to `vRunICT`.
4. Set **Type** to **String**.
5. Leave its default value empty.
6. Leave unrelated existing parameters/variables unchanged.
7. Click **Save** on the pipeline toolbar.

The two Boolean parameters are passed to the correction child. They record approved operating preconditions; they do not themselves pause another writer or prove that a source file is immutable.

## 4. Add the three activities before the existing If condition

### Common clicks/settings for new activities

For each new activity:

1. Return to the **main canvas** before adding it.
2. Click the top **Activities** ribbon.
3. Click the activity type named below. If it is hidden, use the activity search or the ribbon's **More / ...** menu.
4. Click the new activity card.
5. Click **General** and enter its exact **Name**.
6. Where the activity exposes execution-policy fields, set the values below.
7. Click **Settings** to configure its connection and value/query/command.

| UI field | Value |
| --- | --- |
| General > Retry | `0` for the new guarded activities |
| General > Timeout | `0.02:00:00`, where exposed |
| KQL connection | Existing KQL Database `DepositMovement` in this workspace |
| KQL command timeout | `01:00:00` |
| Warehouse connection | Existing `wh_control_framework` in this workspace |
| Lookup > Query timeout | `01:00:00` |

Do not invent a timeout/retry field on a simple activity if the UI does not expose it. The normal-discovery invocation retains its recorded settings as specified in section 6.2.

**To connect On success:** hover over the preceding card, locate its **green check/success connector**, and drag that connector to the next card. Do not use the red failure or completion connector.

Paste values containing `@{...}` with **Add dynamic content**, without JSON `value`/`type` wrappers.

### 4.1 `Freeze Run ICT` - Set variable

1. Click **Activities > Set variable**.
2. Click the new card and open **General**.
3. Set **Name** to `Freeze Run ICT`.
4. Click **Settings**.
5. In **Variable**, select `vRunICT`.
6. Click the **Value** field, then **Add dynamic content**.
7. In the expression builder text box, paste exactly:

   ```text
   @convertFromUtc(utcNow(),'SE Asia Standard Time')
   ```

8. Click **OK** in the expression builder.
9. Leave this activity without an incoming dependency: it is the first activity in the final flow.

This captures the clock once. Do not recalculate today's date separately in each later expression.

### 4.2 `Acquire Batch Lock` - KQL

1. Click **Activities > KQL**.
2. Select the new card, click **General**, and set **Name** to `Acquire Batch Lock`.
3. Set **Retry** to `0` and the exposed activity timeout to `0.02:00:00`.
4. On the main canvas, drag **Freeze Run ICT's green On success connector** to `Acquire Batch Lock`.
5. Select `Acquire Batch Lock` again and click **Settings**.
6. Select workspace **RTI-IDM-PRD2** and KQL Database **DepositMovement**, using the existing workspace-data-store connection selector.
7. Click **Command > Add dynamic content** and paste the complete command:

   ```kql
   .set Refresh0230_BatchLock <|
       print Owner="@{pipeline().RunId}",StartedAtUtc=now()
   ```

8. Click **OK** in the expression builder.
9. Set **Command timeout** to `01:00:00`.

The table is created only when the name is free. If it already exists, acquisition fails and this run must stop. **Never change this to `.set-or-replace` or delete another owner's lock.**

The same lock protects the normal and correction branches. Old/manual entry points must be coordinated; the unchanged ingestion child does not acquire it independently.

### 4.3 `Lookup Refresh State` - Lookup

1. Click **Activities > Lookup**.
2. Select the new card, click **General**, and set **Name** to `Lookup Refresh State`.
3. Set **Retry** to `0` and the exposed activity timeout to `0.02:00:00`.
4. Drag **Acquire Batch Lock's green On success connector** to this Lookup card.
5. Select the Lookup card again and click **Settings**.
6. Select the existing **wh_control_framework** Warehouse in **RTI-IDM-PRD2**.
7. Under **Use query**, select **Query**, not Table.
8. Check **First row only**.
9. Click the **Query** field, then **Add dynamic content**, and paste:

   ```sql
   IF EXISTS(SELECT 1 FROM dbo.Refresh0230Run WHERE Status<>'Completed')
       THROW 51307,'An incomplete refresh blocks normal ingestion; recover it first.',1;

   SELECT COUNT(*) AS CompletedToday
   FROM dbo.Refresh0230Run
   WHERE RefreshDate='@{formatDateTime(variables('vRunICT'),'yyyy-MM-dd')}'
     AND Status='Completed';
   ```

10. Click **OK** in the expression builder.
11. Set **Query timeout** to `01:00:00` where exposed.
12. Click **Save**.

The `dbo.Refresh0230Run` table must already exist from document 05. An incomplete correction fails this activity. Do not turn that failure into a successful empty result.

## 5. Change the existing If condition to route correction or normal ingestion

### 5.1 Rename the activity

1. On the **main canvas**, click the original If condition whose name/expression you backed up in section 2.
2. Click its **General** tab.
3. Click the **Name** field.
4. Select the old name and replace it with **`Is Refresh Due`**.
5. Click outside the field to finish editing.

You are renaming the **activity card**, not the pipeline.

### 5.2 Connect the Lookup to the If condition

1. Hover over the `Lookup Refresh State` card.
2. Drag its **green On success connector** to `Is Refresh Due`.
3. Confirm the visible incoming line to `Is Refresh Due` comes from `Lookup Refresh State`.
4. If an old dependency line would let the If condition run without the new prerequisites, select **that line only** and remove it.
5. Do not delete the If condition card or its branch activities.

The intended order is `Freeze Run ICT > Acquire Batch Lock > Lookup Refresh State > Is Refresh Due`. An activity with no incoming dependency can start independently; the If condition must no longer be an independent starting activity.

### 5.3 Replace the expression

1. Click `Is Refresh Due`.
2. Click its **Activities** tab.
3. Click the **Expression** field to open **Pipeline expression builder**.
4. Click inside the expression text box.
5. Press **Ctrl+A** to select the entire old formula.
6. Paste this complete replacement:

   ```text
   @and(
       greaterOrEquals(int(formatDateTime(variables('vRunICT'),'HHmm')),230),
       equals(int(activity('Lookup Refresh State').output.firstRow.CompletedToday),0)
   )
   ```

7. Click **OK** in the expression builder.
8. Click **Save** on the pipeline toolbar.
9. Leave the schedule disabled and do not click Run.

**True** means it is at or after 02:30 and today's correction has not completed. **False** means normal discovery can run.

Do not leave `@equals(1,1)` as the final formula: it always chooses True and has no daily correction routing.

The time test also catches a missed 02:30 start later **on the same ICT date**. It is not a backfill mechanism for entirely missed previous calendar days; such gaps require an approved recovery plan.

## 6. Configure the two branches

### 6.1 True branch - `Invoke 0230 Refresh`

#### Remove only the old invocation activity from True

1. On `Is Refresh Due`, click the **True branch pencil/edit** control.
2. On the inner canvas, click the old normal-discovery invocation.
3. Confirm its settings were copied in section 2.5.
4. Click **Delete** for that selected activity, or press Delete with only that activity selected.
5. If confirmation appears, confirm removal of the **invocation activity only**.
6. Do not delete any workspace pipeline item. Removing this card does not delete `pl_ingest_DepositMovement_trigger_pipeline`.

#### Add the correction invocation

1. While still inside the True branch, click **Activities > Invoke pipeline**.
2. Select the new card and click **General**.
3. Set **Name** to `Invoke 0230 Refresh`.
4. Set **Retry** to `0` and the exposed activity timeout to `0.02:00:00`.
5. Click **Settings**.
6. Select the approved existing **pipeline-invocation connection**. Use the same supported invocation activity/connection variant as your deployment; some layouts call an existing variant Execute pipeline.
7. In **Workspace**, select **RTI-IDM-PRD2**.
8. In **Invoked pipeline / Pipeline**, select **pl_refresh_DepositMovement_0230**.
9. Check **Wait on completion**.
10. In the child **Parameters** list, set each row using **Add dynamic content**:

    | Child parameter row | Formula to paste, then click OK |
    | --- | --- |
    | `pRefreshDate` | `@formatDateTime(variables('vRunICT'),'yyyy-MM-dd')` |
    | `pLockOwner` | `@pipeline().RunId` |
    | `pMaintenanceApproved` | `@pipeline().parameters.pMaintenanceApproved` |
    | `pSourceFinalized` | `@pipeline().parameters.pSourceFinalized` |

11. If the four parameter rows do not appear, recheck the selected target and that document 05's child was saved. Do not invent differently named parameters.
12. Confirm this True branch contains exactly one invocation of the refresh child and no normal-discovery invocation.
13. Click the parent pipeline breadcrumb to return to the main canvas.

The refresh child owns the six-file replacement/verification. It does not release the scheduler's lock or publish readiness by itself.

### 6.2 False branch - `Invoke Normal Discovery`

1. On `Is Refresh Due`, click the **False branch pencil/edit** control.
2. Click **Activities > Invoke pipeline**.
3. Select the new card and click **General**.
4. Set **Name** to `Invoke Normal Discovery`.
5. Restore the **timeout/retry values recorded for the original normal-discovery invocation**.
6. Click **Settings**.
7. Select the original approved invocation connection recorded in section 2.5.
8. In **Workspace**, select **RTI-IDM-PRD2**.
9. In **Invoked pipeline / Pipeline**, select **pl_ingest_DepositMovement_trigger_pipeline**.
10. Check **Wait on completion**.
11. In the child Parameters area, restore each recorded parameter name/value exactly. If the discovery pipeline had no parameters, leave this list empty.
12. Do not add the one-file ingestion pipeline's `pFileName`/`pFolder` parameters to this discovery invocation unless they are actually part of its recorded contract.
13. Confirm False contains exactly one normal-discovery invocation.
14. Click the parent pipeline breadcrumb to return to the main canvas.
15. Click **Save**.

Do not open/edit the discovery pipeline or its one-file ingestion child to carry out these branch changes.

## 7. Publish readiness and release the lock on success only

### 7.1 `Publish Verified Results` - KQL

1. Confirm you are on the **main canvas**, outside both branches.
2. Click **Activities > KQL**.
3. Select the new card and open **General**.
4. Set **Name** to `Publish Verified Results`.
5. Set **Retry** to `0` and the exposed activity timeout to `0.02:00:00`.
6. Hover over the **outer `Is Refresh Due` card**.
7. Drag that card's **green On success connector** to `Publish Verified Results`.
8. Do not connect this from just one inner branch activity.
9. Select `Publish Verified Results`, click **Settings**, and select **DepositMovement** in this workspace.
10. Click **Command > Add dynamic content** and paste:

    ```kql
    .set-or-append CR01_PublishState <|
        print IsReady=true,ChangedAtUtc=now(),Owner="@{pipeline().RunId}"
    ```

11. Click **OK**.
12. Set **Command timeout** to `01:00:00`.

The correction child sets readiness=false before modifying data. This publication happens only after the selected branch succeeds. It affects consumers bound to the serving gate; it does not automatically reconfigure existing reports.

### 7.2 `Release Owned Batch Lock` - KQL

1. On the main canvas, click **Activities > KQL**.
2. Select the new card, open **General**, and set **Name** to `Release Owned Batch Lock`.
3. Set **Retry** to `0` and the exposed activity timeout to `0.02:00:00`.
4. Drag **Publish Verified Results' green On success connector** to this new card.
5. Select `Release Owned Batch Lock`, click **Settings**, and select **DepositMovement**.
6. Paste this literal command into **Command**:

   ```kql
   .drop table Refresh0230_BatchLock
   ```

7. Set **Command timeout** to `01:00:00`.
8. Inspect the incoming connection: it must be **On success**, not On failure or On completion.
9. Click **Validate** on the toolbar.
10. Read any validation message, correct the specific authoring error, and validate again.
11. Click **Save** after validation passes.
12. Keep the schedule disabled.

The lock is released through the successful owner's execution chain. If any earlier step fails after acquisition, the lock remains for controlled recovery. Do not attach automatic deletion of the lock to a failure handler.

## 8. Configure the existing schedule for every 30 minutes, 24/7

1. On the existing scheduler's **Home** toolbar, click **Schedule**.
2. If a schedule list opens, select the existing schedule and click **Edit**.
3. Do not click Add/New schedule when the intended schedule already exists.
4. Set **Repeat / Frequency** to **By the minute**.
5. Set **Interval / Every** to **30** minutes.
6. Set **Time zone** to **UTC+07:00 Bangkok, Hanoi, Jakarta**.
7. Choose the approved start date and a start time aligned to `:00` or `:30`.
8. If day selection is shown, select **every day**, including Saturday and Sunday.
9. If daily start/end-hour restrictions are shown, remove the old business-hours restriction so the schedule covers the full day.
10. Enter the approved schedule end date and record its renewal owner.
11. Leave **Enabled / Scheduled run Off** during validation.
12. Click **Apply / Save**, then close the panel.
13. Confirm with the owner that no separate discovery-child schedule or another polling controller duplicates this responsibility. Keep event/manual dispatch coordinated under the approved change.

The intended cadence is `00:00, 00:30, 01:00, ... 23:00, 23:30` every day. Capacity and failures can delay actual execution; this is not a guaranteed start-time SLA.

## 9. Validate the complete change before activation

### 9.1 Review the saved configuration without running it

1. On the main canvas, check the six top-level activity names against section 1.
2. Follow the visible arrows from left to right/top to bottom and confirm every dependency is On success.
3. Open `Is Refresh Due > True` and verify it contains only `Invoke 0230 Refresh` with the correct target and Wait on completion On.
4. Return to the parent canvas, open False, and verify only `Invoke Normal Discovery` targets the unchanged discovery pipeline.
5. Return to the parent canvas and select the blank background.
6. Click **Parameters** and confirm both approval defaults are still **false**.
7. Click **Schedule** and confirm the 30-minute, all-day Bangkok schedule is still **disabled**; close the panel.
8. Click **Validate** and then **Save** after any authoring issues are resolved.

Checklist:

- [ ] Document 05's new child and required support objects exist.
- [ ] One existing scheduler has the six main activities in the section 1 diagram.
- [ ] Every dependency uses On success.
- [ ] True invokes only correction; False invokes only normal discovery.
- [ ] Both branch invocations wait for completion.
- [ ] No changes were made to existing discovery/ingestion internals.
- [ ] The schedule is 30 minutes, all day/every day, Bangkok time, and remains disabled.
- [ ] The two scheduler approval parameters remain false until testing is explicitly approved.

### 9.2 Start a supervised test and inspect its run

1. Use an **approved isolated environment first**, with correctly rebound connections/tables. Do not point test objects over production.
2. Confirm source access and the exact six finalized files for the date that the scheduler will select.
3. Obtain approval before clicking **Run**. A manual run can load data; it is not a read-only preflight.
4. For an approved correction test, click **Run** and, when its parameter panel is presented, set `pMaintenanceApproved` and `pSourceFinalized` to Boolean **true** before confirming the run.
5. If your layout runs only with saved defaults instead of prompting, do not experiment on production. Have the test owner set the approved isolated-test defaults explicitly; restore false defaults before leaving authoring/testing.
6. Click the confirmation **Run** button if a run panel is shown.
7. Open the pipeline's **Output** tab, or click **Monitor > Pipeline runs**.
8. Click the row matching the run you just started.
9. Click `Freeze Run ICT` and inspect its **Input/Output** details.
10. Inspect `Acquire Batch Lock`, then `Lookup Refresh State`, and confirm the owner/state before interpreting the branch.
11. Open `Is Refresh Due` details and confirm which branch ran.
12. Open that invocation's child-run link, where provided, or locate the corresponding child run in Monitor.
13. Inspect the child's verification activities and data comparisons, not only its top-level status.
14. Copy actual run IDs, UTC/ICT timestamps, results, and approval evidence into your approved test record.

**Date reminder:** a scheduler run uses the actual frozen ICT date. A run after 02:30 with no Completed entry today selects correction, even when started manually. It does not automatically select the example date `2026-11-20` just because that date appears in a verification query. Do not change the production clock or bypass a guard to force a test.

### 9.3 Click through Warehouse verification

1. Click **Workspaces > RTI-IDM-PRD2**.
2. Open **wh_control_framework**.
3. Click **New SQL query**.
4. Paste the following complete SQL block into the query editor.
5. Change **only** the date assigned to `@d` to the approved correction date.
6. Confirm the query is connected to the intended Warehouse.
7. Click **Run** in the SQL editor.

```sql
DECLARE @d DATE='2026-11-20';

SELECT RunId,RefreshDate,BackupSuffix,Status,Stage,StartedAtUtc,CompletedAtUtc
FROM dbo.Refresh0230Run
WHERE RefreshDate=@d;

SELECT f.FileName,f.SourceBytes,f.SourceLastModified,
       f.ReloadRows,f.ReloadPipelineRunId
FROM dbo.Refresh0230File f
JOIN dbo.Refresh0230Run r ON r.RunId=f.RunId
WHERE r.RefreshDate=@d
ORDER BY f.FileName;

SELECT f.FileName,COUNT(a.FileName) AS CurrentSuccessRows
FROM dbo.Refresh0230File f
JOIN dbo.Refresh0230Run r ON r.RunId=f.RunId
LEFT JOIN dbo.ProcessedFiles a
    ON a.FileName=f.FileName AND a.Status='Success'
WHERE r.RefreshDate=@d
GROUP BY f.FileName
ORDER BY f.FileName;
```

8. Open each result grid/tab and verify:
   - One refresh run with Status **Completed**, Stage **Verified**, and a completion timestamp.
   - Six manifest records with valid replacement child run IDs and nonnegative replacement row counts.
   - Exactly one current Success entry per selected filename.
9. Review the child's audit-preservation checks: original selected Success entries must remain as `Superseded-0230` and in `Refresh0230AuditBefore`.

Warehouse audit timestamps are UTC. Source business dates and the scheduler decision use ICT.

### 9.4 Click through KQL verification

1. Return to **Workspaces > RTI-IDM-PRD2**.
2. Open your approved **KQL Queryset**.
3. In its data-source/database selector, choose **eh-rti-deposit > DepositMovement**.
4. Paste the query below into a query tab.
5. Replace the filename with an exact filename from the approved test.
6. Select that query and click **Run**.

```kql
DepositMovement
| where file_name=="INTRADAY_SUMMARY_20261120_0000_0030.CSV"
| summarize Rows=count(),Credit=sum(Credit_Amount),
    Debit=sum(Debit_Amount),Net=sum(Net_Amount)
    by file_name,pipeline_runid
```

7. Retain the result.
8. Change only the first table name from `DepositMovement` to `DepositMovementClassified`, then run that query separately.
9. Compare counts, replacement run identities, and business values with corrected source control totals, not the old version.
10. In another query block, paste the MV health command below.
11. Highlight **that command only** and click **Run**:

```kql
.show materialized-view mv_Summary_Product_Channel_Alert
```

12. Confirm the view is enabled and healthy.
13. In Monitor, also verify the refresh child's full summary-value comparison passed. A healthy view or table statistics alone are not proof that corrected values are right.

### 9.5 Record the required behavior checks

For each approved test, open its Monitor run as in section 9.2 and retain the evidence. Do not mark an unexecuted case as passed.

| Test | Expected outcome |
| --- | --- |
| Normal batch, before 02:30 | False branch runs normal discovery |
| Today's first eligible batch at/after 02:30 | True branch runs correction once |
| Next batch after successful correction | False branch resumes normal discovery |
| Missed 02:30 start, later same-day run | Correction still has priority if not completed |
| Concurrent scheduler start | Second run fails lock acquisition; it never deletes the first owner's lock |
| Missing or changed source | Correction fails; no success-shaped bypass |
| Partial reload, audit error, or reconciliation mismatch | No completion/publication/release; investigate under the retained lock |
| Incomplete refresh at 03:00 | Normal ingestion remains blocked |
| Corrected and unchanged selected files | Each is represented once after replacement |
| Unrelated/daytime records | Unchanged |

A normal discovery run with no new files is a valid no-op, not proof of ingestion. A green run alone is not financial-data acceptance.

### 9.6 Verified live test

**Normal ingestion, corrected native refresh, and both normal-repeat checks passed.** In RTI-IDM-PRD2, scheduler run `5cf71d07-868e-4e9e-8245-52efc7d5fc58` succeeded with both approval parameters true. It ran on **2026-11-19, 17:23:05-17:47:48 UTC** (**2026-11-20, 00:23:05-00:47:48 ICT**), before 02:30. Automatic scheduling remained disabled.

An independent source-to-output comparison passed for the files dated **2026-11-19 and 2026-11-20**:

| Verified item | Result |
| --- | --- |
| Source files and current Success audit entries | 96 files; 96 current Success entries |
| Bronze and Silver rows | 1,180 each: 612 for November 19 and 568 for November 20; exact match to source |
| Silver classification | All test-date rows `CLASSIFIED` |
| Gold summary | 40 groups, exactly matching the test-date source aggregation |
| Credit / debit / net amounts | `620667116563.36` / `654667116563.50` / `-34000000000.14` |
| Credit / debit / total transactions | `704772` / `680414` / `1385186` |
| Control state after the normal run | No refresh registered; batch lock absent; readiness true |
| Unrelated records | Unchanged |

This is **test-date reconciliation**, not full-database Bronze/Silver parity. Final database-wide counts are 3,015 Bronze and 3,124 Silver, preserving the pre-existing September 17 difference of 109 extra Silver rows. Both test-date counts are exactly 1,180; unrelated history was not repaired.

Correction scheduler run `1769832f-ebfc-42c1-a06d-3a046c0e3005` **failed** after child `37da5dc4-8e67-4c65-8739-151125ba02a9` reached `Rebuild Gold Summary`. All six files reloaded and all pre-rebuild source/audit/Silver/unrelated-record checks passed, but MV backfill rejected historical source extents outside the existing 90-day hot-cache policy. The failed root ran for **31 minutes 54 seconds**; this is not a successful correction duration.

The lock was retained, readiness stayed false, and the checkpoint remained Running/Reloading: no automatic publication or release occurred. **Separate manual derived-stage recovery passed without another Copy:** source cache temporarily changed from 90 to 365 days, Gold rebuilt healthy/exact, the 90-day policy restored, and the original checkpoint completed before publication and release. Audit/isolation checks confirmed six new child identities, six archived/superseded originals, 81 replacement rows, 96 current Success entries, and unchanged unrelated records. The original jobs remain **Failed**.

**The clean corrected native refresh then passed:** scheduler `24ab0ed7-01ee-4d61-9b2f-013e0a4f1932` ran on November 19, **18:45:30-18:57:21 UTC** (November 20, **01:45:30-01:57:21 ICT**), about **11.86 minutes**. Its 02:30 decision time was deliberately frozen for the test. Child `391be264-d3bd-4c32-80a7-d35fe89a25e1` ran **18:46:03-18:56:41 UTC**, recording 92 succeeded activities and zero failures. All six file-invocation intervals overlapped; the 365-day cache extension and 90-day restoration passed natively.

Audit/isolation checks passed: six new child identities, 81 replacement rows, 96 current Success entries, 12 cumulative Superseded entries from two legitimate test cycles, and six current `Refresh0230AuditBefore` rows. First-cycle control snapshots were archived before the completed test fixture was reset; they are not expected as current SQL rows. Unrelated Bronze/Silver records were preserved, readiness was true, and no lock remained. Independent comparison again passed at 1,180 exact rows per layer and 40 Gold groups; all 96 source ETag/size/last-modified values were unchanged.

Six controlled negative tests also passed their expected rejection checks: false approval, wrong owner, same-date child rerun, concurrent scheduler acquisition, absent future-date source files, and an isolated incomplete checkpoint. None changed original customer or November 19-20 data.

The frozen-03:00 scheduler run `8d97bb46-6eb3-44ec-9cc8-f92f384372e6` passed on November 19, **18:59:38-19:01:52 UTC**. `CompletedToday=1` selected normal discovery `6c6105d8-c262-4662-96c3-a618f858a8e7`, not another correction.

The production expression was then restored exactly to `@convertFromUtc(utcNow(),'SE Asia Standard Time')`. Actual-clock scheduler `3ebe2d47-fdb4-4e85-b8d3-c7f689c6f9ed` passed **19:03:15-19:04:53 UTC**, with frozen ICT wall-clock value **2026-11-20 02:03:24**, `CompletedToday=1`, and normal discovery `32bbbcab-5ec3-4843-9c4c-5d91cdd0cd04`. The service serializes that shifted clock value with `Z`; do not reinterpret it as a new UTC instant or apply another seven-hour conversion.

Repeat audit/isolation checks passed after both runs. Current date-scoped Warehouse totals are **96 Success / 1,180 logged rows** and **12 Superseded / 162 logged rows**, reflecting two test replacement cycles. The sole current refresh row is `391be264-d3bd-4c32-80a7-d35fe89a25e1`, Completed/Verified; future-date test controls are removed. Approval defaults remain **false** and the schedule remains **disabled**. See the [single runtime test report](../RUNTIME-TEST-RESULTS.md) for detailed evidence and unexecuted fault-injection cases.

Both repeat discovery runs scanned **839 folder items**, returned **zero filtered/new files**, and invoked ingestion **zero times**. Final control counts are one refresh run, six manifest rows, six AuditBefore rows, and zero incomplete runs; all four pipeline items are idle. Gold is enabled/healthy, source hot cache is 90 days, and readiness is true.

The `2026-11-20` correction is already Completed, so it will **not automatically repeat on that date**, including at the real 02:30 start. Do not delete its checkpoint to force a rerun. Existing discovery and single-file ingestion definitions were independently compared and remain unchanged.

Final independent verification after both repeats exited **0**: all 96 source versions were unchanged; both layers matched 1,180 exact business rows; all Silver test rows were CLASSIFIED; duplicate counts were zero; 81 selected rows and 40 test-date Gold groups matched. Final configuration verification confirmed 38 main/60 total refresh activities, parallelism six, the restored production clock, false approval defaults, disabled scheduling, unchanged reused children, and no live jobs. This is **PASS for the executed suite, not production activation approval**. The report includes self-contained evidence excerpts and [runnable read-only SQL/KQL](../RUNTIME-TEST-RESULTS.md#10-read-only-sqlkql-replay-queries-and-captured-results).

**11.86 minutes is one observed sample, not a future 03:00 SLA.** Normal ingestion must still wait for successful correction and a later eligible batch.

## 10. Activate and monitor

1. Confirm the approved environment's behavior checks and data comparisons have passed and customer approval is recorded.
2. Confirm the producer finalization contract and competing-writer/consumer coordination.
3. Open **Workspaces > RTI-IDM-PRD2 > pl_ingest_DepositMovement_schedule**.
4. Click an empty part of its main canvas.
5. Click **Parameters**.
6. Change the approved **default values** of `pMaintenanceApproved` and `pSourceFinalized` to Boolean **true**.
7. Click **Save**.
8. Click **Schedule** and open the existing schedule's settings.
9. Recheck the 30-minute interval, Bangkok time zone, daily coverage, and approved dates.
10. Change **Enabled / Scheduled run** to **On**.
11. Click **Apply / Save** and close the panel.
12. Click **Monitor > Pipeline runs** and observe the next scheduled starts.
13. Open the relevant scheduler and child runs; verify branch selection, successful publication, and final lock release.
14. Verify overnight operation and retain the next 02:30 correction's audit/checkpoint evidence.
15. Assign owners for monitoring, backup cleanup/retention, recovery, and schedule renewal.

A scheduled run uses the **saved defaults**. Setting true values for only one manual run does not update future scheduled values.

## 11. Failure recovery and configuration rollback

### 11.1 Stop new starts without bypassing the lock

1. Open the existing scheduler and click **Schedule**.
2. Open its existing schedule, set **Enabled / Scheduled run Off**, and click **Apply / Save**.
3. Keep competing writers/consumers coordinated. Do not cancel or alter another operator's work without approval.
4. Click **Monitor > Pipeline runs** and open the failed scheduler run.
5. Click the failed activity and inspect its **Error**, **Input**, and **Output** details.
6. Record the scheduler/child run IDs and failed stage.
7. Have the responsible owner inspect the lock Owner, `Refresh0230Run`, six-file manifest, original audit snapshot, source metadata, backup suffix, and child run identities.
8. Follow [document 05, section 13](../05-data-pipeline/README.md#13-validate-through-fabric-and-handle-failures) for partial replacement/recovery. Do not delete the checkpoint or lock to force another run.

If correction completed but publication/release failed, verify that completed state and recover that final stage; do not re-copy the six files.

### 11.2 Restore the pre-change scheduler only after data recovery

1. Obtain rollback approval and keep the schedule disabled.
2. Complete any required data recovery/reconciliation first. Restoring scheduler configuration does **not** undo deleted/reloaded rows.
3. Open the approved pre-change definition/settings and notes captured in section 2.
4. In the scheduler editor, select the If condition, click **General**, and restore its recorded original **Name**.
5. Click **Activities > Expression** to open the expression builder.
6. Select the entire current formula, paste the recorded **original expression**, and click **OK**.
7. Restore the recorded branch placement and invocation settings. In the original documented wrapper, normal discovery was in **True**, not False.
8. Under approval, remove only the newly added scheduler activity cards/dependency lines that were absent from the pre-change definition. Do not delete workspace child pipelines.
9. Click **Validate**, resolve authoring errors, and click **Save**.
10. Restore the original schedule configuration from the notes; enable it only after the owner approves recovery and the restored behavior.
11. Retain rollback evidence.

Never release a lock owned by an active or different run. There is no automatic atomic rollback across the Warehouse, KQL data, and file ingestion.

## Customer acceptance checklist

- [ ] The two documents were followed in order: 05, then 07.
- [ ] Existing discovery and one-file ingestion definitions remain unchanged.
- [ ] The new child replaces only the agreed six unique filenames.
- [ ] The existing scheduler now runs every 30 minutes, 24/7.
- [ ] Correction/normal branches are mutually exclusive under shared ownership.
- [ ] No incomplete correction can be bypassed by normal ingestion.
- [ ] Source, audit, Silver, unrelated rows, and Gold summary reconcile.
- [ ] Required positive/failure-path evidence is recorded truthfully.
- [ ] Customer activation and recovery responsibilities are approved.

**This is the final scheduler configuration for the CR. No additional implementation guide or new controller pipeline is required.**
