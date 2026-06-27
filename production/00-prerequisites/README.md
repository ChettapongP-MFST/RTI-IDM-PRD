# Production 00 — Prerequisites & Trusted Workspace Access

Before deploying anything, verify Azure and Fabric readiness, collect the values each later module will reference, and configure **Trusted Workspace Access** so the Fabric pipeline can reach the firewall-enabled ADLS Gen2.

> This module is the same as [Workshop 00](../../workshops/00-prerequisites/) with production-specific values and an explicit callout for the **EventGrid EventSubscription Contributor** role required by the production event trigger.

**Estimated time:** 30–45 minutes  
**Next:** [Production 01 — Eventhouse KQL Tables](../01-eventhouse-kql-tables/)

---

## P0.1 Azure Prerequisites

| # | Item | How to verify (Portal) |
|---|---|---|
| 1 | Azure subscription with **Contributor** on target resource group | [portal.azure.com](https://portal.azure.com) → Resource group → **Access control (IAM)** → **View my access** |
| 2 | Permission to create **Storage accounts** | Same IAM view — role must be Contributor / Owner / Storage Account Contributor |
| 3 | Permission to assign **Storage Blob Data Contributor** RBAC | IAM → **Check access** → role must be **User Access Administrator** or **Owner** |
| 4 | Permission to assign **EventGrid EventSubscription Contributor** RBAC | Same IAM view — requires User Access Administrator or Owner on the storage account |
| 5 | Ability to deploy an ARM template via portal **Custom deployment** | Portal → search `deploy a custom template` |

## P0.2 Fabric Prerequisites

| # | Item | How to verify |
|---|---|---|
| 1 | **F-SKU** Fabric capacity (not Trial) | Fabric Admin portal → Capacity settings |
| 2 | Existing workspace attached to the F-SKU capacity | Workspace → Workspace settings → License info |
| 3 | **Workspace identity** enabled for the workspace | Workspace settings → Workspace identity → **+ Add** |
| 4 | Workspace identity is **Contributor** of the workspace | Manage access → ensure identity listed as Contributor |
| 5 | Your account has **Admin** or **Member** role on the workspace | Manage access |
| 6 | Eventhouse licence available (part of Fabric F-SKU) | Create test Eventhouse |

## P0.2.1 Microsoft Teams Prerequisite (for Activator alerts)

| # | Item | How to verify / fix |
|---|---|---|
| 1 | **Activator Teams app** is allowed in your tenant | [Teams Admin Center](https://admin.teams.microsoft.com) → **Teams apps** → **Manage apps** → search "Activator" → status must be **Allowed** |
| 2 | **App permission policy** includes the Activator app | Teams Admin Center → **Teams apps** → **Permission policies** → ensure the policy assigned to your users does not block the Activator app |

> 💡 Only a **Teams Administrator** or **Global Admin** can change app permissions. If you are not a Teams admin, ask your IT admin to allow the Activator app.

---

## P0.3 Production Information to Collect

Fill in these values before starting — every later module references them.

| Item | Value |
|---|---|
| Azure Tenant ID | `___________________________________` |
| Azure Subscription ID | `___________________________________` |
| Resource Group | `___________________________________` |
| Region | `___________________________________` |
| **Storage Account name** (production ADLS Gen2) | `scbestmseasta001adlsprd` |
| **Container name** | `inflowoutflow` |
| **Incoming folder prefix** | `inbound/statement/` |
| Fabric Workspace name | `___________________________________` |
| Fabric Workspace GUID | `___________________________________` |
| Fabric Workspace Identity (object ID) | `___________________________________` |
| Eventhouse name | `___________________________________` |
| KQL Database name | `___________________________________` |
| Fabric Warehouse name | `___________________________________` |

> **Tip:** Get the workspace GUID from the URL bar when the workspace is open:  
> `https://app.fabric.microsoft.com/groups/<WORKSPACE-GUID>/...`

---

## P0.4 Sign In

1. Open **[portal.azure.com](https://portal.azure.com)** → sign in with your work account.
2. Top-right → subscription filter → ensure the **production subscription** is selected.
3. Open **[app.fabric.microsoft.com](https://app.fabric.microsoft.com)** in a second tab → open the **production Fabric workspace**.

---

## P0.5 Create the Fabric Workspace Identity

1. Open **Fabric Portal** → your production workspace.
2. Top-right → **Workspace settings** → left menu → **Workspace identity**.
3. Click **+ Workspace identity** → **Add**.
4. Copy the **Object (principal) ID** — used in P0.6.1.

---

## P0.6 Grant RBAC on the Production Storage Account

> ⚠️ **Both roles below are required.** Missing either role will cause a failure — `Storage Blob Data Contributor` is needed for pipeline ingestion, and `EventGrid EventSubscription Contributor` is needed for the event trigger in [Production 05](../05-event-trigger/).

| Role | Assigned to | Purpose |
|---|---|---|
| **Storage Blob Data Contributor** | Workspace Identity (service principal) | Allows the pipeline Copy Activity to read blobs from ADLS Gen2 |
| **EventGrid EventSubscription Contributor** | **Your user account** | Allows Fabric to register a `Microsoft.Storage.BlobCreated` Event Grid subscription when creating the production event trigger |

---

### P0.6.1 Assign Storage Blob Data Contributor

1. **[portal.azure.com](https://portal.azure.com)** → open the **production storage account**.
2. Left menu → **Access control (IAM)** → **+ Add** → **Add role assignment**.
3. **Role** tab: search **`Storage Blob Data Contributor`** → select → **Next**.
4. **Members** tab:
   - Assign access to: **User, group, or service principal**
   - **+ Select members** → paste the **Workspace Identity Object ID** from P0.5 → **Select**
5. **Review + assign** → **Review + assign**.
6. Verify: IAM → **Role assignments** → filter by `Storage Blob Data Contributor` → workspace identity appears.

---

### P0.6.2 Assign EventGrid EventSubscription Contributor

> 🔑 **Why this role is required for production:**  
> The production event trigger (Production 05) creates an **Event Grid subscription** on storage account **`scbestmseasta001adlsprd`** to listen for `Microsoft.Storage.BlobCreated` events scoped to container **`inflowoutflow`** / folder **`inbound/statement/`**. Fabric must call the Azure Event Grid API to register this subscription. Without the **EventGrid EventSubscription Contributor** role assigned to the **user account** performing the setup, the "Connect" step in the Fabric trigger wizard will fail with a permissions error.

1. Still on the **production storage account** → **Access control (IAM)** → **+ Add** → **Add role assignment**.
2. **Role** tab: search **`EventGrid EventSubscription Contributor`** → select → **Next**.
3. **Members** tab:
   - Assign access to: **User, group, or service principal**
   - **+ Select members** → select **your own user account** (the person who will create the event trigger in Fabric Portal) → **Select**
4. **Review + assign** → **Review + assign**.
5. Verify: IAM → **Role assignments** → filter by `EventGrid EventSubscription Contributor` → your account appears.

> ⚠️ **Important distinction:**
> - `Storage Blob Data Contributor` → assigned to the **Workspace Identity** (service principal)
> - `EventGrid EventSubscription Contributor` → assigned to your **user account** (the human setting up the trigger)

---

## P0.7 Add the Fabric Resource Instance Rule

This allows the firewall-enabled production ADLS Gen2 to accept traffic from the Fabric workspace without opening public access.

> ⚠️ The standard **Networking** blade UI does not yet expose Fabric as a resource type. Use the custom template option below.

### Option A — Azure Portal "Deploy a custom template" (recommended)

1. Open **[portal.azure.com](https://portal.azure.com)** → search → **Deploy a custom template** → **Build your own template in the editor**.
2. Paste the template below → **Save**:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "storageAccountName": { "type": "string" },
    "tenantId":           { "type": "string" },
    "fabricWorkspaceGuid":{ "type": "string" }
  },
  "resources": [
    {
      "type": "Microsoft.Storage/storageAccounts",
      "apiVersion": "2023-05-01",
      "name": "[parameters('storageAccountName')]",
      "location": "[resourceGroup().location]",
      "kind": "StorageV2",
      "sku": { "name": "Standard_LRS" },
      "properties": {
        "networkAcls": {
          "bypass": "AzureServices",
          "defaultAction": "Deny",
          "resourceAccessRules": [
            {
              "tenantId": "[parameters('tenantId')]",
              "resourceId": "[concat('/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/Fabric/providers/Microsoft.Fabric/workspaces/', parameters('fabricWorkspaceGuid'))]"
            }
          ]
        }
      }
    }
  ]
}
```

3. Fill in parameters:
   - `storageAccountName` → **`scbestmseasta001adlsprd`**
   - `tenantId` → your Azure Tenant ID (from P0.3)
   - `fabricWorkspaceGuid` → your Fabric Workspace GUID (from P0.3)
4. **Review + create** → **Create**.

### Option B — Ask your Azure Admin

Send the admin the script at [`scripts/03-add-resource-instance-rule.ps1`](scripts/03-add-resource-instance-rule.ps1). This is a one-time action per storage account.

---

## P0.8 Verify Trusted Workspace Access

1. Production storage account → **Security + networking** → **Networking** → scroll to **Resource instances**.
2. Confirm a row with **Resource type** `Microsoft.Fabric/workspaces` and your workspace GUID.

---

## ✅ Exit Criteria

Before proceeding to [Production 01](../01-eventhouse-kql-tables/), confirm all items below:

- [ ] All rows in **P0.1** and **P0.2** verified in the portal
- [ ] All values in **P0.3** filled in
- [ ] Azure Portal and Fabric Portal open with the correct production tenant selected
- [ ] Workspace identity created; Object ID captured
- [ ] `Storage Blob Data Contributor` role assigned to **workspace identity** — visible on storage account IAM
- [ ] `EventGrid EventSubscription Contributor` role assigned to **your user account** — visible on storage account IAM
- [ ] **Resource instances** on the Networking blade lists the Fabric workspace GUID

→ Proceed to **[Production 01 — Eventhouse KQL Tables](../01-eventhouse-kql-tables/)**

---

## Appendix — Production Dataset Reference

The production pipeline processes **`INTRADAY_SUMMARY`** files from ADLS Gen2 every **15 minutes**. This appendix describes the production data format.

### File naming convention

```
INTRADAY_SUMMARY_<Date>_<TimeFrom>_<TimeTo>.CSV
```

| Element | Format | Example |
|---|---|---|
| `INTRADAY_SUMMARY` | Fixed prefix | `INTRADAY_SUMMARY` |
| `Date` | `YYYYMMDD` | `20260615` |
| `TimeFrom` | `HHMM` | `0945` |
| `TimeTo` | `HHMM` | `1000` |
| Extension | `.CSV` (uppercase) | `.CSV` |

**Full example:** `INTRADAY_SUMMARY_20260615_0945_1000.CSV`

### File format

| Property | Value |
|---|---|
| Encoding | UTF-8 |
| Delimiter | **Pipe `\|`** |
| Header row | **None** — data starts at row 1 |
| Time interval | **15 minutes** |

### Production column layout (11 columns, no header)

| Ordinal | Field Name | Type | Length | Nullable | Example |
|---|---|---|---|---|---|
| 0 | `Date` | Date | 10 | Yes | `2026-06-15` |
| 1 | `Time` | String | 11 | Yes | `09:45-10:00` |
| 2 | `Product` | String | 20 | Yes | `S` |
| 3 | `Channel` | String | 10 | Yes | `ATM` |
| 4 | `Channel_Group` | String | 10 | Yes | `Offline` |
| 5 | `Credit_Amount` | Decimal(16,2) | — | Yes | `9000000.00` |
| 6 | `Debit_Amount` | Decimal(16,2) | — | Yes | `5000000.00` |
| 7 | `Net_Amount` | Decimal(16,2) | — | Yes | `4000000.00` |
| 8 | `Credit_Transaction` | Integer | 20 | Yes | `1000` |
| 9 | `Debit_Transaction` | Integer | 20 | Yes | `500` |
| 10 | `Total_Transaction` | Integer | 20 | Yes | `1500` |

### Changes from workshop to production

| # | Item | Workshop | Production |
|---|---|---|---|
| 1 | Delimiter | Comma `,` | **Pipe `\|`** |
| 2 | Header row | Yes | **No** |
| 3 | File naming | `mock_HHMM_HHMM.csv` | **`INTRADAY_SUMMARY_YYYYMMDD_HHMM_HHMM.CSV`** |
| 4 | Time interval | 30 min | **15 min** |
| 5 | `Transaction_Type` column | Present (col 5) | **Removed** |
| 6 | `Credit_Txn` | Integer | **`Credit_Transaction`** (Integer) |
| 7 | `Debit_Txn` | Integer | **`Debit_Transaction`** (Integer) |
| 8 | `Total_Txn` | Integer | **`Total_Transaction`** (Integer) |
| 9 | Amount types | Integer | **Decimal(16,2)** |
| 10 | Total data columns | 12 | **11** |

### Sample production files

Production sample files are in [`resources/prd_datasets/`](../../resources/prd_datasets/):

| File | Time Window |
|---|---|
| `INTRADAY_SUMMARY_20260615_0945_1000.CSV` | 09:45–10:00 |
| `INTRADAY_SUMMARY_20260615_1000_1015.CSV` | 10:00–10:15 |
| `INTRADAY_SUMMARY_20260615_1015_1030.CSV` | 10:15–10:30 |
| `INTRADAY_SUMMARY_20260615_1030_1045.CSV` | 10:30–10:45 |
| `INTRADAY_SUMMARY_20260615_1045_1100.CSV` | 10:45–11:00 |
| `INTRADAY_SUMMARY_20260615_1100_1115.CSV` | 11:00–11:15 |
| `INTRADAY_SUMMARY_20260615_1115_1130.CSV` | 11:15–11:30 |
| `INTRADAY_SUMMARY_20260615_1130_1145.CSV` | 11:30–11:45 |
| `INTRADAY_SUMMARY_20260615_1145_1200.CSV` | 11:45–12:00 |
