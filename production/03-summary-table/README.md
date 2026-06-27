# Production 03 — Summary Table (Gold Layer)

Create the **Gold aggregation layer** — a pre-aggregated table that stores per-time-window, channel-level summaries of deposit movements, built from the Bronze `DepositMovement` table.

```
Bronze (DepositMovement)  ──►  Stored Function / Materialized View  ──►  Gold (Summary_Alert_Channel)
```

**Prerequisite:** [Production 01 — Eventhouse KQL Tables](../01-eventhouse-kql-tables/) (the `DepositMovement` table exists)
**Next:** [Production 04 — Data Pipeline](../04-data-pipeline/)

---

## P3.1 — Why a Gold table?

`DepositMovement` (Bronze) stores **granular, row-level** facts (per product, per channel, per time slot). The Gold table stores **per-time-window channel-level summaries**, pre-aggregated for:

- **Power BI reports** — dashboards query a small summary table instead of scanning millions of raw rows → faster loads.
- **Activator alerts** (Production 05) — threshold alerting on net amounts / transaction counts per time window per channel.

### Gold schema (`Summary_Alert_Channel`) — 8 columns

| Column | Type | Purpose |
|---|---|---|
| `Date` | `datetime` | Business date (e.g. 2026-06-15) |
| `Time` | `string` | Time window (e.g. `09:45-10:00`) |
| `Channel` | `string` | Channel dimension |
| `Credit_Total` | `decimal` | `sum(Credit_Amount)` for that Date+Time+Channel |
| `Debit_Total` | `decimal` | `sum(Debit_Amount)` |
| `Net_Amount` | `decimal` | `sum(Net_Amount)` |
| `Txn_Count` | `long` | `sum(Total_Transaction)` |
| `UpdatedAtUtc` | `datetime` | When the summary was last recalculated |

> **Production difference:** the source has **no `Transaction_Type` column**, amounts are KQL **`decimal`** (not `real`), and counts come from **`Total_Transaction`** (not `Total_Txn`).

---

## P3.2 — Two options (pick one)

| | Option A — Stored Function | Option B — Materialized View |
|---|---|---|
| **Mechanism** | Pipeline calls `.set-or-append <\| sp_...()` | KQL auto-aggregates as new data arrives |
| **Gold object** | `Summary_Alert_Channel` (regular table) | `Summary_Alert_Channel_MV` (view) |
| **Trigger** | Explicit — needs a KQL Activity in the pipeline | Automatic — no pipeline step |
| **Rows per key** | Multiple (appends each run — dedup via `UpdatedAtUtc`) | Single (auto-merged) |
| **`UpdatedAtUtc`** | `now()` — exact recalc time | `max(load_ts)` — latest load time |
| **Ops overhead** | Pipeline must call the function every run | Zero — KQL manages it |
| **Best for** | Complex/conditional recalculation logic | Simple aggregations that stay fresh |

> 💡 **Production default:** **Option A** (stored function), called by the pipeline in Production 04. Option B is provided as an autonomous alternative.

---

## Option A — Stored Function (incremental recalculation)

### P3.A1 — Create the Gold table

Run in the KQL Database → **Query** pane:

**[kql/03-create-Summary_Alert_Channel.kql](kql/03-create-Summary_Alert_Channel.kql)**

Creates the empty `Summary_Alert_Channel` table (8 columns) and enables streaming ingestion. The table is **populated by the function**, not at creation time.

### P3.A2 — Create the stored function

Run:

**[kql/04-sp-Recalculate-Summary_Alert_Channel.kql](kql/04-sp-Recalculate-Summary_Alert_Channel.kql)**

The function takes the exact `load_ts` the pipeline stamped on the new rows and re-aggregates **only the affected dates**:

```
Step 1  RecentDates = DepositMovement | where load_ts == pipeline_load_ts | distinct Date
Step 2  RecentDates | join kind=inner DepositMovement on Date     // full day, not just new rows
Step 3  summarize Credit_Total=sum(Credit_Amount), Debit_Total=sum(Debit_Amount),
                  Net_Amount=sum(Net_Amount), Txn_Count=sum(Total_Transaction) by Date, Time, Channel
Step 4  extend UpdatedAtUtc = now()
```

> **Kusto design principle:** the function body is a **pure query** (no writes). Fabric Eventhouse has no `.create procedure` / `INSERT`. The write happens externally via `.set-or-append`.

### How it's called

```kusto
// Preview (no write)
sp_Recalculate_Summary_Alert_Channel(datetime(2026-06-15T08:00:00Z))

// Append into the Gold table
.set-or-append Summary_Alert_Channel <| sp_Recalculate_Summary_Alert_Channel(datetime(2026-06-15T08:00:00Z))
```

