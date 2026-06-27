# Production 02 — Warehouse Control Table

Create the `dbo.ProcessedFiles` audit/control table (plus a logging stored procedure) in a **Fabric Warehouse** named **`wh_control_framework`**.

This table is the heart of the pipeline's **idempotency** and **auditability**: before ingesting a CSV the pipeline checks here to avoid duplicate loads, and after each copy it writes one row recording the outcome.

**Prerequisite:** [Production 01 — Eventhouse KQL Tables](../01-eventhouse-kql-tables/)
**Next:** [Production 03 — Summary Table](../03-summary-table/)

---

## P2.1 — Why a Warehouse (not the Eventhouse)?

The control table lives in a **Fabric Warehouse**, deliberately **decoupled** from the hot-path KQL table:

| Reason | Detail |
|---|---|
| **Writeable** | Needs `INSERT` (and the pipeline writes one row per file). KQL/Eventhouse is append-optimized but T-SQL is the natural fit for control logic. |
| **T-SQL friendly** | Ops teams query it with familiar SQL; easy `JOIN` in Power BI for an ingestion-audit page. |
| **Decoupled** | Keeps the hot-path `DepositMovement` KQL table focused on business facts — control/audit noise stays out. |
| **Idempotency** | `Get Metadata → Lookup → If → Copy` reads this table to skip already-processed files. |

> 💡 **Rule of thumb:** Eventhouse for real-time facts, **Warehouse for control & reporting**, Lakehouse for big-data ETL.

---

## P2.2 — Create the Warehouse

1. Open **Fabric Portal** → your **RTI-IDM-PRD** workspace.
2. **+ New item** → **Warehouse** → name it **`wh_control_framework`** → **Create**.
3. Wait for provisioning, then open it and click **New SQL query**.

---

## P2.3 — Create the Control Table

In the Warehouse SQL query editor, paste and run:

**[sql/01-create-ProcessedFiles.sql](sql/01-create-ProcessedFiles.sql)**

This script does **two things:**

1. **Creates `dbo.ProcessedFiles`** (8 columns) — idempotent (`IF OBJECT_ID(...) IS NULL`).
2. **Creates `dbo.usp_LogProcessedFile`** — a `CREATE OR ALTER` stored procedure the pipeline calls to write an audit row. Keeping the insert logic in a versioned procedure keeps the pipeline JSON clean.

### P2.3.1 — Schema (8 columns)

| Column | Type | Purpose |
|---|---|---|
| `FileName` | `VARCHAR(260)` | Natural key for dedup (blob path / file name) |
| `IngestedAtUtc` | `DATETIME2(3)` | When the row was written (`SYSUTCDATETIME()`) |
| `RowCount_` | `BIGINT` | Rows copied *(trailing `_` — `ROWCOUNT` is reserved in T-SQL)* |
| `Status` | `VARCHAR(32)` | `Success` / `Failed` / `Skipped-Duplicate` |
| `PipelineName` | `VARCHAR(200)` | `@pipeline().Pipeline` |
| `PipelineRunId` | `VARCHAR(64)` | `@pipeline().RunId` |
| `RunAsUser` | `VARCHAR(200)` | Trigger type + name |
| `ErrorMsg` | `VARCHAR(4000)` | Copy Activity error (if any) |

> **Note:** Fabric Warehouse does not enforce `PRIMARY KEY` / `UNIQUE` constraints. Deduplication is enforced by the **pipeline logic** (lookup before copy), not a DB constraint.

### P2.3.2 — Logging stored procedure

The pipeline calls this after each Copy Activity:

```sql
EXEC dbo.usp_LogProcessedFile
     @FileName      = @{item().name},
     @RowCount      = @{activity('Copy_DepositMovement').output.rowsCopied},
     @Status        = 'Success',
     @PipelineName  = @{pipeline().Pipeline},
     @PipelineRunId = @{pipeline().RunId},
     @RunAsUser     = @{pipeline().TriggerType},
     @ErrorMsg      = NULL;
```

