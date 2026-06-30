# Production 05 — Event Trigger

> **Status:** 🔧 In Progress

Wire the production pipeline **`pl_ingest_DepositMovement`** to `Microsoft.Storage.BlobCreated` events so every `INTRADAY_SUMMARY_*.CSV` landing in `inbound/statement/` triggers ingestion automatically — no manual runs.

| Item | Value |
|---|---|
| Storage Account | `mockadlsidimdprd001` |
| Container | `inflowoutflow` |
| Folder | `inbound/statement/` |
| Event type | `Microsoft.Storage.BlobCreated` |
| File filter | `*.CSV` |
| Workspace | `RTI-IDM-PRD` |

**Prerequisite:** [Production 04 — Data Pipeline](../04-data-pipeline/) complete
**Next:** [Production 06 — Sample Data](../06-sample-data/)

---

## P5.0 — What changed from the workshop

This module mirrors [Workshop 05](../../workshops/05-event-trigger/) but targets **production storage**. The trigger mechanics (Event Grid subscription → Eventstream → Activator rule → pipeline) are identical.

| Aspect | Workshop | **Production** |
|---|---|---|
| Storage account | `rtistorage01` | **`mockadlsidimdprd001`** |
| Container | `intraday-deposits` | **`inflowoutflow`** |
| Folder | `incoming/` | **`inbound/statement/`** |
| File filter | `.csv` (lowercase) | **`.CSV`** (uppercase) |
| Workspace | `RTI-IntradayDepositMovement` | **`RTI-IDM-PRD`** |
| `subject` begins-with | `.../intraday-deposits/blobs/incoming/` | **`.../inflowoutflow/blobs/inbound/statement/`** |

> **Production ADLS Gen2 path:**
> `https://mockadlsidimdprd001.dfs.core.windows.net` → container `inflowoutflow` → folder `inbound/statement/` → file `INTRADAY_SUMMARY_20260630_0945_1000.CSV`

---

## P5.1 — RBAC prerequisite — EventGrid EventSubscription Contributor

Creating an event-based trigger on ADLS Gen2 requires the **EventGrid EventSubscription Contributor** role on storage account **`mockadlsidimdprd001`**. This allows Fabric to register an Event Grid subscription for `Microsoft.Storage.BlobCreated` events.