In the pipeline (Production 04) the KQL Activity passes the pipeline variable:

```kusto
.set-or-append Summary_Alert_Channel <| sp_Recalculate_Summary_Alert_Channel(datetime(@{variables('vLoadTs')}))
```

> **Append, not upsert.** Re-running for the same Date+Time+Channel adds rows; the latest by `UpdatedAtUtc` is current. Downstream queries should pick the latest:
> ```kusto
> Summary_Alert_Channel | summarize arg_max(UpdatedAtUtc, *) by Date, Time, Channel
> ```

---

## Option B — Materialized View (automatic aggregation)

### P3.B1 — Create the materialized view

Run:

**[kql/05-create-Summary_Alert_Channel_MV.kql](kql/05-create-Summary_Alert_Channel_MV.kql)**

```kql
.create materialized-view with (backfill=true) Summary_Alert_Channel_MV on table DepositMovement
{
    DepositMovement
    | summarize
        Credit_Total = sum(Credit_Amount),
        Debit_Total  = sum(Debit_Amount),
        Net_Amount   = sum(Net_Amount),
        Txn_Count    = sum(Total_Transaction),
        UpdatedAtUtc = max(load_ts)
        by Date, Time, Channel
}
```

| Part | What it does |
|---|---|
| `with (backfill=true)` | Aggregates all existing data immediately. Remove if the table is empty at creation. |
| `on table DepositMovement` | KQL watches this source for new extents. |
| `max(load_ts)` | Freshness proxy — `now()` is **not** mergeable in a materialized view, but `max()` of a column is. |
| `summarize ... by Date, Time, Channel` | Same aggregation as Option A, run automatically by KQL. |

The view keeps **exactly one row** per Date+Time+Channel (auto-merged), so no dedup is needed.

---

## P3.3 — Verify

Run the verification script:

**[kql/06-verify-Summary_Alert_Channel.kql](kql/06-verify-Summary_Alert_Channel.kql)**

| # | Check | Expected |
|---|---|---|
| 1 / 1b | Gold table + schema | `Summary_Alert_Channel`, **8 columns** |
| 2 / 2b | Streaming ingestion policy | `IsEnabled = true` |
| 3 | Stored function exists | `sp_Recalculate_Summary_Alert_Channel` |
| 4 | Preview function output | rows returned, no write |
| 5 | Row count + latest-per-key | dedup via `arg_max(UpdatedAtUtc, *)` |
| 6 / 6b | Materialized view (Option B) | `IsHealthy = true` |
| 7 | Query the view | one row per Date+Time+Channel |
| 8 | Reconcile Gold vs Bronze | totals match for a date |

Each `.show` command has a clean table-format **"b"** companion (using `todynamic(...)`), consistent with Production 01's verify script.

---

## P3.4 — Differences from Workshop

| Aspect | Workshop 03 | Production 03 |
|---|---|---|
| **Source schema** | included `Transaction_Type` | **removed** — aggregation unaffected (groups by Date+Time+Channel) |
| **Amount totals** | `real` | **`decimal`** (matches Bronze `decimal` columns) |
| **Txn count source** | `Total_Txn` | **`Total_Transaction`** |
| **Verify script** | inline checks | dedicated [06-verify-Summary_Alert_Channel.kql](kql/06-verify-Summary_Alert_Channel.kql) with clean "b" tables |

---

## ✅ Exit Criteria

Before proceeding to **[Production 04](../04-data-pipeline/)**, verify:

- [ ] Gold table `Summary_Alert_Channel` exists with **8 columns**
- [ ] Streaming ingestion enabled on the Gold table
- [ ] **Option A:** function `sp_Recalculate_Summary_Alert_Channel` exists and previews rows
- [ ] **Option B:** materialized view `Summary_Alert_Channel_MV` exists and is healthy
- [ ] Gold totals reconcile against Bronze for a sample date

---

## 📚 Reference Links

| Concept | Documentation |
|---|---|
| Stored functions | [Functions overview (KQL)](https://learn.microsoft.com/kusto/query/functions/user-defined-functions) |
| `.set-or-append` | [Append data to a table](https://learn.microsoft.com/kusto/management/data-ingestion/ingest-from-query) |
| Materialized views | [Materialized views overview](https://learn.microsoft.com/fabric/real-time-intelligence/materialized-view) |
| Aggregation functions | [summarize operator](https://learn.microsoft.com/kusto/query/summarize-operator) |
