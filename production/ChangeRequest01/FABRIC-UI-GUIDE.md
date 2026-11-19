# CR01 - Create the Pipelines Using the Fabric UI

> **For the current RTI-IDM-PRD2 deployment:** use the [revised 02:30 refresh guide](05-data-pipeline/README.md). Its inspected database has Bronze/Silver and the summary MV, but no EWI objects. This older walkthrough and its generated activities describe the earlier 03:30 stored-EWI design. Do not copy its EWI requirements into PRD2.

This is the **portal-first, step-by-step setup guide** for a Fabric operator. No Azure CLI, PowerShell, REST client, or JSON-import feature is required.

You will create/configure the new CR01 items in Fabric, paste SQL/KQL into Fabric editors, configure activities on the pipeline canvas, and verify runs in Monitor.

Use the [UI activity reference](UI-ACTIVITY-REFERENCE.md) alongside this guide. It contains **every activity's exact name, field values, expressions, SQL/KQL text, dependencies, and nested branch placement**, extracted from the delivered definitions. Do not substitute shorter example logic for those values.

> **Do not activate production processing yet.** The previous live validation found ADLS `Forbidden` and 864 threshold rows for 288 distinct keys. See [TEST-RESULTS.md](TEST-RESULTS.md). Those are recorded validation findings, not a fresh connectivity test performed while writing this guide.
>
> The existing pipelines must remain unchanged. In the supplied production workspace, the CR01 pipelines already exist: **open/review those CR01 items instead of creating duplicates or overwriting an original**. The creation steps below explain how to reproduce their configuration in an approved setup.

## What this guide creates

| Item | Purpose |
| --- | --- |
| `qs_CR01_Setup` | A saved KQL Queryset for setup and verification |
| Four `dbo.CR01*` Warehouse tables | Controller ownership, refresh checkpoints, frozen manifests, and audit history |
| `CR01_PublishState` and one core summary function | Hold summary consumers during maintenance; EWI gates are separate optional scripts |
| `pl_CR01_Preflight` | Source, Warehouse, and KQL readiness checks |
| `pl_CR01_DepositMovement_Discover` | New today+yesterday file discovery; invokes the existing ingestion child |
| `pl_CR01_DepositMovement_OvernightRefresh` | Stage, validate, back up, replace, rebuild, and verify overnight data |
| `pl_CR01_DepositMovement_24x7` | New 30-minute controller, without a business-hours restriction |
| Two optional isolated validation pipelines | Repeat the synthetic data-plane and SQL-control tests |

**Reused as-is:** `pl_ingest_DepositMovement`, the existing production Warehouse, Eventhouse/KQL database, source connection where it is approved/working, and the original source/reference tables and functions.

**Not recreated here:** the whole production environment. If the prerequisites below are missing, complete the linked production module first. This guide adds CR01 to the existing design.

## Navigation

