# Production 06 — Interval Scheduler

> **Status:** ✅ Complete

Build a **scheduled orchestrator** pipeline **`pl_ingest_DepositMovement_schedule`** that runs every **15 minutes**, lists **today's** `INTRADAY_SUMMARY_*.CSV` files in ADLS Gen2, compares them against `wh_control_framework.dbo.ProcessedFiles` to find the **new (not-yet-loaded)** files, and invokes the existing ingestion pipeline **`pl_ingest_DepositMovement`** (Production 04) **once per new file, in parallel**.

**Prerequisite:** [Production 04 — Data Pipeline](../04-data-pipeline/)
**Next:** [Production 07 — Sample Data](../07-sample-data/)

| Setting | Value |
|---|---|
| Orchestrator pipeline | `pl_ingest_DepositMovement_schedule` |
| Child (reused) pipeline | `pl_ingest_DepositMovement` |
| Storage account | `mockadlsidimdprd001` |
| Container | `inflowoutflow` |
| Folder | `inbound/statement/` |
| Control table | `wh_control_framework.dbo.ProcessedFiles` |
| Schedule | every **15 minutes** |
| Parallelism | ForEach, **non-sequential**, batch count `10` |
| File-name time zone | **Bangkok / ICT (UTC+7)** — Windows ID `SE Asia Standard Time` |
| Workspace | `RTI-IDM-PRD` |

---

## P6.0 — Why a scheduler (push vs pull)

[Production 05](../05-event-trigger/) is **push**: a `BlobCreated` event fires the ingestion pipeline the instant a file lands — near-zero latency, one run per file. This module is **pull**: a clock-driven sweep that catches **anything the event trigger missed** (events dropped, files copied in bulk, trigger paused, backfill/replay).

Both paths call the **same** child pipeline `pl_ingest_DepositMovement`, and both are safe to run together because the child is **idempotent** — every file is checked against `dbo.ProcessedFiles` before loading, so a file can never be double-ingested no matter how many times it is offered.

| | Production 05 — Event Trigger | **Production 06 — Interval Scheduler** |
|---|---|---|
| Model | Push (event-driven) | **Pull (time-driven)** |
| Latency | Seconds | **Up to 15 min** |
| Granularity | One run per file | **One sweep → N parallel child runs** |
| Best at | Steady real-time flow | **Catch-up / backfill / safety net** |
| Reuses child pipeline | ✅ | ✅ |

---

## P6.1 — How it works

The orchestrator does **no copying or auditing of its own** — it only decides *which* files to hand to the existing pipeline.

```
[Set vToday] → [Get Metadata: list childItems] → [Lookup Processed Files] → [Filter New Files]
                                                                                    │
                                                              [ForEach New Files]  (parallel, batch 10)
                                                                                    │
                                                          [Execute Pipeline: pl_ingest_DepositMovement]
                                                                  pFileName = @item().name
                                                                  pFolder   = inbound/statement
```

- **`Set vToday`** freezes today's file prefix once (`INTRADAY_SUMMARY_yyyyMMdd`).
- **`Get Metadata`** lists every child item in `inbound/statement/`.
- **`Lookup Processed Files`** returns the delimited set of today's **already-loaded** file names from `dbo.ProcessedFiles`.
- **`Filter New Files`** keeps only items that are *today's* `.CSV` **and** are **not** in the processed set → the **new-file** list.
- **`ForEach`** fans out the new-file list and calls the child pipeline **in parallel** (one run per new file). The child handles the copy, the 4 lineage columns, the audit row, and the automatic Gold refresh — exactly as in Production 04.

> **Reuse, don't duplicate.** All ingestion, idempotency, audit, and Gold logic lives in `pl_ingest_DepositMovement`. This module is a thin discovery + dispatch wrapper.

---

## P6.2 — Create the orchestrator pipeline

1. Open **Fabric Portal** → **RTI-IDM-PRD** workspace.
2. **+ New item** → **Data pipeline**.
3. Name: **`pl_ingest_DepositMovement_schedule`** → **Create**.

> Tip: if you prefer, **clone** `pl_ingest_DepositMovement` (**⋯ → Duplicate**) and rename it, then replace its body with the activities below. Cloning is optional — this orchestrator shares only the **connections** (ADLS Gen2 + Warehouse) with the original, not its activities.

---

## P6.3 — Parameters & variables

Click the **canvas background** → bottom pane.

