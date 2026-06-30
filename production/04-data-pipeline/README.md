# Production 04 — Data Pipeline

> **Status:** 🔧 In Progress

Build the hardened, idempotent Fabric Data Pipeline **`pl_ingest_DepositMovement`** that ingests one **pipe-delimited, no-header** `INTRADAY_SUMMARY_*.CSV` per run into the KQL table `DepositMovement`, with duplicate protection and full audit written to the Warehouse table `wh_control_framework.dbo.ProcessedFiles`.

**Prerequisite:** [Production 03 — Summary Table](../03-summary-table/)
**Next:** [Production 05 — Event Trigger](../05-event-trigger/)

---

## P4.0 — What changed from the workshop

This module mirrors [Workshop 04](../../workshops/04-data-pipeline/) but reflects the **production data spec** and **production storage**. Everything else (idempotency design, audit logic, Gold materialized view) is identical.

| Aspect | Workshop | **Production** |
|---|---|---|
| Storage account | `<workshop storage>` | **`mockadlsidimdprd001`** |
| Container | `intraday-deposits` | **`inflowoutflow`** |
| Folder (`pFolder`) | `incoming` | **`inbound/statement`** |
| Delimiter | comma `,` | **pipe `\|`** |
| Header row | yes (First row as header ✅) | **no header (First row as header ❌)** |
| File naming | `mock_HHMM_HHMM.csv` | **`INTRADAY_SUMMARY_YYYYMMDD_HHMM_HHMM.CSV`** |
| Time interval | 30 min | **15 min** |
| Data columns | included `Transaction_Type` | **11 cols, no `Transaction_Type`** |
| Amount columns | integer | **`decimal`** (KQL 128-bit fixed-point) |
| Ingestion mapping | `DepositMovement_mapping` | **`DepositMovement_mapping`** (11 data + 4 system, ordinal-based) |

> **Production ADLS Gen2 path:**
> `https://mockadlsidimdprd001.dfs.core.windows.net` → container `inflowoutflow` → folder `inbound/statement/` → file `INTRADAY_SUMMARY_20260615_0945_1000.CSV`

---

## P4.1 — Pipeline components (what & why)

### Parameters (inputs from the caller / trigger)

| Name | Type | Default | Purpose |
|---|---|---|---|
| `pFileName` | String | *(empty)* | File name for **manual** runs. |
| `pFolder` | String | `inbound/statement` | Source directory inside the container. |
| `Subject` | String | *(empty)* | Full blob path delivered by the **event trigger** (Production 05). |

### Variables (computed during the run)

| Name | Type | Purpose |
|---|---|---|
| `vLoadTs` | String | **Freeze the clock** — one `@utcNow()` written to `load_ts` for every row copied in the run, so the whole file shares one ingestion timestamp. |
| `vFileName` | String | **Resolve the file name** from the trigger `Subject` path, or fall back to `pFileName` for manual runs. |

### Activities (execution order)

```
[Set vLoadTs] → [Set vFileName] → [Get Metadata] → [Lookup ProcessedFiles] → [If Condition]
        ├─ True  (new file):  Copy → Append Success
        │                       └─ On Failure → Append Failed
        └─ False (duplicate): Append Skipped-Duplicate
```

> **Goal — idempotent:** the pipeline can fire any number of times for the same file and produce the same result: one copy of the data, one `Success` audit row, zero errors.

> **Gold is automatic:** the materialized view `mv_Summary_Product_Channel_Alert` (Production 03) aggregates `DepositMovement` incrementally — no Gold-refresh activity is needed in this pipeline.

---

## P4.2 — Create the pipeline

1. Open **Fabric Portal** → **RTI-IDM-PRD** workspace.
2. **+ New item** → **Data pipeline**.
3. Name: **`pl_ingest_DepositMovement`** → **Create**.

---

## P4.3 — Parameters & variables

Click the **canvas background** → bottom pane.