If you followed [Production 00 § P0.6.2](../00-prerequisites/README.md#p062-assign-eventgrid-eventsubscription-contributor), this is already in place. If not, assign it now:

1. **[portal.azure.com](https://portal.azure.com)** → storage account **`mockadlsidimdprd001`** → **Access control (IAM)** → **+ Add** → **Add role assignment**.
2. **Role**: `EventGrid EventSubscription Contributor` → **Next**.
3. **Members**: select **your user account** (the person creating the trigger) → **Select** → **Review + assign**.

> ⚠️ Without this role, the **Connect** step in P5.4.3 will fail with a permissions error.

---

## P5.2 — Open the trigger panel

1. **Fabric Portal** → **RTI-IDM-PRD** workspace → open pipeline **`pl_ingest_DepositMovement`**.
2. **Home** ribbon → **Trigger** → **Add trigger**.
3. The **"Add rule"** panel opens on the right.

---

## P5.3 — Rule details

In the **Details** section:

| Field | Value |
|---|---|
| **Rule name** | `rule_new_files_created_deposit` |

---

## P5.4 — Connect the event source (Monitor)

1. Under **Monitor** → click **"Select source events"**.
2. The **Real-Time hub** "Select a data source" panel opens.
3. Select **Azure Blob Storage events**.

### P5.4.1 — Configure connection settings

The **"Configure connection settings"** wizard opens (3-step: Configure → Configure alert → Review + connect).

**Step 1 — Configure:**

| Field | Value |
|---|---|
| Storage account | ● Connect to existing Azure Blob Storage account |
| Subscription | *(select your production subscription)* |
| Azure Blob Storage account | `mockadlsidimdprd001` |

On the right **Stream details** panel:
- **Workspace**: `RTI-IDM-PRD` (should be auto-selected)
- **Eventstream name**: click the pencil icon ✏️ and rename to **`es_adls_blobcreated`**

Click **Next**.

### P5.4.2 — Configure alert — event type and filters

**Step 2 — Configure alert:**

| Field | Value |
|---|---|
| **Event type(s)** | `Microsoft.Storage.BlobCreated` *(default)* |

Under **Set filters**, add two filter rows:

| # | Field | Operator | Value |
|---|---|---|---|
| 1 | `subject` | `String begins with` | `/blobServices/default/containers/inflowoutflow/blobs/inbound/statement/` |
| 2 | `subject` | `String ends with` | `.CSV` |

> 💡 **Why these filters?** The first scopes to blobs in `inbound/statement/` of the `inflowoutflow` container. The second excludes sidecars (`.tmp`, `.crc`, `_SUCCESS`, etc.) and fires **only** for `.CSV` files.

Click **Next**.

### P5.4.3 — Review + connect

**Step 3 — Review + connect:**

Verify the summary:

| Setting | Expected |
|---|---|
| Event source type | Azure Blob Storage events |
| Subscription | *(your production subscription)* |
| Azure Blob Storage account | `mockadlsidimdprd001` |
| Event types | Microsoft.Storage.BlobCreated |
| Event filters | subject StringBeginsWith `.../inflowoutflow/blobs/inbound/statement/` |
| | subject StringEndsWith `.CSV` |
| Workspace | RTI-IDM-PRD |
| Eventstream name | `es_adls_blobcreated` |

Click **Connect**.

Wait for all three tasks to complete:

| Task | Expected status |
|---|---|
| Create Azure blob storage system events | ✅ Successful |
| Create Eventstream | ✅ Successful |
| Link Azure blob storage system events to Fabric events | ✅ Successful |

Click **Save** to return to the "Add rule" panel.

---

## P5.5 — Verify action and parameters

Back on the **"Add rule"** panel, verify:

**Action** section — pre-populated from the pipeline:

| Field | Value |
|---|---|
| Select action | Run Pipeline |
| Fabric item | `pl_ingest_DepositMovement` / RTI-IDM-PRD |

**Parameters** section — auto-mapped event properties:

| Parameter | Type | Mapped to |
|---|---|---|
| Type | String | `__type` |
| Subject | String | `__subject` |
| Source | String | `__source` |

> 💡 **About `__subject`:** The `Subject` parameter receives the full blob path, e.g.
> `/blobServices/default/containers/inflowoutflow/blobs/inbound/statement/INTRADAY_SUMMARY_20260630_0945_1000.CSV`
> The pipeline's `Set vFileName` activity ([Production 04 § P4.4.0b](../04-data-pipeline/README.md)) extracts just the filename using `replace(coalesce(Subject, pFileName), '...inbound/statement/', '')` → `INTRADAY_SUMMARY_20260630_0945_1000.CSV`.

---

## P5.6 — Save location and create

In the **Save location** section:

| Field | Value |
|---|---|
| Workspace | `RTI-IDM-PRD` |
| Item | Create a new item |
| New item name | `tg_blobcreated_deposit` |

Click **Create**.

The **Rules** panel shows:

```
rule_new_files_created_deposit   [New]   🟢 Running
```

The trigger is now live.

---

## P5.7 — Workspace items created

After completing this module, your workspace has two new items:

| Item | Type | Purpose |
|---|---|---|
| `es_adls_blobcreated` | Eventstream | Receives Azure Blob Storage events from `mockadlsidimdprd001` |
| `tg_blobcreated_deposit` | Activator (Reflex) | Contains the rule that triggers the pipeline on new `.CSV` files |

---

## P5.8 — Validate (via Azure Portal upload)

1. **[portal.azure.com](https://portal.azure.com)** → open storage account `mockadlsidimdprd001` → **Data storage** → **Containers** → `inflowoutflow`.
2. Navigate into the `inbound/statement/` folder (create it via **+ Add Directory** if it does not exist).
3. Top toolbar → **Upload** → pick `resources/prd_datasets/INTRADAY_SUMMARY_20260630_0945_1000.CSV` from your local copy of this repo → **Upload**.
4. Switch to **Fabric Portal** → left nav → **Monitor** (Monitor hub) → **Pipeline runs**.
5. Within ~30 seconds a new run of `pl_ingest_DepositMovement` should appear and complete **Succeeded**.
6. Confirm one new `Success` row in `wh_control_framework.dbo.ProcessedFiles`, fresh rows in `DepositMovement`, and that the Gold materialized view `mv_Summary_Product_Channel_Alert` reflects the new data (auto-refresh — no pipeline step).

> ⚠️ **First trigger may take 1–2 minutes.** The Eventstream needs to warm up on first use. Subsequent triggers fire within seconds.

> 💡 **Idempotency check:** re-upload the same file — the pipeline still runs, but the audit row is `Skipped-Duplicate` and no new Bronze rows are added.

---

## ✅ Exit Criteria

- [ ] EventGrid EventSubscription Contributor role assigned on `mockadlsidimdprd001`
- [ ] Eventstream `es_adls_blobcreated` exists in workspace `RTI-IDM-PRD`
- [ ] Activator `tg_blobcreated_deposit` exists and shows **Running**
- [ ] Trigger fires on `.CSV` landing in `inbound/statement/`
- [ ] Pipeline completes with 1 `Success` row in `wh_control_framework.dbo.ProcessedFiles`
- [ ] Gold materialized view `mv_Summary_Product_Channel_Alert` reflects the ingested file (auto-refresh)

→ Proceed to **[Production 06 — Sample Data](../06-sample-data/)**

---

## Reference

| Topic | Link |
|---|---|
| Workshop equivalent | [Workshop 05 — Event-Based Trigger](../../workshops/05-event-trigger/) |
| RBAC setup | [Production 00 § P0.6.2](../00-prerequisites/README.md#p062-assign-eventgrid-eventsubscription-contributor) |
| Pipeline build | [Production 04 — Data Pipeline](../04-data-pipeline/) |
| Filename parsing | [Production 04 § P4.4.0b](../04-data-pipeline/README.md) |
