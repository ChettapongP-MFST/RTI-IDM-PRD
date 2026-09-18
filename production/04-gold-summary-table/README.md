# Production 04 — Gold Layer: Early Warning Indicators (Deposit Outflow Alerts)

Define the **Gold aggregation and the 8 Early Warning Indicators (EWIs)** that feed the
Data Activator alert model for **intraday deposit-outflow monitoring**. This layer is built
on the **Silver** table `DepositMovementClassified` (which already carries day type,
event flags, and the operating-window / comparable-time tag) and produces, every **30
minutes**, one evaluated row per **Scope × Indicator** with an assigned **Alert Level**.

> The previous per-Product/Channel summary table (`mv_Summary_Product_Channel_Alert`) is
> **not replaced**. Its documentation is preserved in
> [README_old.md](README_old.md); this EWI model is a **new, standalone** Gold addition.

---

## Data flow

```
Silver: DepositMovementClassified        row-level, classified (day type · event flags · window)
        │
        ▼
mv_DepositMovementEarlyWarning (Gold MV)  additive per-bucket sums
        │   AUTO-refreshes as Silver ingests (no pipeline / notebook / scheduler)
        │   retention keeps history
        ▼
Gold_EarlyWarning()  ◄──  EWI_AlertThreshold   (reference: Scope × Indicator × Window × DayType)
        │   reads the MV: roll up 3 scopes · cumulative · velocity · cluster share · sudden jump
        │   join value → L1/L2/L3 → assign Alert_Level (L0–L3)
        ▼
one row per Scope × 30-min bucket × indicator  ·  Value + Alert_Level
        │
        ▼
Data Activator (runs Gold_EarlyWarning() every 30 min)  +  Power BI
```