**Parameters tab → + New** (×3):

| Name | Type | Default Value |
|---|---|---|
| `pFileName` | String | *(empty)* |
| `pFolder` | String | `inbound/statement` |
| `Subject` | String | *(empty)* |

**Variables tab → + New** (×2):

| Name | Type | Default Value |
|---|---|---|
| `vLoadTs` | String | *(empty)* |
| `vFileName` | String | *(empty)* |

---

## P4.4 — Build the activities

### P4.4.0 — `Set vLoadTs` (Set variable)

| Tab | Setting | Value |
|---|---|---|
| General | Name | `Set vLoadTs` |
| Settings | Variable | `vLoadTs` |
| Settings | Value | `@utcNow()` |

---

### P4.4.0b — `Set vFileName` (Set variable)

Connect **On Success** from `Set vLoadTs`.

| Tab | Setting | Value |
|---|---|---|
| General | Name | `Set vFileName` |
| Settings | Variable | `vFileName` |
| Settings | Value | *(see expression below)* |

```
@replace(coalesce(pipeline().parameters.Subject, pipeline().parameters.pFileName), '/blobServices/default/containers/inflowoutflow/blobs/inbound/statement/', '')
```

> - **Trigger run:** `Subject` holds the full blob path (e.g. `/blobServices/default/containers/inflowoutflow/blobs/inbound/statement/INTRADAY_SUMMARY_20260615_0945_1000.CSV`). `replace()` strips the known prefix → leaves `INTRADAY_SUMMARY_20260615_0945_1000.CSV`.
> - **Manual run:** `Subject` is empty → `coalesce()` falls back to `pFileName`; `replace()` finds nothing to strip.
>
> ⚠️ Avoid `last(split(...))` — Fabric's expression engine throws *"Cannot fit string list item into the function parameter string"*. The `replace()` approach is the reliable pattern.

---

### P4.4.1 — `Get Metadata`

Connect **On Success** from `Set vFileName`.

| Tab | Setting | Value |
|---|---|---|
| General | Name | `Get Metadata` |
| General | Retry / Interval | `2` / `30` sec |

**ADLS Gen2 connection** (first time — **+ New**):

| Setting | Value |
|---|---|
| URL | `https://mockadlsidimdprd001.dfs.core.windows.net` |
| Authentication kind | **Workspace Identity** |

→ **Test connection** must show ✅. If it fails, revisit [Production 00 — Prerequisites](../00-prerequisites/) (Workspace Identity + RBAC + Trusted Workspace Access resource instance rule).

**Settings:**

| Setting | Value |
|---|---|
| Connection | *(the ADLS Gen2 connection)* |
| Container | `inflowoutflow` |
| Directory | `@pipeline().parameters.pFolder` |
| File name | `@variables('vFileName')` |
| Field list | `exists`, `size`, `lastModified` |

---

### P4.4.2 — `Lookup ProcessedFiles`

Connect **On Success** from `Get Metadata`.

| Setting | Value |
|---|---|
| Name | `Lookup ProcessedFiles` |
| Connection | **Warehouse** → `wh_control_framework` |
| Use query | **Query** |
| First row only | ❌ **Unchecked** |

```sql
SELECT TOP (1) FileName
FROM dbo.ProcessedFiles
WHERE FileName = '@{variables('vFileName')}'
  AND Status   = 'Success';
```

> Uncheck **First row only** so the output exposes `count` (returns `count = 0` for a new file). This keeps the `If Condition` safe even when zero rows match.

---

### P4.4.3 — `If Condition`

Connect **On Success** from `Lookup ProcessedFiles`.

| Setting | Value |
|---|---|
| Name | `If Condition` |
| Expression | `@equals(activity('Lookup ProcessedFiles').output.count, 0)` |

- `true` → new file → **True** branch (load it).
- `false` → duplicate → **False** branch (skip + audit).

---

### P4.4.3a — True branch: `Copy CSV to Eventhouse` (Copy data)