1. [Sign in and check prerequisites](#1-sign-in-and-check-prerequisites)
2. [Prepare connections and resolve blockers](#2-prepare-connections-and-resolve-blockers)
3. [Create supporting Warehouse and KQL objects](#3-create-supporting-warehouse-and-kql-objects)
4. [Inspect/capture the materialized-view baseline](#4-inspectcapture-the-materialized-view-baseline)
5. [Learn the common pipeline authoring steps](#5-common-pipeline-authoring-steps)
6. [Create the preflight pipeline](#6-create-the-preflight-pipeline)
7. [Create the discovery pipeline](#7-create-the-discovery-pipeline)
8. [Create the overnight refresh pipeline](#8-create-the-overnight-refresh-pipeline)
9. [Create the 24/7 controller](#9-create-the-247-controller)
10. [Create the disabled schedule](#10-create-the-disabled-30-minute-schedule)
11. [Validate in the UI](#11-validate-in-the-ui)
12. [Approve cutover and operate](#12-approve-cutover-and-operate)

---

## 1. Sign in and check prerequisites

1. Open [Fabric](https://app.fabric.microsoft.com/).
2. Use your profile/account menu to select the approved tenant/account for this deployment.
3. Open **Workspaces > RTI-IDM-PRD**.
4. Confirm the workspace is assigned to the required Fabric capacity.
5. Locate these existing items:

   | Existing item | What to check |
   | --- | --- |
   | `wh_control_framework` | Opens as a Warehouse; contains `dbo.ProcessedFiles` |
   | `eh-rti-deposit` | Opens as an Eventhouse |
   | `DepositMovement` | KQL database inside that Eventhouse |
   | `pl_ingest_DepositMovement` | Existing single-file ingestion pipeline; do not edit it |
   | `pl_ingest_DepositMovement_trigger_pipeline` | Existing discovery item; do not edit it |

6. In the KQL database explorer, confirm these source objects exist:

   - `DepositMovement` - Bronze.
   - `DepositMovementClassified` - Silver.
   - `ThailandFinancialInstitutionHoliday`, `OperatingWindowsTimes`, `EWI_AlertThreshold`.
   - `Transform_DepositMovementClassified()` and `Gold_EarlyWarning()`.
   - `DepositMovementEarlyWarning` only for this older persisted-table workflow; it is not required by the revised function-based 02:30 guide.
   - The two MVs listed in section 4.

7. Confirm your permissions cover creating pipelines, reading the source, running Warehouse scripts, and executing the approved KQL management commands.

**If something is missing:** use [production prerequisites](../00-prerequisites/README.md), [Bronze setup](../01-eventhouse-kql-tables/README.md), [Warehouse control setup](../02-warehouse-control/README.md), [Silver setup](../03-silver-deposit-movement-classified/README.md), and [Gold setup](../04-gold-summary-table/README.md). Do not point CR01 at similarly named items in another workspace.

## 2. Prepare connections and resolve blockers

### 2.1 Review the existing source connection

1. In Fabric, open **Settings > Manage connections and gateways**.
2. Find the ADLS Gen2 connection for `mockadlsidimdprd001`.
3. Review its server/path and authentication settings without saving changes to the existing connection.
4. Confirm the intended source:

   | Field | Value |
   | --- | --- |
   | Account URL | `https://mockadlsidimdprd001.dfs.core.windows.net` |
   | Container / file system | `inflowoutflow` |
   | Directory | `inbound/statement` |
   | Files | `INTRADAY_SUMMARY_YYYYMMDD_HHMM_HHMM.CSV` |
   | Delimiter | Pipe, `|` |
   | First row is header | Off |

5. If the connection is unavailable, expired, or forbidden, obtain an **approved working connection** from the storage/network owner. Select that connection in the **new CR01 activities only**.
6. Do not enable public storage access or broaden firewall rules merely to complete the walkthrough. A private-access/network change requires its own approval.

The connection screen alone is not sufficient proof of access. Section 6 tests an actual directory-listing activity inside Fabric.

### 2.2 Verify the threshold reference

1. From the workspace, select **New item > KQL Queryset**. Some layouts show **+ New** instead.
2. Name it `qs_CR01_Setup`.
3. Add/select the data source **RTI-IDM-PRD > eh-rti-deposit > DepositMovement**.
4. Confirm the editor's active database is `DepositMovement`.
5. Paste and run:

   ```kql
   EWI_AlertThreshold
   | summarize Copies=count() by Scope,IndicatorKey,WindowCode,DayType
   | where Copies!=1
   ```

6. A duplicate-key result is a **stop condition**, not permission to delete reference rows.
7. Have the reference owner review/back up/correct the source configuration. The complete contract requires **288 unique expected keys**; the pipeline also detects missing/unexpected keys.
8. Save the Queryset.

In the recorded live validation, each key had three identical copies. CR01 deliberately does not fix that production reference automatically.

## 3. Create supporting Warehouse and KQL objects

### 3.1 Create the four new Warehouse tables

1. Return to the workspace and open **wh_control_framework**.
2. Select **New SQL query**.
3. Open [01-create-CR01-control.sql](sql/01-create-CR01-control.sql) from this documentation.
4. Copy its SQL into the Warehouse query editor.
5. Verify the selected Warehouse is `wh_control_framework`.
6. Select **Run**.
7. Refresh the object explorer. Confirm:

   - `dbo.CR01ControllerRun`.
   - `dbo.CR01RefreshRun`.
   - `dbo.CR01RefreshManifest`.
   - `dbo.CR01AuditBefore`.

8. Run this query to verify the new schema:

   ```sql
   SELECT TABLE_NAME,COLUMN_NAME,DATA_TYPE,DATETIME_PRECISION
   FROM INFORMATION_SCHEMA.COLUMNS
   WHERE TABLE_SCHEMA='dbo'
     AND TABLE_NAME IN (
       'CR01ControllerRun','CR01RefreshRun',
       'CR01RefreshManifest','CR01AuditBefore'
     )
   ORDER BY TABLE_NAME,ORDINAL_POSITION;
   ```

9. Confirm `SourceLastModified` uses `DATETIME2(6)`. Do not change it to precision 7.
10. Leave the existing `dbo.ProcessedFiles` and logging procedure unchanged.

The controller also contains an idempotent initialization activity for these tables. Their existence is not a mutex and does not authorize a refresh.

### 3.2 Create the new serving objects

1. Open `qs_CR01_Setup`, bound to the `DepositMovement` KQL database.
2. Open [01-create-CR01-serving-gates.kql](kql/01-create-CR01-serving-gates.kql).
3. Copy the first `.create-merge table` command into the query editor.
4. Highlight **that command only**, then select **Run**.
5. Run the complete `.create-or-alter function ... { ... }` block separately. The core file has two management commands: one table and one summary function.
6. Refresh the database explorer and confirm:

   | Object | Kind |
   | --- | --- |
   | `CR01_PublishState` | Table |
   | `CR01_Summary_Product_Channel_Alert` | Function |

   Only if the corresponding EWI object is actually deployed, run [the optional query-function gate](kql/03-create-CR01-function-serving-gate.kql) for `CR01_EarlyWarning_Latest` or [the optional stored-table gate](kql/02-create-CR01-stored-serving-gate.kql) for `CR01_EarlyWarning_StoredLatest`. Skip both in RTI-IDM-PRD2.

7. Run each function separately to confirm it compiles:

   ```kql
   CR01_Summary_Product_Channel_Alert()
   | summarize Rows=count()
   ```

   Before a verified controller run publishes readiness, these gates intentionally return no rows. **Do not insert an `IsReady=true` record to bypass the cutover controls.**

### 3.3 Do not manually pre-create runtime staging/backup tables

Date-specific `CR01_Stage_*`, `CR01_Backup*`, and unrelated-row snapshot tables are created by the refresh activities. The controller creates its lock when it starts.

Do not pre-create `CR01_ControllerLock`: its create-only behavior is the concurrency mechanism. Do not delete it to force a failed job to restart.

## 4. Inspect/capture the materialized-view baseline

### 4.1 Understand the JSON file

[CR01-materialized-view-baseline.json](pipeline/CR01-materialized-view-baseline.json) is a **metadata snapshot**, not a Fabric pipeline, table-ingestion file, or separate Fabric item.

There is no need to import it into Eventhouse. Its `Query`, source table, folder, and policies describe the existing MVs that CR01 must reconstruct after replacement. Fields such as `LastRun` and `MaterializedTo` are observations, not settings to paste into a creation dialog.

### 4.2 Read the definitions through the UI

1. In `qs_CR01_Setup`, run:

   ```kql
   .show materialized-views
   | where SourceTable in ("DepositMovement","DepositMovementClassified")
   | project Name,SourceTable,Query,Folder,DocString,
       IsEnabled,IsHealthy,AutoUpdateSchema,Lookback
   ```

2. Confirm exactly these two reviewed views:

   | View | Source |
   | --- | --- |
   | `mv_Summary_Product_Channel_Alert` | `DepositMovement` |
   | `mv_EarlyWarning_Base` | `DepositMovementClassified` |

3. Expand/copy the complete `Query` cell for each view. Do not capture only the visible truncated text.
4. Run each of the following **separately** and retain its full policy value:

   ```kql
   .show materialized-view mv_Summary_Product_Channel_Alert policy retention
   ```

   ```kql
   .show materialized-view mv_Summary_Product_Channel_Alert policy caching
   ```

   ```kql
   .show materialized-view mv_EarlyWarning_Base policy retention
   ```

   ```kql
   .show materialized-view mv_EarlyWarning_Base policy caching
   ```

5. Compare the results with the supplied baseline:

   - Both explicit retention policies were `null`.
   - Summary MV explicit caching was `null`.
   - Early-warning-base caching was 90 days for data and indexes.
   - Both views were enabled, with no configured lookback and automatic schema updates off.

6. Save these verification queries in the Queryset. Retain the approved result capture using the result grid's copy/export controls available in your tenant.

`"null"` in the snapshot means there was **no explicit policy at that level**. It does not mean zero retention or an instruction to erase a policy.

### 4.3 Keep the baseline and checks aligned

The activity reference contains the reviewed definitions and encoded comparison values. If the live query, schema, function, or policy differs, **stop and review that difference**. Do not alter the comparison simply to make the guard pass.

For an approved MV-definition update, this UI query exposes the current encoded query without using a shell:

```kql
.show materialized-views
| where Name in ("mv_Summary_Product_Channel_Alert","mv_EarlyWarning_Base")
| project Name,SourceTable,Query,ExpectedQueryBase64=base64_encode_tostring(Query)
```

An engineer must review and keep the corresponding `Check Existing Gold Definitions`, reconstruction, and policy activities consistent. Query whitespace can affect an exact definition comparison. Timestamp-only snapshot changes are not a reason to change a definition guard.

**Missing views in a new, approved database:** see [Appendix A](#appendix-a-create-the-two-mvs-only-if-genuinely-missing). Do not drop/recreate existing production views during UI authoring.

## 5. Common pipeline authoring steps

These steps apply to every pipeline in sections 6-9.

### 5.1 Create a blank pipeline

1. In the workspace, select **New item > Data pipeline**.
2. Enter the exact new CR01 name.
3. Open its canvas and select **Save**.
4. Never choose an original pipeline as the destination of these changes.

If that CR01 item already exists in this workspace, open it for review instead of creating a second item.

### 5.2 Add parameters and variables

1. Select the blank canvas background.
2. Open the **Parameters** pane/tab.
3. Select **+ New** for every parameter in the corresponding activity-reference section.
4. Set its exact name, type, and default.
5. Open **Variables**, add each variable, and set its type/default as listed.
6. Save.

| Reference term | UI meaning |
| --- | --- |
| `string` / `String` | String |
| `bool` | Bool / Boolean |
| `int` | Int/integer |
| `false` | Off/unchecked |
| `true` | On/checked |
| `retry` | General > Retry |
| `retryIntervalInSeconds` | Retry interval in seconds |
| `firstRowOnly` | First row only checkbox |

Do not enter the word `false` into a String parameter that should have Boolean type.

### 5.3 Add and connect activities

1. Select the required activity from the **Activities** ribbon/search.
2. In **General**, set its **Name exactly** as listed.
3. Set timeout, retry, and secure-input/output fields where specified.
4. Open **Settings** and the source/destination tabs where applicable.
5. Enter the exact values from the [activity reference](UI-ACTIVITY-REFERENCE.md).
6. For a `Succeeded` dependency, connect the preceding activity's **green On success** connector.
7. Do not wire a later financial step to **On completion**; that would allow it to run after a failure.

### 5.4 Paste expressions, SQL, and KQL correctly

- When the reference says **Add dynamic content**, use that control and paste only the displayed value. Do not paste JSON `{"value":...,"type":"Expression"}` wrappers.
- Preserve `@{...}` embedded expressions in a complete SQL/KQL text block. Use the activity's dynamic-content editor for blocks marked as expressions.
- Put literal long KQL function definitions in the plain **Command** editor. Do not turn them into one enormous expression.
- A Script block's SQL input `@ControllerRunId` is a **bound SQL parameter**, not a pipeline string interpolation. Configure its input parameter separately.
- The pipeline editor resolves `pipeline()`, `activity()`, `item()`, and `variables()`. The KQL Queryset editor does not: do not run dynamic activity snippets directly there.

### 5.5 Add nested branches/loops

| Activity | Where its inner activities go |
| --- | --- |
| If condition | Open its True or False branch canvas, as specified |
| ForEach | Open its Activities canvas; set Sequential and Batch count |
| Until | Open its Activities canvas; set the exit expression and timeout |

The activity reference identifies the exact canvas path for every child. Leave explicitly empty branches empty.

### 5.6 Bind resources by name

Choose the existing Warehouse/KQL database/connection and invoked pipeline using the UI selectors. **Do not type the old recorded item GUIDs when reproducing this in another approved workspace.**

For **Invoke pipeline**, select the correct target, check **Wait on completion**, and populate all listed child parameters. A pipeline-to-pipeline connection may be required by the UI.

## 6. Create the preflight pipeline

Full fields: [reference section 1](UI-ACTIVITY-REFERENCE.md#1-pl_cr01_preflight).

1. Create/open `pl_CR01_Preflight`.
2. It has no pipeline parameters or variables.
3. Add these three independent activities:

   | Activity | UI type | Configuration |
   | --- | --- | --- |
   | `List Source Files Read Only` | Get Metadata | ADLS directory; no file name; field list `childItems` |
   | `Read Audit Baseline` | Lookup | Warehouse count query; First row only on |
   | `Read KQL Baseline` | KQL | `.show table DepositMovement schema as json` |

4. Do not connect a success chain between them; each has no incoming dependency.
5. Save, then select **Run**.
6. Open **Output**, or **Monitor > Pipeline runs**, and select the run.
7. Inspect each activity's status/output.
8. Require all three to succeed before real-CSV acceptance testing.

A KQL activity executes management commands; retain the leading dot in the supplied schema command. Do not replace it with an arbitrary `print` query.

## 7. Create the discovery pipeline

Full fields/expressions: [reference section 2](UI-ACTIVITY-REFERENCE.md#2-pl_cr01_depositmovement_discover).

1. Create/open `pl_CR01_DepositMovement_Discover`.
2. Add String parameters `pControllerRunId` and `pRunICT`; their values come from the controller.
3. Add String variables `vToday` and `vYesterday`.
4. Build the top-level success chain:

   ```text
   Validate Controller Owner
       -> Set vToday -> Set vYesterday
       -> Get Metadata List Files
       -> Lookup Processed Files
       -> Filter New Files
       -> ForEach New Files
   ```

5. For `Validate Controller Owner`:
   - Choose **Script** and Warehouse `wh_control_framework`.
   - Add the NonQuery text from the reference.
   - Add its **Input / String** SQL parameter `ControllerRunId`, bound to the pipeline parameter as shown.
6. Configure both date-prefix variables from the passed `pRunICT`, not two separate clocks.
7. In `Get Metadata List Files`, choose the approved ADLS connection and directory; leave file name empty and request `childItems`.
8. In `Lookup Processed Files`, paste the today+yesterday success query and leave **First row only on**.
9. In `Filter New Files`, paste the exact Items and Condition expressions. They reject folders, restrict the date prefixes/CSV suffix, and exclude successful filenames.
10. In `ForEach New Files`, set:
    - Items from the Filter output.
    - **Sequential off**.
    - **Batch count 10**.
11. Inside the ForEach, add `Invoke Ingestion`:
    - Invoked pipeline: **existing `pl_ingest_DepositMovement`**.
    - **Wait on completion on**.
    - Retry `0`.
    - Pass all listed values, including the complete `Subject`.
12. Save. Do not give this internal pipeline its own schedule or run it without an active controller owner.

## 8. Create the overnight refresh pipeline

Full, ordered activity-by-activity instructions: [reference section 3](UI-ACTIVITY-REFERENCE.md#3-pl_cr01_depositmovement_overnightrefresh).

This pipeline has **79 top-level activities plus nested activities**. Use the reference checklist in order; the phase table below is a walkthrough, not a substitute for the exact commands.

### 8.1 Create the item and inputs

1. Create/open `pl_CR01_DepositMovement_OvernightRefresh`.
2. Add:

   | Parameter | Type | Default / source |
   | --- | --- | --- |
   | `pRefreshDate` | String | Supplied by controller |
   | `pControllerRunId` | String | Supplied by controller |
   | `pSourceIntervalMinutes` | Int | `15`, unless the approved feed is 30-minute |
   | `pSourceFinalized` | Boolean | `false` |

3. Add String variables `vRefreshDate`, `vLoadTs`.
4. Save.

### 8.2 Build the phases, in order

| Reference top-level positions | Phase | UI work |
| --- | --- | --- |
| 1-4 | Approval and frozen values | Add the finalization If condition/Fail branch, date/load-time variables, and bound owner Script |
| 5-12 | Schema/reference guards | Add KQL checks and If condition/Fail guards; preserve exact expressions |
| 13-17 | Frozen manifest/staging schema | Add manifest Script/Lookups and KQL staging/mapping commands |
| 18-20 | Stage and wait | Add parallel staging ForEach, staged-manifest Lookup, and Until readiness loop |
| 21-30 | Source/classification checks | Add the exact source contract, transformation/version/calendar preview, source-version ForEach, and loaded-file coverage guards |
| 31-41 | Review Gold definitions/policies | Add KQL metadata reads and mismatch guards |
| 42-47 | Backups and visibility hold | Add scoped backups, unrelated-row fingerprints, and serving hold |
| 48-56 | Replace the exact scope | Add MV drops, literal filename deletes, empty-scope guard, audit Script, snapshot promotion, and Until reconciliation |
| 57-70 | Verify source and rebuild MVs | Add classification/unrelated-row guards, both MV reconstructions, cache restoration, reconciliation, and health loop |
| 71-79 | Rebuild EWI and commit | Add rank checks, both-date EWI replacement, grain/value guards, and the final SQL commit |

### 8.3 Configure `Stage All Overnight Files`

1. Add **ForEach**, name it exactly, use the reference Items expression, Sequential off, Batch count `10`.
2. Open its inner Activities canvas.
3. Add `Read Source Version` (Get Metadata):
   - Approved ADLS connection.
   - File name from `item().FileName`.
   - Field list **size** and **lastModified**.
4. Connect its success output to `Stage Source File` (Copy data).
5. Configure the Copy source:

   | Setting | Value |
   | --- | --- |
   | File format | DelimitedText |
   | Delimiter | `|` |
   | First row as header | Off |
   | Directory | `inbound/statement` |
   | File name | Dynamic expression from the reference |
   | Additional columns | Exactly the four lineage columns in the reference |
   | Retry | `0` |

6. Configure the destination:
   - Workspace KQL Database `DepositMovement`.
   - Table: the **dynamic date-specific staging table expression**, not Bronze.
   - Ingestion mapping: `DepositMovement_mapping`.
   - Leave explicit Mapping-tab column mappings empty.
7. Do not import a dynamic schema at design time or select an unrelated existing table just to satisfy the dropdown.
8. Add `Capture Source Control Totals` (Script) on Copy success, using the supplied SQL.
9. Return to the outer canvas.

### 8.4 Configure loops and failure branches carefully

1. `Wait For Queryable Staging`, `Wait For Bronze And Silver`, and `Wait For Healthy Gold Views` are **Until** activities.
2. Add their inner KQL/Wait activities on their own canvases.
3. Preserve the exact exit conditions and the Wait time of 5 seconds.
4. Most `Validate ...` If conditions mean **a problem exists** when the expression is true:
   - True branch: the supplied **Fail** activity.
   - False branch: empty.
5. Do not reverse those branches.
6. Correctness checks inspect nonempty synchronous command output, **not `.show table` row statistics**.

### 8.5 Save without executing replacement

1. Save and inspect every success connection.
2. Check all nested activities using the reference's canvas paths.
3. Confirm `pSourceFinalized` remains false.
4. Do not run individual delete, promotion, or commit activities from the canvas/query editor.
5. This internal pipeline receives ownership and the due date from the controller. It is not independently scheduled.

## 9. Create the 24/7 controller

Full fields: [reference section 4](UI-ACTIVITY-REFERENCE.md#4-pl_cr01_depositmovement_24x7).

### 9.1 Parameters and variables

1. Create/open `pl_CR01_DepositMovement_24x7`.
2. Add these parameters:

   | Name | Type | Safe default |
   | --- | --- | --- |
   | `pEnableProcessing` | Boolean | `false` |
   | `pCutoverConfirmed` | Boolean | `false` |
   | `pFirstRefreshDate` | String | Empty |
   | `pSourceFinalized` | Boolean | `false` |
   | `pSourceIntervalMinutes` | Int | `15` |

3. Add String variables `vRunICT`, `vFirstRefreshDate`.
4. Do **not** add the old `If In Execution Window (ICT)` activity. CR01 has no 03:30-22:30 ingestion-hours gate.

### 9.2 Build the controller success chain

Add all 16 top-level activities in the order shown in the reference:

```text
Require Approved Cutover -> Freeze Run ICT
    -> Require First Refresh Date -> Normalize First Refresh Date
    -> Acquire Global Controller Lock
    -> Initialize CR01 Control Tables -> Register Controller Owner
    -> Initialize Serving State
    -> Compute / Validate Threshold Reference Keys
    -> Finish All Due Refreshes
    -> Invoke Normal Discovery -> Append Normal EWI Buckets
    -> Publish Verified Data -> Complete Controller Owner
    -> Release Owned Controller Lock
```

1. For the two approval/date If conditions, place the supplied Fail activity on the **True** problem branch.
2. The lock is created by the supplied KQL `.set` command. Do not replace it with a table-exists check.
3. The SQL initialization Script uses the same four-table schema created in section 3.
4. Keep every failure path fail-closed. Do not connect lock release to On completion.

### 9.3 Build `Finish All Due Refreshes`

1. Add **Until**, set its name, exit expression, and timeout exactly.
2. Inside it, add `Lookup Next Refresh`.
3. Use the Warehouse query from the reference and **First row only on**.
4. Add `Run Due Refresh` (If condition) on Lookup success.
5. In that If condition's **True** branch, add `Invoke Overnight Refresh`:
   - Select the **new `pl_CR01_DepositMovement_OvernightRefresh`** by name.
   - Check **Wait on completion**.
   - Set Retry `0`.
   - Map all four child parameters as listed.
6. Leave its False branch empty.
7. Return to the outer canvas.

This loop finishes due dates oldest first. It does not refresh only when the clock equals exactly 03:30.

### 9.4 Add normal discovery and publication

1. Configure `Invoke Normal Discovery` to select the **new `pl_CR01_DepositMovement_Discover`**.
2. Check Wait on completion and map controller ownership/frozen ICT time.
3. Copy the full normal EWI append command, including the physical-schema projection.
4. Publish readiness only on success, then complete ownership and release the lock.
5. Save with both activation flags false.

## 10. Create the disabled 30-minute schedule

Only the **new controller** gets a schedule.

1. Open `pl_CR01_DepositMovement_24x7`.
2. On the pipeline toolbar, select **Schedule**.
3. Configure:

   | UI setting | Value |
   | --- | --- |
   | Repeat | By the minute |
   | Interval | `30` |
   | Time zone | Bangkok/Hanoi/Jakarta, UTC+07:00 (`SE Asia Standard Time`) |
   | Start time | An approved `:00` or `:30` boundary |
   | Days/hours | All days, full day; no business-hours restriction |
   | End date | Approved expiry with a renewal owner |
   | Enabled / scheduled run | **Off during setup** |

4. Save/apply the configuration.
5. If your UI only saves after enabling, **do not enable it to complete this step**. Record the values and create/enable it later during approved cutover.
6. In the supplied workspace a disabled schedule already exists. Review it rather than adding another.
7. Confirm neither internal child pipeline has its own schedule.

The supplied schedule expires on 2027-11-18; use the approved renewal policy, not an assumption that scheduling lasts forever.

## 11. Validate in the UI

### 11.1 Confirm disabled guards first

1. Run the new controller with its safe defaults.
2. In **Monitor > Pipeline runs**, open the run.
3. An expected `CR01_GUARD` failure at `Require Approved Cutover` confirms it did not start processing. Do not call this a successful ingestion test.
4. The internal refresh without producer finalization must also reject execution.
5. Do not set production flags true simply to produce a green run.

### 11.2 Inspect and/or create isolated test pipelines

The provided workspace already contains the two test items. To reproduce them using the UI, follow:

- [Reference section 5: SQL control test](UI-ACTIVITY-REFERENCE.md#5-pl_cr01_sqlcontroltest).
- [Reference section 6: isolated data-plane test](UI-ACTIVITY-REFERENCE.md#6-pl_cr01_isolatedrefreshtest).

For each:

1. Create/open the **test** item, not an original or production processing item.
2. Enter the complete parameters/variables/activity tree from its reference section.
3. Preserve the supplied `CR01Test_*` namespace consistently. Check that the exact namespace is empty before a fresh test; do not reuse an occupied namespace.
4. Do not replace that prefix with production object names.
5. Save and run the complete pipeline.
6. Inspect Output/Monitor, including the deliberately tested negative-verifier condition.

The data-plane fixture copies distinct full threshold rows into its **isolated** reference. It does not repair production reference data.

### 11.3 Check exact data, not only the green run status

In the KQL Queryset, use the **exact test namespace shown in your test activity commands**:

```kql
// Replace the placeholder with the complete recorded test table name.
['<test-prefix>DepositMovement']
| summarize Rows=count(),NetBaht=sum(Net_Amount)
```

Expected accepted fixture:

| Check | Expected |
| --- | --- |
| Test Bronze / Silver rows | 3 / 3 |
| Test Bronze net | 195 Baht |
| Stored test EWI rows | 72 |
| Test threshold rows | 288 |
| Duplicate test EWI object/bucket keys | 0 |
| Both test MVs | Healthy and reconciled with source |
| Unrelated daytime source row | Unchanged |

Use `summarize count()` on the actual tables; do not use cached table statistics as an acceptance count.

For the SQL control test, inspect `Read SQL Test Results`:

- `Successful = 20` for the supplied 15-minute test.
- `Superseded = 1`, `Archived = 1`, `Completed = 1`.
- Its final cleanup activity removes only its owned test tables.

See [the test report](TEST-RESULTS.md) for the actual accepted run IDs and limitations. Those runs validate the deployed native activities; they are **not a claim that this new click-by-click walkthrough was manually replayed in the portal**.

### 11.4 Clean up through the query editors

1. Confirm the test job is terminal and no other user/job uses its exact namespace.
2. List the corresponding test tables, functions, and MVs in the KQL explorer.
3. Use the [exact test cleanup commands](UI-ACTIVITY-REFERENCE.md#test-cleanup-through-the-fabric-editors) in the companion reference.
4. Verify every name before running a drop command; skip objects that were never created.
5. Never clear or drop the original production tables, reference table, or MVs.
6. If SQL cleanup did not run, use the exact test-only SQL cleanup block from the reference.
7. Keep the validation pipeline and its run history if required; do not delete the original production pipelines.

## 12. Approve cutover and operate

Authoring the items does not authorize production replacement.

Before enabling:

1. Resolve the storage/network connection and threshold-reference blockers.
2. Obtain approval for the producer finalization SLA, first refresh date, file interval, data-volume SLA, and recovery procedure.
3. Coordinate old schedules/event dispatch and independent EWI writers. Disable old dispatch **at trigger/schedule level** only under the approved change; leave original pipeline definitions unchanged.
4. Drain existing/queued ingestion and EWI jobs using Monitor.
5. Coordinate consumers:
   - Function EWI, only if deployed: `CR01_EarlyWarning_Latest()` from the optional script.
   - Stored EWI, only if deployed: `CR01_EarlyWarning_StoredLatest()` from the optional script.
   - Maintenance-safe summary query: `CR01_Summary_Product_Channel_Alert()`.
6. Update the approved consumer source in its Queryset/model/Activator authoring surface. If a report requires an owner-managed source change outside Fabric's browser editor, obtain that change before cutover; do not assume creating the gate automatically rewires a report.
7. On the **new controller only**, set approved defaults:
   - `pEnableProcessing = true`.
   - `pCutoverConfirmed = true`.
   - `pFirstRefreshDate =` approved `yyyy-MM-dd`.
   - `pSourceFinalized = true` only under the producer contract.
   - `pSourceIntervalMinutes = 15` or `30` as confirmed.
8. Run one supervised controller cycle and inspect all child runs and reconciliations.
9. Enable the single new 30-minute schedule only after acceptance.
10. Monitor owner/checkpoint completion, missing files, source freshness, classification, MV health, EWI uniqueness/reconciliation, and publication readiness.

On failure, **do not delete the lock and rerun blindly**. Keep writers/consumers coordinated and follow [the recovery and rollback procedure](README.md#7-failure-recovery-and-rollback).

---

## Appendix A. Create the two MVs only if genuinely missing

This appendix is for an approved new/restored database whose Bronze/Silver dependencies already exist. **It is not a drop/recreate instruction for the current live database.**

1. In `qs_CR01_Setup`, list current views:

   ```kql
   .show materialized-views
   | where Name in ("mv_Summary_Product_Channel_Alert","mv_EarlyWarning_Base")
   ```

2. If a view already exists, compare its definition; do not drop it to resolve an "already exists" message.
3. If the summary view is absent, open [the existing summary creation script](../04-gold-summary-table/kql/05-create-mv_Summary_Product_Channel_Alert.kql). Copy/highlight its `.create materialized-view ... { ... }` block and run it alone.
4. If the early-warning-base view is absent, run this reviewed baseline definition:

   ```kql
   .create materialized-view with (backfill=true,folder="Gold")
   mv_EarlyWarning_Base on table DepositMovementClassified
   {
       DepositMovementClassified
       | where isnotnull(LocalDateTime)
       | where Channel !in ("MSYG","SYSG")
       | extend IsRetail=Channel in ("ENET","ATM","CDM"),
           BucketStart=bin(LocalDateTime,30m)
       | summarize
           GrossOutflow=sum(Debit_Amount),
           Credit=sum(Credit_Amount),
           Net=sum(Net_Amount),
           DebitTxn=sum(Debit_Transaction),
           UpdatedAtUtc=max(load_ts)
           by LocalDate,BucketStart,DayClassification,EventFlag,
               IsMonthEnd,IsPayroll,IsLongWeekend,IsRetail
   }
   ```

5. Restore its reviewed cache setting as a separate command:

   ```kql
   .alter materialized-view mv_EarlyWarning_Base policy caching hot = 90d
   ```

6. Check both views' health/enabled state and reconcile their query results against the source.
7. Repeat section 4 to capture the actual definitions/policies. The reformatted example above is logically the same baseline query but may not have byte-identical whitespace. Review and synchronize the approved definition comparisons before constructing/running the refresh.
8. Do not paste observational JSON fields such as `LastRun`, `Status`, or `MaterializedTo` into creation commands.

## References

- [Complete field-by-field UI activity reference](UI-ACTIVITY-REFERENCE.md).
- [Technical runbook and optional engineering automation](README.md).
- [Deployment inventory](deployment.json).
- [Recorded live test results and blockers](TEST-RESULTS.md).
