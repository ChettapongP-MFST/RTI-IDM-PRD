# Production 08 — Data Activator Alerts (Email & Teams Notification)

> **Status:** ✅ Ready

Configure **Data Activator (Reflex)** to monitor the intraday `Net_Amount` from the **Gold** materialized view `mv_Summary_Product_Channel_Alert`, at **Product + Channel** granularity, and send **tiered alerts** to **email** and **Microsoft Teams** when net outflow breaches a threshold.

```
Gold MV (mv_Summary_Product_Channel_Alert)  ──►  Activator rules (3 tiers)  ──►  Email + Teams
```

**Prerequisite:** [Production 03 — Summary Table (Gold)](../03-summary-table/) (the MV exists & is healthy) · [Production 07 — Sample Data](../07-sample-data/) (data to alert on)

| Item | Value |
|---|---|
| Source object | `mv_Summary_Product_Channel_Alert` (Gold, auto-aggregated) |
| Monitored measure | `Net_Amount` (Baht) |
| Monitor granularity | **Product + Channel** |
| Scope | **Current intraday only** — `Date == startofday(now() + 7h)` |
| Activator item | `act-deposit-alerts` |
| Alert tiers | High / Medium / Low / Normal |
| Actions | **Email** + **Message in Teams** |
| Time zone | **Bangkok / ICT (UTC+7)** |

---

## P8.0 — What changed from the workshop

This module mirrors [Workshop 08](../../workshops/08-activator-alerts/) but targets the **production Gold layer** and adds an **email** channel.

| Aspect | Workshop 08 | **Production 08** |
|---|---|---|
| Source | Bronze `DepositMovement` | **Gold `mv_Summary_Product_Channel_Alert`** |
| Granularity | Channel only (cumulative total) | **Product + Channel** (per-object) |
| Threshold applies to | one cumulative grand total | **each `Net_Amount` row (Product + Channel)** |
| Scope | today (intraday) | **today only** — `now() + 7h`, yesterday excluded |
| Rule design | Option A (3 rules) **or** Option B (1 rule) | **3 rules, one per tier** (as required) |
| Actions | Teams only | **Email + Teams** |

---

## P8.1 — Alert requirement

Monitor `Net_Amount` for **each Product + Channel** for **today's date (ICT)**. When a Product/Channel's net crosses a threshold, fire an alert to email and Teams.

### Three alert tiers (thresholds in **Baht**)

| Tier | Condition on `Net_Amount` | Flag | Severity |
|---|---|---|---|
| 🔴 **High** | `Net_Amount <= -15000000000` | `High` | Red |
| 🟠 **Medium** | `Net_Amount <= -10000000000` | `Medium` | Orange |
| 🟡 **Low** | `Net_Amount <=  -5000000000` | `Low` | Yellow |
| ✅ **Normal** | otherwise | `Normal` | — |

> ⚠ **Units** — the raw data is in **Baht**, not millions. So −15,000 M Baht = `-15000000000` in the KQL/rule. `case()` is evaluated **top-to-bottom** (High first), so each row lands in exactly one tier.

### Every notification includes