| Tab | Setting | Value |
|---|---|---|
| General | Name | `Copy CSV to Eventhouse` |
| General | Retry / Interval | `3` / `60` sec |

**Source:**

| Setting | Value |
|---|---|
| Connection | *(ADLS Gen2 from P4.4.1)* |
| Container | `inflowoutflow` |
| Directory | `@pipeline().parameters.pFolder` |
| File name | `@variables('vFileName')` |
| File format | **DelimitedText** |
| Column delimiter | **Pipe (`\|`)** |
| **First row as header** | ❌ **Unchecked** (production files have **no header**) |

**Additional columns** (**+ New** ×4 — these inject the 4 system columns at ordinals 11–14):

| Name | Value |
|---|---|
| `load_ts` | `@variables('vLoadTs')` |
| `file_name` | `@variables('vFileName')` |
| `pipeline_name` | `@pipeline().Pipeline` |
| `pipeline_runid` | `@pipeline().RunId` |

**Destination:**

| Setting | Value |
|---|---|
| Connection | **KQL Database** → `DepositMovement` |
| Table | `DepositMovement` |
| Ingestion mapping name | `DepositMovement_mapping` *(free-text — type exactly)* |

> **Mapping tab — skip it.** The named mapping `DepositMovement_mapping` (created in [Production 01](../01-eventhouse-kql-tables/)) maps **by ordinal**: CSV ordinals 0–10 → the 11 data columns, ordinals 11–14 → the 4 injected system columns. **Import schemas** fails at design time because the source path is dynamic — that's expected. Leave Mapping empty.

> **Amount padding note:** the production CSVs right-pad amounts with spaces (e.g. `         350300.00`). KQL CSV ingestion trims surrounding whitespace when parsing `decimal`, so values land exactly — no extra transform needed.

---

### P4.4.3b — True branch: `Append Success` (Script)

Connect **On Success** from `Copy CSV to Eventhouse`.

| Setting | Value |
|---|---|
| Name | `Append Success` |
| Connection | `wh_control_framework` |
| Script type | **NonQuery** |

```sql
INSERT INTO dbo.ProcessedFiles
    (FileName, IngestedAtUtc, RowCount_, Status, PipelineName, PipelineRunId, RunAsUser, ErrorMsg)
VALUES (
    '@{variables('vFileName')}',
    SYSUTCDATETIME(),
    @{activity('Copy CSV to Eventhouse').output.rowsCopied},
    'Success',
    '@{pipeline().Pipeline}',
    '@{pipeline().RunId}',
    'Pipeline',
    NULL
);
```

---

### P4.4.3c — True branch: `Append Failed` (Script)

Connect **On Failure** (red arrow) from `Copy CSV to Eventhouse`.

| Setting | Value |
|---|---|
| Name | `Append Failed` |
| Connection | `wh_control_framework` |
| Script type | **NonQuery** |

```sql
INSERT INTO dbo.ProcessedFiles
    (FileName, IngestedAtUtc, RowCount_, Status, PipelineName, PipelineRunId, RunAsUser, ErrorMsg)
VALUES (
    '@{variables('vFileName')}',
    SYSUTCDATETIME(),
    0,
    'Failed',
    '@{pipeline().Pipeline}',
    '@{pipeline().RunId}',
    'Pipeline',
    NULL
);
```

