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

**3 Day types** (from Silver `DayClassification`): `BUSINESS_DAY`, `WEEKEND`, `HOLIDAY` (= "Public Holiday").

**3 Event flags** (from Silver): `IsMonthEnd`, `IsPayroll`, `IsLongWeekend` (`EventFlag`). Carried for context and future threshold overrides.

**Alert levels:**

| Level | Name | Derivation basis |
| --- | --- | --- |
| `L0` | Normal | value below the L1 threshold (`< P80`) |
| `L1` | Watch | `P80 to < P90` |
| `L2` | Warning | `P90 to < P95` |
| `L3` | Critical | `P95 up` |

> The `P80/P90/P95` percentiles are the **derivation basis** documented by the business.
> The threshold tabs already provide **absolute values** per cell, so tiering compares the
> indicator against those numbers (no live percentile computation).

---

## Measurement period (working assumption)

Each indicator is computed **per current 30-minute bucket** (periodic), **except**:

- **#3 Accum Net Outflow** — cumulative from **00:00** to the current bucket.
- **#5 Transaction Velocity** — current bucket ÷ **expanding** average of all prior buckets that day.

The comparable-time **window + day type** select the applicable threshold row; they do
**not** change the measurement span.

> ⚠️ **Open point to confirm:** whether #1/#2/#4/#6 should instead be *window-to-date*
> (accumulated within the current comparable-time window). This README assumes **30-minute
> periodic**; change here if window-to-date is intended.

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
| 7 | Cluster Share | Concentration | ratio/% | *thresholds pending (`xx`)* |
| 8 | Sudden Share Jump | Concentration | ratio/% | *thresholds pending (`xx`)* |

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
Ratio of the current bucket's debit count to the **average of all prior 30-minute buckets
that day** (00:00 → current − 1). `N` is the **expanding** number of available prior
buckets (grows through the day), not a fixed window.

```kql
// per (Scope, Date) ordered by bucket ascending
| serialize
| extend _priorSum   = row_cumsum(DebitTxn_b) - DebitTxn_b     // sum of prior buckets
| extend _priorCount = row_cumsum(1) - 1                        // N = number of prior buckets
| extend AvgPrior    = iff(_priorCount > 0, _priorSum / _priorCount, real(null))
| extend Velocity    = iff(isnull(AvgPrior) or AvgPrior == 0, real(null), DebitTxn_b / AvgPrior)
```
- **Example:** current 08:00–08:30 → N = 16 prior buckets; current 09:00–09:30 → N = 18.
  If the current bucket has 800 debits and the prior average is 375 → Velocity = **2.13×**.
- **Detects:** an abrupt spike in transaction pace relative to the day's own baseline.
- **Breach:** `Velocity >= threshold` (e.g. L1 1.5, L2 2.0, L3 3.0).
- **Guardrails:** first bucket of the day (no prior) or a zero baseline → `null` → Normal.
  "Available" prior buckets = buckets that have data; truly-empty slots are excluded.

### 6. Average Debit Amount — `Gross Outflow / Debit_Transaction`
Mean value per debit transaction — a **large-value-movement** signal (a few big tickets
rather than many small ones).

```kql
AvgDebit_MB = iff(DebitTxn_b > 0, (GrossOutflow_b / DebitTxn_b) / 1000000.0, real(null))
```
- **Detects:** unusually large average ticket size (institutional / high-value withdrawals).
- **Breach:** `AvgDebit_MB >= threshold`.
- **Guardrail:** `DebitTxn_b = 0` → `null` → Normal.

### 7. Cluster Share (Retails vs Non-Retails) — `Cluster net outflow / Total-bank net outflow`
Share of the bank's net outflow concentrated in a cluster (Retails or Non-Retails).
A **concentration** signal: outflow bunching into one channel group.

```kql
RetailsShare    = iff(Net_Total != 0, Net_Retails    / Net_Total, real(null))
NonRetailsShare = iff(Net_Total != 0, Net_NonRetails / Net_Total, real(null))
```
- **Detects:** whether outflow is broad-based or driven by one cluster.
- **Breach:** thresholds **pending** (`xx` in the requirement) — the value is computed and
  carried, tiering is deferred until thresholds are provided.
- **Guardrail:** `Net_Total = 0` → `null`.

### 8. Sudden Share Jump — `Current share − Prior share`
Change in a cluster's share versus the **prior 30-minute bucket** — detects an abrupt
concentration shift even when the absolute share is not yet extreme.

```kql
// per (Scope/cluster, Date) ordered by bucket ascending
| serialize
| extend ShareJump = Share_b - prev(Share_b)
```
- **Detects:** rapid migration of outflow into a cluster between consecutive buckets.
- **Breach:** thresholds **pending** (`xx`).

---

## Alert levels & thresholds

Thresholds form a matrix of **Scope × Indicator × Level × Window × Day type = 864 cells**
(`3 × 8 × 3 × 4 × 3`). Because that is far too many to hand-manage as Activator rules,
they live in a **reference table** `EarlyWarningThresholds` (CSV-editable, mirroring the
`OperatingWindowsTimes` / holiday pattern):

| Column | Example |
| --- | --- |
| `Scope` | `TOTAL_BANK` |
| `IndicatorNo` | `2` |
| `AlertLevel` | `L3` |
| `WindowCode` | `MORNING_WORKING_HOUR` |
| `DayType` | `BUSINESS_DAY` |
| `Comparator` | `LE` (`GE` / `LE`) |
| `Threshold` | `-5500` (null for pending `xx`) |

**Tier assignment:** the indicator value is compared to its L1/L2/L3 thresholds for the
current `(Scope, Window, DayType)`; the assigned level is the **highest breached** tier
(`L3 > L2 > L1 > L0`). Editing a threshold = update one row and re-ingest the CSV — no KQL
or Activator rule change. Activator then simply watches the computed `Alert_Level`.

**Example (Total Bank · Net Outflow · morning · Business Day):** L1 −3500, L2 −4500,
L3 −5500 MB. A net of −4800 MB → breaches L1 and L2, not L3 → **L2 Warning**.

---

## 30-minute notification (digest)

Independent of the tier alerts, a scheduled 30-minute message reports, per scope:

```
Periodic net outflow of 08:00 - 08:30 = xx.xx bn,
Cumulative net outflow from 00:00 until 08:30 = xx.xx bn
```

- **Periodic** = current 30-minute `NetOutflow` (in **billions**, `/1e9`).
- **Cumulative** = `AccumNetOutflow` from 00:00 (in **billions**).

---

## Planned artifacts (build order)

1. **`EarlyWarningThresholds`** reference table — DDL + CSV mapping + generated 864-row CSV (from the three scope tabs) + verify.
2. **`mv_EarlyWarning_Base`** — 30-minute base MV on Silver: channel-excluded, `IsRetail`-tagged, with `WindowCode` / `DayClassification` / `EventFlag`, periodic sums (`GrossOutflow`, `Credit`, `Net`, `DebitTxn`).
3. **`Gold_EarlyWarning()`** — scope roll-up + cumulative / velocity / avg-debit / cluster-share / sudden-jump + threshold join → `Alert_Level` per Scope × Indicator.
4. **Activator source query + 30-minute digest query**.

---

## Open points

- Confirm the **measurement period** for indicators #1/#2/#4/#6 (30-min periodic — assumed — vs window-to-date).
- Provide **thresholds for #7 Cluster Share and #8 Sudden Share Jump** (currently `xx`).
- Confirm **Sudden Share Jump** compares against the **prior 30-min bucket** (vs prior window).