**The base MV auto-refreshes** as Silver ingests — no pipeline, notebook, or scheduler. The three
window-function indicators (cumulative #3, velocity #5, sudden jump #8) and `Alert_Level` are not
allowed in an MV, so `Gold_EarlyWarning()` computes them **on read** over the MV. History lives in
the MV (retention below); the enriched rows are derived on demand, so there is no separate stored
table and nothing to schedule.

---

## Architecture (MV + function — auto-refresh, no scheduler)

| Object | Role |
| --- | --- |
| `EWI_AlertThreshold` (reference) | L1/L2/L3 per Scope × Indicator × Window × DayType |
| `mv_DepositMovementEarlyWarning` (materialized view) | additive per-bucket sums; **auto-refreshes** as Silver ingests; retains history |
| `Gold_EarlyWarning()` (function) | reads the MV; computes window-function indicators + `Alert_Level` on read |

Data Activator runs `Gold_EarlyWarning()` on its 30-minute evaluation cadence, and Power BI queries
the same function. No pipeline, notebook, scheduler, or stored output table. The Activator wiring is
in [Production 09](../09-activator-alerts/).

---

## Conventions

| Item | Value |
| --- | --- |
| Source | Silver `DepositMovementClassified` (Bronze → Silver already classified) |
| Evaluation cadence | **every 30 minutes** (48 buckets/day; a bucket = `[HH:00, HH:30)` or `[HH:30, HH+1:00)`) |
| Excluded channels | `Channel !in ('MSYG', 'SYSG')` — removed from **all** calculations |
| Sign convention | `Net = Sum(Credit_Amount) − Sum(Debit_Amount)`; **negative ⇒ net outflow** |
| Amount unit | raw data is **Baht**; indicators in **MB** divide by `1e6` |
| Count unit | `Debit_Transaction` is a count; "Million" indicators divide by `1e6` |
| Time zone | Asia/Bangkok (ICT, UTC+7); `now()` is UTC, add `+7h` before truncating |

---

## Supporting dimensions

These select **which threshold applies**; they do not change how an indicator is measured.

**3 Scopes** (channel membership is configurable):

| Scope | Definition |
| --- | --- |
| `TOTAL_BANK` | all channels (excluding `MSYG`, `SYSG`) |
| `RETAILS` | `Channel in ('ENET', 'ATM', 'CDM')` |
| `NON_RETAILS` | all other channels (excluding `MSYG`, `SYSG`) |

**4 Comparable-time windows** (from `OperatingWindowsTimes`, tagged on every Silver row as `OperatingWindowCode`):

| Code | Window |
| --- | --- |
| `BEFORE_WORKING_HOUR` | 00:00 – 08:30 |
| `MORNING_WORKING_HOUR` | 08:30 – 12:00 |
| `AFTERNOON_WORKING_HOUR` | 12:00 – 17:30 |
| `AFTER_WORKING_HOUR` | 17:30 – 24:00 |

**3 Day types** (from Silver `DayClassification`): `BUSINESS_DAY`, `WEEKEND`, `HOLIDAY`.

**3 Event flags** (from Silver): `IsMonthEnd`, `IsPayroll`, `IsLongWeekend` (`EventFlag`). Carried for context and future threshold overrides.

**Alert levels:**

| Level | Name | Derivation basis |
| --- | --- | --- |
| `L0` | Normal | value below the L1 threshold (`< P80`) |
| `L1` | Watch | `P80 to < P90` |
| `L2` | Warning | `P90 to < P95` |
| `L3` | Critical | `P95 up` |

> **Threshold model (confirmed):** the L1/L2/L3 **absolute amounts** for every
> `Scope × Indicator × Window × DayType` live in the **`EWI_AlertThreshold` reference table**
> (loaded from [data/ewi-alert-threshold.csv](data/ewi-alert-threshold.csv)). `Gold_EarlyWarning`
> **joins** each computed value to this table and assigns the **Alert Level** (L0–L3) in KQL — so
> retuning a threshold is a **one-cell edit** in the reference table, not a code or Activator
> change. The amounts are calibrated from historical percentiles (`P80/P90/P95` of the same
> bucket × day type × scope); the percentile rank stays as drill-down methodology, not the KPI.

---

## Measurement period (confirmed)

Each indicator is computed **per current 30-minute bucket** (periodic), **except**:

- **#3 Accum Net Outflow** — cumulative from **00:00** to the current bucket.
- **#5 Transaction Velocity** — current bucket ÷ average of the **prior N=4** 30-min buckets (configurable; `N=0` = expanding all-day).

The comparable-time **window + day type** are emitted as **filter columns** for Activator;
they do **not** change the measurement span.

> ✅ **Confirmed:** #1/#2/#4/#6 are **30-minute periodic**.

---

## The 8 Early Warning Indicators

For a given **Scope**, **Date `d`**, and current 30-minute **bucket `b`**, the base
per-bucket aggregates (over in-scope, non-excluded rows) are:

```kql
GrossOutflow_b = sum(Debit_Amount)                       // Baht
Credit_b       = sum(Credit_Amount)                       // Baht
Net_b          = sum(Net_Amount)                          // = Credit − Debit (Baht, negative ⇒ outflow)
DebitTxn_b     = sum(Debit_Transaction)                   // count
```

| # | Indicator | Group | Unit | Direction (breach when) |
| --- | --- | --- | --- | --- |
| 1 | Gross Outflow | Deposit outflow | MB | value **≥** threshold |
| 2 | Net Outflow | Deposit outflow | MB | value **≤** threshold (negative) |
| 3 | Accum Net Outflow | Deposit outflow | MB | value **≤** threshold (negative) |
| 4 | Debit Transaction Count | Traffic | Million | value **≥** threshold |
| 5 | Transaction Velocity | Traffic | X (ratio) | value **≥** threshold |
| 6 | Average Debit Amount | Large Value Movement | MB | value **≥** threshold |
| 7 | Cluster Share | Concentration | % (0–100) | value **≥** threshold *(numbers pending)* |
| 8 | Sudden Share Jump | Concentration | pp | value **≥** threshold *(numbers pending)* |

### 1. Gross Outflow — `Sum(Debit_Amount)`
Total money **leaving** in the bucket (debit volume). A high gross outflow is the first
sign of unusual withdrawal pressure.

```kql
GrossOutflow_MB = GrossOutflow_b / 1000000.0
```
- **Detects:** raw magnitude of outflow, before netting against inflow.
- **Breach:** `GrossOutflow_MB >= threshold`.

### 2. Net Outflow — `Sum(Credit_Amount) − Sum(Debit_Amount)`
Net movement for the bucket. Despite the name "outflow", the formula is a **net flow**:
positive = net inflow, **negative = net outflow**.

```kql
NetOutflow_MB = Net_b / 1000000.0
```
- **Detects:** genuine drain after inflows offset withdrawals.
- **Breach:** `NetOutflow_MB <= threshold` (thresholds are negative, e.g. −5500).

### 3. Accum Net Outflow — `Sum(Net Flow from 00:00 to current)`
Running total of net flow since midnight (ICT). Tracks how deep the cumulative drain is
through the day.

```kql
// per (Scope, Date) ordered by bucket ascending
AccumNetOutflow_MB = (row_cumsum(Net_b)) / 1000000.0
```
- **Detects:** sustained day-long outflow even when individual buckets look mild.
- **Breach:** `AccumNetOutflow_MB <= threshold` (negative).

### 4. Debit Transaction Count — `Sum(Debit_Transaction)`
Number of debit transactions in the bucket (traffic, not amount).

```kql
DebitTxn_M = DebitTxn_b / 1000000.0                        // in millions
```
- **Detects:** surges in **how many** withdrawals occur (e.g. a run driven by many small debits).
- **Breach:** `DebitTxn_M >= threshold`.

### 5. Transaction Velocity — `Current Debit_Transaction / Avg. prior N buckets`
Ratio of the current bucket's debit count to the **average of the prior `N` 30-minute
buckets** (default **N = 4** → the last 2 hours, per the customer dashboards). `N` is a
configurable parameter (`VelocityN`); set `N = 0` for an expanding all-day average.

```kql
// per (Scope, Date), ordered by bucket ascending; N = 4
| serialize
| extend AvgPriorN = (prev(DebitTxn_b,1) + prev(DebitTxn_b,2) + prev(DebitTxn_b,3) + prev(DebitTxn_b,4)) / 4.0
| extend Velocity  = iff(isnull(AvgPriorN) or AvgPriorN == 0, real(null), DebitTxn_b / AvgPriorN)
```
- **Example (N=4):** current 14:30–15:00 has 620 K debits; the prior four buckets average
  ~437 K → Velocity = **1.42×** (matches the customer dashboard).
- **Detects:** an abrupt spike in transaction pace vs the recent 2-hour baseline.
- **Breach:** `Velocity >= threshold` (e.g. L1 1.5, L2 2.0, L3 3.0).
- **Guardrails:** fewer than `N` prior buckets (start of day) or a zero baseline → `null` → Normal.

### 6. Average Debit Amount — `Gross Outflow / Debit_Transaction`
Mean value per debit transaction — a **large-value-movement** signal (a few big tickets
rather than many small ones).

```kql
AvgDebitAmount_MB = iff(DebitTxn_b > 0, (GrossOutflow_b / DebitTxn_b) / 1000000.0, real(null))
```
- **Unit:** **MB** per transaction (matches the customer trigger sheet, `Average Debit Amount (MB)`).
- **Detects:** unusually large average ticket size (institutional / high-value withdrawals).
- **Breach:** `AvgDebitAmount_MB >= threshold`.
- **Guardrail:** `DebitTxn_b = 0` → `null` → Normal.

### 7. Cluster Share (Retails vs Non-Retails) — `Cluster net outflow ÷ total cluster outflow`
Concentration signal: how much of the bank's **draining** comes from one channel group.
Computed on the **draining magnitude** so it stays bounded 0–100% and is easy to threshold.

```kql
Out_R  = max_of(0.0, -Net_Retails);  Out_NR = max_of(0.0, -Net_NonRetails)
Denom  = Out_R + Out_NR
ClusterShare_Pct(RETAILS)     = iff(Denom > 0, 100.0 * Out_R  / Denom, real(null))
ClusterShare_Pct(NON_RETAILS) = iff(Denom > 0, 100.0 * Out_NR / Denom, real(null))
ClusterShare_Pct(TOTAL_BANK)  = real(null)   // its own share is trivially 100%
```
- **Unit:** percent (0–100); the two cluster rows sum to 100%.
- **Direction:** higher = worse → breach when `ClusterShare_Pct >= threshold`.
- **Detects:** whether outflow is broad-based or dominated by one cluster.
- **Guardrail:** `Denom = 0` (no cluster draining) → `null` → Normal.
- **Thresholds:** pending — value is computed and carried; the customer sets the % in Activator.

> The literal `cluster_net ÷ total_net` was rejected because it can exceed 100% or go negative
> when the clusters offset (one inflow, one outflow); the magnitude form above stays bounded.

### 8. Sudden Share Jump — `Current share − prior-bucket share`
Change in a cluster's `ClusterShare_Pct` versus the **prior 30-minute bucket** — flags an
abrupt concentration shift before the absolute share is extreme.

```kql
// per (Scope, Date) ordered by 30-min bucket ascending
| serialize
| extend ShareJump_Pct = iff(Scope == prev(Scope), ClusterShare_Pct - prev(ClusterShare_Pct), real(null))
```
- **Unit:** percentage points (pp).
- **Direction:** more positive = worse (a cluster's share rising fast) → breach when `ShareJump_Pct >= threshold`.
- **Detects:** rapid migration of outflow into a cluster between consecutive buckets.
- **Guardrail:** first bucket of the day, or a null current/prior share → `null` → Normal.
- **Thresholds:** pending — value computed; customer sets the pp threshold in Activator.

---

## Alerting model — reference-table–driven levels

Scope, thresholds, and criteria are **not** hard-coded and are **not** typed into Activator.
They live in the **`EWI_AlertThreshold` reference table**, and `Gold_EarlyWarning` **joins** each
computed indicator value to that table to assign the current **Alert Level** (L0–L3). Activator
then reacts to the ready-made level (e.g. alert when `Alert_Level in ('L2','L3')`), or still
thresholds a raw value directly if preferred.

### `EWI_AlertThreshold` — the single threshold reference table

One row per `Scope × Indicator × Window × DayType`, loaded from
[data/ewi-alert-threshold.csv](data/ewi-alert-threshold.csv) (**288 rows** = 3 scopes × 8
indicators × 4 windows × 3 day types):

| Column | Type | Purpose |
| --- | --- | --- |
| `Scope` | string | `TOTAL_BANK` / `RETAILS` / `NON_RETAILS` |
| `IndicatorId` | int | 1–8 |
| `IndicatorKey` | string | matches the function's indicator column (e.g. `NetOutflow_MB`) |
| `WindowCode` | string | comparable-time window |
| `DayType` | string | `BUSINESS_DAY` / `WEEKEND` / `HOLIDAY` |
| `Direction` | string | `HIGH_IS_BAD` (≥) or `LOW_IS_BAD` (≤, net-outflow) |
| `L1` `L2` `L3` | real | Watch / Warning / Critical amounts (blank ⇒ level unused) |

**Level derivation** (per matched row, honouring `Direction`):

```kql
Alert_Level = case(
    Direction == "LOW_IS_BAD",
        case(Value <= L3, "L3", Value <= L2, "L2", Value <= L1, "L1", "L0"),
        case(Value >= L3, "L3", Value >= L2, "L2", Value >= L1, "L1", "L0"))
```

Retune a threshold with a **one-cell edit** in
[data/ewi-alert-threshold.csv](data/ewi-alert-threshold.csv) → reload the table; no function or
Activator change. Blank `L1/L2/L3` (e.g. #7 / #8 pending) ⇒ that level is skipped and the
indicator stays `L0` until the customer supplies numbers.

> This **restores a reference-table** approach: instead of typing L1/L2/L3 into Activator per
> rule, the full `Scope × Indicator × Window × DayType` matrix is versioned in the repo and the
> level is computed in KQL. Activator rules become simple — they watch `Alert_Level`.

### `Gold_EarlyWarning` — one row per Scope × 30-min bucket × indicator (long)

| Column | Type | Purpose |
| --- | --- | --- |
| `Object_Id` | string | Activator object identity = `Scope|IndicatorKey` (per Scope × indicator) |
| `Scope` | string | `TOTAL_BANK` / `RETAILS` / `NON_RETAILS` — **filter** |
| `Date_ICT` | string | Business date (ICT) |
| `Bucket_Start` | datetime | 30-min bucket start (ICT) |
| `Bucket_Label` | string | e.g. `08:00-08:30` |
| `Alert_Time` | datetime | Evaluation time (ICT) |
| `WindowCode` / `WindowName` | string | comparable-time window — **filter** |
| `DayType` | string | `BUSINESS_DAY` / `WEEKEND` / `HOLIDAY` — **filter** |
| `EventFlag` | string | `NORMAL` / `MONTH_END,PAYROLL` … — **filter** |
| `IsMonthEnd` / `IsPayroll` / `IsLongWeekend` | bool | **filter** |
| `IndicatorId` | int | 1–8 |
| `IndicatorKey` | string | e.g. `NetOutflow_MB` — **filter** |
| `IndicatorName` | string | display, e.g. `Net Outflow` |
| `Unit` | string | `MB` / `Million` / `X` / `%` / `pp` |
| `Value` | real | the computed indicator value |
| `Direction` | string | `HIGH_IS_BAD` / `LOW_IS_BAD` (from threshold) |
| `L1` `L2` `L3` | real | matched thresholds (from `EWI_AlertThreshold`) |
| `Alert_Level` | string | `L0` / `L1` / `L2` / `L3` — **the alert signal** |
| `Alert_Rank` | int | 0–3 (numeric level, for ordering / max) |

**Grain:** 3 scopes × 8 indicators × 48 buckets/day = 1 152 rows/day.
`Object_Id = Scope|IndicatorKey`, so each scope-indicator is tracked independently by Activator.

**Assigned levels** — `Gold_EarlyWarning` joins `EWI_AlertThreshold` (on
`Scope × IndicatorKey × WindowCode × DayType`) and emits, per **Scope × 30-min bucket ×
indicator**, the `Value`, matched `L1/L2/L3`, and the resulting `Alert_Level` (L0–L3). Thresholds
are no longer typed into Activator.

**Refresh & history** — the base MV `mv_DepositMovementEarlyWarning` **auto-refreshes** as Silver
ingests (no scheduler) and retains history per its retention policy. `Gold_EarlyWarning()` derives
the enriched rows **on read**, so Activator and Power BI always see current data without a stored
table.

**Example Activator rule**
> Object `TOTAL_BANK|NetOutflow_MB` · when `Alert_Level in ('L2','L3')` → alert.
>
> The level already encodes the `Window × DayType` threshold from `EWI_AlertThreshold`, so the
> rule is a single condition — no per-window numbers typed in Activator. Retune by editing the
> reference CSV and reloading.

---

## 30-minute notification (digest)

Independent of the tier alerts, a scheduled 30-minute message reports, per scope:

```
Periodic net outflow of 08:00 - 08:30 = xx.xx bn,
Cumulative net outflow from 00:00 until 08:30 = xx.xx bn
```

- **Periodic** = current 30-minute net outflow. Filter `IndicatorKey == "NetOutflow_MB"`; the
  digest value in **billions** is `Value / 1000` (MB → Bn).
- **Cumulative** = `IndicatorKey == "AccumNetOutflow_MB"` from 00:00; billions = `Value / 1000`.

---

## Deployment (KQL scripts)

Run in the `DepositMovement` KQL database (inside Eventhouse `eh-rti-deposit`).

**Deploy in order:**

1. ⏳ **`EWI_AlertThreshold`** reference table — [kql/16-create-EWI_AlertThreshold.kql](kql/16-create-EWI_AlertThreshold.kql)
   (create + policies + CSV mapping) and [kql/17-load-EWI_AlertThreshold.kql](kql/17-load-EWI_AlertThreshold.kql)
   (load 288 rows from [data/ewi-alert-threshold.csv](data/ewi-alert-threshold.csv)). Retune by
   editing the CSV, re-running the melt script, and re-running kql/17.
2. ⏳ **`mv_DepositMovementEarlyWarning`** base MV — [kql/10-create-mv_DepositMovementEarlyWarning.kql](kql/10-create-mv_DepositMovementEarlyWarning.kql)
   Additive per-bucket sums on Silver (exclude `MSYG`/`SYSG`, tag `IsRetail`, bin 30-min). Created
   `WITH (backfill=true)` → **auto-backfills and then auto-refreshes** as Silver ingests. Retention
   `365d` keeps history.
3. ⏳ **`Gold_EarlyWarning(TargetDate, VelocityN=4)`** — [kql/11-create-fn_Gold_EarlyWarning.kql](kql/11-create-fn_Gold_EarlyWarning.kql)
   Reads the MV, rolls up to the 3 scopes, computes all 8 indicators, **joins `EWI_AlertThreshold`**,
   and assigns `Alert_Level` (L0–L3) per Scope × bucket × indicator.
4. ⏳ **Verification** — [kql/12-verify-EarlyWarning.kql](kql/12-verify-EarlyWarning.kql).

**Activator:** runs `Gold_EarlyWarning()` every 30 min — [Production 09 — Activator Alerts](../09-activator-alerts/) *(⏳ wiring next)*. No scheduler or stored table required.

---

## Open points

- **#7 Cluster Share** and **#8 Sudden Share Jump** thresholds — the customer supplies the
  % / pp numbers; add them to [data/ewi-alert-threshold.csv](data/ewi-alert-threshold.csv) and
  reload `EWI_AlertThreshold`. Values are computed now; these two stay `L0` until filled.
- **Trigger-amount calibration** — the L1/L2/L3 amounts in the reference table are calibrated
  from historical percentiles (P80/P90/P95) per 30-min bucket × day type × scope (Phase 1.5).
- **Engine enrichment (later phases)** — add *deviation*, *persistence*, and *multi-signal*
  logic on top of the Phase-1 magnitude comparison.
- **`single-transaction max`** — deferred; needs transaction-level data not in the aggregated feed.