`IngestedAtUtc` is set inside the procedure via `SYSUTCDATETIME()`, so the pipeline never has to pass a timestamp.

---

## P2.4 — Verify

Run the verification script in the same Warehouse SQL editor:

**[sql/02-verify-ProcessedFiles.sql](sql/02-verify-ProcessedFiles.sql)**

It checks:

| # | Check | Expected |
|---|---|---|
| 1 | Table exists | `dbo.ProcessedFiles` returned |
| 2 | Column schema | 8 columns with correct types/nullability |
| 3 | Stored procedure exists | `usp_LogProcessedFile` returned |
| 4 | Table is empty | `Rows_ = 0` (awaiting pipeline writes) |
| 5 | *(Optional)* Smoke-test the proc | inserts → reads → deletes one test row |

**Quick checks:**

```sql
-- Table is empty and ready
SELECT COUNT(*) AS Rows_ FROM dbo.ProcessedFiles;

-- Audit summary by status (once data flows)
SELECT Status, COUNT(*) AS Files, SUM(RowCount_) AS Rows_
FROM dbo.ProcessedFiles
GROUP BY Status;
```

---

## P2.5 — How the Pipeline Uses This Table (preview)

The event-driven pipeline (Production 04) follows the canonical idempotent pattern:

```
BlobCreated event
   │
   ▼
Get Metadata (file exists?)
   │
   ▼
Lookup  ──►  SELECT COUNT(*) FROM dbo.ProcessedFiles
             WHERE FileName = @file AND Status = 'Success'
   │
   ▼
If Condition
   ├─ already processed ──►  EXEC usp_LogProcessedFile @Status='Skipped-Duplicate'
   └─ new file ──►  Copy → Eventhouse  ──►  EXEC usp_LogProcessedFile @Status='Success'/'Failed'
```

This gives **file-level idempotency** in the Warehouse, complementing the KQL `ingest-by:` tag used on the Eventhouse side.

---

## P2.6 — Differences from Workshop

| Aspect | Workshop 02 | Production 02 |
|---|---|---|
| **Table** | `dbo.ProcessedFiles` (8 cols) | Same — unchanged ✅ |
| **Logging** | Inline pipeline `INSERT` | **Stored procedure** `usp_LogProcessedFile` (versioned, reusable) |
| **Verify script** | Two ad-hoc `SELECT`s | Dedicated [02-verify-ProcessedFiles.sql](sql/02-verify-ProcessedFiles.sql) (schema + proc + smoke test) |

> The control table itself is **format-agnostic** — the CSV spec changes (pipe delimiter, no header, removed `Transaction_Type`) only affect the Eventhouse table and the pipeline mapping, not this audit table.

---

## ✅ Exit Criteria

Before proceeding to **[Production 03](../03-summary-table/)**, verify:

- [ ] Warehouse `wh_control_framework` exists in the **RTI-IDM-PRD** workspace
- [ ] Table `dbo.ProcessedFiles` exists with **8 columns**
- [ ] Stored procedure `dbo.usp_LogProcessedFile` exists
- [ ] `SELECT COUNT(*) FROM dbo.ProcessedFiles` returns **0** (empty, awaiting pipeline)

---

## 📚 Reference Links

| Concept | Documentation |
|---|---|
| Fabric Warehouse | [Warehouse in Microsoft Fabric](https://learn.microsoft.com/fabric/data-warehouse/data-warehousing) |
| T-SQL surface area | [T-SQL in Fabric Warehouse](https://learn.microsoft.com/fabric/data-warehouse/tsql-surface-area) |
| `CREATE PROCEDURE` | [CREATE PROCEDURE (T-SQL)](https://learn.microsoft.com/sql/t-sql/statements/create-procedure-transact-sql) |
| Idempotent pipelines | [Data pipeline patterns in Fabric](https://learn.microsoft.com/fabric/data-factory/) |