- **Alert flag** (High / Medium / Low)
- **Product** and **Channel** that breached
- **Net Amount** (today's total for that Product/Channel)
- **Date** and **Latest time slot**
- **Alert timestamp** (ICT)

---

## P8.2 — Create the Activator item

1. Open the **`RTI-IDM-PRD`** workspace.
2. **+ New item** → search for **Activator** (a.k.a. **Reflex**) → name it `act-deposit-alerts`.
3. Click **Create**.

> 💡 If you don't see "Activator", ensure the workspace has a Fabric capacity (F2+) and Activator is enabled in the admin portal.

---

## P8.3 — Prepare & validate the KQL event source

Before wiring the rule, validate the query that powers the alerts. Run it in the **KQL Database query editor** (DB `DepositMovement`) to confirm the shape.

> ⏰ **Timezone** — `Date` is stored in **ICT (UTC+7)**. KQL `now()` is UTC, so offset by **+7 h** before truncating: `let now_ict = now() + 7h;`.

**[kql/08-alert-source-Product-Channel.kql](kql/08-alert-source-Product-Channel.kql)**

```kusto
let now_ict = now() + 7h;                       // UTC -> ICT (Bangkok, UTC+7)
let today   = startofday(now_ict);
mv_Summary_Product_Channel_Alert
| where Date == today                           // intraday only — excludes yesterday
| summarize
    Net_Amount        = sum(Net_Amount),        // monitored measure (Baht)
    Credit_Amount     = sum(Credit_Amount),
    Debit_Amount      = sum(Debit_Amount),
    Total_Transaction = sum(Total_Transaction),
    Latest_Time       = max(Time)
    by Product, Channel                         // monitor granularity
| extend Alert_Flag = case(
        Net_Amount <= -15000000000, "High",
        Net_Amount <= -10000000000, "Medium",
        Net_Amount <=  -5000000000, "Low",
        "Normal")
| extend
    Object_Id    = strcat(Product, " / ", Channel),   // Activator object identity
    Net_Amount_M = round(Net_Amount / 1000000, 1),    // millions of Baht (display)
    Date_ICT     = format_datetime(today, "yyyy-MM-dd"),
    Alert_Time   = now_ict
| project
    Object_Id, Product, Channel, Alert_Flag,
    Net_Amount, Net_Amount_M,
    Credit_Amount, Debit_Amount, Total_Transaction,
    Latest_Time, Date_ICT, Alert_Time
| order by Net_Amount asc
```

**Column explanation:**

| Column | Meaning |
|---|---|
| `Object_Id` | `Product / Channel` — the **object identity** Activator tracks state on |
| `Product` | Product dimension (`C`, `L`, `S`) |
| `Channel` | Channel dimension (`ATM`, `BCMS`, `ENET`, `TELL`, …) |
| `Alert_Flag` | Tier for this row: `High` / `Medium` / `Low` / `Normal` |
| `Net_Amount` | Today's `sum(Net_Amount)` for this Product/Channel, in **Baht** — the number compared to thresholds |
| `Net_Amount_M` | Same value in **millions of Baht** (display only) |
| `Credit_Amount` / `Debit_Amount` | Inflow / outflow totals (Baht) |
| `Total_Transaction` | Transaction count |
| `Latest_Time` | Most recent time slot with data today |
| `Date_ICT` | ICT date being evaluated — verify it equals today |
| `Alert_Time` | Current Bangkok time when the query ran |

> 💡 **Why per-object?** Activator tracks **one state per `Object_Id`**, so each Product/Channel fires independently. With the `Changes` condition (P8.5), a given Product/Channel alerts **once per tier transition**, not on every cycle.
>
> If the query returns **0 rows**, check: (a) there is data for today's ICT date, (b) the `+7h` offset is applied, (c) the MV is healthy (Production 03).

---

## P8.4 — Add the alert from the KQL Queryset

> ⚠️ **Do not** try to wire KQL from inside Activator. The Activator (and Eventstream) **"Select a data source" / "Connect data source"** dialogs do **not** list **KQL / Kusto / Eventhouse** — searching returns no results. An Eventstream "bridge" is **not** needed and does **not** work for this. The supported path is to push the alert **out** from the **KQL Queryset** side.

1. Open the **KQL Queryset** connected to the `DepositMovement` database.
2. Paste the query from **P8.3** and **Run** to confirm it returns rows.
3. Toolbar → **More… (⋯)** → **Add alert** (a.k.a. **Set alert**).
4. In the **Add rule** panel (this is the **seed dialog** — intentionally limited):
   - **Rule name**: `rule_Net_Amount_alert` (renamed per tier next)
   - **Source / Query**: auto-filled from the queryset
   - **Run query every**: `5 minutes` (or `1 minute` for testing)
   - **Condition → Check**: only **`On each event`** is offered here — leave it as-is.
   - **Action**: pick any (e.g. **Message to individuals** → yourself) — refined in P8.6
5. **Save location**: `act-deposit-alerts` → **Create**.

> ⚠️ **The seed dialog cannot build the tiers.** It has **no** `+ Add condition`, no **Changes**, and no **Numeric** operators — only `On each event`. That is expected. The **full condition editor** appears only **after** you create the rule and **open the Activator item** (`act-deposit-alerts-01`). All tier logic (P8.5) is built there, not in this dialog.

6. After **Create**, click **Open** (or open the `act-deposit-alerts-01` item from the workspace) to reach the full rule editor.

---

## P8.5 — Configure the 3 alert rules (one per tier)

> 🧭 **You must be inside the `act-deposit-alerts-01` Activator item** (not the seed dialog) for the steps below. The multi-condition editor with **Changes** and **Numeric** operators only exists here.

Create **3 rules** with **exclusive numeric ranges** on `Net_Amount` so each fires **only** for its own tier — no overlap.

> 💡 Multiple conditions in one rule act as **AND**. A `Changes` condition on `Alert_Flag` (Condition 1) makes each rule fire **once per tier transition** per object, not every cycle.
>
> ⚠️ **Order matters** — the `Changes` condition **must be Condition 1**. Placing it after numeric conditions causes a save error.
>
> Thresholds are entered in **Baht** because the rule monitors the raw `Net_Amount` column.

| Rule | Condition 1 | Condition 2 (Numeric) | Condition 3 (Numeric) | Fires for |
|---|---|---|---|---|
| `rule_alert_High` | `Alert_Flag` **Changes** | `Net_Amount` ≤ `-15000000000` | — | 🔴 High |
| `rule_alert_Medium` | `Alert_Flag` **Changes** | `Net_Amount` ≤ `-10000000000` | `Net_Amount` > `-15000000000` | 🟠 Medium |
| `rule_alert_Low` | `Alert_Flag` **Changes** | `Net_Amount` ≤ `-5000000000` | `Net_Amount` > `-10000000000` | 🟡 Low |

### P8.5.1 — 🔴 High

1. Rename the seed rule `rule_Net_Amount_alert` → `rule_alert_High`.
2. **Condition 1** — Operation: **Common change → Changes**; Column: `Alert_Flag`; Occurrence: `Every time the condition is met`.
3. **+ Add condition** → **Condition 2** — **Numeric state → Is less than or equal to**; Column: `Net_Amount`; Value: `-15000000000`.
4. Configure **Actions** (P8.6). **Save and update**.

### P8.5.2 — 🟠 Medium

1. Right-click the event → **New rule** → `rule_alert_Medium`.
2. **Condition 1** — **Changes** on `Alert_Flag`.
3. **Condition 2** — **Is less than or equal to** `Net_Amount` = `-10000000000`.
4. **Condition 3** — **Is greater than** `Net_Amount` = `-15000000000`.
5. Configure **Actions** (P8.6). **Save and update**.

### P8.5.3 — 🟡 Low

1. Right-click the event → **New rule** → `rule_alert_Low`.
2. **Condition 1** — **Changes** on `Alert_Flag`.
3. **Condition 2** — **Is less than or equal to** `Net_Amount` = `-5000000000`.
4. **Condition 3** — **Is greater than** `Net_Amount` = `-10000000000`.
5. Configure **Actions** (P8.6). **Save and update**.

### Final Explorer panel

```
mv_Summary_Product_Channel_Alert
  └─ alert event
       ├─ rule_alert_Low      (Running)
       ├─ rule_alert_Medium   (Running)
       └─ rule_alert_High     (Running)
```

> 💡 **Quick test** — click **Send me a test action** on each rule to verify both email and Teams connections work.

---

## P8.6 — Actions & message templates

Each rule sends **two** actions: an **Email** and a **Teams** message. Both use **dynamic content** placeholders — in the Activator message editor, click **Insert dynamic content** to insert each `{ColumnName}` chip mapped to the query columns: `Alert_Flag`, `Product`, `Channel`, `Net_Amount`, `Net_Amount_M`, `Credit_Amount`, `Debit_Amount`, `Total_Transaction`, `Latest_Time`, `Date_ICT`, `Alert_Time`.

### 4.1 — Email template

Rule **Action → Email**. Set **To** (e.g. treasury distribution list), then:

**Subject:**
```
[Deposit Alert – {Alert_Flag}] {Product}/{Channel} Net {Net_Amount_M} M THB — {Date_ICT}
```

**Body:**
```
Intraday Deposit Movement Alert
========================================================

Alert Level    : {Alert_Flag}
Product         : {Product}
Channel         : {Channel}
Business Date    : {Date_ICT}  (ICT / UTC+7)
Latest Slot      : {Latest_Time}
Evaluated At     : {Alert_Time}

--------------------------------------------------------
Net Amount       : {Net_Amount_M} M THB   ( {Net_Amount} THB )
Credit (Inflow)  : {Credit_Amount} THB
Debit  (Outflow) : {Debit_Amount} THB
Transactions      : {Total_Transaction}
--------------------------------------------------------

Thresholds (Net_Amount, Baht):
  • Low     : <= -5,000,000,000   (-5,000 M)
  • Medium  : <= -10,000,000,000  (-10,000 M)
  • High    : <= -15,000,000,000  (-15,000 M)

Action Required:
  • Low     : Monitor closely
  • Medium  : Escalate to Treasury
  • High    : Immediate management action

Source : mv_Summary_Product_Channel_Alert (Gold) · Workspace RTI-IDM-PRD
This is an automated alert from Data Activator (act-deposit-alerts).
```

### 4.2 — Microsoft Teams chat template

Rule **Action → Message me in Teams** (or select a Team/Channel, e.g. `#rti-alerts`). Sign in with your M365 account, then:

**Headline:**
```
🏦 Deposit Alert {Alert_Flag} — {Product}/{Channel}: {Net_Amount_M} M THB
```

**Message:**
```
Intraday Deposit Movement Alert
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Alert Level : {Alert_Flag}
Product     : {Product}
Channel     : {Channel}
Date        : {Date_ICT}  (ICT)
Latest Slot : {Latest_Time}
Alert Time  : {Alert_Time}

Net Amount  : {Net_Amount_M} M THB
Credit      : {Credit_Amount} THB
Debit       : {Debit_Amount} THB
Txns        : {Total_Transaction}

Action Required:
• 🟡 Low (-5,000 M)   : Monitor closely
• 🟠 Medium (-10,000 M): Escalate to Treasury
• 🔴 High (-15,000 M)  : Immediate management action
```

> 💡 Each `{ColumnName}` becomes a **dynamic content chip** (a pill with `×`). In the **Context** dropdown, optionally add `Net_Amount`, `Alert_Flag`, `Product`, `Channel` as supplementary data.
>
> 💡 **Richer Teams card (optional)** — Rule action → **Run a Power Automate flow** → **Post adaptive card in a chat or channel**, and color the card by tier.

---

## P8.7 — Test the alerts

**Option A — use existing intraday data.** Run the **Quick check** at the bottom of [kql/08-alert-source-Product-Channel.kql](kql/08-alert-source-Product-Channel.kql); any row with `Alert_Flag != "Normal"` should trigger the matching rule on the next cycle.

**Option B — lower thresholds temporarily.** If nothing breaches, edit each rule's numeric value (e.g. High `-1000000000`, Medium `-500000000`, Low `-100000000`), wait one cycle, confirm email + Teams arrive, then **reset** to production values.

**Option C — simulate ingestion.** Upload sample CSVs from [Production 07](../07-sample-data/) into `inbound/statement/` for **today's ICT date**; ingestion → MV auto-aggregates → Activator evaluates → alerts fire.

### Verification checklist

- [ ] Email **and** Teams arrive within one evaluation cycle of a breach
- [ ] `Alert_Flag` matches the tier (Low / Medium / High)
- [ ] `Product` + `Channel` + `Net_Amount` shown correctly
- [ ] Only **today's** data alerts (yesterday excluded)
- [ ] Each Product/Channel fires **once per tier transition**, not every cycle

---

## ✅ Exit Criteria

- [ ] Activator item `act-deposit-alerts` exists and is running (green)
- [ ] Event source = `mv_Summary_Product_Channel_Alert`, filtered to **today (ICT)**, grouped by **Product + Channel**, with `Object_Id`
- [ ] **3 rules** — `rule_alert_High` (−15,000,000,000), `rule_alert_Medium` (−10,000,000,000), `rule_alert_Low` (−5,000,000,000) on `Net_Amount` with a `Changes` guard on `Alert_Flag`
- [ ] Each rule sends **Email + Teams** using the P8.6 templates
- [ ] At least one **test alert** delivered to both channels
- [ ] Alerts fire **once per breach**, intraday only

---

## 📚 Reference Links

| Concept | Documentation |
|---|---|
| Data Activator overview | [What is Data Activator?](https://learn.microsoft.com/fabric/data-activator/data-activator-introduction) |
| Create Activator rules | [Create rules in Data Activator](https://learn.microsoft.com/fabric/data-activator/data-activator-create-triggers-design-mode) |
| Activator + KQL event source | [Get data from Eventhouse](https://learn.microsoft.com/fabric/data-activator/data-activator-get-data-eventstreams) |
| Email action | [Email alerts from Activator](https://learn.microsoft.com/fabric/data-activator/data-activator-trigger-action-email) |
| Teams notification action | [Send Teams notifications](https://learn.microsoft.com/fabric/data-activator/data-activator-teams-notifications) |
| Materialized views | [Materialized views overview](https://learn.microsoft.com/fabric/real-time-intelligence/materialized-view) |
| KQL `case()` | [case()](https://learn.microsoft.com/kusto/query/case-function?view=microsoft-fabric) |

---

**Prerequisite:** [Production 03 — Summary Table (Gold)](../03-summary-table/) · **Back to:** [Production overview](../)