> A failed file is **not** marked processed, so the next trigger retry will attempt it again. Full error detail stays in **Monitor → Pipeline runs → Activity details** (escaping the error message inline breaks Fabric's expression parser).

---

### P4.4.3d — Gold is automatic (no activity)

The Gold layer is the materialized view **`mv_Summary_Product_Channel_Alert`** (Production 03). KQL refreshes it **incrementally and automatically** as new rows land in `DepositMovement`, so the pipeline needs **no** Gold-recalculation activity. After `Append Success`, the True branch is complete.

> Query the Gold layer any time via the view directly, or via the wrapper `Summary_Alert_Channel_Gold()` for the canonical column order. The view always returns correct totals (materialized data + uncommitted delta combined), even while the `MaterializedTo` watermark catches up.

---

### P4.4.3e — False branch: `Append Skipped-Duplicate` (Script)

| Setting | Value |
|---|---|
| Name | `Append Skipped-Duplicate` |
| Connection | `wh_control_framework` |
| Script type | **NonQuery** |

```sql
INSERT INTO dbo.ProcessedFiles
    (FileName, IngestedAtUtc, RowCount_, Status, PipelineName, PipelineRunId, RunAsUser, ErrorMsg)
VALUES (
    '@{variables('vFileName')}',
    SYSUTCDATETIME(),
    0,
    'Skipped-Duplicate',
    '@{pipeline().Pipeline}',
    '@{pipeline().RunId}',
    'Pipeline',
    NULL
);
```

---

## P4.5 — Save & test manually

1. Upload one production file (e.g. `INTRADAY_SUMMARY_20260615_0945_1000.CSV` from [`resources/prd_datasets/`](../../resources/prd_datasets/)) to `inflowoutflow/inbound/statement/`.
2. Run the pipeline with:
   - `pFileName = INTRADAY_SUMMARY_20260615_0945_1000.CSV`
   - `pFolder = inbound/statement`
   - `Subject` = *(empty)*
3. Verify the three layers:

**Bronze (KQL):**
```kql
DepositMovement
| where file_name == "INTRADAY_SUMMARY_20260615_0945_1000.CSV"
| count
```
> Expect the row count of that file (5 rows in the sample), each carrying the 4 lineage columns.

**Control (Warehouse):**
```sql
SELECT TOP (5) * FROM dbo.ProcessedFiles ORDER BY IngestedAtUtc DESC;
```
> Expect **1** `Success` row with `RowCount_` = rows copied.

**Gold (KQL):**
```kql
mv_Summary_Product_Channel_Alert
| count
```
> Expect one row per `Date, Product, Channel, Channel_Group` — the view auto-aggregates the new Bronze rows (no manual step).

4. **Idempotency test** — re-run the same file → **no new Bronze rows**, just a new `Skipped-Duplicate` audit row.

---

## P4.6 — Clean up test data

> Run only after verifying the pipeline. Tables/mappings/views stay intact — only rows are removed.

| Step | Target | Engine | Command |
|---|---|---|---|
| 1 | `DepositMovement` | KQL | `.clear table DepositMovement data` |
| 2 | `mv_Summary_Product_Channel_Alert` | KQL | `.clear materialized-view mv_Summary_Product_Channel_Alert data` *(then verify `.show materialized-view mv_Summary_Product_Channel_Alert`)* |
| 3 | `dbo.ProcessedFiles` | T-SQL | `DELETE FROM dbo.ProcessedFiles;` |

---

## ✅ Exit Criteria

- [ ] Pipeline `pl_ingest_DepositMovement` runs end-to-end on a production `INTRADAY_SUMMARY_*.CSV`
- [ ] Source reads **pipe-delimited, no-header** with the 11-column ordinal mapping
- [ ] 4 system columns (`load_ts`, `file_name`, `pipeline_name`, `pipeline_runid`) populated
- [ ] Idempotency proven (re-run = `Skipped-Duplicate`, no new Bronze rows)
- [ ] Failure path tested (missing file = `Failed` audit row)
- [ ] Gold materialized view `mv_Summary_Product_Channel_Alert` reflects each successful ingestion (auto-refresh — no pipeline step)

→ Proceed to **[Production 05 — Event Trigger](../05-event-trigger/)**

---

## Reference

Once built, export the pipeline from Fabric (**⋯ → Export → Pipeline JSON**) and save it to [`pipeline/pl_ingest_DepositMovement.json`](pipeline/) for version control and re-import.
