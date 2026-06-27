# Production 01 — Eventhouse KQL Tables

Create the Eventhouse and KQL Database for the **intraday deposit movement** real-time intelligence workload.

**Prerequisite:** [Production 00 — Prerequisites & Trusted Workspace Access](../00-prerequisites/)  
**Next:** [Production 02 — Warehouse Control Table](../02-warehouse-control/)

---

## P1.1 — Create the Eventhouse

1. Open **Fabric Portal** → your **RTI-IDM-PRD** workspace.
2. **+ New item** → **Eventhouse** → name it **`eh-rti-deposit`** → **Create**.
3. Wait for provisioning. Inside the Eventhouse, a default **KQL Database** is auto-created.
4. Rename the default database to **`DepositMovement`** (or create a new one with that name).

> 💡 **Tip:** You can have multiple KQL Databases inside one Eventhouse for multi-team scenarios. In this production setup, we use one Eventhouse with one KQL Database.

---

## P1.2 — Production Schema Overview

The production `DepositMovement` table has **11 data columns** (from the CSV) + **4 system columns** (injected by the pipeline) = **15 columns total**.

### Complete Schema Table (15 columns)

| Ord | Column Name | Type | Category | Source | Example |
|---|---|---|---|---|---|
| 0 | `Date` | `datetime` | Data | CSV column 0 | `2026-06-15` |
| 1 | `Time` | `string` | Data | CSV column 1 | `09:45-10:00` |
| 2 | `Product` | `string` | Data | CSV column 2 | `S` (Fixed, Saving, Current) |
| 3 | `Channel` | `string` | Data | CSV column 3 | `ATM` |
| 4 | `Channel_Group` | `string` | Data | CSV column 4 | `Offline` |
| 5 | `Credit_Amount` | `decimal(16,2)` | Data | CSV column 5 | `9000000.00` |
| 6 | `Debit_Amount` | `decimal(16,2)` | Data | CSV column 6 | `5000000.00` |
| 7 | `Net_Amount` | `decimal(16,2)` | Data | CSV column 7 | `4000000.00` |
| 8 | `Credit_Transaction` | `long` | Data | CSV column 8 | `1000` |
| 9 | `Debit_Transaction` | `long` | Data | CSV column 9 | `500` |
| 10 | `Total_Transaction` | `long` | Data | CSV column 10 | `1500` |
| 11 | `load_ts` | `datetime` | System | Pipeline `utcNow()` | `2026-06-28T17:09:47Z` |
| 12 | `file_name` | `string` | System | Pipeline `$$FILEPATH` | `inbound/statement/INTRADAY_SUMMARY_...CSV` |
| 13 | `pipeline_name` | `string` | System | Pipeline `@pipeline().Pipeline` | `pl_ingest_DepositMovement` |
| 14 | `pipeline_runid` | `string` | System | Pipeline `@pipeline().RunId` | `12345678-abcd-ef01-2345-6789abcdef00` |

> **Key differences from workshop:**
> - `Transaction_Type` column **removed** ✂️
> - `Credit_Txn` → **`Credit_Transaction`**, `Debit_Txn` → **`Debit_Transaction`**, `Total_Txn` → **`Total_Transaction`** (renamed)
> - Amounts: `real` → **`decimal(16,2)`** (precision for banking data)
> - Ingestion format: **pipe `|` delimiter** (vs comma in workshop)
> - No header row in CSV (vs header=true in workshop)

---

## P1.3 — Create the DepositMovement Table

Open the **KQL Database "DepositMovement"** → click **Query** → paste and run:

**[kql/01-create-DepositMovement.kql](kql/01-create-DepositMovement.kql)**

This script does **three things:**

1. **Creates the 15-column table** with data + system columns
2. **Creates a CSV ingestion mapping** (`DepositMovement_mapping`) that maps pipe-delimited columns to table columns
3. **Enables streaming ingestion** (seconds-level latency) + **retention/caching policies**

---

### P1.3.1 — Table Creation

The table schema includes:
- **11 data columns** (Date, Time, Product, Channel, Channel_Group, Credit_Amount, Debit_Amount, Net_Amount, Credit_Transaction, Debit_Transaction, Total_Transaction)
- **4 system columns** (load_ts, file_name, pipeline_name, pipeline_runid)

