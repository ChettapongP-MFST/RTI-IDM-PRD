# Production 03 — Summary Table (Gold Layer)

Create the **Gold aggregation layer** — a pre-aggregated table that stores per-time-window, channel-level summaries of deposit movements, built from the Bronze `DepositMovement` table.

```
Bronze (DepositMovement)  ──►  Materialized View  ──►  Gold (mv_Summary_Product_Channel_Alert)
```

**Prerequisite:** [Production 01 — Eventhouse KQL Tables](../01-eventhouse-kql-tables/) (the `DepositMovement` table exists)
**Next:** [Production 04 — Data Pipeline](../04-data-pipeline/)

---

## P3.1 — Why a Gold table?

`DepositMovement` (Bronze) stores **granular, row-level** facts (per product, per channel, per time slot). The Gold table stores **per-dimension aggregated summaries**, pre-aggregated for:

- **Power BI reports** — dashboards query a small summary table instead of scanning millions of raw rows → faster loads.
- **Activator alerts** (Production 05) — threshold alerting on net amounts / transaction counts per time window per channel.

### Gold schema (`mv_Summary_Product_Channel_Alert`) — 12 columns

| Column | Type | Purpose |
|---|---|---|
| `Date` | `datetime` | Business date (e.g. 2026-06-15) — group key |
| `Time` | `string` | `max(Time)` |
| `Product` | `string` | Product dimension — group key |
| `Channel` | `string` | Channel dimension — group key |
| `Channel_Group` | `string` | Channel group dimension — group key |
| `Credit_Amount` | `decimal` | `sum(Credit_Amount)` |
| `Debit_Amount` | `decimal` | `sum(Debit_Amount)` |
| `Net_Amount` | `decimal` | `sum(Net_Amount)` |
| `Credit_Transaction` | `long` | `sum(Credit_Transaction)` |
| `Debit_Transaction` | `long` | `sum(Debit_Transaction)` |
| `Total_Transaction` | `long` | `sum(Total_Transaction)` |
| `UpdatedAtUtc` | `datetime` | When the summary was last recalculated |

> **Production difference:** the source has **no `Transaction_Type` column**, and amounts are KQL **`decimal`** (not `real`). Column names mirror the Bronze source; rows are grouped by `Date` + `Product` + `Channel` + `Channel_Group`, with `Time` aggregated via `max(Time)`.
>
> **Column order:** a KQL materialized-view schema is always **group keys first, then aggregates**, and a trailing `| project` is not permitted inside an MV definition. The MV's physical order is therefore `Date, Product, Channel, Channel_Group, Time, Credit_Amount, …, UpdatedAtUtc`. The canonical order above (`Date, Time, Product, Channel, Channel_Group, …, UpdatedAtUtc`) is exposed at query time via the wrapper function.
>
> **Wrapper function:** `Summary_Alert_Channel_Gold()` (see `kql/07-create-Summary_Alert_Channel_Gold-wrapper.kql`) projects the MV to the canonical column order. Use it instead of querying `mv_Summary_Product_Channel_Alert` directly wherever the exact order matters (Power BI, exports).

---

## P3.2 — Create the Materialized View

`mv_Summary_Product_Channel_Alert` is the **Gold object**. It is defined directly on the Bronze `DepositMovement` table, and KQL **auto-aggregates** it incrementally as new data lands — no pipeline step and no recalculation function required.

Run:

**[kql/05-create-mv_Summary_Product_Channel_Alert.kql](kql/05-create-mv_Summary_Product_Channel_Alert.kql)**

```kql
.create materialized-view with (backfill=true) mv_Summary_Product_Channel_Alert on table DepositMovement
{
    DepositMovement
    | summarize
        Time               = max(Time),
        Credit_Amount      = sum(Credit_Amount),
        Debit_Amount       = sum(Debit_Amount),
        Net_Amount         = sum(Net_Amount),
        Credit_Transaction = sum(Credit_Transaction),
        Debit_Transaction  = sum(Debit_Transaction),
        Total_Transaction  = sum(Total_Transaction),
        UpdatedAtUtc       = max(load_ts)
        by Date, Product, Channel, Channel_Group
}
```

| Part | What it does |
|---|---|
| `with (backfill=true)` | Aggregates all existing data immediately. Remove if the table is empty at creation. |
| `on table DepositMovement` | KQL watches this source for new extents. |
| `max(load_ts)` | Freshness proxy — `now()` is **not** mergeable in a materialized view, but `max()` of a column is. |
| `summarize ... by Date, Product, Channel, Channel_Group` | Aggregation run automatically by KQL as data lands. |

The view keeps **exactly one row** per Date+Product+Channel+Channel_Group (auto-merged), so no dedup is needed.

### Wrapper for canonical column order

The MV's physical schema is **keys-first**. To expose the canonical order (`Date, Time, Product, Channel, Channel_Group, …, UpdatedAtUtc`) for Power BI and exports, create the wrapper function:

**[kql/07-create-Summary_Alert_Channel_Gold-wrapper.kql](kql/07-create-Summary_Alert_Channel_Gold-wrapper.kql)**

```kusto
Summary_Alert_Channel_Gold()   // = mv_Summary_Product_Channel_Alert projected to canonical order
```

---

## P3.3 — Verify

Run the verification script:

**[kql/06-verify-Summary_Alert_Channel.kql](kql/06-verify-Summary_Alert_Channel.kql)**

| Check | Expected |
|---|---|
| Materialized view exists & healthy | `mv_Summary_Product_Channel_Alert`, `IsHealthy = true` |
| MV schema | 12 columns (group keys first, then aggregates) |
| Query the view | one row per Date+Product+Channel+Channel_Group |
| Wrapper function | `Summary_Alert_Channel_Gold()` returns the canonical column order |
| Reconcile MV vs Bronze | totals match for a sample date |

Each `.show` command has a clean table-format **"b"** companion (using `todynamic(...)`), consistent with Production 01's verify script.

---

## P3.4 — Differences from Workshop

| Aspect | Workshop 03 | Production 03 |
|---|---|---|
| **Source schema** | included `Transaction_Type` | **removed** — groups by Date+Product+Channel+Channel_Group (Time via `max(Time)`) |
| **Amount totals** | `real` | **`decimal`** (matches Bronze `decimal` columns) |
| **Txn count source** | `Total_Txn` | **`Total_Transaction`** |
| **Verify script** | inline checks | dedicated [06-verify-Summary_Alert_Channel.kql](kql/06-verify-Summary_Alert_Channel.kql) with clean "b" tables |

---

## ✅ Exit Criteria

Before proceeding to **[Production 04](../04-data-pipeline/)**, verify:

- [ ] Materialized view `mv_Summary_Product_Channel_Alert` exists and is healthy (`IsHealthy = true`)
- [ ] MV auto-aggregates Bronze — one row per `Date + Product + Channel + Channel_Group`
- [ ] Wrapper function `Summary_Alert_Channel_Gold()` returns the canonical column order
- [ ] MV totals reconcile against Bronze for a sample date

---

## 📚 Reference Links

| Concept | Documentation |
|---|---|
| Materialized views | [Materialized views overview](https://learn.microsoft.com/fabric/real-time-intelligence/materialized-view) |
| Wrapper functions | [User-defined functions (KQL)](https://learn.microsoft.com/kusto/query/functions/user-defined-functions) |
| Aggregation functions | [summarize operator](https://learn.microsoft.com/kusto/query/summarize-operator) |