**Variables tab → + New** (×1):

| Name | Type | Default Value |
|---|---|---|
| `vToday` | String | *(empty)* |

> No pipeline **parameters** are needed — the sweep always targets *today* and the fixed `inbound/statement` folder. (Add an optional `pDatePrefix` parameter later if you want to replay a past day.)

---

## P6.4 — Build the activities

### P6.4.0 — `Set vToday` (Set variable)

| Tab | Setting | Value |
|---|---|---|
| General | Name | `Set vToday` |
| Settings | Variable | `vToday` |
| Settings | Value | `@concat('INTRADAY_SUMMARY_', convertFromUtc(utcNow(), 'SE Asia Standard Time', 'yyyyMMdd'))` |

> ⚠️ **Time zone matters.** The source files are named in **Bangkok local time (ICT, UTC+7)**, but `utcNow()` returns **UTC**. Between **00:00–06:59 ICT** the UTC date is still *yesterday*, so a raw `utcNow()` prefix would point at the wrong day and miss every new file for the first 7 hours of each Bangkok day. `convertFromUtc(..., 'SE Asia Standard Time', ...)` shifts the clock to ICT first, so `vToday` (e.g. `INTRADAY_SUMMARY_20260630`) always matches the file-naming convention. ICT has **no daylight saving**, so the +7 offset is constant year-round.

---

### P6.4.1 — `Get Metadata — List Files` (Get Metadata)

Connect **On Success** from `Set vToday`.

| Tab | Setting | Value |
|---|---|---|
| General | Name | `Get Metadata — List Files` |
| General | Retry / Interval | `2` / `30` sec |

**Settings** (reuse the **ADLS Gen2 connection** from [Production 04](../04-data-pipeline/) — Workspace Identity):

| Setting | Value |
|---|---|
| Connection | *(the ADLS Gen2 connection)* |
| Container | `inflowoutflow` |
| Directory | `inbound/statement` |
| File name | *(leave empty — point at the directory)* |
| Field list | `childItems` |

> `childItems` returns an array of `{ name, type }` for every file in the folder.

---

### P6.4.2 — `Lookup Processed Files` (Lookup)

Connect **On Success** from `Get Metadata — List Files`.

| Setting | Value |
|---|---|
| Name | `Lookup Processed Files` |
| Connection | **Warehouse** → `wh_control_framework` |
| Use query | **Query** |
| First row only | ✅ **Checked** |

```sql
SELECT COALESCE('|' + STRING_AGG(FileName, '|') + '|', '|') AS ProcessedList
FROM dbo.ProcessedFiles
WHERE Status = 'Success'
  AND FileName LIKE '@{variables('vToday')}%';
```

> Returns **one** delimited string of today's already-loaded files, wrapped in pipe bars — e.g. `|INTRADAY_SUMMARY_20260630_0945_1000.CSV|INTRADAY_SUMMARY_20260630_1000_1015.CSV|`. The leading/trailing `|` let the next step match on the **whole** file name (no partial-name false positives). When nothing is loaded yet, the result is `|`.

---

### P6.4.3 — `Filter New Files` (Filter)

Connect **On Success** from `Lookup Processed Files`.

| Setting | Value |
|---|---|
| Name | `Filter New Files` |
| Items | `@activity('Get Metadata — List Files').output.childItems` |
| Condition | *(see expression below)* |

```
@and(
    and(
        startswith(item().name, variables('vToday')),
        endswith(toLower(item().name), '.csv')
    ),
    not(contains(
        activity('Lookup Processed Files').output.firstRow.ProcessedList,
        concat('|', item().name, '|')
    ))
)
```

> Keeps an item only when it is **today's** file, ends in `.CSV`, **and** its delimiter-wrapped name is **not** found in the processed set. The survivors are the **new** files. Output array: `@activity('Filter New Files').output.Value`.

---

### P6.4.4 — `ForEach New Files` (ForEach) → parallel child runs

Connect **On Success** from `Filter New Files`.

| Tab | Setting | Value |
|---|---|---|
| General | Name | `ForEach New Files` |
| Settings | Items | `@activity('Filter New Files').output.Value` |
| Settings | **Sequential** | ❌ **Unchecked** (run in **parallel**) |
| Settings | Batch count | `10` |

> Unchecking **Sequential** lets Fabric launch up to **Batch count** child runs at once. With ≥ 2 new files they ingest concurrently; with 1 new file it simply runs once; with 0 new files the loop is skipped.