All amount columns are `decimal(16,2)` to preserve banking-grade precision.

---

### P1.3.2 — CSV Ingestion Mapping

After table creation, the script creates **`DepositMovement_mapping`** — a separate KQL object that tells the ingestion system:

> **"When you see a pipe-delimited CSV with no header, map ordinal position N to column X."**

**Mapping structure:**

| Ordinal | Column | From | Notes |
|---|---|---|---|
| 0–10 | Data columns | CSV file (pipe-delimited, no header) | Positions match column order |
| 11–14 | System columns | Pipeline "Additional columns" | Injected by the pipeline at runtime |

---

### P1.3.3 — Streaming Ingestion Policy

```kusto
.alter-merge database DepositMovement policy streamingingestion '{ "IsEnabled": true }'
.alter table DepositMovement policy streamingingestion enable
```

**Why it matters:**

| Setting | Latency | Use case |
|---|---|---|
| Batched ingestion (default) | 1–5 minutes | Bulk historical loads |
| Streaming ingestion (enabled) | Seconds | Real-time dashboards, alerts |

Production intraday monitoring needs **seconds**, so streaming is **critical**.

---

### P1.3.4 — Retention & Caching Policy

```kusto
.alter table DepositMovement policy retention '{ "SoftDeletePeriod": "365.00:00:00", "Recoverability": "Enabled" }'
.alter table DepositMovement policy caching hot = 90d
```

| Policy | Setting | Effect |
|---|---|---|
| **Retention** | 365 days | Data older than 1 year is auto-deleted |
| **Hot cache** | 90 days | Last 90 days in SSD/RAM (fast queries) |
| **Cold storage** | 90–365 days | Slower, but still queryable |

---

## P1.4 — Verify Table & Mapping

After running the script, confirm everything was created.

**Run the full verification script:** [`kql/02-verify-DepositMovement.kql`](kql/02-verify-DepositMovement.kql)

This script contains every check below plus clean table-format ("`b`") versions
that flatten the JSON output into readable columns (schema, mappings, and all policies).

**Or, in the KQL query pane, run the quick checks:**

```kusto
// See the table schema
.show table DepositMovement schema as json

// See all ingestion mappings
.show table DepositMovement ingestion csv mappings

// See streaming ingestion status
.show database DepositMovement policy streamingingestion
.show table DepositMovement policy streamingingestion

// See the actual table (should be empty)
DepositMovement | count
```

**Expected output:**
- Table `DepositMovement` with 15 columns ✅
- Mapping `DepositMovement_mapping` listing ordinals 0–14 ✅
- Streaming ingestion status: `Enabled` ✅
- Row count: `0` (empty, awaiting pipeline data) ✅

---

## P1.5 — Differences from Workshop

| Aspect | Workshop 02 | Production 01 |
|---|---|---|
| **Table columns** | 12 data + 4 system = 16 | 11 data + 4 system = 15 |
| **Removed column** | — | `Transaction_Type` |
| **Column renames** | `Credit_Txn`, `Debit_Txn`, `Total_Txn` | `Credit_Transaction`, `Debit_Transaction`, `Total_Transaction` |
| **Amount types** | `real` | `decimal(16,2)` |
| **CSV delimiter** | Comma `,` | **Pipe `\|`** |
| **CSV header** | Present (line 1) | **None** (data starts at line 1) |

---

## ✅ Exit Criteria

Before proceeding to **[Production 02](../02-warehouse-control/)**, verify:

- [ ] Eventhouse `eh-rti-deposit` exists
- [ ] KQL Database `DepositMovement` exists
- [ ] Table `DepositMovement` with 15 columns exists
- [ ] Ingestion mapping `DepositMovement_mapping` exists (15 ordinal mappings)
- [ ] Streaming ingestion is **Enabled**
- [ ] Retention policy = 365 days
- [ ] Hot cache policy = 90 days
- [ ] Table count = 0 (ready for pipeline ingestion)

→ Proceed to **[Production 02 — Warehouse Control Table](../02-warehouse-control/)**