**Inside the ForEach — add `Invoke Ingestion` (Execute Pipeline / Invoke Pipeline):**

| Setting | Value |
|---|---|
| Name | `Invoke Ingestion` |
| Invoked pipeline | **`pl_ingest_DepositMovement`** |
| Wait on completion | ✅ **Checked** |

**Parameters passed to the child:**

| Child parameter | Value |
|---|---|
| `pFileName` | `@item().name` |
| `pFolder` | `inbound/statement` |
| `Subject` | *(leave unset — uses the child default; the child's `coalesce` falls back to `pFileName`)* |

> This is exactly the **manual-run** contract the child pipeline already supports (Production 04, P4.4.0b). The child resolves `vFileName` from `pFileName`, runs its own `Lookup ProcessedFiles → If Condition`, and writes the `Success` / `Skipped-Duplicate` / `Failed` audit row. **No ingestion logic is duplicated here.**

---

## P6.5 — Configure the 15-minute schedule

1. On the pipeline toolbar → **Schedule**.
2. Set:

| Setting | Value |
|---|---|
| Scheduled run | **On** |
| Repeat | **By the minute** → every **15** minutes |
| Start date & time | *(now, or next quarter hour)* |
| Time zone | **(UTC+07:00) Bangkok, Hanoi, Jakarta** |

3. **Apply**.

> The sweep is cheap when idle: if no new files exist, `Filter New Files` returns an empty array and the ForEach does nothing. Overlap is harmless — even if a run is still finishing when the next fires, the child's idempotency check prevents any double load.

---

## P6.6 — Save & test

1. Drop **2 or more** today-dated files into `inflowoutflow/inbound/statement/` (e.g. from [`resources/prd_datasets/`](../../resources/prd_datasets/), renamed to today's date) so parallelism is exercised.
2. **Run** `pl_ingest_DepositMovement_schedule` manually (don't wait for the timer).
3. Open **Monitor → Pipeline runs**:
   - The orchestrator run lists **N child runs** of `pl_ingest_DepositMovement` (one per new file), started near-simultaneously.
4. Verify the layers:

**Control (Warehouse):**
```sql
SELECT FileName, Status, RowCount_, IngestedAtUtc
FROM dbo.ProcessedFiles
ORDER BY IngestedAtUtc DESC;
```
> Expect one `Success` row per new file.

**Bronze (KQL):**
```kql
DepositMovement
| where file_name startswith "INTRADAY_SUMMARY_"
| summarize rows = count() by file_name
```

**Idempotency — re-run the orchestrator:**
> `Filter New Files` now returns **0** items (all files are in `dbo.ProcessedFiles`), so the ForEach is skipped — **no** new child runs, **no** new Bronze rows.

---

## P6.7 — Clean up test data (optional)

> Only after verifying. Same teardown as [Production 04, P4.6](../04-data-pipeline/) — clear Bronze, clear the Gold materialized view, and delete the control rows so the next test starts clean.

| Step | Target | Engine | Command |
|---|---|---|---|
| 1 | `DepositMovement` | KQL | `.clear table DepositMovement data` |
| 2 | `mv_Summary_Product_Channel_Alert` | KQL | `.clear materialized-view mv_Summary_Product_Channel_Alert data` |
| 3 | `dbo.ProcessedFiles` | T-SQL | `DELETE FROM dbo.ProcessedFiles;` |

---

## ✅ Exit Criteria

- [ ] Pipeline `pl_ingest_DepositMovement_schedule` created with `vToday`, Get Metadata, Lookup, Filter, ForEach
- [ ] `Filter New Files` correctly returns only today's, not-yet-loaded `.CSV` files
- [ ] `ForEach New Files` runs **non-sequentially** and invokes `pl_ingest_DepositMovement` once per new file
- [ ] Multiple new files trigger **parallel** child runs (visible in Monitor)
- [ ] No ingestion/audit logic is duplicated — the child pipeline does all loading
- [ ] Re-running the orchestrator loads **nothing** (idempotent: 0 new files)
- [ ] 15-minute schedule enabled

→ Proceed to **[Production 07 — Sample Data](../07-sample-data/)**

---

## Reference

Once built, export both pipelines from Fabric (**⋯ → Export → Pipeline JSON**) and save the orchestrator to [`pipeline/pl_ingest_DepositMovement_schedule.json`](pipeline/) for version control and re-import.
