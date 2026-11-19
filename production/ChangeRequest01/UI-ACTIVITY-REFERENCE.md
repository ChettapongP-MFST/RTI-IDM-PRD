# CR01 - Fabric UI Activity Reference

Companion to the [Fabric UI setup guide](FABRIC-UI-GUIDE.md). This is a field-by-field authoring reference, not a JSON-import procedure.

All names, dependencies, expressions, SQL/KQL, parameter defaults, and nested branches below are extracted from the delivered pipeline definitions. No shell is required to follow this document.

## How to enter values

- Create each item through Fabric **New item > Data pipeline**. Keep the existing pipelines unchanged.
- Keep activity names exact: expressions refer to them by name.
- For **Add dynamic content**, paste only the displayed value, without JSON `value` / `type` wrappers. Preserve `@{...}` interpolation in SQL/KQL text.
- Literal long KQL function definitions belong in the plain Command editor, not in an expression wrapper.
- For a `Succeeded` dependency, connect the preceding activity's green On success connector. Put nested entries on the specified branch/loop canvas.
- `false` means unchecked/off; `true` means checked/on. Pipeline parameter types `bool`, `int`, `string` correspond to Bool/Boolean, Int, and String in the UI.
- Bind connections, databases, and child pipelines by their names in the target workspace. Fabric generates its own item/connection IDs.
- Do not run individual destructive KQL/SQL activity snippets in a query editor. They are intended to execute in order under the controller lock.
- Existing storage/ref-data blockers remain in force. Save with processing disabled and do not enable a schedule during authoring.

## 1. pl_CR01_Preflight

Validated definition: [pipeline/pl_CR01_Preflight.json](pipeline/pl_CR01_Preflight.json).

### parameters

None.

### variables

None.

### Top-level activity order

| Order | Activity | Type |
| --- | --- | --- |
| 1 | List Source Files Read Only | GetMetadata |
| 2 | Read Audit Baseline | Lookup |
| 3 | Read KQL Baseline | KustoQueryLanguage |

### 1.1 - List Source Files Read Only

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Get Metadata |
| General > Name (exact) | List Source Files Read Only |
| Incoming dependency | None inside this canvas/branch |
| General > timeout | 0.00:10:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

| Settings / connection field | Value |
| --- | --- |
| Connection | Approved ADLS Gen2 connection for mockadlsidimdprd001 |
| File format / dataset | Binary |
| Container / file system | inflowoutflow |

**Directory** - literal value; do not add an expression wrapper.

```text
inbound/statement
```

File name: **leave empty** to list the directory.

**Field list (add each listed field)** - literal value; do not add an expression wrapper.

```text
"childItems"
```

**Source advanced > recursive** - literal value; do not add an expression wrapper.

```text
True
```

**Source advanced > enablePartitionDiscovery** - literal value; do not add an expression wrapper.

```text
False
```

### 1.2 - Read Audit Baseline

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Lookup |
| General > Name (exact) | Read Audit Baseline |
| Incoming dependency | None inside this canvas/branch |
| General > timeout | 0.00:10:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse). Select **Use query > Query**.

**Settings > Query** - literal value; do not add an expression wrapper.

```sql
SELECT COUNT_BIG(*) AS SuccessfulFiles FROM dbo.ProcessedFiles WHERE Status='Success';
```

**Settings > First row only** - literal value; do not add an expression wrapper.

```text
True
```

**Settings > Query timeout** - literal value; do not add an expression wrapper.

```text
00:05:00
```

**Source advanced > Partition option (where exposed)** - literal value; do not add an expression wrapper.

```text
None
```

### 1.3 - Read KQL Baseline

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Read KQL Baseline |
| Incoming dependency | None inside this canvas/branch |
| General > timeout | 0.00:10:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.show table DepositMovement schema as json
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
00:05:00
```

## 2. pl_CR01_DepositMovement_Discover

Validated definition: [pipeline/pl_CR01_DepositMovement_Discover.json](pipeline/pl_CR01_DepositMovement_Discover.json).

### parameters

| Name | UI type | Default |
| --- | --- | --- |
| pControllerRunId | string | (no default; supplied by caller / Set variable) |
| pRunICT | string | (no default; supplied by caller / Set variable) |

### variables

| Name | UI type | Default |
| --- | --- | --- |
| vToday | String | (no default; supplied by caller / Set variable) |
| vYesterday | String | (no default; supplied by caller / Set variable) |

### Top-level activity order

| Order | Activity | Type |
| --- | --- | --- |
| 1 | Validate Controller Owner | Script |
| 2 | Set vToday | SetVariable |
| 3 | Set vYesterday | SetVariable |
| 4 | Get Metadata List Files | GetMetadata |
| 5 | Lookup Processed Files | Lookup |
| 6 | Filter New Files | Filter |
| 7 | ForEach New Files | ForEach |

### 2.1 - Validate Controller Owner

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Script |
| General > Name (exact) | Validate Controller Owner |
| Incoming dependency | None inside this canvas/branch |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse).

**Script block execution timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

Script block 1 > Type: **NonQuery**.

**Script block 1 > Text** - literal value; do not add an expression wrapper.

```sql
IF (SELECT COUNT(*) FROM dbo.CR01ControllerRun
    WHERE RunId=@ControllerRunId AND Status='Running') <> 1
    THROW 51100, 'CR01 internal pipeline requires an active controller owner.', 1;
```

| Script input parameter | Type | Direction | Value / expression |
| --- | --- | --- | --- |
| ControllerRunId | String | Input | `@pipeline().parameters.pControllerRunId` |

Add these under the Script block Parameters control. Keep the SQL `@ControllerRunId` parameter bound; do not replace it with an interpolated SQL string.

### 2.2 - Set vToday

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Set variable |
| General > Name (exact) | Set vToday |
| Incoming dependency | Validate Controller Owner [Succeeded] |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Variable: **vToday**.

**Settings > Value** - use Add dynamic content.

```text
@concat('INTRADAY_SUMMARY_', formatDateTime(pipeline().parameters.pRunICT, 'yyyyMMdd'))
```

### 2.3 - Set vYesterday

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Set variable |
| General > Name (exact) | Set vYesterday |
| Incoming dependency | Set vToday [Succeeded] |

Settings > Variable: **vYesterday**.

**Settings > Value** - use Add dynamic content.

```text
@concat('INTRADAY_SUMMARY_', formatDateTime(addDays(pipeline().parameters.pRunICT,-1),'yyyyMMdd'))
```

### 2.4 - Get Metadata List Files

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Get Metadata |
| General > Name (exact) | Get Metadata List Files |
| Incoming dependency | Set vYesterday [Succeeded] |
| General > timeout | 0.12:00:00 |
| General > retry | 2 |
| General > retryIntervalInSeconds | 30 |
| General > secureInput | False |
| General > secureOutput | False |

| Settings / connection field | Value |
| --- | --- |
| Connection | Approved ADLS Gen2 connection for mockadlsidimdprd001 |
| File format / dataset | Binary |
| Container / file system | inflowoutflow |

**Directory** - literal value; do not add an expression wrapper.

```text
inbound/statement
```

File name: **leave empty** to list the directory.

**Field list (add each listed field)** - literal value; do not add an expression wrapper.

```text
"childItems"
```

**Source advanced > recursive** - literal value; do not add an expression wrapper.

```text
True
```

**Source advanced > enablePartitionDiscovery** - literal value; do not add an expression wrapper.

```text
False
```

### 2.5 - Lookup Processed Files

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Lookup |
| General > Name (exact) | Lookup Processed Files |
| Incoming dependency | Get Metadata List Files [Succeeded] |
| General > timeout | 0.12:00:00 |
| General > retry | 2 |
| General > retryIntervalInSeconds | 30 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse). Select **Use query > Query**.

**Settings > Query** - use Add dynamic content.

```sql
SELECT COALESCE('|' + STRING_AGG(FileName, '|') + '|', '|') AS ProcessedList
FROM dbo.ProcessedFiles
WHERE Status = 'Success'
  AND (FileName LIKE '@{variables('vToday')}%' OR FileName LIKE '@{variables('vYesterday')}%');
```

**Settings > First row only** - literal value; do not add an expression wrapper.

```text
True
```

**Settings > Query timeout** - literal value; do not add an expression wrapper.

```text
02:00:00
```

**Source advanced > Partition option (where exposed)** - literal value; do not add an expression wrapper.

```text
None
```

### 2.6 - Filter New Files

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Filter |
| General > Name (exact) | Filter New Files |
| Incoming dependency | Lookup Processed Files [Succeeded] |

**Settings > Items** - use Add dynamic content.

```text
@activity('Get Metadata List Files').output.childItems
```

**Settings > Condition** - use Add dynamic content.

```text
@and(and(equals(item().type,'File'),or(startswith(item().name,variables('vToday')),startswith(item().name,variables('vYesterday')))),and(endswith(toLower(item().name),'.csv'),not(contains(activity('Lookup Processed Files').output.firstRow.ProcessedList,concat('|',item().name,'|')))))
```

### 2.7 - ForEach New Files

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | ForEach |
| General > Name (exact) | ForEach New Files |
| Incoming dependency | Filter New Files [Succeeded] |

**Settings > Items** - use Add dynamic content.

```text
@activity('Filter New Files').output.Value
```

**Settings > Sequential (checkbox)** - literal value; do not add an expression wrapper.

```text
False
```

**Settings > Batch count** - literal value; do not add an expression wrapper.

```text
10
```

Open the Activities canvas inside this ForEach; add the following activities there, not on the outer canvas.

### 2.7.1 - Invoke Ingestion

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > ForEach New Files > Activities |
| Activity to select | Invoke pipeline |
| General > Name (exact) | Invoke Ingestion |
| Incoming dependency | None inside this canvas/branch |
| General > timeout | 0.12:00:00 |
| General > retry | 0 |
| General > retryIntervalInSeconds | 30 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **existing Fabric pipeline-invocation connection**.

Select workspace **RTI-IDM-PRD** and invoked pipeline **pl_ingest_DepositMovement**.

Select by name in your workspace; do not paste a recorded item GUID into a different environment.

**Settings > Wait on completion** - literal value; do not add an expression wrapper.

```text
True
```

**Child parameter > pFileName** - use Add dynamic content.

```text
@item().name
```

**Child parameter > pFolder** - literal value; do not add an expression wrapper.

```text
inbound/statement
```

**Child parameter > Subject** - use Add dynamic content.

```text
@concat('/blobServices/default/containers/inflowoutflow/blobs/inbound/statement/', item().name)
```

## 3. pl_CR01_DepositMovement_OvernightRefresh

Validated definition: [pipeline/pl_CR01_DepositMovement_OvernightRefresh.json](pipeline/pl_CR01_DepositMovement_OvernightRefresh.json).

### parameters

| Name | UI type | Default |
| --- | --- | --- |
| pSourceFinalized | bool | False |
| pControllerRunId | string | (no default; supplied by caller / Set variable) |
| pSourceIntervalMinutes | int | 15 |
| pRefreshDate | string | (no default; supplied by caller / Set variable) |

### variables

| Name | UI type | Default |
| --- | --- | --- |
| vRefreshDate | String | (no default; supplied by caller / Set variable) |
| vLoadTs | String | (no default; supplied by caller / Set variable) |

### Top-level activity order

| Order | Activity | Type |
| --- | --- | --- |
| 1 | Require Finalized Source | IfCondition |
| 2 | Freeze Refresh Date | SetVariable |
| 3 | Freeze Load Time | SetVariable |
| 4 | Validate Controller Owner | Script |
| 5 | Check Schema DepositMovement | KustoQueryLanguage |
| 6 | Validate Schema DepositMovement | IfCondition |
| 7 | Check Schema DepositMovementClassified | KustoQueryLanguage |
| 8 | Validate Schema DepositMovementClassified | IfCondition |
| 9 | Check Schema DepositMovementEarlyWarning | KustoQueryLanguage |
| 10 | Validate Schema DepositMovementEarlyWarning | IfCondition |
| 11 | Compute Threshold Reference Keys | KustoQueryLanguage |
| 12 | Validate Threshold Reference Keys | IfCondition |
| 13 | Register Frozen Manifest | Script |
| 14 | Read Manifest | Lookup |
| 15 | Read Manifest Predicate | Lookup |
| 16 | Create Frozen Staging Table | KustoQueryLanguage |
| 17 | Create Staging Mapping | KustoQueryLanguage |
| 18 | Stage All Overnight Files | ForEach |
| 19 | Read Staged Manifest | Lookup |
| 20 | Wait For Queryable Staging | Until |
| 21 | Compute Staged Source Contract | KustoQueryLanguage |
| 22 | Validate Staged Source Contract | IfCondition |
| 23 | Check Silver Transformation Version | KustoQueryLanguage |
| 24 | Validate Silver Transformation Version | IfCondition |
| 25 | Preview Existing Silver Classification | KustoQueryLanguage |
| 26 | Compute Preview Calendar Classification | KustoQueryLanguage |
| 27 | Validate Preview Calendar Classification | IfCondition |
| 28 | Validate Frozen Source Versions | ForEach |
| 29 | Compute Loaded File Coverage | KustoQueryLanguage |
| 30 | Validate Loaded File Coverage | IfCondition |
| 31 | Read Existing Gold Views | KustoQueryLanguage |
| 32 | Check Existing Gold Definitions | KustoQueryLanguage |
| 33 | Validate Gold Baseline | IfCondition |
| 34 | Check retention mv_Summary_Product_Channel_Alert | KustoQueryLanguage |
| 35 | Validate retention mv_Summary_Product_Channel_Alert | IfCondition |
| 36 | Check caching mv_Summary_Product_Channel_Alert | KustoQueryLanguage |
| 37 | Validate caching mv_Summary_Product_Channel_Alert | IfCondition |
| 38 | Check retention mv_EarlyWarning_Base | KustoQueryLanguage |
| 39 | Validate retention mv_EarlyWarning_Base | IfCondition |
| 40 | Check caching mv_EarlyWarning_Base | KustoQueryLanguage |
| 41 | Validate caching mv_EarlyWarning_Base | IfCondition |
| 42 | Backup Target Bronze | KustoQueryLanguage |
| 43 | Backup Target Silver | KustoQueryLanguage |
| 44 | Backup Both EWI Dates | KustoQueryLanguage |
| 45 | Snapshot Unrelated DepositMovement | KustoQueryLanguage |
| 46 | Snapshot Unrelated DepositMovementClassified | KustoQueryLanguage |
| 47 | Hold Serving Visibility | KustoQueryLanguage |
| 48 | Drop mv_Summary_Product_Channel_Alert | KustoQueryLanguage |
| 49 | Drop mv_EarlyWarning_Base | KustoQueryLanguage |
| 50 | Delete Only Manifest Bronze | KustoQueryLanguage |
| 51 | Delete Only Manifest Silver | KustoQueryLanguage |
| 52 | Compute Empty Replacement Scope | KustoQueryLanguage |
| 53 | Validate Empty Replacement Scope | IfCondition |
| 54 | Preserve And Supersede Audit | Script |
| 55 | Promote Frozen Overnight Snapshot | KustoQueryLanguage |
| 56 | Wait For Bronze And Silver | Until |
| 57 | Compute Silver Classification | KustoQueryLanguage |
| 58 | Validate Silver Classification | IfCondition |
| 59 | Compute Unrelated DepositMovement | KustoQueryLanguage |
| 60 | Validate Unrelated DepositMovement | IfCondition |
| 61 | Compute Unrelated DepositMovementClassified | KustoQueryLanguage |
| 62 | Validate Unrelated DepositMovementClassified | IfCondition |
| 63 | Rebuild mv_Summary_Product_Channel_Alert | KustoQueryLanguage |
| 64 | Compute Reconciled mv_Summary_Product_Channel_Alert | KustoQueryLanguage |
| 65 | Validate Reconciled mv_Summary_Product_Channel_Alert | IfCondition |
| 66 | Rebuild mv_EarlyWarning_Base | KustoQueryLanguage |
| 67 | Restore Caching mv_EarlyWarning_Base | KustoQueryLanguage |
| 68 | Compute Reconciled mv_EarlyWarning_Base | KustoQueryLanguage |
| 69 | Validate Reconciled mv_EarlyWarning_Base | IfCondition |
| 70 | Wait For Healthy Gold Views | Until |
| 71 | Compute EWI Level Contract | KustoQueryLanguage |
| 72 | Validate EWI Level Contract | IfCondition |
| 73 | Delete Affected Persisted EWI Dates | KustoQueryLanguage |
| 74 | Recompute Both Complete EWI Dates | KustoQueryLanguage |
| 75 | Compute Persisted EWI Grain | KustoQueryLanguage |
| 76 | Validate Persisted EWI Grain | IfCondition |
| 77 | Compute Reconciled Persisted EWI | KustoQueryLanguage |
| 78 | Validate Reconciled Persisted EWI | IfCondition |
| 79 | Commit Verified Refresh | Script |

### 3.1 - Require Finalized Source

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Require Finalized Source |
| Incoming dependency | None inside this canvas/branch |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@not(pipeline().parameters.pSourceFinalized)
```

**True branch:** open this branch and add its activities below.

### 3.1-True.1 - Require Finalized Source Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Require Finalized Source > True branch |
| Activity to select | Fail |
| General > Name (exact) | Require Finalized Source Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
Producer finalization must be confirmed before a refresh.
```

**False branch:** leave empty.

### 3.2 - Freeze Refresh Date

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Set variable |
| General > Name (exact) | Freeze Refresh Date |
| Incoming dependency | Require Finalized Source [Succeeded] |

Settings > Variable: **vRefreshDate**.

**Settings > Value** - use Add dynamic content.

```text
@formatDateTime(pipeline().parameters.pRefreshDate,'yyyy-MM-dd')
```

### 3.3 - Freeze Load Time

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Set variable |
| General > Name (exact) | Freeze Load Time |
| Incoming dependency | Freeze Refresh Date [Succeeded] |

Settings > Variable: **vLoadTs**.

**Settings > Value** - use Add dynamic content.

```text
@convertFromUtc(utcNow(),'SE Asia Standard Time')
```

### 3.4 - Validate Controller Owner

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Script |
| General > Name (exact) | Validate Controller Owner |
| Incoming dependency | Freeze Load Time [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse).

**Script block execution timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

Script block 1 > Type: **NonQuery**.

**Script block 1 > Text** - literal value; do not add an expression wrapper.

```sql
IF (SELECT COUNT(*) FROM dbo.CR01ControllerRun
    WHERE RunId=@ControllerRunId AND Status='Running') <> 1
    THROW 51100, 'CR01 internal pipeline requires an active controller owner.', 1;
```

| Script input parameter | Type | Direction | Value / expression |
| --- | --- | --- | --- |
| ControllerRunId | String | Input | `@pipeline().parameters.pControllerRunId` |

Add these under the Script block Parameters control. Keep the SQL `@ControllerRunId` parameter bound; do not replace it with an interpolated SQL string.

### 3.5 - Check Schema DepositMovement

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Check Schema DepositMovement |
| Incoming dependency | Validate Controller Owner [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.show table DepositMovement schema as json | mv-expand with_itemindex=i c=todynamic(Schema).OrderedColumns | order by i asc | summarize Signature=strcat_array(make_list(strcat(tostring(c.Name),':',tostring(c.CslType))),'|') | where Signature!=base64_decode_tostring('RGF0ZTpkYXRldGltZXxUaW1lOnN0cmluZ3xQcm9kdWN0OnN0cmluZ3xDaGFubmVsOnN0cmluZ3xDaGFubmVsX0dyb3VwOnN0cmluZ3xDcmVkaXRfQW1vdW50OmRlY2ltYWx8RGViaXRfQW1vdW50OmRlY2ltYWx8TmV0X0Ftb3VudDpkZWNpbWFsfENyZWRpdF9UcmFuc2FjdGlvbjpsb25nfERlYml0X1RyYW5zYWN0aW9uOmxvbmd8VG90YWxfVHJhbnNhY3Rpb246bG9uZ3xsb2FkX3RzOmRhdGV0aW1lfGZpbGVfbmFtZTpzdHJpbmd8cGlwZWxpbmVfbmFtZTpzdHJpbmd8cGlwZWxpbmVfcnVuaWQ6c3RyaW5n')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.6 - Validate Schema DepositMovement

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Schema DepositMovement |
| Incoming dependency | Check Schema DepositMovement [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Check Schema DepositMovement').output.count),0)
```

**True branch:** open this branch and add its activities below.

### 3.6-True.1 - Validate Schema DepositMovement Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Schema DepositMovement > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Schema DepositMovement Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
A source/output schema changed. Regenerate and review CR01 before replacing data.
```

**False branch:** leave empty.

### 3.7 - Check Schema DepositMovementClassified

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Check Schema DepositMovementClassified |
| Incoming dependency | Validate Schema DepositMovement [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.show table DepositMovementClassified schema as json | mv-expand with_itemindex=i c=todynamic(Schema).OrderedColumns | order by i asc | summarize Signature=strcat_array(make_list(strcat(tostring(c.Name),':',tostring(c.CslType))),'|') | where Signature!=base64_decode_tostring('RGF0ZTpkYXRldGltZXxUaW1lOnN0cmluZ3xQcm9kdWN0OnN0cmluZ3xDaGFubmVsOnN0cmluZ3xDaGFubmVsX0dyb3VwOnN0cmluZ3xDcmVkaXRfQW1vdW50OmRlY2ltYWx8RGViaXRfQW1vdW50OmRlY2ltYWx8TmV0X0Ftb3VudDpkZWNpbWFsfENyZWRpdF9UcmFuc2FjdGlvbjpsb25nfERlYml0X1RyYW5zYWN0aW9uOmxvbmd8VG90YWxfVHJhbnNhY3Rpb246bG9uZ3xsb2FkX3RzOmRhdGV0aW1lfGZpbGVfbmFtZTpzdHJpbmd8cGlwZWxpbmVfbmFtZTpzdHJpbmd8cGlwZWxpbmVfcnVuaWQ6c3RyaW5nfExvY2FsRGF0ZTpkYXRldGltZXxMb2NhbERhdGVUaW1lOmRhdGV0aW1lfExvY2FsVGltZU9mRGF5OnRpbWVzcGFufElzV2Vla2VuZDpib29sfElzRmluYW5jaWFsSW5zdGl0dXRpb25Ib2xpZGF5OmJvb2x8SXNCdXNpbmVzc0RheTpib29sfERheUNsYXNzaWZpY2F0aW9uOnN0cmluZ3xIb2xpZGF5TmFtZTpzdHJpbmd8T3BlcmF0aW5nV2luZG93Q29kZTpzdHJpbmd8T3BlcmF0aW5nV2luZG93TmFtZTpzdHJpbmd8T3BlcmF0aW5nV2luZG93U3RhcnRUaW1lOnRpbWVzcGFufE9wZXJhdGluZ1dpbmRvd0VuZFRpbWU6dGltZXNwYW58T3BlcmF0aW5nV2luZG93U29ydE9yZGVyOmludHxXaW5kb3dNYXRjaENvdW50Omxvbmd8Q2xhc3NpZmljYXRpb25TdGF0dXM6c3RyaW5nfElzTW9udGhFbmQ6Ym9vbHxJc1BheXJvbGw6Ym9vbHxJc0xvbmdXZWVrZW5kOmJvb2x8RXZlbnRGbGFnOnN0cmluZw==')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.8 - Validate Schema DepositMovementClassified

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Schema DepositMovementClassified |
| Incoming dependency | Check Schema DepositMovementClassified [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Check Schema DepositMovementClassified').output.count),0)
```

**True branch:** open this branch and add its activities below.

### 3.8-True.1 - Validate Schema DepositMovementClassified Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Schema DepositMovementClassified > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Schema DepositMovementClassified Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
A source/output schema changed. Regenerate and review CR01 before replacing data.
```

**False branch:** leave empty.

### 3.9 - Check Schema DepositMovementEarlyWarning

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Check Schema DepositMovementEarlyWarning |
| Incoming dependency | Validate Schema DepositMovementClassified [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.show table DepositMovementEarlyWarning schema as json | mv-expand with_itemindex=i c=todynamic(Schema).OrderedColumns | order by i asc | summarize Signature=strcat_array(make_list(strcat(tostring(c.Name),':',tostring(c.CslType))),'|') | where Signature!=base64_decode_tostring('T2JqZWN0X0lkOnN0cmluZ3xTY29wZTpzdHJpbmd8RGF0ZV9JQ1Q6c3RyaW5nfEJ1Y2tldF9TdGFydDpkYXRldGltZXxCdWNrZXRfTGFiZWw6c3RyaW5nfEFsZXJ0X1RpbWU6ZGF0ZXRpbWV8V2luZG93Q29kZTpzdHJpbmd8V2luZG93TmFtZTpzdHJpbmd8RGF5VHlwZTpzdHJpbmd8RXZlbnRGbGFnOnN0cmluZ3xJc01vbnRoRW5kOmJvb2x8SXNQYXlyb2xsOmJvb2x8SXNMb25nV2Vla2VuZDpib29sfEluZGljYXRvcklkOmludHxJbmRpY2F0b3JLZXk6c3RyaW5nfEluZGljYXRvck5hbWU6c3RyaW5nfFVuaXQ6c3RyaW5nfFZhbHVlOnJlYWx8RGlyZWN0aW9uOnN0cmluZ3xMMTpyZWFsfEwyOnJlYWx8TDM6cmVhbHxBbGVydF9MZXZlbDpzdHJpbmd8QWxlcnRfUmFuazppbnQ=')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.10 - Validate Schema DepositMovementEarlyWarning

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Schema DepositMovementEarlyWarning |
| Incoming dependency | Check Schema DepositMovementEarlyWarning [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Check Schema DepositMovementEarlyWarning').output.count),0)
```

**True branch:** open this branch and add its activities below.

### 3.10-True.1 - Validate Schema DepositMovementEarlyWarning Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Schema DepositMovementEarlyWarning > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Schema DepositMovementEarlyWarning Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
A source/output schema changed. Regenerate and review CR01 before replacing data.
```

**False branch:** leave empty.

### 3.11 - Compute Threshold Reference Keys

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Threshold Reference Keys |
| Incoming dependency | Validate Schema DepositMovementEarlyWarning [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-replace CR01_Checks <| let expected=print Scope=dynamic(["TOTAL_BANK","RETAILS","NON_RETAILS"])
| mv-expand Scope to typeof(string)
| extend IndicatorKey=dynamic(["GrossOutflow_MB","NetOutflow_MB","AccumNetOutflow_MB","DebitTxnCount_M","Velocity_X","AvgDebitAmount_MB","ClusterShare_Pct","ShareJump_Pct"])
| mv-expand IndicatorKey to typeof(string)
| extend WindowCode=dynamic(["BEFORE_WORKING_HOUR","MORNING_WORKING_HOUR","AFTERNOON_WORKING_HOUR","AFTER_WORKING_HOUR"])
| mv-expand WindowCode to typeof(string)
| extend DayType=dynamic(["BUSINESS_DAY","WEEKEND","HOLIDAY"])
| mv-expand DayType to typeof(string) | extend Expected=true;
expected
| join kind=fullouter (
    EWI_AlertThreshold | summarize Copies=count() by Scope,IndicatorKey,WindowCode,DayType
) on Scope,IndicatorKey,WindowCode,DayType
| where isnull(Expected) or isnull(Copies) or Copies!=1
| project Problem='Missing, unexpected, or duplicate threshold reference key'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.12 - Validate Threshold Reference Keys

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Threshold Reference Keys |
| Incoming dependency | Compute Threshold Reference Keys [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Threshold Reference Keys').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 3.12-True.1 - Validate Threshold Reference Keys Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Threshold Reference Keys > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Threshold Reference Keys Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Threshold Reference Keys has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 3.13 - Register Frozen Manifest

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Script |
| General > Name (exact) | Register Frozen Manifest |
| Incoming dependency | Validate Threshold Reference Keys [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse).

**Script block execution timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

Script block 1 > Type: **NonQuery**.

**Script block 1 > Text** - use Add dynamic content.

```sql
DECLARE @d DATE='@{variables('vRefreshDate')}';
DECLARE @step INT=@{pipeline().parameters.pSourceIntervalMinutes};
IF @step NOT IN (15,30) THROW 51101, 'Source interval must be 15 or 30 minutes.', 1;
IF EXISTS(SELECT 1 FROM dbo.CR01RefreshRun WHERE RefreshDate=@d)
    THROW 51102, 'Refresh already exists. Recover its original stage and manifest; do not replay blindly.', 1;
INSERT INTO dbo.CR01RefreshRun
VALUES(@d,'@{pipeline().parameters.pControllerRunId}','Running','Staging',SYSUTCDATETIME(),NULL);
INSERT INTO dbo.CR01RefreshManifest(RefreshDate,FileName)
SELECT @d, CONCAT('INTRADAY_SUMMARY_',CONVERT(CHAR(8),s,112),'_',
    REPLACE(CONVERT(CHAR(5),s,108),':',''),'_',
    CASE WHEN CAST(e AS DATE)>CAST(s AS DATE) THEN '2400'
         ELSE REPLACE(CONVERT(CHAR(5),e,108),':','') END,'.CSV')
FROM (VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9),
    (10),(11),(12),(13),(14),(15),(16),(17),(18),(19)) n(i)
CROSS APPLY(SELECT DATEADD(MINUTE,-90+i*@step,CAST(@d AS DATETIME2(6))) s) a
CROSS APPLY(SELECT DATEADD(MINUTE,@step,s) e) b
WHERE i<300/@step;
```

### 3.14 - Read Manifest

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Lookup |
| General > Name (exact) | Read Manifest |
| Incoming dependency | Register Frozen Manifest [Succeeded] |
| General > timeout | 0.12:00:00 |
| General > retry | 0 |
| General > retryIntervalInSeconds | 30 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse). Select **Use query > Query**.

**Settings > Query** - use Add dynamic content.

```sql
SELECT FileName FROM dbo.CR01RefreshManifest WHERE RefreshDate='@{variables('vRefreshDate')}' ORDER BY FileName;
```

**Settings > First row only** - literal value; do not add an expression wrapper.

```text
False
```

**Settings > Query timeout** - literal value; do not add an expression wrapper.

```text
02:00:00
```

**Source advanced > Partition option (where exposed)** - literal value; do not add an expression wrapper.

```text
None
```

### 3.15 - Read Manifest Predicate

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Lookup |
| General > Name (exact) | Read Manifest Predicate |
| Incoming dependency | Read Manifest [Succeeded] |
| General > timeout | 0.12:00:00 |
| General > retry | 0 |
| General > retryIntervalInSeconds | 30 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse). Select **Use query > Query**.

**Settings > Query** - use Add dynamic content.

```sql
IF EXISTS(SELECT 1 FROM dbo.CR01RefreshManifest
    WHERE RefreshDate='@{variables('vRefreshDate')}' AND FileName LIKE '%[^A-Z0-9_.]%')
    THROW 51107,'Unsafe filename in the frozen manifest.',1;
SELECT STRING_AGG(CONCAT('"',FileName,'"'),',') AS KqlFileList
FROM dbo.CR01RefreshManifest WHERE RefreshDate='@{variables('vRefreshDate')}';
```

**Settings > First row only** - literal value; do not add an expression wrapper.

```text
True
```

**Settings > Query timeout** - literal value; do not add an expression wrapper.

```text
02:00:00
```

**Source advanced > Partition option (where exposed)** - literal value; do not add an expression wrapper.

```text
None
```

### 3.16 - Create Frozen Staging Table

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Create Frozen Staging Table |
| Incoming dependency | Read Manifest Predicate [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set CR01_Stage_@{formatDateTime(variables('vRefreshDate'),'yyyyMMdd')} <| DepositMovement | take 0
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.17 - Create Staging Mapping

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Create Staging Mapping |
| Incoming dependency | Create Frozen Staging Table [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.create-or-alter table CR01_Stage_@{formatDateTime(variables('vRefreshDate'),'yyyyMMdd')} ingestion csv mapping 'DepositMovement_mapping' '[{"Properties":{"Ordinal":"0"},"Column":"Date"},{"Properties":{"Ordinal":"1"},"Column":"Time"},{"Properties":{"Ordinal":"2"},"Column":"Product"},{"Properties":{"Ordinal":"3"},"Column":"Channel"},{"Properties":{"Ordinal":"4"},"Column":"Channel_Group"},{"Properties":{"Ordinal":"5"},"Column":"Credit_Amount"},{"Properties":{"Ordinal":"6"},"Column":"Debit_Amount"},{"Properties":{"Ordinal":"7"},"Column":"Net_Amount"},{"Properties":{"Ordinal":"8"},"Column":"Credit_Transaction"},{"Properties":{"Ordinal":"9"},"Column":"Debit_Transaction"},{"Properties":{"Ordinal":"10"},"Column":"Total_Transaction"},{"Properties":{"Ordinal":"11"},"Column":"load_ts"},{"Properties":{"Ordinal":"12"},"Column":"file_name"},{"Properties":{"Ordinal":"13"},"Column":"pipeline_name"},{"Properties":{"Ordinal":"14"},"Column":"pipeline_runid"}]'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.18 - Stage All Overnight Files

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | ForEach |
| General > Name (exact) | Stage All Overnight Files |
| Incoming dependency | Create Staging Mapping [Succeeded] |

**Settings > Items** - use Add dynamic content.

```text
@activity('Read Manifest').output.value
```

**Settings > Sequential (checkbox)** - literal value; do not add an expression wrapper.

```text
False
```

**Settings > Batch count** - literal value; do not add an expression wrapper.

```text
10
```

Open the Activities canvas inside this ForEach; add the following activities there, not on the outer canvas.

### 3.18.1 - Read Source Version

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Stage All Overnight Files > Activities |
| Activity to select | Get Metadata |
| General > Name (exact) | Read Source Version |
| Incoming dependency | None inside this canvas/branch |
| General > timeout | 0.12:00:00 |
| General > retry | 0 |
| General > retryIntervalInSeconds | 30 |
| General > secureInput | False |
| General > secureOutput | False |

| Settings / connection field | Value |
| --- | --- |
| Connection | Approved ADLS Gen2 connection for mockadlsidimdprd001 |
| File format / dataset | Binary |
| Container / file system | inflowoutflow |

**Directory** - literal value; do not add an expression wrapper.

```text
inbound/statement
```

**File name** - use Add dynamic content.

```text
@item().FileName
```

**Field list (add each listed field)** - literal value; do not add an expression wrapper.

```text
["size","lastModified"]
```

**Source advanced > recursive** - literal value; do not add an expression wrapper.

```text
True
```

**Source advanced > enablePartitionDiscovery** - literal value; do not add an expression wrapper.

```text
False
```

### 3.18.2 - Stage Source File

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Stage All Overnight Files > Activities |
| Activity to select | Copy data |
| General > Name (exact) | Stage Source File |
| Incoming dependency | Read Source Version [Succeeded] |
| General > timeout | 0.12:00:00 |
| General > retry | 0 |
| General > retryIntervalInSeconds | 60 |
| General > secureInput | False |
| General > secureOutput | False |

Source tab > Connection: **approved ADLS Gen2 connection**.

**Source > Container** - literal value; do not add an expression wrapper.

```text
inflowoutflow
```

**Source > Directory** - literal value; do not add an expression wrapper.

```text
inbound/statement
```

**Source > File name** - use Add dynamic content.

```text
@item().FileName
```

**Source > File format** - literal value; do not add an expression wrapper.

```text
DelimitedText
```

**Source > columnDelimiter** - literal value; do not add an expression wrapper.

```text
|
```

**Source > firstRowAsHeader** - literal value; do not add an expression wrapper.

```text
False
```

**Source > quoteChar** - literal value; do not add an expression wrapper.

```text
"
```

**Source > escapeChar** - literal value; do not add an expression wrapper.

```text
\
```

**Source advanced > recursive** - literal value; do not add an expression wrapper.

```text
True
```

**Source advanced > enablePartitionDiscovery** - literal value; do not add an expression wrapper.

```text
False
```

| Source > Additional column | Value / expression |
| --- | --- |
| load_ts | `@variables('vLoadTs')` |
| file_name | `@item().FileName` |
| pipeline_name | `@pipeline().Pipeline` |
| pipeline_runid | `@pipeline().RunId` |

Destination tab > Workspace data store: **KQL Database > DepositMovement**.

**Destination > Table (dynamic content)** - use Add dynamic content.

```text
CR01_Stage_@{formatDateTime(variables('vRefreshDate'),'yyyyMMdd')}
```

**Destination > Ingestion mapping name** - literal value; do not add an expression wrapper.

```text
DepositMovement_mapping
```

Mapping tab: leave explicit column mappings empty. The named ordinal mapping is created by the preceding KQL activity; do not import a dynamic source schema at design time.

**Settings > Enable staging** - literal value; do not add an expression wrapper.

```text
False
```

**Mapping > Type conversion** - literal value; do not add an expression wrapper.

```text
True
```

**Mapping > allowDataTruncation** - literal value; do not add an expression wrapper.

```text
False
```

**Mapping > treatBooleanAsNumber** - literal value; do not add an expression wrapper.

```text
False
```

### 3.18.3 - Capture Source Control Totals

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Stage All Overnight Files > Activities |
| Activity to select | Script |
| General > Name (exact) | Capture Source Control Totals |
| Incoming dependency | Stage Source File [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse).

**Script block execution timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

Script block 1 > Type: **NonQuery**.

**Script block 1 > Text** - use Add dynamic content.

```sql
UPDATE dbo.CR01RefreshManifest
SET SourceBytes=@{activity('Read Source Version').output.size},
    SourceLastModified='@{formatDateTime(activity('Read Source Version').output.lastModified,'yyyy-MM-ddTHH:mm:ss.ffffff')}',
    ExpectedRows=@{activity('Stage Source File').output.rowsCopied}
WHERE RefreshDate='@{variables('vRefreshDate')}' AND FileName='@{item().FileName}';
```

### 3.19 - Read Staged Manifest

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Lookup |
| General > Name (exact) | Read Staged Manifest |
| Incoming dependency | Stage All Overnight Files [Succeeded] |
| General > timeout | 0.12:00:00 |
| General > retry | 0 |
| General > retryIntervalInSeconds | 30 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse). Select **Use query > Query**.

**Settings > Query** - use Add dynamic content.

```sql
SELECT FileName,ExpectedRows FROM dbo.CR01RefreshManifest WHERE RefreshDate='@{variables('vRefreshDate')}' ORDER BY FileName;
```

**Settings > First row only** - literal value; do not add an expression wrapper.

```text
False
```

**Settings > Query timeout** - literal value; do not add an expression wrapper.

```text
02:00:00
```

**Source advanced > Partition option (where exposed)** - literal value; do not add an expression wrapper.

```text
None
```

### 3.20 - Wait For Queryable Staging

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Until |
| General > Name (exact) | Wait For Queryable Staging |
| Incoming dependency | Read Staged Manifest [Succeeded] |

**Settings > Expression (exit condition)** - use Add dynamic content.

```text
@equals(int(activity('Compute Staging Readiness').output.count),0)
```

**Settings > Timeout** - literal value; do not add an expression wrapper.

```text
0.00:30:00
```

Open the Activities canvas inside Until. The condition is evaluated after an iteration; retain the Wait activity.

### 3.20.1 - Compute Staging Readiness

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Wait For Queryable Staging > Activities |
| Activity to select | KQL |
| General > Name (exact) | Compute Staging Readiness |
| Incoming dependency | None inside this canvas/branch |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set-or-replace CR01_Checks <| let expected=print items=parse_json(base64_decode_tostring("@{base64(string(activity('Read Staged Manifest').output.value))}"))
    | mv-expand items | project file_name=tostring(items.FileName), Expected=tolong(items.ExpectedRows); expected | join kind=fullouter (CR01_Stage_@{formatDateTime(variables('vRefreshDate'),'yyyyMMdd')} | summarize Actual=count() by file_name) on file_name | where isnull(Expected) or Expected!=coalesce(Actual,0) | project Problem=strcat(file_name,' stage count mismatch')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.20.2 - Wait For Staging

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Wait For Queryable Staging > Activities |
| Activity to select | Wait |
| General > Name (exact) | Wait For Staging |
| Incoming dependency | Compute Staging Readiness [Succeeded] |

**Settings > Wait time in seconds** - literal value; do not add an expression wrapper.

```text
5
```

### 3.21 - Compute Staged Source Contract

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Staged Source Contract |
| Incoming dependency | Wait For Queryable Staging [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set-or-replace CR01_Checks <| CR01_Stage_@{formatDateTime(variables('vRefreshDate'),'yyyyMMdd')}
| where isnull(Date) or isnull(Credit_Amount) or isnull(Debit_Amount) or isnull(Net_Amount)
    or isnull(Credit_Transaction) or isnull(Debit_Transaction) or isnull(Total_Transaction)
    or format_datetime(Date,'yyyyMMdd') != extract(@"^INTRADAY_SUMMARY_(\d{8})_",1,file_name)
    or replace_string(trim(@"\s",Time),':','') != strcat(
        extract(@"^INTRADAY_SUMMARY_\d{8}_(\d{4})_(\d{4})\.CSV$",1,file_name),'-',
        extract(@"^INTRADAY_SUMMARY_\d{8}_(\d{4})_(\d{4})\.CSV$",2,file_name))
| project Problem=strcat(file_name,' invalid source data or filename/business interval mismatch')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.22 - Validate Staged Source Contract

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Staged Source Contract |
| Incoming dependency | Compute Staged Source Contract [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Staged Source Contract').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 3.22-True.1 - Validate Staged Source Contract Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Staged Source Contract > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Staged Source Contract Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Staged Source Contract has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 3.23 - Check Silver Transformation Version

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Check Silver Transformation Version |
| Incoming dependency | Validate Staged Source Contract [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.show function Transform_DepositMovementClassified | where Body!=base64_decode_tostring('ewogICAgLy8gTm90ZSAxOiBUaGUgZnVuY3Rpb24gaGFzIG5vIHBhcmFtZXRlcnMgYmVjYXVzZSB0aGUgdXBkYXRlIHBvbGljeSBzdXBwbGllcwogICAgLy8gdGhlIG5ld2x5IGluZ2VzdGVkIHJvd3MgdGhyb3VnaCB0aGUgRGVwb3NpdE1vdmVtZW50IHNvdXJjZSB0YWJsZSBiZWxvdy4KICAgIC8vCiAgICAvLyBOb3RlIDI6IFJlZmVyZW5jZSB0YWJsZXMgYXJlIHJlZHVjZWQgdG8gc2NhbGFyIGR5bmFtaWMgdmFsdWVzIG9uY2UgcGVyCiAgICAvLyBmdW5jdGlvbiBleGVjdXRpb24sIHRoZW4gcmV1c2VkIHdoaWxlIGV2ZXJ5IHNvdXJjZSByb3cgaXMgY2xhc3NpZmllZC4KICAgIC8vIEEgc2NhbGFyIHByb3BlcnR5IGJhZyBhdm9pZHMgYSBqb2luIGluIHRoZSB1cGRhdGUtcG9saWN5IHF1ZXJ5LiBGYWJyaWMKICAgIC8vIG90aGVyd2lzZSByZXF1aXJlcyBzdHJlYW1pbmcgaW5nZXN0aW9uIHRvIGJlIGRpc2FibGVkIG9uIHRoZSBzb3VyY2UgdGFibGUuCiAgICAvLwogICAgLy8gTm90ZSAzOiBUaGVzZSBib3VuZGFyaWVzIGZvcm0gW0phbnVhcnkgMSB0aGlzIHllYXIsIEphbnVhcnkgMSBuZXh0IHllYXIpLgogICAgLy8gVGhlIGhhbGYtb3BlbiByYW5nZSBpbmNsdWRlcyBldmVyeSBpbnN0YW50IGluIHRoZSBjdXJyZW50IGV4ZWN1dGlvbiB5ZWFyLgogICAgbGV0IEN1cnJlbnRZZWFyU3RhcnQgPSBzdGFydG9meWVhcihub3coKSk7CiAgICBsZXQgTmV4dFllYXJTdGFydCA9IGRhdGV0aW1lX2FkZCgieWVhciIsIDEsIEN1cnJlbnRZZWFyU3RhcnQpOwogICAgLy8gTm90ZSAzYjogVGhlIGV2ZW50LWZsYWcgY2FsZW5kYXIgc3BhbnMgYSBzbWFsbCBwYWQgb24gZWFjaCBzaWRlIG9mIHRoZSB5ZWFyCiAgICAvLyBzbyBsb25nLXdlZWtlbmQgcnVucyBhbmQgcGF5cm9sbCBzaGlmdHMgdGhhdCBjcm9zcyB0aGUgYm91bmRhcnkgcmVzb2x2ZQogICAgLy8gY29ycmVjdGx5LiBQYWRkZWQgZGF0ZXMgb3V0c2lkZSB0aGUgY3VycmVudCB5ZWFyIGFyZSBuZXZlciBlbWl0dGVkLgogICAgbGV0IENhbGVuZGFyU3RhcnQgPSBkYXRldGltZV9hZGQoImRheSIsIC0zLCBDdXJyZW50WWVhclN0YXJ0KTsKICAgIGxldCBDYWxlbmRhckVuZCA9IGRhdGV0aW1lX2FkZCgiZGF5IiwgMywgTmV4dFllYXJTdGFydCk7CiAgICAvLyBOb3RlIDQ6IEhvbGlkYXlCeURhdGUgYmVjb21lcyBhIHByb3BlcnR5IGJhZyBzdWNoIGFzCiAgICAvLyB7IjIwMjYtMDEtMDEiOiJOZXcgWWVhcidzIERheSJ9LCBlbmFibGluZyBhIGxvb2t1cCBieSBsb2NhbCBkYXRlIGtleS4KICAgIGxldCBIb2xpZGF5QnlEYXRlID0gdG9zY2FsYXIoCiAgICAgICAgVGhhaWxhbmRGaW5hbmNpYWxJbnN0aXR1dGlvbkhvbGlkYXkKICAgICAgICAvLyBOb3RlIDU6IEZpbHRlciBiZWZvcmUgc3VtbWFyaXplIHNvIGhvbGlkYXlzIG91dHNpZGUgdGhlIGN1cnJlbnQgeWVhcgogICAgICAgIC8vIGRvIG5vdCBjb25zdW1lIGFnZ3JlZ2F0aW9uIG1lbW9yeSBvciBwYXJ0aWNpcGF0ZSBpbiBjbGFzc2lmaWNhdGlvbi4KICAgICAgICB8IHdoZXJlIEhvbGlkYXlEYXRlID49IENhbGVuZGFyU3RhcnQKICAgICAgICAgICAgYW5kIEhvbGlkYXlEYXRlIDwgQ2FsZW5kYXJFbmQKICAgICAgICAvLyBOb3RlIDY6IE5vcm1hbGl6ZSB0aW1lc3RhbXBzIHRvIGRhdGVzIGFuZCBjaG9vc2Ugb25lIGRldGVybWluaXN0aWMKICAgICAgICAvLyBuYW1lIGlmIHRoZSByZWZlcmVuY2UgdGFibGUgY29udGFpbnMgZHVwbGljYXRlIHJvd3MgZm9yIHRoZSBzYW1lIGRheS4KICAgICAgICB8IHN1bW1hcml6ZSBIb2xpZGF5TmFtZSA9IG1pbihIb2xpZGF5TmFtZSkKICAgICAgICAgICAgYnkgSG9saWRheURhdGUgPSBzdGFydG9mZGF5KEhvbGlkYXlEYXRlKQogICAgICAgIHwgZXh0ZW5kIEhvbGlkYXlEYXRlS2V5ID0gZm9ybWF0X2RhdGV0aW1lKEhvbGlkYXlEYXRlLCAieXl5eS1NTS1kZCIpCiAgICAgICAgLy8gTm90ZSA3OiBtYWtlX2JhZyBjcmVhdGVzIHRoZSBkYXRlLXRvLW5hbWUgZGljdGlvbmFyeSB1c2VkIGxhdGVyIGJ5CiAgICAgICAgLy8gYmFnX2hhc19rZXkgYW5kIGluZGV4ZWQgbG9va3VwIG9wZXJhdGlvbnMuCiAgICAgICAgfCBzdW1tYXJpemUgSG9saWRheXMgPSBtYWtlX2JhZyhiYWdfcGFjayhIb2xpZGF5RGF0ZUtleSwgSG9saWRheU5hbWUpKQogICAgKTsKICAgIC8vIE5vdGUgODogV2luZG93cyBiZWNvbWVzIG9uZSBvcmRlcmVkIGR5bmFtaWMgYXJyYXkgY29udGFpbmluZyBhbGwgb3BlcmF0aW5nCiAgICAvLyB3aW5kb3cgZGVmaW5pdGlvbnMuIFNvcnRPcmRlciBrZWVwcyB0aGUgcmVmZXJlbmNlLXRhYmxlIHNlcXVlbmNlIHN0YWJsZS4KICAgIGxldCBXaW5kb3dzID0gdG9zY2FsYXIoCiAgICAgICAgT3BlcmF0aW5nV2luZG93c1RpbWVzCiAgICAgICAgfCBvcmRlciBieSBTb3J0T3JkZXIgYXNjCiAgICAgICAgfCBzdW1tYXJpemUgV2luZG93RGVmaW5pdGlvbnMgPSBtYWtlX2xpc3QocGFjaygKICAgICAgICAgICAgIldpbmRvd0NvZGUiLCBXaW5kb3dDb2RlLAogICAgICAgICAgICAiV2luZG93TmFtZSIsIFdpbmRvd05hbWUsCiAgICAgICAgICAgICJTdGFydFRpbWUiLCBTdGFydFRpbWUsCiAgICAgICAgICAgICJFbmRUaW1lIiwgRW5kVGltZSwKICAgICAgICAgICAgIlNvcnRPcmRlciIsIFNvcnRPcmRlcikpCiAgICApOwogICAgLy8gTm90ZSA4YjogWWVhckNhbGVuZGFyIGVudW1lcmF0ZXMgZXZlcnkgbG9jYWwgZGF0ZSBpbiB0aGUgcGFkZGVkIHllYXIgYW5kCiAgICAvLyBmbGFncyB3ZWVrZW5kcyBhbmQgaG9saWRheXMgc28gYnVzaW5lc3MgZGF5cyBjYW4gYmUgZGVyaXZlZCBkZXRlcm1pbmlzdGljYWxseS4KICAgIGxldCBZZWFyQ2FsZW5kYXIgPQogICAgICAgIHJhbmdlIF9DYWxEYXkgZnJvbSBDYWxlbmRhclN0YXJ0IHRvIGRhdGV0aW1lX2FkZCgiZGF5IiwgLTEsIENhbGVuZGFyRW5kKSBzdGVwIDFkCiAgICAgICAgfCBleHRlbmQgX0NhbEtleSA9IGZvcm1hdF9kYXRldGltZShfQ2FsRGF5LCAieXl5eS1NTS1kZCIpCiAgICAgICAgfCBleHRlbmQgX0NhbElzV2Vla2VuZCA9IGRheW9md2VlayhfQ2FsRGF5KSBpbiAoMGQsIDZkKQogICAgICAgIHwgZXh0ZW5kIF9DYWxJc0hvbGlkYXkgPSBiYWdfaGFzX2tleShIb2xpZGF5QnlEYXRlLCBfQ2FsS2V5KQogICAgICAgIHwgZXh0ZW5kIF9DYWxJc0J1c2luZXNzRGF5ID0gbm90KF9DYWxJc1dlZWtlbmQpIGFuZCBub3QoX0NhbElzSG9saWRheSk7CiAgICAvLyBOb3RlIDhjOiBQYXlyb2xsRGF0ZXMgcmVzb2x2ZXMgZWFjaCBzY2hlZHVsZWQgcGF5ZGF5ICh0aGUgMjV0aCBhbmQgdGhlIGxhc3QKICAgIC8vIGNhbGVuZGFyIGRheSBvZiB0aGUgbW9udGgpIGJhY2t3YXJkIHRvIHRoZSBwcmV2aW91cyBidXNpbmVzcyBkYXkgd2hlbiBpdAogICAgLy8gZmFsbHMgb24gYSB3ZWVrZW5kIG9yIGhvbGlkYXksIHRoZW4ga2VlcHMgdGhlIGVmZmVjdGl2ZSBkYXRlcyBhcyBhIHNldC4KICAgIGxldCBQYXlyb2xsRGF0ZXMgPSB0b3NjYWxhcigKICAgICAgICBZZWFyQ2FsZW5kYXIKICAgICAgICB8IHdoZXJlIGRheW9mbW9udGgoX0NhbERheSkgPT0gMjUgb3IgX0NhbERheSA9PSBzdGFydG9mZGF5KGVuZG9mbW9udGgoX0NhbERheSkpCiAgICAgICAgfCBwcm9qZWN0IF9BbmNob3JEYXRlID0gX0NhbERheQogICAgICAgIHwgbXYtZXhwYW5kIF9PZmZzZXQgPSByYW5nZSgwLCAxNCwgMSkgdG8gdHlwZW9mKGxvbmcpCiAgICAgICAgfCBleHRlbmQgX0NhbmRpZGF0ZSA9IGRhdGV0aW1lX2FkZCgiZGF5IiwgLV9PZmZzZXQsIF9BbmNob3JEYXRlKQogICAgICAgIHwgZXh0ZW5kIF9DYW5kS2V5ID0gZm9ybWF0X2RhdGV0aW1lKF9DYW5kaWRhdGUsICJ5eXl5LU1NLWRkIikKICAgICAgICB8IGV4dGVuZCBfQ2FuZElzQnVzaW5lc3NEYXkgPQogICAgICAgICAgICBub3QoZGF5b2Z3ZWVrKF9DYW5kaWRhdGUpIGluICgwZCwgNmQpKQogICAgICAgICAgICBhbmQgbm90KGJhZ19oYXNfa2V5KEhvbGlkYXlCeURhdGUsIF9DYW5kS2V5KSkKICAgICAgICB8IHdoZXJlIF9DYW5kSXNCdXNpbmVzc0RheQogICAgICAgIHwgc3VtbWFyaXplIGFyZ19taW4oX09mZnNldCwgX0NhbmRpZGF0ZSkgYnkgX0FuY2hvckRhdGUKICAgICAgICB8IHN1bW1hcml6ZSBQYXlyb2xsU2V0ID0gbWFrZV9zZXQoZm9ybWF0X2RhdGV0aW1lKF9DYW5kaWRhdGUsICJ5eXl5LU1NLWRkIikpCiAgICApOwogICAgLy8gTm90ZSA4ZDogTG9uZ1dlZWtlbmREYXRlcyBmaW5kcyBtYXhpbWFsIHJ1bnMgb2YgY29uc2VjdXRpdmUgbm9uLWJ1c2luZXNzCiAgICAvLyBkYXlzLiBBIHJ1bm5pbmcgY291bnQgb2YgYnVzaW5lc3MgZGF5cyBob2xkcyBvbmUgaWQgYWNyb3NzIGVhY2ggZ2FwLCBzbyBhCiAgICAvLyBydW4gb2YgdGhyZWUgb3IgbW9yZSBub24tYnVzaW5lc3MgZGF5cyBtYXJrcyBldmVyeSBkYXRlIGl0IGNvbnRhaW5zLgogICAgbGV0IExvbmdXZWVrZW5kRGF0ZXMgPSB0b3NjYWxhcigKICAgICAgICBZZWFyQ2FsZW5kYXIKICAgICAgICB8IG9yZGVyIGJ5IF9DYWxEYXkgYXNjCiAgICAgICAgfCBleHRlbmQgX0J1c2luZXNzUnVuSWQgPSByb3dfY3Vtc3VtKHRvaW50KF9DYWxJc0J1c2luZXNzRGF5KSkKICAgICAgICB8IHdoZXJlIG5vdChfQ2FsSXNCdXNpbmVzc0RheSkKICAgICAgICB8IHN1bW1hcml6ZSBfUnVuTGVuZ3RoID0gY291bnQoKSwgX1J1bkRhdGVzID0gbWFrZV9saXN0KF9DYWxLZXkpIGJ5IF9CdXNpbmVzc1J1bklkCiAgICAgICAgfCB3aGVyZSBfUnVuTGVuZ3RoID49IDMKICAgICAgICB8IG12LWV4cGFuZCBfUnVuRGF0ZSA9IF9SdW5EYXRlcyB0byB0eXBlb2Yoc3RyaW5nKQogICAgICAgIHwgc3VtbWFyaXplIExvbmdXZWVrZW5kU2V0ID0gbWFrZV9zZXQoX1J1bkRhdGUpCiAgICApOwogICAgLy8gTm90ZSA5OiBQcm9jZXNzaW5nIHN0YXJ0cyB3aXRoIHRoZSBCcm9uemUgcm93cyBzdXBwbGllZCB0byB0aGlzIGZ1bmN0aW9uLgogICAgRGVwb3NpdE1vdmVtZW50CiAgICAvLyBOb3RlIDliOiBOb3JtYWxpemUgQ2hhbm5lbCAtIHNvdXJjZSBjYW4gY2FycnkgbGVhZGluZy90cmFpbGluZyB3aGl0ZXNwYWNlLAogICAgLy8gd2hpY2ggYnJlYWtzIGV4YWN0IG1hdGNoZXMgKE1TWUcvU1lTRyBleGNsdXNpb24sIElzUmV0YWlsLCBDaGFubmVsX0dyb3VwKS4KICAgIHwgZXh0ZW5kIENoYW5uZWwgPSB0cmltKEAiXHMiLCB0b3N0cmluZyhDaGFubmVsKSkKICAgIC8vIE5vdGUgMTA6IERhdGUgaXMgaW50ZXJwcmV0ZWQgYXMgQmFuZ2tvayBsb2NhbCBjYWxlbmRhciB0aW1lLiBUaW1lIHN0b3JlcwogICAgLy8gYW4gaW50ZXJ2YWwsIHNvIG9ubHkgaXRzIEhIOm1tIHN0YXJ0IHZhbHVlIGlzIGV4dHJhY3RlZCBmb3IgY2xhc3NpZmljYXRpb24uCiAgICB8IGV4dGVuZAogICAgICAgIExvY2FsRGF0ZSA9IHN0YXJ0b2ZkYXkoRGF0ZSksCiAgICAgICAgX1RpbWVTdGFydFRleHQgPSBleHRyYWN0KEAiXihbMC05XXsyfTpbMC05XXsyfSktWzAtOV17Mn06WzAtOV17Mn0kIiwgMSwgVGltZSkKICAgIC8vIE5vdGUgMTE6IEFwcGVuZGluZyBzZWNvbmRzIGNvbnZlcnRzIEhIOm1tIGludG8gYSB0aW1lc3BhbiB0aGF0IGNhbiBiZQogICAgLy8gY29tcGFyZWQgd2l0aCB0aGUgU3RhcnRUaW1lIGFuZCBFbmRUaW1lIHZhbHVlcyBmcm9tIHRoZSB3aW5kb3cgcmVmZXJlbmNlLgogICAgfCBleHRlbmQgTG9jYWxUaW1lT2ZEYXkgPSB0b3RpbWVzcGFuKHN0cmNhdChfVGltZVN0YXJ0VGV4dCwgIjowMCIpKQogICAgfCBleHRlbmQgTG9jYWxEYXRlVGltZSA9IExvY2FsRGF0ZSArIExvY2FsVGltZU9mRGF5CiAgICAvLyBOb3RlIDEyOiBLUUwgZGF5b2Z3ZWVrIHJldHVybnMgU3VuZGF5IGFzIDBkIGFuZCBTYXR1cmRheSBhcyA2ZC4KICAgIHwgZXh0ZW5kCiAgICAgICAgSXNXZWVrZW5kID0gZGF5b2Z3ZWVrKExvY2FsRGF0ZSkgaW4gKDBkLCA2ZCksCiAgICAgICAgX0xvY2FsRGF0ZUtleSA9IGZvcm1hdF9kYXRldGltZShMb2NhbERhdGUsICJ5eXl5LU1NLWRkIikKICAgIC8vIE5vdGUgMTM6IFRoZSBkYXRlIGtleSBjaGVja3MgaG9saWRheSBtZW1iZXJzaGlwIGFuZCByZXRyaWV2ZXMgaXRzIG5hbWUKICAgIC8vIHdpdGhvdXQgam9pbmluZyBlYWNoIERlcG9zaXRNb3ZlbWVudCByb3cgdG8gdGhlIGhvbGlkYXkgdGFibGUuCiAgICB8IGV4dGVuZAogICAgICAgIElzRmluYW5jaWFsSW5zdGl0dXRpb25Ib2xpZGF5ID0gYmFnX2hhc19rZXkoSG9saWRheUJ5RGF0ZSwgX0xvY2FsRGF0ZUtleSksCiAgICAgICAgSG9saWRheU5hbWUgPSB0b3N0cmluZyhIb2xpZGF5QnlEYXRlW19Mb2NhbERhdGVLZXldKQogICAgLy8gTm90ZSAxNDogQSBidXNpbmVzcyBkYXkgbXVzdCBwYXNzIGJvdGggY2FsZW5kYXIgY2hlY2tzLiBPcGVyYXRpbmctd2luZG93CiAgICAvLyBhc3NpZ25tZW50IGlzIGluZGVwZW5kZW50IGFuZCBhcHBsaWVzIHRvIGV2ZXJ5IHZhbGlkIHNvdXJjZSByb3cuCiAgICB8IGV4dGVuZCBJc0J1c2luZXNzRGF5ID0gbm90KElzV2Vla2VuZCkKICAgICAgICBhbmQgbm90KElzRmluYW5jaWFsSW5zdGl0dXRpb25Ib2xpZGF5KQogICAgLy8gTm90ZSAxNTogV2Vla2VuZCBoYXMgcHJlY2VkZW5jZSB3aGVuIGEgZGF0ZSBpcyBib3RoIGEgd2Vla2VuZCBhbmQgYSBsaXN0ZWQKICAgIC8vIGhvbGlkYXk7IG90aGVyd2lzZSB0aGUgZGF0ZSBpcyBjbGFzc2lmaWVkIGFzIGhvbGlkYXkgb3IgYnVzaW5lc3MgZGF5LgogICAgfCBleHRlbmQgRGF5Q2xhc3NpZmljYXRpb24gPSBjYXNlKAogICAgICAgIElzV2Vla2VuZCwgIldFRUtFTkQiLAogICAgICAgIElzRmluYW5jaWFsSW5zdGl0dXRpb25Ib2xpZGF5LCAiSE9MSURBWSIsCiAgICAgICAgIkJVU0lORVNTX0RBWSIpCiAgICAvLyBtdi1hcHBseSBldmFsdWF0ZXMgYWxsIHJlZmVyZW5jZSByYW5nZXMgaW5zaWRlIGVhY2ggc291cmNlIHJvdy4gVGhlIHN1bW1hcml6ZQogICAgLy8gcmV0dXJucyBvbmUgcmVzdWx0IHBlciBpbnB1dCByb3csIGluY2x1ZGluZyBtYWxmb3JtZWQgb3IgdW5tYXRjaGVkIHJvd3MuCiAgICAvLyBOb3RlIDE2OiBXaW5kb3cgcmFuZ2VzIGFyZSBoYWxmLW9wZW4gW1N0YXJ0VGltZSwgRW5kVGltZSksIHNvIGEgYm91bmRhcnkKICAgIC8vIHRpbWUgYmVsb25ncyB0byB0aGUgd2luZG93IHRoYXQgc3RhcnRzIHRoZXJlIGFuZCBuZXZlciB0byB0aGUgcHJldmlvdXMgb25lLgogICAgfCBtdi1hcHBseSBfV2luZG93ID0gV2luZG93cyB0byB0eXBlb2YoZHluYW1pYykgb24gKAogICAgICAgIGV4dGVuZAogICAgICAgICAgICBfV2luZG93U3RhcnQgPSB0b3RpbWVzcGFuKF9XaW5kb3dbIlN0YXJ0VGltZSJdKSwKICAgICAgICAgICAgX1dpbmRvd0VuZCA9IHRvdGltZXNwYW4oX1dpbmRvd1siRW5kVGltZSJdKQogICAgICAgIHwgZXh0ZW5kIF9Jc1dpbmRvd01hdGNoID0KICAgICAgICAgICAgaXNub3RudWxsKExvY2FsVGltZU9mRGF5KQogICAgICAgICAgICBhbmQgTG9jYWxUaW1lT2ZEYXkgPj0gX1dpbmRvd1N0YXJ0CiAgICAgICAgICAgIGFuZCBMb2NhbFRpbWVPZkRheSA8IF9XaW5kb3dFbmQKICAgICAgICAvLyBOb3RlIDE3OiBDb3VudGluZyBtYXRjaGVzIGRldGVjdHMgbWlzc2luZyBhbmQgb3ZlcmxhcHBpbmcgcmVmZXJlbmNlCiAgICAgICAgLy8gd2luZG93cy4gVGhlIG1hdGNoaW5nIGRlZmluaXRpb25zIGFyZSByZXRhaW5lZCBmb3IgZmllbGQgZXh0cmFjdGlvbi4KICAgICAgICB8IHN1bW1hcml6ZQogICAgICAgICAgICBXaW5kb3dNYXRjaENvdW50ID0gY291bnRpZihfSXNXaW5kb3dNYXRjaCksCiAgICAgICAgICAgIF9NYXRjaGVkV2luZG93cyA9IG1ha2VfbGlzdF9pZihfV2luZG93LCBfSXNXaW5kb3dNYXRjaCkKICAgICkKICAgIC8vIE5vdGUgMTg6IEluZGV4IHplcm8gaXMgc2FmZSB0byBpbnNwZWN0IGFzIGEgZHluYW1pYyB2YWx1ZS4gT3V0cHV0IHdpbmRvdwogICAgLy8gZmllbGRzIGFyZSBwb3B1bGF0ZWQgb25seSB3aGVuIGV4YWN0bHkgb25lIGRlZmluaXRpb24gbWF0Y2hlZC4KICAgIHwgZXh0ZW5kIF9NYXRjaGVkV2luZG93ID0gX01hdGNoZWRXaW5kb3dzWzBdCiAgICB8IGV4dGVuZAogICAgICAgIE9wZXJhdGluZ1dpbmRvd0NvZGUgPSBpZmYoV2luZG93TWF0Y2hDb3VudCA9PSAxLCB0b3N0cmluZyhfTWF0Y2hlZFdpbmRvd1siV2luZG93Q29kZSJdKSwgIiIpLAogICAgICAgIE9wZXJhdGluZ1dpbmRvd05hbWUgPSBpZmYoV2luZG93TWF0Y2hDb3VudCA9PSAxLCB0b3N0cmluZyhfTWF0Y2hlZFdpbmRvd1siV2luZG93TmFtZSJdKSwgIiIpLAogICAgICAgIE9wZXJhdGluZ1dpbmRvd1N0YXJ0VGltZSA9IGlmZihXaW5kb3dNYXRjaENvdW50ID09IDEsIHRvdGltZXNwYW4oX01hdGNoZWRXaW5kb3dbIlN0YXJ0VGltZSJdKSwgdGltZXNwYW4obnVsbCkpLAogICAgICAgIE9wZXJhdGluZ1dpbmRvd0VuZFRpbWUgPSBpZmYoV2luZG93TWF0Y2hDb3VudCA9PSAxLCB0b3RpbWVzcGFuKF9NYXRjaGVkV2luZG93WyJFbmRUaW1lIl0pLCB0aW1lc3BhbihudWxsKSksCiAgICAgICAgT3BlcmF0aW5nV2luZG93U29ydE9yZGVyID0gaWZmKFdpbmRvd01hdGNoQ291bnQgPT0gMSwgdG9pbnQoX01hdGNoZWRXaW5kb3dbIlNvcnRPcmRlciJdKSwgaW50KG51bGwpKSwKICAgICAgICAvLyBOb3RlIDE5OiBTdGF0dXMgcHJlY2VkZW5jZSByZXBvcnRzIG1hbGZvcm1lZCB0aW1lIGZpcnN0LCBmb2xsb3dlZCBieQogICAgICAgIC8vIG1pc3Npbmcgb3Igb3ZlcmxhcHBpbmcgd2luZG93IGRlZmluaXRpb25zIGZvciBldmVyeSBkYXkgY2xhc3NpZmljYXRpb24uCiAgICAgICAgQ2xhc3NpZmljYXRpb25TdGF0dXMgPSBjYXNlKAogICAgICAgICAgICBpc2VtcHR5KF9UaW1lU3RhcnRUZXh0KSwgIklOVkFMSURfVElNRV9GT1JNQVQiLAogICAgICAgICAgICBXaW5kb3dNYXRjaENvdW50ID09IDAsICJOT19XSU5ET1dfTUFUQ0giLAogICAgICAgICAgICBXaW5kb3dNYXRjaENvdW50ID4gMSwgIk1VTFRJUExFX1dJTkRPV19NQVRDSEVTIiwKICAgICAgICAgICAgIkNMQVNTSUZJRUQiKQogICAgLy8gTm90ZSAxOWI6IEV2ZW50IGZsYWdzIG1hcmsgY2FsZW5kYXIgZXZlbnRzIHRoYXQgc2hpZnQgZGVwb3NpdCBiZWhhdmlvdXIuCiAgICAvLyBNb250aC1lbmQgaXMgdGhlIGxhc3QgY2FsZW5kYXIgZGF5OyBwYXlyb2xsIGFuZCBsb25nLXdlZWtlbmQgbWVtYmVyc2hpcAogICAgLy8gY29tZSBmcm9tIHRoZSBwcmUtY29tcHV0ZWQgc2V0cy4gRXZlbnRGbGFnIGpvaW5zIHRoZSBhY3RpdmUgZXZlbnRzIHdpdGggYQogICAgLy8gY29tbWEsIG9yIHJlcG9ydHMgTk9STUFMIHdoZW4gbm9uZSBhcHBseS4KICAgIHwgZXh0ZW5kCiAgICAgICAgSXNNb250aEVuZCA9IExvY2FsRGF0ZSA9PSBzdGFydG9mZGF5KGVuZG9mbW9udGgoTG9jYWxEYXRlKSksCiAgICAgICAgSXNQYXlyb2xsID0gc2V0X2hhc19lbGVtZW50KFBheXJvbGxEYXRlcywgX0xvY2FsRGF0ZUtleSksCiAgICAgICAgSXNMb25nV2Vla2VuZCA9IHNldF9oYXNfZWxlbWVudChMb25nV2Vla2VuZERhdGVzLCBfTG9jYWxEYXRlS2V5KQogICAgfCBleHRlbmQgX0V2ZW50TGlzdCA9IHNldF9kaWZmZXJlbmNlKHBhY2tfYXJyYXkoCiAgICAgICAgICAgIGlmZihJc01vbnRoRW5kLCAiTU9OVEhfRU5EIiwgIiIpLAogICAgICAgICAgICBpZmYoSXNQYXlyb2xsLCAiUEFZUk9MTCIsICIiKSwKICAgICAgICAgICAgaWZmKElzTG9uZ1dlZWtlbmQsICJMT05HX1dFRUtFTkQiLCAiIikpLCBkeW5hbWljKFsiIl0pKQogICAgfCBleHRlbmQgRXZlbnRGbGFnID0gaWZmKGFycmF5X2xlbmd0aChfRXZlbnRMaXN0KSA9PSAwLCAiTk9STUFMIiwgc3RyY2F0X2FycmF5KF9FdmVudExpc3QsICIsIikpCiAgICAvLyBOb3RlIDIwOiBUaGUgZmluYWwgcHJvamVjdGlvbiByZW1vdmVzIHRlbXBvcmFyeSB1bmRlcnNjb3JlLXByZWZpeGVkIGZpZWxkcwogICAgLy8gYW5kIGZpeGVzIHRoZSBleGFjdCBjb2x1bW4gb3JkZXIgcmVxdWlyZWQgYnkgRGVwb3NpdE1vdmVtZW50Q2xhc3NpZmllZC4KICAgIHwgcHJvamVjdAogICAgICAgIERhdGUsIFRpbWUsIFByb2R1Y3QsIENoYW5uZWwsIENoYW5uZWxfR3JvdXAsCiAgICAgICAgQ3JlZGl0X0Ftb3VudCwgRGViaXRfQW1vdW50LCBOZXRfQW1vdW50LAogICAgICAgIENyZWRpdF9UcmFuc2FjdGlvbiwgRGViaXRfVHJhbnNhY3Rpb24sIFRvdGFsX1RyYW5zYWN0aW9uLAogICAgICAgIGxvYWRfdHMsIGZpbGVfbmFtZSwgcGlwZWxpbmVfbmFtZSwgcGlwZWxpbmVfcnVuaWQsCiAgICAgICAgTG9jYWxEYXRlLCBMb2NhbERhdGVUaW1lLCBMb2NhbFRpbWVPZkRheSwKICAgICAgICBJc1dlZWtlbmQsIElzRmluYW5jaWFsSW5zdGl0dXRpb25Ib2xpZGF5LCBJc0J1c2luZXNzRGF5LAogICAgICAgIERheUNsYXNzaWZpY2F0aW9uLCBIb2xpZGF5TmFtZSwKICAgICAgICBPcGVyYXRpbmdXaW5kb3dDb2RlLCBPcGVyYXRpbmdXaW5kb3dOYW1lLAogICAgICAgIE9wZXJhdGluZ1dpbmRvd1N0YXJ0VGltZSwgT3BlcmF0aW5nV2luZG93RW5kVGltZSwgT3BlcmF0aW5nV2luZG93U29ydE9yZGVyLAogICAgICAgIFdpbmRvd01hdGNoQ291bnQsIENsYXNzaWZpY2F0aW9uU3RhdHVzLAogICAgICAgIElzTW9udGhFbmQsIElzUGF5cm9sbCwgSXNMb25nV2Vla2VuZCwgRXZlbnRGbGFnCn0=')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.24 - Validate Silver Transformation Version

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Silver Transformation Version |
| Incoming dependency | Check Silver Transformation Version [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Check Silver Transformation Version').output.count),0)
```

**True branch:** open this branch and add its activities below.

### 3.24-True.1 - Validate Silver Transformation Version Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Silver Transformation Version > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Silver Transformation Version Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
Silver transformation changed since deployment. Regenerate the CR01 preview.
```

**False branch:** leave empty.

### 3.25 - Preview Existing Silver Classification

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Preview Existing Silver Classification |
| Incoming dependency | Validate Silver Transformation Version [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.create-or-alter function CR01_PreviewSilver(SourceRows:(Date:datetime,Time:string,Product:string,Channel:string,Channel_Group:string,Credit_Amount:decimal,Debit_Amount:decimal,Net_Amount:decimal,Credit_Transaction:long,Debit_Transaction:long,Total_Transaction:long,load_ts:datetime,file_name:string,pipeline_name:string,pipeline_runid:string)) {
    // Note 1: The function has no parameters because the update policy supplies
    // the newly ingested rows through the SourceRows source table below.
    //
    // Note 2: Reference tables are reduced to scalar dynamic values once per
    // function execution, then reused while every source row is classified.
    // A scalar property bag avoids a join in the update-policy query. Fabric
    // otherwise requires streaming ingestion to be disabled on the source table.
    //
    // Note 3: These boundaries form [January 1 this year, January 1 next year).
    // The half-open range includes every instant in the current execution year.
    let CurrentYearStart = startofyear(now());
    let NextYearStart = datetime_add("year", 1, CurrentYearStart);
    // Note 3b: The event-flag calendar spans a small pad on each side of the year
    // so long-weekend runs and payroll shifts that cross the boundary resolve
    // correctly. Padded dates outside the current year are never emitted.
    let CalendarStart = datetime_add("day", -3, CurrentYearStart);
    let CalendarEnd = datetime_add("day", 3, NextYearStart);
    // Note 4: HolidayByDate becomes a property bag such as
    // {"2026-01-01":"New Year's Day"}, enabling a lookup by local date key.
    let HolidayByDate = toscalar(
        ThailandFinancialInstitutionHoliday
        // Note 5: Filter before summarize so holidays outside the current year
        // do not consume aggregation memory or participate in classification.
        | where HolidayDate >= CalendarStart
            and HolidayDate < CalendarEnd
        // Note 6: Normalize timestamps to dates and choose one deterministic
        // name if the reference table contains duplicate rows for the same day.
        | summarize HolidayName = min(HolidayName)
            by HolidayDate = startofday(HolidayDate)
        | extend HolidayDateKey = format_datetime(HolidayDate, "yyyy-MM-dd")
        // Note 7: make_bag creates the date-to-name dictionary used later by
        // bag_has_key and indexed lookup operations.
        | summarize Holidays = make_bag(bag_pack(HolidayDateKey, HolidayName))
    );
    // Note 8: Windows becomes one ordered dynamic array containing all operating
    // window definitions. SortOrder keeps the reference-table sequence stable.
    let Windows = toscalar(
        OperatingWindowsTimes
        | order by SortOrder asc
        | summarize WindowDefinitions = make_list(pack(
            "WindowCode", WindowCode,
            "WindowName", WindowName,
            "StartTime", StartTime,
            "EndTime", EndTime,
            "SortOrder", SortOrder))
    );
    // Note 8b: YearCalendar enumerates every local date in the padded year and
    // flags weekends and holidays so business days can be derived deterministically.
    let YearCalendar =
        range _CalDay from CalendarStart to datetime_add("day", -1, CalendarEnd) step 1d
        | extend _CalKey = format_datetime(_CalDay, "yyyy-MM-dd")
        | extend _CalIsWeekend = dayofweek(_CalDay) in (0d, 6d)
        | extend _CalIsHoliday = bag_has_key(HolidayByDate, _CalKey)
        | extend _CalIsBusinessDay = not(_CalIsWeekend) and not(_CalIsHoliday);
    // Note 8c: PayrollDates resolves each scheduled payday (the 25th and the last
    // calendar day of the month) backward to the previous business day when it
    // falls on a weekend or holiday, then keeps the effective dates as a set.
    let PayrollDates = toscalar(
        YearCalendar
        | where dayofmonth(_CalDay) == 25 or _CalDay == startofday(endofmonth(_CalDay))
        | project _AnchorDate = _CalDay
        | mv-expand _Offset = range(0, 14, 1) to typeof(long)
        | extend _Candidate = datetime_add("day", -_Offset, _AnchorDate)
        | extend _CandKey = format_datetime(_Candidate, "yyyy-MM-dd")
        | extend _CandIsBusinessDay =
            not(dayofweek(_Candidate) in (0d, 6d))
            and not(bag_has_key(HolidayByDate, _CandKey))
        | where _CandIsBusinessDay
        | summarize arg_min(_Offset, _Candidate) by _AnchorDate
        | summarize PayrollSet = make_set(format_datetime(_Candidate, "yyyy-MM-dd"))
    );
    // Note 8d: LongWeekendDates finds maximal runs of consecutive non-business
    // days. A running count of business days holds one id across each gap, so a
    // run of three or more non-business days marks every date it contains.
    let LongWeekendDates = toscalar(
        YearCalendar
        | order by _CalDay asc
        | extend _BusinessRunId = row_cumsum(toint(_CalIsBusinessDay))
        | where not(_CalIsBusinessDay)
        | summarize _RunLength = count(), _RunDates = make_list(_CalKey) by _BusinessRunId
        | where _RunLength >= 3
        | mv-expand _RunDate = _RunDates to typeof(string)
        | summarize LongWeekendSet = make_set(_RunDate)
    );
    // Note 9: Processing starts with the Bronze rows supplied to this function.
    SourceRows
    // Note 9b: Normalize Channel - source can carry leading/trailing whitespace,
    // which breaks exact matches (MSYG/SYSG exclusion, IsRetail, Channel_Group).
    | extend Channel = trim(@"\s", tostring(Channel))
    // Note 10: Date is interpreted as Bangkok local calendar time. Time stores
    // an interval, so only its HH:mm start value is extracted for classification.
    | extend
        LocalDate = startofday(Date),
        _TimeStartText = extract(@"^([0-9]{2}:[0-9]{2})-[0-9]{2}:[0-9]{2}$", 1, Time)
    // Note 11: Appending seconds converts HH:mm into a timespan that can be
    // compared with the StartTime and EndTime values from the window reference.
    | extend LocalTimeOfDay = totimespan(strcat(_TimeStartText, ":00"))
    | extend LocalDateTime = LocalDate + LocalTimeOfDay
    // Note 12: KQL dayofweek returns Sunday as 0d and Saturday as 6d.
    | extend
        IsWeekend = dayofweek(LocalDate) in (0d, 6d),
        _LocalDateKey = format_datetime(LocalDate, "yyyy-MM-dd")
    // Note 13: The date key checks holiday membership and retrieves its name
    // without joining each SourceRows row to the holiday table.
    | extend
        IsFinancialInstitutionHoliday = bag_has_key(HolidayByDate, _LocalDateKey),
        HolidayName = tostring(HolidayByDate[_LocalDateKey])
    // Note 14: A business day must pass both calendar checks. Operating-window
    // assignment is independent and applies to every valid source row.
    | extend IsBusinessDay = not(IsWeekend)
        and not(IsFinancialInstitutionHoliday)
    // Note 15: Weekend has precedence when a date is both a weekend and a listed
    // holiday; otherwise the date is classified as holiday or business day.
    | extend DayClassification = case(
        IsWeekend, "WEEKEND",
        IsFinancialInstitutionHoliday, "HOLIDAY",
        "BUSINESS_DAY")
    // mv-apply evaluates all reference ranges inside each source row. The summarize
    // returns one result per input row, including malformed or unmatched rows.
    // Note 16: Window ranges are half-open [StartTime, EndTime), so a boundary
    // time belongs to the window that starts there and never to the previous one.
    | mv-apply _Window = Windows to typeof(dynamic) on (
        extend
            _WindowStart = totimespan(_Window["StartTime"]),
            _WindowEnd = totimespan(_Window["EndTime"])
        | extend _IsWindowMatch =
            isnotnull(LocalTimeOfDay)
            and LocalTimeOfDay >= _WindowStart
            and LocalTimeOfDay < _WindowEnd
        // Note 17: Counting matches detects missing and overlapping reference
        // windows. The matching definitions are retained for field extraction.
        | summarize
            WindowMatchCount = countif(_IsWindowMatch),
            _MatchedWindows = make_list_if(_Window, _IsWindowMatch)
    )
    // Note 18: Index zero is safe to inspect as a dynamic value. Output window
    // fields are populated only when exactly one definition matched.
    | extend _MatchedWindow = _MatchedWindows[0]
    | extend
        OperatingWindowCode = iff(WindowMatchCount == 1, tostring(_MatchedWindow["WindowCode"]), ""),
        OperatingWindowName = iff(WindowMatchCount == 1, tostring(_MatchedWindow["WindowName"]), ""),
        OperatingWindowStartTime = iff(WindowMatchCount == 1, totimespan(_MatchedWindow["StartTime"]), timespan(null)),
        OperatingWindowEndTime = iff(WindowMatchCount == 1, totimespan(_MatchedWindow["EndTime"]), timespan(null)),
        OperatingWindowSortOrder = iff(WindowMatchCount == 1, toint(_MatchedWindow["SortOrder"]), int(null)),
        // Note 19: Status precedence reports malformed time first, followed by
        // missing or overlapping window definitions for every day classification.
        ClassificationStatus = case(
            isempty(_TimeStartText), "INVALID_TIME_FORMAT",
            WindowMatchCount == 0, "NO_WINDOW_MATCH",
            WindowMatchCount > 1, "MULTIPLE_WINDOW_MATCHES",
            "CLASSIFIED")
    // Note 19b: Event flags mark calendar events that shift deposit behaviour.
    // Month-end is the last calendar day; payroll and long-weekend membership
    // come from the pre-computed sets. EventFlag joins the active events with a
    // comma, or reports NORMAL when none apply.
    | extend
        IsMonthEnd = LocalDate == startofday(endofmonth(LocalDate)),
        IsPayroll = set_has_element(PayrollDates, _LocalDateKey),
        IsLongWeekend = set_has_element(LongWeekendDates, _LocalDateKey)
    | extend _EventList = set_difference(pack_array(
            iff(IsMonthEnd, "MONTH_END", ""),
            iff(IsPayroll, "PAYROLL", ""),
            iff(IsLongWeekend, "LONG_WEEKEND", "")), dynamic([""]))
    | extend EventFlag = iff(array_length(_EventList) == 0, "NORMAL", strcat_array(_EventList, ","))
    // Note 20: The final projection removes temporary underscore-prefixed fields
    // and fixes the exact column order required by DepositMovementClassified.
    | project
        Date, Time, Product, Channel, Channel_Group,
        Credit_Amount, Debit_Amount, Net_Amount,
        Credit_Transaction, Debit_Transaction, Total_Transaction,
        load_ts, file_name, pipeline_name, pipeline_runid,
        LocalDate, LocalDateTime, LocalTimeOfDay,
        IsWeekend, IsFinancialInstitutionHoliday, IsBusinessDay,
        DayClassification, HolidayName,
        OperatingWindowCode, OperatingWindowName,
        OperatingWindowStartTime, OperatingWindowEndTime, OperatingWindowSortOrder,
        WindowMatchCount, ClassificationStatus,
        IsMonthEnd, IsPayroll, IsLongWeekend, EventFlag
}
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.26 - Compute Preview Calendar Classification

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Preview Calendar Classification |
| Incoming dependency | Preview Existing Silver Classification [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set-or-replace CR01_Checks <| let preview=CR01_PreviewSilver(CR01_Stage_@{formatDateTime(variables('vRefreshDate'),'yyyyMMdd')});
let holidayDates=toscalar(ThailandFinancialInstitutionHoliday | summarize make_set(format_datetime(HolidayDate,'yyyy-MM-dd')));
let knownYears=toscalar(ThailandFinancialInstitutionHoliday | summarize make_set(getyear(HolidayDate)));
union
    (preview | where ClassificationStatus!='CLASSIFIED' | project Problem=strcat(file_name,' ',ClassificationStatus)),
    (preview | where IsFinancialInstitutionHoliday!=set_has_element(holidayDates,format_datetime(LocalDate,'yyyy-MM-dd'))
        | project Problem=strcat(file_name,' holiday classification disagrees with reference')),
    (CR01_Stage_@{formatDateTime(variables('vRefreshDate'),'yyyyMMdd')} | distinct Year=getyear(Date) | where not(set_has_element(knownYears,Year))
        | project Problem=strcat('Holiday reference year missing: ',Year)),
    (print StageRows=toscalar(CR01_Stage_@{formatDateTime(variables('vRefreshDate'),'yyyyMMdd')} | count),PreviewRows=toscalar(preview | count)
        | where StageRows!=PreviewRows | project Problem='Silver preview is not row preserving')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.27 - Validate Preview Calendar Classification

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Preview Calendar Classification |
| Incoming dependency | Compute Preview Calendar Classification [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Preview Calendar Classification').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 3.27-True.1 - Validate Preview Calendar Classification Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Preview Calendar Classification > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Preview Calendar Classification Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Preview Calendar Classification has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 3.28 - Validate Frozen Source Versions

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | ForEach |
| General > Name (exact) | Validate Frozen Source Versions |
| Incoming dependency | Validate Preview Calendar Classification [Succeeded] |

**Settings > Items** - use Add dynamic content.

```text
@activity('Read Manifest').output.value
```

**Settings > Sequential (checkbox)** - literal value; do not add an expression wrapper.

```text
False
```

**Settings > Batch count** - literal value; do not add an expression wrapper.

```text
10
```

Open the Activities canvas inside this ForEach; add the following activities there, not on the outer canvas.

### 3.28.1 - Recheck Source Version

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Frozen Source Versions > Activities |
| Activity to select | Get Metadata |
| General > Name (exact) | Recheck Source Version |
| Incoming dependency | None inside this canvas/branch |
| General > timeout | 0.12:00:00 |
| General > retry | 0 |
| General > retryIntervalInSeconds | 30 |
| General > secureInput | False |
| General > secureOutput | False |

| Settings / connection field | Value |
| --- | --- |
| Connection | Approved ADLS Gen2 connection for mockadlsidimdprd001 |
| File format / dataset | Binary |
| Container / file system | inflowoutflow |

**Directory** - literal value; do not add an expression wrapper.

```text
inbound/statement
```

**File name** - use Add dynamic content.

```text
@item().FileName
```

**Field list (add each listed field)** - literal value; do not add an expression wrapper.

```text
["size","lastModified"]
```

**Source advanced > recursive** - literal value; do not add an expression wrapper.

```text
True
```

**Source advanced > enablePartitionDiscovery** - literal value; do not add an expression wrapper.

```text
False
```

### 3.28.2 - Reject Changed Source

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Frozen Source Versions > Activities |
| Activity to select | Script |
| General > Name (exact) | Reject Changed Source |
| Incoming dependency | Recheck Source Version [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse).

**Script block execution timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

Script block 1 > Type: **NonQuery**.

**Script block 1 > Text** - use Add dynamic content.

```sql
IF NOT EXISTS(SELECT 1 FROM dbo.CR01RefreshManifest
    WHERE RefreshDate='@{variables('vRefreshDate')}' AND FileName='@{item().FileName}'
    AND SourceBytes=@{activity('Recheck Source Version').output.size}
    AND SourceLastModified='@{formatDateTime(activity('Recheck Source Version').output.lastModified,'yyyy-MM-ddTHH:mm:ss.ffffff')}')
    THROW 51103, 'Source changed while staging. No live deposit rows may be deleted.', 1;
```

### 3.29 - Compute Loaded File Coverage

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Loaded File Coverage |
| Incoming dependency | Validate Frozen Source Versions [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set-or-replace CR01_Checks <| let names=toscalar(print items=parse_json(base64_decode_tostring("@{base64(string(activity('Read Manifest').output.value))}"))
    | mv-expand items | summarize make_set(tostring(items.FileName)));
union (DepositMovement | project file_name), (DepositMovementClassified | project file_name)
| where file_name startswith strcat('INTRADAY_SUMMARY_',format_datetime(datetime(@{variables('vRefreshDate')})-1d,'yyyyMMdd'))
    or file_name startswith strcat('INTRADAY_SUMMARY_',format_datetime(datetime(@{variables('vRefreshDate')}),'yyyyMMdd'))
| extend t=toint(extract(@"^INTRADAY_SUMMARY_\d{8}_(\d{4})_",1,file_name)),
    d=extract(@"^INTRADAY_SUMMARY_(\d{8})_",1,file_name)
| where isnull(t) or (d==format_datetime(datetime(@{variables('vRefreshDate')})-1d,'yyyyMMdd') and t>=2230)
    or (d==format_datetime(datetime(@{variables('vRefreshDate')}),'yyyyMMdd') and t<330)
| where file_name !in (names)
| distinct Problem=strcat(file_name,' is loaded but absent from the frozen manifest')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.30 - Validate Loaded File Coverage

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Loaded File Coverage |
| Incoming dependency | Compute Loaded File Coverage [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Loaded File Coverage').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 3.30-True.1 - Validate Loaded File Coverage Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Loaded File Coverage > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Loaded File Coverage Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Loaded File Coverage has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 3.31 - Read Existing Gold Views

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Read Existing Gold Views |
| Incoming dependency | Validate Loaded File Coverage [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.show materialized-views | where Name in ("mv_Summary_Product_Channel_Alert","mv_EarlyWarning_Base") | project Name,Query,SourceTable
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.32 - Check Existing Gold Definitions

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Check Existing Gold Definitions |
| Incoming dependency | Read Existing Gold Views [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.show materialized-views | where SourceTable in ('DepositMovement','DepositMovementClassified') | summarize Present=count(),Mismatch=countif(Name !in ("mv_Summary_Product_Channel_Alert","mv_EarlyWarning_Base") or (Name=='mv_Summary_Product_Channel_Alert' and Query!=base64_decode_tostring('RGVwb3NpdE1vdmVtZW50DQogICAgfCBzdW1tYXJpemUNCiAgICAgICAgVGltZSAgICAgICAgICAgICAgID0gbWF4KFRpbWUpLA0KICAgICAgICBDcmVkaXRfQW1vdW50ICAgICAgPSBzdW0oQ3JlZGl0X0Ftb3VudCksDQogICAgICAgIERlYml0X0Ftb3VudCAgICAgICA9IHN1bShEZWJpdF9BbW91bnQpLA0KICAgICAgICBOZXRfQW1vdW50ICAgICAgICAgPSBzdW0oTmV0X0Ftb3VudCksDQogICAgICAgIENyZWRpdF9UcmFuc2FjdGlvbiA9IHN1bShDcmVkaXRfVHJhbnNhY3Rpb24pLA0KICAgICAgICBEZWJpdF9UcmFuc2FjdGlvbiAgPSBzdW0oRGViaXRfVHJhbnNhY3Rpb24pLA0KICAgICAgICBUb3RhbF9UcmFuc2FjdGlvbiAgPSBzdW0oVG90YWxfVHJhbnNhY3Rpb24pLA0KICAgICAgICBVcGRhdGVkQXRVdGMgICAgICAgPSBtYXgobG9hZF90cykNCiAgICAgICAgYnkgRGF0ZSwgUHJvZHVjdCwgQ2hhbm5lbCwgQ2hhbm5lbF9Hcm91cA==')) or (Name=='mv_EarlyWarning_Base' and Query!=base64_decode_tostring('RGVwb3NpdE1vdmVtZW50Q2xhc3NpZmllZAogICAgLy8gT25seSByb3dzIHdpdGggYSB2YWxpZCBsb2NhbCB0aW1lIGNhbiBmYWxsIGludG8gYSAzMC1taW51dGUgYnVja2V0LgogICAgfCB3aGVyZSBpc25vdG51bGwoTG9jYWxEYXRlVGltZSkKICAgIC8vIE1haW4gY29uZGl0aW9uICMxOiBleGNsdWRlIE1TWUcgLyBTWVNHIGZyb20gZXZlcnkgY2FsY3VsYXRpb24uCiAgICB8IHdoZXJlIENoYW5uZWwgIWluICgiTVNZRyIsICJTWVNHIikKICAgIHwgZXh0ZW5kCiAgICAgICAgSXNSZXRhaWwgICAgPSBDaGFubmVsIGluICgiRU5FVCIsICJBVE0iLCAiQ0RNIiksCiAgICAgICAgQnVja2V0U3RhcnQgPSBiaW4oTG9jYWxEYXRlVGltZSwgMzBtKQogICAgfCBzdW1tYXJpemUKICAgICAgICBHcm9zc091dGZsb3cgPSBzdW0oRGViaXRfQW1vdW50KSwKICAgICAgICBDcmVkaXQgICAgICAgPSBzdW0oQ3JlZGl0X0Ftb3VudCksCiAgICAgICAgTmV0ICAgICAgICAgID0gc3VtKE5ldF9BbW91bnQpLAogICAgICAgIERlYml0VHhuICAgICA9IHN1bShEZWJpdF9UcmFuc2FjdGlvbiksCiAgICAgICAgVXBkYXRlZEF0VXRjID0gbWF4KGxvYWRfdHMpCiAgICAgICAgYnkgTG9jYWxEYXRlLCBCdWNrZXRTdGFydCwgRGF5Q2xhc3NpZmljYXRpb24sIEV2ZW50RmxhZywKICAgICAgICAgICBJc01vbnRoRW5kLCBJc1BheXJvbGwsIElzTG9uZ1dlZWtlbmQsIElzUmV0YWls')) or IsEnabled!=true or AutoUpdateSchema!=false or isnotnull(Lookback) or Folder!='Gold' or DocString!='')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.33 - Validate Gold Baseline

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Gold Baseline |
| Incoming dependency | Check Existing Gold Definitions [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@or(not(equals(int(activity('Check Existing Gold Definitions').output.value[0].Present),2)),not(equals(int(activity('Check Existing Gold Definitions').output.value[0].Mismatch),0)))
```

**True branch:** open this branch and add its activities below.

### 3.33-True.1 - Validate Gold Baseline Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Gold Baseline > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Gold Baseline Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
Gold definitions changed since deployment. Regenerate and review the CR01 artifacts.
```

**False branch:** leave empty.

### 3.34 - Check retention mv_Summary_Product_Channel_Alert

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Check retention mv_Summary_Product_Channel_Alert |
| Incoming dependency | Validate Gold Baseline [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.show materialized-view mv_Summary_Product_Channel_Alert policy retention | where Policy!=base64_decode_tostring('bnVsbA==')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.35 - Validate retention mv_Summary_Product_Channel_Alert

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate retention mv_Summary_Product_Channel_Alert |
| Incoming dependency | Check retention mv_Summary_Product_Channel_Alert [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Check retention mv_Summary_Product_Channel_Alert').output.count),0)
```

**True branch:** open this branch and add its activities below.

### 3.35-True.1 - Validate retention mv_Summary_Product_Channel_Al Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate retention mv_Summary_Product_Channel_Alert > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate retention mv_Summary_Product_Channel_Al Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
A Gold policy changed since deployment. Stop and regenerate the restoration baseline.
```

**False branch:** leave empty.

### 3.36 - Check caching mv_Summary_Product_Channel_Alert

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Check caching mv_Summary_Product_Channel_Alert |
| Incoming dependency | Validate retention mv_Summary_Product_Channel_Alert [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.show materialized-view mv_Summary_Product_Channel_Alert policy caching | where Policy!=base64_decode_tostring('bnVsbA==')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.37 - Validate caching mv_Summary_Product_Channel_Alert

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate caching mv_Summary_Product_Channel_Alert |
| Incoming dependency | Check caching mv_Summary_Product_Channel_Alert [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Check caching mv_Summary_Product_Channel_Alert').output.count),0)
```

**True branch:** open this branch and add its activities below.

### 3.37-True.1 - Validate caching mv_Summary_Product_Channel_Aler Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate caching mv_Summary_Product_Channel_Alert > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate caching mv_Summary_Product_Channel_Aler Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
A Gold policy changed since deployment. Stop and regenerate the restoration baseline.
```

**False branch:** leave empty.

### 3.38 - Check retention mv_EarlyWarning_Base

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Check retention mv_EarlyWarning_Base |
| Incoming dependency | Validate caching mv_Summary_Product_Channel_Alert [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.show materialized-view mv_EarlyWarning_Base policy retention | where Policy!=base64_decode_tostring('bnVsbA==')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.39 - Validate retention mv_EarlyWarning_Base

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate retention mv_EarlyWarning_Base |
| Incoming dependency | Check retention mv_EarlyWarning_Base [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Check retention mv_EarlyWarning_Base').output.count),0)
```

**True branch:** open this branch and add its activities below.

### 3.39-True.1 - Validate retention mv_EarlyWarning_Base Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate retention mv_EarlyWarning_Base > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate retention mv_EarlyWarning_Base Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
A Gold policy changed since deployment. Stop and regenerate the restoration baseline.
```

**False branch:** leave empty.

### 3.40 - Check caching mv_EarlyWarning_Base

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Check caching mv_EarlyWarning_Base |
| Incoming dependency | Validate retention mv_EarlyWarning_Base [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.show materialized-view mv_EarlyWarning_Base policy caching | where Policy!=base64_decode_tostring('ew0KICAiRGF0YUhvdFNwYW4iOiB7DQogICAgIlZhbHVlIjogIjkwLjAwOjAwOjAwIg0KICB9LA0KICAiSW5kZXhIb3RTcGFuIjogew0KICAgICJWYWx1ZSI6ICI5MC4wMDowMDowMCINCiAgfQ0KfQ==')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.41 - Validate caching mv_EarlyWarning_Base

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate caching mv_EarlyWarning_Base |
| Incoming dependency | Check caching mv_EarlyWarning_Base [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Check caching mv_EarlyWarning_Base').output.count),0)
```

**True branch:** open this branch and add its activities below.

### 3.41-True.1 - Validate caching mv_EarlyWarning_Base Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate caching mv_EarlyWarning_Base > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate caching mv_EarlyWarning_Base Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
A Gold policy changed since deployment. Stop and regenerate the restoration baseline.
```

**False branch:** leave empty.

### 3.42 - Backup Target Bronze

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Backup Target Bronze |
| Incoming dependency | Validate caching mv_EarlyWarning_Base [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set CR01_BackupBronze_@{formatDateTime(variables('vRefreshDate'),'yyyyMMdd')} <| let names=toscalar(print items=parse_json(base64_decode_tostring("@{base64(string(activity('Read Manifest').output.value))}"))
    | mv-expand items | summarize make_set(tostring(items.FileName))); DepositMovement | where file_name in (names)
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.43 - Backup Target Silver

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Backup Target Silver |
| Incoming dependency | Backup Target Bronze [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set CR01_BackupSilver_@{formatDateTime(variables('vRefreshDate'),'yyyyMMdd')} <| let names=toscalar(print items=parse_json(base64_decode_tostring("@{base64(string(activity('Read Manifest').output.value))}"))
    | mv-expand items | summarize make_set(tostring(items.FileName))); DepositMovementClassified | where file_name in (names)
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.44 - Backup Both EWI Dates

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Backup Both EWI Dates |
| Incoming dependency | Backup Target Silver [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set CR01_BackupEwi_@{formatDateTime(variables('vRefreshDate'),'yyyyMMdd')} <| let names=toscalar(print items=parse_json(base64_decode_tostring("@{base64(string(activity('Read Manifest').output.value))}"))
    | mv-expand items | summarize make_set(tostring(items.FileName))); DepositMovementEarlyWarning | where Date_ICT in (format_datetime(datetime(@{variables('vRefreshDate')})-1d,'yyyy-MM-dd'),'@{variables('vRefreshDate')}')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.45 - Snapshot Unrelated DepositMovement

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Snapshot Unrelated DepositMovement |
| Incoming dependency | Backup Both EWI Dates [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set CR01_UnrelatedBronze_@{formatDateTime(variables('vRefreshDate'),'yyyyMMdd')} <| let names=toscalar(print items=parse_json(base64_decode_tostring("@{base64(string(activity('Read Manifest').output.value))}"))
    | mv-expand items | summarize make_set(tostring(items.FileName))); DepositMovement | where file_name !in (names) | summarize Copies=count() by Fingerprint=hash_sha256(tostring(pack_array(Date,Time,Product,Channel,Channel_Group,Credit_Amount,Debit_Amount,Net_Amount,Credit_Transaction,Debit_Transaction,Total_Transaction,load_ts,file_name,pipeline_name,pipeline_runid)))
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.46 - Snapshot Unrelated DepositMovementClassified

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Snapshot Unrelated DepositMovementClassified |
| Incoming dependency | Snapshot Unrelated DepositMovement [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set CR01_UnrelatedSilver_@{formatDateTime(variables('vRefreshDate'),'yyyyMMdd')} <| let names=toscalar(print items=parse_json(base64_decode_tostring("@{base64(string(activity('Read Manifest').output.value))}"))
    | mv-expand items | summarize make_set(tostring(items.FileName))); DepositMovementClassified | where file_name !in (names) | summarize Copies=count() by Fingerprint=hash_sha256(tostring(pack_array(Date,Time,Product,Channel,Channel_Group,Credit_Amount,Debit_Amount,Net_Amount,Credit_Transaction,Debit_Transaction,Total_Transaction,load_ts,file_name,pipeline_name,pipeline_runid,LocalDate,LocalDateTime,LocalTimeOfDay,IsWeekend,IsFinancialInstitutionHoliday,IsBusinessDay,DayClassification,HolidayName,OperatingWindowCode,OperatingWindowName,OperatingWindowStartTime,OperatingWindowEndTime,OperatingWindowSortOrder,WindowMatchCount,ClassificationStatus,IsMonthEnd,IsPayroll,IsLongWeekend,EventFlag)))
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.47 - Hold Serving Visibility

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Hold Serving Visibility |
| Incoming dependency | Snapshot Unrelated DepositMovementClassified [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set-or-append CR01_PublishState <| print IsReady=false, ChangedAtUtc=now(), Owner='@{pipeline().parameters.pControllerRunId}'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.48 - Drop mv_Summary_Product_Channel_Alert

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Drop mv_Summary_Product_Channel_Alert |
| Incoming dependency | Hold Serving Visibility [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.drop materialized-view mv_Summary_Product_Channel_Alert
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.49 - Drop mv_EarlyWarning_Base

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Drop mv_EarlyWarning_Base |
| Incoming dependency | Drop mv_Summary_Product_Channel_Alert [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.drop materialized-view mv_EarlyWarning_Base
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.50 - Delete Only Manifest Bronze

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Delete Only Manifest Bronze |
| Incoming dependency | Drop mv_EarlyWarning_Base [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.delete table DepositMovement records <| DepositMovement | where file_name in (@{activity('Read Manifest Predicate').output.firstRow.KqlFileList})
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.51 - Delete Only Manifest Silver

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Delete Only Manifest Silver |
| Incoming dependency | Delete Only Manifest Bronze [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.delete table DepositMovementClassified records <| DepositMovementClassified | where file_name in (@{activity('Read Manifest Predicate').output.firstRow.KqlFileList})
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.52 - Compute Empty Replacement Scope

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Empty Replacement Scope |
| Incoming dependency | Delete Only Manifest Silver [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set-or-replace CR01_Checks <| let names=toscalar(print items=parse_json(base64_decode_tostring("@{base64(string(activity('Read Manifest').output.value))}"))
    | mv-expand items | summarize make_set(tostring(items.FileName))); union (DepositMovement | project file_name),(DepositMovementClassified | project file_name) | where file_name in (names) | project Problem=file_name
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.53 - Validate Empty Replacement Scope

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Empty Replacement Scope |
| Incoming dependency | Compute Empty Replacement Scope [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Empty Replacement Scope').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 3.53-True.1 - Validate Empty Replacement Scope Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Empty Replacement Scope > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Empty Replacement Scope Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Empty Replacement Scope has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 3.54 - Preserve And Supersede Audit

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Script |
| General > Name (exact) | Preserve And Supersede Audit |
| Incoming dependency | Validate Empty Replacement Scope [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse).

**Script block execution timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

Script block 1 > Type: **NonQuery**.

**Script block 1 > Text** - use Add dynamic content.

```sql
BEGIN TRANSACTION;
INSERT INTO dbo.CR01AuditBefore
SELECT m.RefreshDate,a.FileName,a.IngestedAtUtc,a.RowCount_,a.Status,a.PipelineName,a.PipelineRunId,a.RunAsUser,a.ErrorMsg
FROM dbo.ProcessedFiles a JOIN dbo.CR01RefreshManifest m ON a.FileName=m.FileName
WHERE m.RefreshDate='@{variables('vRefreshDate')}' AND a.Status='Success';
UPDATE a SET Status='Superseded-CR01'
FROM dbo.ProcessedFiles a JOIN dbo.CR01RefreshManifest m ON a.FileName=m.FileName
WHERE m.RefreshDate='@{variables('vRefreshDate')}' AND a.Status='Success';
UPDATE dbo.CR01RefreshRun SET Stage='Replacing' WHERE RefreshDate='@{variables('vRefreshDate')}';
COMMIT TRANSACTION;
```

### 3.55 - Promote Frozen Overnight Snapshot

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Promote Frozen Overnight Snapshot |
| Incoming dependency | Preserve And Supersede Audit [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set-or-append DepositMovement <| CR01_Stage_@{formatDateTime(variables('vRefreshDate'),'yyyyMMdd')}
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.56 - Wait For Bronze And Silver

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Until |
| General > Name (exact) | Wait For Bronze And Silver |
| Incoming dependency | Promote Frozen Overnight Snapshot [Succeeded] |

**Settings > Expression (exit condition)** - use Add dynamic content.

```text
@equals(int(activity('Compute Replayed Row Mismatches').output.count),0)
```

**Settings > Timeout** - literal value; do not add an expression wrapper.

```text
0.00:30:00
```

Open the Activities canvas inside Until. The condition is evaluated after an iteration; retain the Wait activity.

### 3.56.1 - Compute Replayed Row Mismatches

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Wait For Bronze And Silver > Activities |
| Activity to select | KQL |
| General > Name (exact) | Compute Replayed Row Mismatches |
| Incoming dependency | None inside this canvas/branch |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set-or-replace CR01_Checks <| let names=toscalar(print items=parse_json(base64_decode_tostring("@{base64(string(activity('Read Manifest').output.value))}"))
    | mv-expand items | summarize make_set(tostring(items.FileName))); union (CR01_Stage_@{formatDateTime(variables('vRefreshDate'),'yyyyMMdd')} | summarize Expected=count() by file_name,Fingerprint=tostring(pack_array(Date,Time,Product,trim(@"\s",Channel),Channel_Group,Credit_Amount,Debit_Amount,Net_Amount,Credit_Transaction,Debit_Transaction,Total_Transaction)) | join kind=fullouter (DepositMovement | where file_name in (names) | summarize Actual=count() by file_name,Fingerprint=tostring(pack_array(Date,Time,Product,trim(@"\s",Channel),Channel_Group,Credit_Amount,Debit_Amount,Net_Amount,Credit_Transaction,Debit_Transaction,Total_Transaction))) on file_name,Fingerprint | where coalesce(Expected,0)!=coalesce(Actual,0) | project Problem=strcat('DepositMovement ',file_name,' business-row mismatch')),(CR01_Stage_@{formatDateTime(variables('vRefreshDate'),'yyyyMMdd')} | summarize Expected=count() by file_name,Fingerprint=tostring(pack_array(Date,Time,Product,trim(@"\s",Channel),Channel_Group,Credit_Amount,Debit_Amount,Net_Amount,Credit_Transaction,Debit_Transaction,Total_Transaction)) | join kind=fullouter (DepositMovementClassified | where file_name in (names) | summarize Actual=count() by file_name,Fingerprint=tostring(pack_array(Date,Time,Product,trim(@"\s",Channel),Channel_Group,Credit_Amount,Debit_Amount,Net_Amount,Credit_Transaction,Debit_Transaction,Total_Transaction))) on file_name,Fingerprint | where coalesce(Expected,0)!=coalesce(Actual,0) | project Problem=strcat('DepositMovementClassified ',file_name,' business-row mismatch'))
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.56.2 - Wait For Replay

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Wait For Bronze And Silver > Activities |
| Activity to select | Wait |
| General > Name (exact) | Wait For Replay |
| Incoming dependency | Compute Replayed Row Mismatches [Succeeded] |

**Settings > Wait time in seconds** - literal value; do not add an expression wrapper.

```text
5
```

### 3.57 - Compute Silver Classification

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Silver Classification |
| Incoming dependency | Wait For Bronze And Silver [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set-or-replace CR01_Checks <| let names=toscalar(print items=parse_json(base64_decode_tostring("@{base64(string(activity('Read Manifest').output.value))}"))
    | mv-expand items | summarize make_set(tostring(items.FileName))); DepositMovementClassified | where file_name in (names) and ClassificationStatus!='CLASSIFIED' | project Problem=strcat(file_name,' ',ClassificationStatus)
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.58 - Validate Silver Classification

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Silver Classification |
| Incoming dependency | Compute Silver Classification [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Silver Classification').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 3.58-True.1 - Validate Silver Classification Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Silver Classification > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Silver Classification Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Silver Classification has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 3.59 - Compute Unrelated DepositMovement

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Unrelated DepositMovement |
| Incoming dependency | Validate Silver Classification [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set-or-replace CR01_Checks <| let names=toscalar(print items=parse_json(base64_decode_tostring("@{base64(string(activity('Read Manifest').output.value))}"))
    | mv-expand items | summarize make_set(tostring(items.FileName))); CR01_UnrelatedBronze_@{formatDateTime(variables('vRefreshDate'),'yyyyMMdd')} | project Fingerprint,Before=Copies | join kind=fullouter (DepositMovement | where file_name !in (names) | summarize After=count() by Fingerprint=hash_sha256(tostring(pack_array(Date,Time,Product,Channel,Channel_Group,Credit_Amount,Debit_Amount,Net_Amount,Credit_Transaction,Debit_Transaction,Total_Transaction,load_ts,file_name,pipeline_name,pipeline_runid)))) on Fingerprint | where coalesce(Before,0)!=coalesce(After,0) | project Problem='Unrelated source rows changed'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.60 - Validate Unrelated DepositMovement

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Unrelated DepositMovement |
| Incoming dependency | Compute Unrelated DepositMovement [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Unrelated DepositMovement').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 3.60-True.1 - Validate Unrelated DepositMovement Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Unrelated DepositMovement > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Unrelated DepositMovement Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Unrelated DepositMovement has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 3.61 - Compute Unrelated DepositMovementClassified

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Unrelated DepositMovementClassified |
| Incoming dependency | Validate Unrelated DepositMovement [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set-or-replace CR01_Checks <| let names=toscalar(print items=parse_json(base64_decode_tostring("@{base64(string(activity('Read Manifest').output.value))}"))
    | mv-expand items | summarize make_set(tostring(items.FileName))); CR01_UnrelatedSilver_@{formatDateTime(variables('vRefreshDate'),'yyyyMMdd')} | project Fingerprint,Before=Copies | join kind=fullouter (DepositMovementClassified | where file_name !in (names) | summarize After=count() by Fingerprint=hash_sha256(tostring(pack_array(Date,Time,Product,Channel,Channel_Group,Credit_Amount,Debit_Amount,Net_Amount,Credit_Transaction,Debit_Transaction,Total_Transaction,load_ts,file_name,pipeline_name,pipeline_runid,LocalDate,LocalDateTime,LocalTimeOfDay,IsWeekend,IsFinancialInstitutionHoliday,IsBusinessDay,DayClassification,HolidayName,OperatingWindowCode,OperatingWindowName,OperatingWindowStartTime,OperatingWindowEndTime,OperatingWindowSortOrder,WindowMatchCount,ClassificationStatus,IsMonthEnd,IsPayroll,IsLongWeekend,EventFlag)))) on Fingerprint | where coalesce(Before,0)!=coalesce(After,0) | project Problem='Unrelated source rows changed'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.62 - Validate Unrelated DepositMovementClassified

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Unrelated DepositMovementClassified |
| Incoming dependency | Compute Unrelated DepositMovementClassified [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Unrelated DepositMovementClassified').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 3.62-True.1 - Validate Unrelated DepositMovementClassified Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Unrelated DepositMovementClassified > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Unrelated DepositMovementClassified Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Unrelated DepositMovementClassified has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 3.63 - Rebuild mv_Summary_Product_Channel_Alert

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Rebuild mv_Summary_Product_Channel_Alert |
| Incoming dependency | Validate Unrelated DepositMovementClassified [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.create materialized-view with (backfill=true,folder="Gold",docstring="") mv_Summary_Product_Channel_Alert on table DepositMovement { DepositMovement
    | summarize
        Time               = max(Time),
        Credit_Amount      = sum(Credit_Amount),
        Debit_Amount       = sum(Debit_Amount),
        Net_Amount         = sum(Net_Amount),
        Credit_Transaction = sum(Credit_Transaction),
        Debit_Transaction  = sum(Debit_Transaction),
        Total_Transaction  = sum(Total_Transaction),
        UpdatedAtUtc       = max(load_ts)
        by Date, Product, Channel, Channel_Group }
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.64 - Compute Reconciled mv_Summary_Product_Channel_Alert

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Reconciled mv_Summary_Product_Channel_Alert |
| Incoming dependency | Rebuild mv_Summary_Product_Channel_Alert [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-replace CR01_Checks <| let expected=DepositMovement
    | summarize
        Time               = max(Time),
        Credit_Amount      = sum(Credit_Amount),
        Debit_Amount       = sum(Debit_Amount),
        Net_Amount         = sum(Net_Amount),
        Credit_Transaction = sum(Credit_Transaction),
        Debit_Transaction  = sum(Debit_Transaction),
        Total_Transaction  = sum(Total_Transaction),
        UpdatedAtUtc       = max(load_ts)
        by Date, Product, Channel, Channel_Group | summarize Expected=count() by Fingerprint=tostring(pack_array(Date,Product,Channel,Channel_Group,Time,Credit_Amount,Debit_Amount,Net_Amount,Credit_Transaction,Debit_Transaction,Total_Transaction,UpdatedAtUtc)); expected | join kind=fullouter (mv_Summary_Product_Channel_Alert | summarize Actual=count() by Fingerprint=tostring(pack_array(Date,Product,Channel,Channel_Group,Time,Credit_Amount,Debit_Amount,Net_Amount,Credit_Transaction,Debit_Transaction,Total_Transaction,UpdatedAtUtc))) on Fingerprint | where coalesce(Expected,0)!=coalesce(Actual,0) | project Problem='Gold MV does not reconcile with corrected source'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.65 - Validate Reconciled mv_Summary_Product_Channel_Alert

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Reconciled mv_Summary_Product_Channel_Alert |
| Incoming dependency | Compute Reconciled mv_Summary_Product_Channel_Alert [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Reconciled mv_Summary_Product_Channel_Alert').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 3.65-True.1 - Validate Reconciled mv_Summary_Product_Channel_A Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Reconciled mv_Summary_Product_Channel_Alert > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Reconciled mv_Summary_Product_Channel_A Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Reconciled mv_Summary_Product_Channel_Alert has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 3.66 - Rebuild mv_EarlyWarning_Base

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Rebuild mv_EarlyWarning_Base |
| Incoming dependency | Validate Reconciled mv_Summary_Product_Channel_Alert [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.create materialized-view with (backfill=true,folder="Gold",docstring="") mv_EarlyWarning_Base on table DepositMovementClassified { DepositMovementClassified
    // Only rows with a valid local time can fall into a 30-minute bucket.
    | where isnotnull(LocalDateTime)
    // Main condition #1: exclude MSYG / SYSG from every calculation.
    | where Channel !in ("MSYG", "SYSG")
    | extend
        IsRetail    = Channel in ("ENET", "ATM", "CDM"),
        BucketStart = bin(LocalDateTime, 30m)
    | summarize
        GrossOutflow = sum(Debit_Amount),
        Credit       = sum(Credit_Amount),
        Net          = sum(Net_Amount),
        DebitTxn     = sum(Debit_Transaction),
        UpdatedAtUtc = max(load_ts)
        by LocalDate, BucketStart, DayClassification, EventFlag,
           IsMonthEnd, IsPayroll, IsLongWeekend, IsRetail }
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.67 - Restore Caching mv_EarlyWarning_Base

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Restore Caching mv_EarlyWarning_Base |
| Incoming dependency | Rebuild mv_EarlyWarning_Base [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.alter materialized-view mv_EarlyWarning_Base policy caching hot = 90d
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.68 - Compute Reconciled mv_EarlyWarning_Base

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Reconciled mv_EarlyWarning_Base |
| Incoming dependency | Restore Caching mv_EarlyWarning_Base [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-replace CR01_Checks <| let expected=DepositMovementClassified
    // Only rows with a valid local time can fall into a 30-minute bucket.
    | where isnotnull(LocalDateTime)
    // Main condition #1: exclude MSYG / SYSG from every calculation.
    | where Channel !in ("MSYG", "SYSG")
    | extend
        IsRetail    = Channel in ("ENET", "ATM", "CDM"),
        BucketStart = bin(LocalDateTime, 30m)
    | summarize
        GrossOutflow = sum(Debit_Amount),
        Credit       = sum(Credit_Amount),
        Net          = sum(Net_Amount),
        DebitTxn     = sum(Debit_Transaction),
        UpdatedAtUtc = max(load_ts)
        by LocalDate, BucketStart, DayClassification, EventFlag,
           IsMonthEnd, IsPayroll, IsLongWeekend, IsRetail | summarize Expected=count() by Fingerprint=tostring(pack_array(LocalDate,BucketStart,DayClassification,EventFlag,IsMonthEnd,IsPayroll,IsLongWeekend,IsRetail,GrossOutflow,Credit,Net,DebitTxn,UpdatedAtUtc)); expected | join kind=fullouter (mv_EarlyWarning_Base | summarize Actual=count() by Fingerprint=tostring(pack_array(LocalDate,BucketStart,DayClassification,EventFlag,IsMonthEnd,IsPayroll,IsLongWeekend,IsRetail,GrossOutflow,Credit,Net,DebitTxn,UpdatedAtUtc))) on Fingerprint | where coalesce(Expected,0)!=coalesce(Actual,0) | project Problem='Gold MV does not reconcile with corrected source'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.69 - Validate Reconciled mv_EarlyWarning_Base

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Reconciled mv_EarlyWarning_Base |
| Incoming dependency | Compute Reconciled mv_EarlyWarning_Base [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Reconciled mv_EarlyWarning_Base').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 3.69-True.1 - Validate Reconciled mv_EarlyWarning_Base Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Reconciled mv_EarlyWarning_Base > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Reconciled mv_EarlyWarning_Base Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Reconciled mv_EarlyWarning_Base has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 3.70 - Wait For Healthy Gold Views

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Until |
| General > Name (exact) | Wait For Healthy Gold Views |
| Incoming dependency | Validate Reconciled mv_EarlyWarning_Base [Succeeded] |

**Settings > Expression (exit condition)** - use Add dynamic content.

```text
@and(equals(int(activity('Read Gold Health').output.value[0].Present),2),equals(int(activity('Read Gold Health').output.value[0].Unhealthy),0))
```

**Settings > Timeout** - literal value; do not add an expression wrapper.

```text
0.01:00:00
```

Open the Activities canvas inside Until. The condition is evaluated after an iteration; retain the Wait activity.

### 3.70.1 - Read Gold Health

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Wait For Healthy Gold Views > Activities |
| Activity to select | KQL |
| General > Name (exact) | Read Gold Health |
| Incoming dependency | None inside this canvas/branch |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.show materialized-views | where Name in ("mv_Summary_Product_Channel_Alert","mv_EarlyWarning_Base") | summarize Present=count(),Unhealthy=countif(IsHealthy!=true or IsEnabled!=true)
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.70.2 - Wait For Materialization

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Wait For Healthy Gold Views > Activities |
| Activity to select | Wait |
| General > Name (exact) | Wait For Materialization |
| Incoming dependency | Read Gold Health [Succeeded] |

**Settings > Wait time in seconds** - literal value; do not add an expression wrapper.

```text
5
```

### 3.71 - Compute EWI Level Contract

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute EWI Level Contract |
| Incoming dependency | Wait For Healthy Gold Views [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set-or-replace CR01_Checks <| union (Gold_EarlyWarning(datetime(@{variables('vRefreshDate')})-1d)),(Gold_EarlyWarning(datetime(@{variables('vRefreshDate')}))) | where isnull(Alert_Rank) or Alert_Rank<0 or Alert_Rank>3 or Alert_Level !in ('L0','L1','L2','L3') | project Problem='Invalid EWI level/rank before persistence'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.72 - Validate EWI Level Contract

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate EWI Level Contract |
| Incoming dependency | Compute EWI Level Contract [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute EWI Level Contract').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 3.72-True.1 - Validate EWI Level Contract Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate EWI Level Contract > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate EWI Level Contract Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 EWI Level Contract has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 3.73 - Delete Affected Persisted EWI Dates

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Delete Affected Persisted EWI Dates |
| Incoming dependency | Validate EWI Level Contract [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.delete table DepositMovementEarlyWarning records <| DepositMovementEarlyWarning | where Date_ICT in (format_datetime(datetime(@{variables('vRefreshDate')})-1d,'yyyy-MM-dd'),'@{variables('vRefreshDate')}')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.74 - Recompute Both Complete EWI Dates

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Recompute Both Complete EWI Dates |
| Incoming dependency | Delete Affected Persisted EWI Dates [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set-or-append DepositMovementEarlyWarning <| union (Gold_EarlyWarning(datetime(@{variables('vRefreshDate')})-1d)),(Gold_EarlyWarning(datetime(@{variables('vRefreshDate')}))) | project Object_Id,Scope,Date_ICT,Bucket_Start,Bucket_Label,Alert_Time,WindowCode,WindowName,DayType,EventFlag,IsMonthEnd,IsPayroll,IsLongWeekend,IndicatorId,IndicatorKey,IndicatorName,Unit,Value,Direction,L1,L2,L3,Alert_Level,Alert_Rank=toint(Alert_Rank)
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.75 - Compute Persisted EWI Grain

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Persisted EWI Grain |
| Incoming dependency | Recompute Both Complete EWI Dates [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set-or-replace CR01_Checks <| DepositMovementEarlyWarning | where Date_ICT in (format_datetime(datetime(@{variables('vRefreshDate')})-1d,'yyyy-MM-dd'),'@{variables('vRefreshDate')}') | summarize Copies=count() by Object_Id,Bucket_Start | where Copies!=1 | project Problem='Stored EWI grain is not one row per scope/indicator/bucket'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.76 - Validate Persisted EWI Grain

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Persisted EWI Grain |
| Incoming dependency | Compute Persisted EWI Grain [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Persisted EWI Grain').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 3.76-True.1 - Validate Persisted EWI Grain Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Persisted EWI Grain > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Persisted EWI Grain Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Persisted EWI Grain has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 3.77 - Compute Reconciled Persisted EWI

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Reconciled Persisted EWI |
| Incoming dependency | Validate Persisted EWI Grain [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set-or-replace CR01_Checks <| let e=union (Gold_EarlyWarning(datetime(@{variables('vRefreshDate')})-1d)),(Gold_EarlyWarning(datetime(@{variables('vRefreshDate')}))) | project Object_Id,Scope,Date_ICT,Bucket_Start,Bucket_Label,Alert_Time,WindowCode,WindowName,DayType,EventFlag,IsMonthEnd,IsPayroll,IsLongWeekend,IndicatorId,IndicatorKey,IndicatorName,Unit,Value,Direction,L1,L2,L3,Alert_Level,Alert_Rank=toint(Alert_Rank); e | summarize Expected=count() by Fingerprint=tostring(pack_array(Object_Id,Scope,Date_ICT,Bucket_Start,Bucket_Label,WindowCode,WindowName,DayType,EventFlag,IsMonthEnd,IsPayroll,IsLongWeekend,IndicatorId,IndicatorKey,IndicatorName,Unit,Value,Direction,L1,L2,L3,Alert_Level,Alert_Rank)) | join kind=fullouter (DepositMovementEarlyWarning | where Date_ICT in (format_datetime(datetime(@{variables('vRefreshDate')})-1d,'yyyy-MM-dd'),'@{variables('vRefreshDate')}') | summarize Actual=count() by Fingerprint=tostring(pack_array(Object_Id,Scope,Date_ICT,Bucket_Start,Bucket_Label,WindowCode,WindowName,DayType,EventFlag,IsMonthEnd,IsPayroll,IsLongWeekend,IndicatorId,IndicatorKey,IndicatorName,Unit,Value,Direction,L1,L2,L3,Alert_Level,Alert_Rank))) on Fingerprint | where coalesce(Expected,0)!=coalesce(Actual,0) | project Problem='Persisted EWI mismatch'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 3.78 - Validate Reconciled Persisted EWI

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Reconciled Persisted EWI |
| Incoming dependency | Compute Reconciled Persisted EWI [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Reconciled Persisted EWI').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 3.78-True.1 - Validate Reconciled Persisted EWI Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Reconciled Persisted EWI > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Reconciled Persisted EWI Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Reconciled Persisted EWI has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 3.79 - Commit Verified Refresh

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Script |
| General > Name (exact) | Commit Verified Refresh |
| Incoming dependency | Validate Reconciled Persisted EWI [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse).

**Script block execution timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

Script block 1 > Type: **NonQuery**.

**Script block 1 > Text** - use Add dynamic content.

```sql
BEGIN TRANSACTION;
IF EXISTS(SELECT 1 FROM dbo.ProcessedFiles a JOIN dbo.CR01RefreshManifest m ON a.FileName=m.FileName
    WHERE m.RefreshDate='@{variables('vRefreshDate')}' AND a.Status='Success')
    THROW 51104,'Unexpected concurrent Success audit row. Keep the controller lock.',1;
INSERT INTO dbo.ProcessedFiles
SELECT FileName,SYSUTCDATETIME(),ExpectedRows,'Success','@{pipeline().Pipeline}','@{pipeline().RunId}','CR01',NULL
FROM dbo.CR01RefreshManifest WHERE RefreshDate='@{variables('vRefreshDate')}';
UPDATE dbo.CR01RefreshRun SET Status='Completed',Stage='Verified',CompletedAtUtc=SYSUTCDATETIME()
WHERE RefreshDate='@{variables('vRefreshDate')}' AND Status='Running';
COMMIT TRANSACTION;
```

## 4. pl_CR01_DepositMovement_24x7

Validated definition: [pipeline/pl_CR01_DepositMovement_24x7.json](pipeline/pl_CR01_DepositMovement_24x7.json).

### parameters

| Name | UI type | Default |
| --- | --- | --- |
| pEnableProcessing | bool | False |
| pSourceFinalized | bool | False |
| pCutoverConfirmed | bool | False |
| pSourceIntervalMinutes | int | 15 |
| pFirstRefreshDate | string | (empty) |

### variables

| Name | UI type | Default |
| --- | --- | --- |
| vRunICT | String | (no default; supplied by caller / Set variable) |
| vFirstRefreshDate | String | (no default; supplied by caller / Set variable) |

### Top-level activity order

| Order | Activity | Type |
| --- | --- | --- |
| 1 | Require Approved Cutover | IfCondition |
| 2 | Freeze Run ICT | SetVariable |
| 3 | Require First Refresh Date | IfCondition |
| 4 | Normalize First Refresh Date | SetVariable |
| 5 | Acquire Global Controller Lock | KustoQueryLanguage |
| 6 | Initialize CR01 Control Tables | Script |
| 7 | Register Controller Owner | Script |
| 8 | Initialize Serving State | KustoQueryLanguage |
| 9 | Compute Threshold Reference Keys | KustoQueryLanguage |
| 10 | Validate Threshold Reference Keys | IfCondition |
| 11 | Finish All Due Refreshes | Until |
| 12 | Invoke Normal Discovery | InvokePipeline |
| 13 | Append Normal EWI Buckets | KustoQueryLanguage |
| 14 | Publish Verified Data | KustoQueryLanguage |
| 15 | Complete Controller Owner | Script |
| 16 | Release Owned Controller Lock | KustoQueryLanguage |

### 4.1 - Require Approved Cutover

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Require Approved Cutover |
| Incoming dependency | None inside this canvas/branch |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@not(and(pipeline().parameters.pEnableProcessing,pipeline().parameters.pCutoverConfirmed))
```

**True branch:** open this branch and add its activities below.

### 4.1-True.1 - Require Approved Cutover Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Require Approved Cutover > True branch |
| Activity to select | Fail |
| General > Name (exact) | Require Approved Cutover Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 processing is disabled until storage, consumers, and writer cutover are approved.
```

**False branch:** leave empty.

### 4.2 - Freeze Run ICT

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Set variable |
| General > Name (exact) | Freeze Run ICT |
| Incoming dependency | Require Approved Cutover [Succeeded] |

Settings > Variable: **vRunICT**.

**Settings > Value** - use Add dynamic content.

```text
@convertFromUtc(utcNow(),'SE Asia Standard Time')
```

### 4.3 - Require First Refresh Date

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Require First Refresh Date |
| Incoming dependency | Freeze Run ICT [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@empty(pipeline().parameters.pFirstRefreshDate)
```

**True branch:** open this branch and add its activities below.

### 4.3-True.1 - Require First Refresh Date Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Require First Refresh Date > True branch |
| Activity to select | Fail |
| General > Name (exact) | Require First Refresh Date Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
Set the first approved refresh date; no historical date is assumed.
```

**False branch:** leave empty.

### 4.4 - Normalize First Refresh Date

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Set variable |
| General > Name (exact) | Normalize First Refresh Date |
| Incoming dependency | Require First Refresh Date [Succeeded] |

Settings > Variable: **vFirstRefreshDate**.

**Settings > Value** - use Add dynamic content.

```text
@formatDateTime(pipeline().parameters.pFirstRefreshDate,'yyyy-MM-dd')
```

### 4.5 - Acquire Global Controller Lock

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Acquire Global Controller Lock |
| Incoming dependency | Normalize First Refresh Date [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set CR01_ControllerLock <| print Owner='@{pipeline().RunId}',StartedAtUtc=now()
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 4.6 - Initialize CR01 Control Tables

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Script |
| General > Name (exact) | Initialize CR01 Control Tables |
| Incoming dependency | Acquire Global Controller Lock [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse).

**Script block execution timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

Script block 1 > Type: **NonQuery**.

**Script block 1 > Text** - literal value; do not add an expression wrapper.

```sql
-- Dedicated CR01 state. Existing ProcessedFiles schema and procedures are unchanged.
-- These tables are NOT mutexes. The controller acquires CR01_ControllerLock in KQL first.
IF OBJECT_ID('dbo.CR01ControllerRun', 'U') IS NULL
CREATE TABLE dbo.CR01ControllerRun (
    RunId VARCHAR(64) NOT NULL,
    Status VARCHAR(20) NOT NULL,
    StartedAtUtc DATETIME2(3) NOT NULL,
    CompletedAtUtc DATETIME2(3) NULL
);

IF OBJECT_ID('dbo.CR01RefreshRun', 'U') IS NULL
CREATE TABLE dbo.CR01RefreshRun (
    RefreshDate DATE NOT NULL,
    ControllerRunId VARCHAR(64) NOT NULL,
    Status VARCHAR(20) NOT NULL,
    Stage VARCHAR(64) NOT NULL,
    StartedAtUtc DATETIME2(3) NOT NULL,
    CompletedAtUtc DATETIME2(3) NULL
);

IF OBJECT_ID('dbo.CR01RefreshManifest', 'U') IS NULL
CREATE TABLE dbo.CR01RefreshManifest (
    RefreshDate DATE NOT NULL,
    FileName VARCHAR(260) NOT NULL,
    SourceBytes BIGINT NULL,
    SourceLastModified DATETIME2(6) NULL,
    ExpectedRows BIGINT NULL
);

IF OBJECT_ID('dbo.CR01AuditBefore', 'U') IS NULL
CREATE TABLE dbo.CR01AuditBefore (
    RefreshDate DATE NOT NULL,
    FileName VARCHAR(260) NOT NULL,
    IngestedAtUtc DATETIME2(3) NOT NULL,
    RowCount_ BIGINT NOT NULL,
    Status VARCHAR(32) NOT NULL,
    PipelineName VARCHAR(200) NULL,
    PipelineRunId VARCHAR(64) NULL,
    RunAsUser VARCHAR(200) NULL,
    ErrorMsg VARCHAR(4000) NULL
);

```

### 4.7 - Register Controller Owner

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Script |
| General > Name (exact) | Register Controller Owner |
| Incoming dependency | Initialize CR01 Control Tables [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse).

**Script block execution timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

Script block 1 > Type: **NonQuery**.

**Script block 1 > Text** - use Add dynamic content.

```sql
INSERT INTO dbo.CR01ControllerRun VALUES('@{pipeline().RunId}','Running',SYSUTCDATETIME(),NULL);
```

### 4.8 - Initialize Serving State

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Initialize Serving State |
| Incoming dependency | Register Controller Owner [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.create-merge table CR01_PublishState (IsReady:bool,ChangedAtUtc:datetime,Owner:string)
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 4.9 - Compute Threshold Reference Keys

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Threshold Reference Keys |
| Incoming dependency | Initialize Serving State [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-replace CR01_Checks <| let expected=print Scope=dynamic(["TOTAL_BANK","RETAILS","NON_RETAILS"])
| mv-expand Scope to typeof(string)
| extend IndicatorKey=dynamic(["GrossOutflow_MB","NetOutflow_MB","AccumNetOutflow_MB","DebitTxnCount_M","Velocity_X","AvgDebitAmount_MB","ClusterShare_Pct","ShareJump_Pct"])
| mv-expand IndicatorKey to typeof(string)
| extend WindowCode=dynamic(["BEFORE_WORKING_HOUR","MORNING_WORKING_HOUR","AFTERNOON_WORKING_HOUR","AFTER_WORKING_HOUR"])
| mv-expand WindowCode to typeof(string)
| extend DayType=dynamic(["BUSINESS_DAY","WEEKEND","HOLIDAY"])
| mv-expand DayType to typeof(string) | extend Expected=true;
expected
| join kind=fullouter (
    EWI_AlertThreshold | summarize Copies=count() by Scope,IndicatorKey,WindowCode,DayType
) on Scope,IndicatorKey,WindowCode,DayType
| where isnull(Expected) or isnull(Copies) or Copies!=1
| project Problem='Missing, unexpected, or duplicate threshold reference key'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 4.10 - Validate Threshold Reference Keys

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Threshold Reference Keys |
| Incoming dependency | Compute Threshold Reference Keys [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Threshold Reference Keys').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 4.10-True.1 - Validate Threshold Reference Keys Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Threshold Reference Keys > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Threshold Reference Keys Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Threshold Reference Keys has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 4.11 - Finish All Due Refreshes

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Until |
| General > Name (exact) | Finish All Due Refreshes |
| Incoming dependency | Validate Threshold Reference Keys [Succeeded] |

**Settings > Expression (exit condition)** - use Add dynamic content.

```text
@equals(int(activity('Lookup Next Refresh').output.firstRow.HasDue),0)
```

**Settings > Timeout** - literal value; do not add an expression wrapper.

```text
0.12:00:00
```

Open the Activities canvas inside Until. The condition is evaluated after an iteration; retain the Wait activity.

### 4.11.1 - Lookup Next Refresh

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Finish All Due Refreshes > Activities |
| Activity to select | Lookup |
| General > Name (exact) | Lookup Next Refresh |
| Incoming dependency | None inside this canvas/branch |
| General > timeout | 0.12:00:00 |
| General > retry | 0 |
| General > retryIntervalInSeconds | 30 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse). Select **Use query > Query**.

**Settings > Query** - use Add dynamic content.

```sql
DECLARE @first DATE=TRY_CONVERT(DATE,'@{variables('vFirstRefreshDate')}',23);
IF @first IS NULL THROW 51105,'Invalid first refresh date.',1;
DECLARE @now DATETIME2(6)='@{variables('vRunICT')}';
DECLARE @due DATE=CAST(DATEADD(DAY,CASE WHEN CAST(@now AS TIME)<'03:30' THEN -1 ELSE 0 END,@now) AS DATE);
DECLARE @last DATE=(SELECT MAX(RefreshDate) FROM dbo.CR01RefreshRun WHERE Status='Completed');
DECLARE @next DATE=CASE WHEN @last IS NULL THEN @first ELSE DATEADD(DAY,1,@last) END;
IF EXISTS(SELECT 1 FROM dbo.CR01RefreshRun WHERE Status<>'Completed')
    THROW 51106,'An incomplete refresh requires recovery with its original manifest.',1;
SELECT CASE WHEN @next<=@due THEN 1 ELSE 0 END AS HasDue,CONVERT(VARCHAR(10),@next,23) AS RefreshDate;
```

**Settings > First row only** - literal value; do not add an expression wrapper.

```text
True
```

**Settings > Query timeout** - literal value; do not add an expression wrapper.

```text
02:00:00
```

**Source advanced > Partition option (where exposed)** - literal value; do not add an expression wrapper.

```text
None
```

### 4.11.2 - Run Due Refresh

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Finish All Due Refreshes > Activities |
| Activity to select | If condition |
| General > Name (exact) | Run Due Refresh |
| Incoming dependency | Lookup Next Refresh [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@equals(int(activity('Lookup Next Refresh').output.firstRow.HasDue),1)
```

**True branch:** open this branch and add its activities below.

### 4.11.2-True.1 - Invoke Overnight Refresh

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Finish All Due Refreshes > Activities > Run Due Refresh > True branch |
| Activity to select | Invoke pipeline |
| General > Name (exact) | Invoke Overnight Refresh |
| Incoming dependency | None inside this canvas/branch |
| General > timeout | 0.12:00:00 |
| General > retry | 0 |
| General > retryIntervalInSeconds | 30 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **existing Fabric pipeline-invocation connection**.

Select workspace **RTI-IDM-PRD** and invoked pipeline **pl_CR01_DepositMovement_OvernightRefresh**.

Select by name in your workspace; do not paste a recorded item GUID into a different environment.

**Settings > Wait on completion** - literal value; do not add an expression wrapper.

```text
True
```

**Child parameter > pSourceFinalized** - use Add dynamic content.

```text
@pipeline().parameters.pSourceFinalized
```

**Child parameter > pControllerRunId** - use Add dynamic content.

```text
@pipeline().RunId
```

**Child parameter > pSourceIntervalMinutes** - use Add dynamic content.

```text
@pipeline().parameters.pSourceIntervalMinutes
```

**Child parameter > pRefreshDate** - use Add dynamic content.

```text
@activity('Lookup Next Refresh').output.firstRow.RefreshDate
```

**False branch:** leave empty.

### 4.12 - Invoke Normal Discovery

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Invoke pipeline |
| General > Name (exact) | Invoke Normal Discovery |
| Incoming dependency | Finish All Due Refreshes [Succeeded] |
| General > timeout | 0.12:00:00 |
| General > retry | 0 |
| General > retryIntervalInSeconds | 30 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **existing Fabric pipeline-invocation connection**.

Select workspace **RTI-IDM-PRD** and invoked pipeline **pl_CR01_DepositMovement_Discover**.

Select by name in your workspace; do not paste a recorded item GUID into a different environment.

**Settings > Wait on completion** - literal value; do not add an expression wrapper.

```text
True
```

**Child parameter > pControllerRunId** - use Add dynamic content.

```text
@pipeline().RunId
```

**Child parameter > pRunICT** - use Add dynamic content.

```text
@variables('vRunICT')
```

### 4.13 - Append Normal EWI Buckets

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Append Normal EWI Buckets |
| Incoming dependency | Invoke Normal Discovery [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set-or-append DepositMovementEarlyWarning <|
    let _today = startofday(datetime(@{variables('vRunICT')}));
    let _existing = toscalar(
        DepositMovementEarlyWarning
        | where Bucket_Start >= _today
        | summarize make_set(strcat(Object_Id, "|", format_datetime(Bucket_Start, "yyyy-MM-dd HH:mm"))));
    Gold_EarlyWarning(datetime(@{variables('vRunICT')}))
    | where not(set_has_element(_existing, strcat(Object_Id, "|", format_datetime(Bucket_Start, "yyyy-MM-dd HH:mm"))))
| project Object_Id,Scope,Date_ICT,Bucket_Start,Bucket_Label,Alert_Time,WindowCode,WindowName,DayType,EventFlag,IsMonthEnd,IsPayroll,IsLongWeekend,IndicatorId,IndicatorKey,IndicatorName,Unit,Value,Direction,L1,L2,L3,Alert_Level,Alert_Rank=toint(Alert_Rank)
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 4.14 - Publish Verified Data

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Publish Verified Data |
| Incoming dependency | Append Normal EWI Buckets [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - use Add dynamic content.

```kusto
.set-or-append CR01_PublishState <| print IsReady=true,ChangedAtUtc=now(),Owner='@{pipeline().RunId}'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 4.15 - Complete Controller Owner

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Script |
| General > Name (exact) | Complete Controller Owner |
| Incoming dependency | Publish Verified Data [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse).

**Script block execution timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

Script block 1 > Type: **NonQuery**.

**Script block 1 > Text** - use Add dynamic content.

```sql
UPDATE dbo.CR01ControllerRun SET Status='Completed',CompletedAtUtc=SYSUTCDATETIME() WHERE RunId='@{pipeline().RunId}' AND Status='Running';
```

### 4.16 - Release Owned Controller Lock

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Release Owned Controller Lock |
| Incoming dependency | Complete Controller Owner [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.drop table CR01_ControllerLock
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

## 5. pl_CR01_SQLControlTest

Validated definition: [pipeline/pl_CR01_SQLControlTest.json](pipeline/pl_CR01_SQLControlTest.json).

### parameters

| Name | UI type | Default |
| --- | --- | --- |
| pControllerRunId | string | 2161afc4-a944-4f0c-a96f-b6b8e35dd2b6 |
| pSourceIntervalMinutes | int | 15 |

### variables

| Name | UI type | Default |
| --- | --- | --- |
| vRefreshDate | String | 2026-11-18 |

### Top-level activity order

| Order | Activity | Type |
| --- | --- | --- |
| 1 | Initialize Isolated SQL Fixtures | Script |
| 2 | Validate Controller Owner | Script |
| 3 | Register Frozen Manifest | Script |
| 4 | Seed Prior Audit And Staged Totals | Script |
| 5 | Preserve And Supersede Audit | Script |
| 6 | Commit Verified Refresh | Script |
| 7 | Read SQL Test Results | Lookup |
| 8 | Validate SQL Test Results | IfCondition |
| 9 | Remove Isolated SQL Fixtures | Script |

### 5.1 - Initialize Isolated SQL Fixtures

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Script |
| General > Name (exact) | Initialize Isolated SQL Fixtures |
| Incoming dependency | None inside this canvas/branch |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse).

**Script block execution timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

Script block 1 > Type: **NonQuery**.

**Script block 1 > Text** - use Add dynamic content.

```sql
IF OBJECT_ID('dbo.CR01Test_47915723_CR01ControllerRun','U') IS NOT NULL THROW 51200,'Isolated SQL namespace is not empty.',1;
IF OBJECT_ID('dbo.CR01Test_47915723_CR01RefreshRun','U') IS NOT NULL THROW 51200,'Isolated SQL namespace is not empty.',1;
IF OBJECT_ID('dbo.CR01Test_47915723_CR01RefreshManifest','U') IS NOT NULL THROW 51200,'Isolated SQL namespace is not empty.',1;
IF OBJECT_ID('dbo.CR01Test_47915723_CR01AuditBefore','U') IS NOT NULL THROW 51200,'Isolated SQL namespace is not empty.',1;
IF OBJECT_ID('dbo.CR01Test_47915723_ProcessedFiles','U') IS NOT NULL THROW 51200,'Isolated SQL namespace is not empty.',1;
-- Dedicated CR01 state. Existing ProcessedFiles schema and procedures are unchanged.
-- These tables are NOT mutexes. The controller acquires CR01_ControllerLock in KQL first.
IF OBJECT_ID('dbo.CR01Test_47915723_CR01ControllerRun', 'U') IS NULL
CREATE TABLE dbo.CR01Test_47915723_CR01ControllerRun (
    RunId VARCHAR(64) NOT NULL,
    Status VARCHAR(20) NOT NULL,
    StartedAtUtc DATETIME2(3) NOT NULL,
    CompletedAtUtc DATETIME2(3) NULL
);

IF OBJECT_ID('dbo.CR01Test_47915723_CR01RefreshRun', 'U') IS NULL
CREATE TABLE dbo.CR01Test_47915723_CR01RefreshRun (
    RefreshDate DATE NOT NULL,
    ControllerRunId VARCHAR(64) NOT NULL,
    Status VARCHAR(20) NOT NULL,
    Stage VARCHAR(64) NOT NULL,
    StartedAtUtc DATETIME2(3) NOT NULL,
    CompletedAtUtc DATETIME2(3) NULL
);

IF OBJECT_ID('dbo.CR01Test_47915723_CR01RefreshManifest', 'U') IS NULL
CREATE TABLE dbo.CR01Test_47915723_CR01RefreshManifest (
    RefreshDate DATE NOT NULL,
    FileName VARCHAR(260) NOT NULL,
    SourceBytes BIGINT NULL,
    SourceLastModified DATETIME2(6) NULL,
    ExpectedRows BIGINT NULL
);

IF OBJECT_ID('dbo.CR01Test_47915723_CR01AuditBefore', 'U') IS NULL
CREATE TABLE dbo.CR01Test_47915723_CR01AuditBefore (
    RefreshDate DATE NOT NULL,
    FileName VARCHAR(260) NOT NULL,
    IngestedAtUtc DATETIME2(3) NOT NULL,
    RowCount_ BIGINT NOT NULL,
    Status VARCHAR(32) NOT NULL,
    PipelineName VARCHAR(200) NULL,
    PipelineRunId VARCHAR(64) NULL,
    RunAsUser VARCHAR(200) NULL,
    ErrorMsg VARCHAR(4000) NULL
);

CREATE TABLE dbo.CR01Test_47915723_ProcessedFiles (
    FileName VARCHAR(260) NOT NULL, IngestedAtUtc DATETIME2(3) NOT NULL,
    RowCount_ BIGINT NOT NULL, Status VARCHAR(32) NOT NULL,
    PipelineName VARCHAR(200) NULL, PipelineRunId VARCHAR(64) NULL,
    RunAsUser VARCHAR(200) NULL, ErrorMsg VARCHAR(4000) NULL
);
INSERT INTO dbo.CR01Test_47915723_CR01ControllerRun
VALUES('@{pipeline().parameters.pControllerRunId}','Running',SYSUTCDATETIME(),NULL);
```

### 5.2 - Validate Controller Owner

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Script |
| General > Name (exact) | Validate Controller Owner |
| Incoming dependency | Initialize Isolated SQL Fixtures [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse).

**Script block execution timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

Script block 1 > Type: **NonQuery**.

**Script block 1 > Text** - literal value; do not add an expression wrapper.

```sql
IF (SELECT COUNT(*) FROM dbo.CR01Test_47915723_CR01ControllerRun
    WHERE RunId=@ControllerRunId AND Status='Running') <> 1
    THROW 51100, 'CR01 internal pipeline requires an active controller owner.', 1;
```

| Script input parameter | Type | Direction | Value / expression |
| --- | --- | --- | --- |
| ControllerRunId | String | Input | `@pipeline().parameters.pControllerRunId` |

Add these under the Script block Parameters control. Keep the SQL `@ControllerRunId` parameter bound; do not replace it with an interpolated SQL string.

### 5.3 - Register Frozen Manifest

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Script |
| General > Name (exact) | Register Frozen Manifest |
| Incoming dependency | Validate Controller Owner [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse).

**Script block execution timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

Script block 1 > Type: **NonQuery**.

**Script block 1 > Text** - use Add dynamic content.

```sql
DECLARE @d DATE='@{variables('vRefreshDate')}';
DECLARE @step INT=@{pipeline().parameters.pSourceIntervalMinutes};
IF @step NOT IN (15,30) THROW 51101, 'Source interval must be 15 or 30 minutes.', 1;
IF EXISTS(SELECT 1 FROM dbo.CR01Test_47915723_CR01RefreshRun WHERE RefreshDate=@d)
    THROW 51102, 'Refresh already exists. Recover its original stage and manifest; do not replay blindly.', 1;
INSERT INTO dbo.CR01Test_47915723_CR01RefreshRun
VALUES(@d,'@{pipeline().parameters.pControllerRunId}','Running','Staging',SYSUTCDATETIME(),NULL);
INSERT INTO dbo.CR01Test_47915723_CR01RefreshManifest(RefreshDate,FileName)
SELECT @d, CONCAT('INTRADAY_SUMMARY_',CONVERT(CHAR(8),s,112),'_',
    REPLACE(CONVERT(CHAR(5),s,108),':',''),'_',
    CASE WHEN CAST(e AS DATE)>CAST(s AS DATE) THEN '2400'
         ELSE REPLACE(CONVERT(CHAR(5),e,108),':','') END,'.CSV')
FROM (VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9),
    (10),(11),(12),(13),(14),(15),(16),(17),(18),(19)) n(i)
CROSS APPLY(SELECT DATEADD(MINUTE,-90+i*@step,CAST(@d AS DATETIME2(6))) s) a
CROSS APPLY(SELECT DATEADD(MINUTE,@step,s) e) b
WHERE i<300/@step;
```

### 5.4 - Seed Prior Audit And Staged Totals

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Script |
| General > Name (exact) | Seed Prior Audit And Staged Totals |
| Incoming dependency | Register Frozen Manifest [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse).

**Script block execution timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

Script block 1 > Type: **NonQuery**.

**Script block 1 > Text** - use Add dynamic content.

```sql
INSERT INTO dbo.CR01Test_47915723_ProcessedFiles
SELECT TOP(1) FileName,SYSUTCDATETIME(),1,'Success','PreviousPipeline','previous-run','CR01Test',NULL
FROM dbo.CR01Test_47915723_CR01RefreshManifest
WHERE RefreshDate='@{variables('vRefreshDate')}' ORDER BY FileName;
UPDATE dbo.CR01Test_47915723_CR01RefreshManifest SET ExpectedRows=1,SourceBytes=100,
    SourceLastModified='2026-11-18T03:30:00'
WHERE RefreshDate='@{variables('vRefreshDate')}';
```

### 5.5 - Preserve And Supersede Audit

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Script |
| General > Name (exact) | Preserve And Supersede Audit |
| Incoming dependency | Seed Prior Audit And Staged Totals [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse).

**Script block execution timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

Script block 1 > Type: **NonQuery**.

**Script block 1 > Text** - use Add dynamic content.

```sql
BEGIN TRANSACTION;
INSERT INTO dbo.CR01Test_47915723_CR01AuditBefore
SELECT m.RefreshDate,a.FileName,a.IngestedAtUtc,a.RowCount_,a.Status,a.PipelineName,a.PipelineRunId,a.RunAsUser,a.ErrorMsg
FROM dbo.CR01Test_47915723_ProcessedFiles a JOIN dbo.CR01Test_47915723_CR01RefreshManifest m ON a.FileName=m.FileName
WHERE m.RefreshDate='@{variables('vRefreshDate')}' AND a.Status='Success';
UPDATE a SET Status='Superseded-CR01'
FROM dbo.CR01Test_47915723_ProcessedFiles a JOIN dbo.CR01Test_47915723_CR01RefreshManifest m ON a.FileName=m.FileName
WHERE m.RefreshDate='@{variables('vRefreshDate')}' AND a.Status='Success';
UPDATE dbo.CR01Test_47915723_CR01RefreshRun SET Stage='Replacing' WHERE RefreshDate='@{variables('vRefreshDate')}';
COMMIT TRANSACTION;
```

### 5.6 - Commit Verified Refresh

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Script |
| General > Name (exact) | Commit Verified Refresh |
| Incoming dependency | Preserve And Supersede Audit [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse).

**Script block execution timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

Script block 1 > Type: **NonQuery**.

**Script block 1 > Text** - use Add dynamic content.

```sql
BEGIN TRANSACTION;
IF EXISTS(SELECT 1 FROM dbo.CR01Test_47915723_ProcessedFiles a JOIN dbo.CR01Test_47915723_CR01RefreshManifest m ON a.FileName=m.FileName
    WHERE m.RefreshDate='@{variables('vRefreshDate')}' AND a.Status='Success')
    THROW 51104,'Unexpected concurrent Success audit row. Keep the controller lock.',1;
INSERT INTO dbo.CR01Test_47915723_ProcessedFiles
SELECT FileName,SYSUTCDATETIME(),ExpectedRows,'Success','@{pipeline().Pipeline}','@{pipeline().RunId}','CR01',NULL
FROM dbo.CR01Test_47915723_CR01RefreshManifest WHERE RefreshDate='@{variables('vRefreshDate')}';
UPDATE dbo.CR01Test_47915723_CR01RefreshRun SET Status='Completed',Stage='Verified',CompletedAtUtc=SYSUTCDATETIME()
WHERE RefreshDate='@{variables('vRefreshDate')}' AND Status='Running';
COMMIT TRANSACTION;
```

### 5.7 - Read SQL Test Results

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Lookup |
| General > Name (exact) | Read SQL Test Results |
| Incoming dependency | Commit Verified Refresh [Succeeded] |
| General > timeout | 0.12:00:00 |
| General > retry | 0 |
| General > retryIntervalInSeconds | 30 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse). Select **Use query > Query**.

**Settings > Query** - literal value; do not add an expression wrapper.

```sql
SELECT
    (SELECT COUNT(*) FROM dbo.CR01Test_47915723_ProcessedFiles WHERE Status='Success') AS Successful,
    (SELECT COUNT(*) FROM dbo.CR01Test_47915723_ProcessedFiles WHERE Status='Superseded-CR01') AS Superseded,
    (SELECT COUNT(*) FROM dbo.CR01Test_47915723_CR01AuditBefore WHERE Status='Success') AS Archived,
    (SELECT COUNT(*) FROM dbo.CR01Test_47915723_CR01RefreshRun WHERE Status='Completed') AS Completed;
```

**Settings > First row only** - literal value; do not add an expression wrapper.

```text
True
```

**Settings > Query timeout** - literal value; do not add an expression wrapper.

```text
02:00:00
```

**Source advanced > Partition option (where exposed)** - literal value; do not add an expression wrapper.

```text
None
```

### 5.8 - Validate SQL Test Results

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate SQL Test Results |
| Incoming dependency | Read SQL Test Results [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@not(and(and(equals(int(activity('Read SQL Test Results').output.firstRow.Successful),div(300,pipeline().parameters.pSourceIntervalMinutes)),equals(int(activity('Read SQL Test Results').output.firstRow.Superseded),1)),and(equals(int(activity('Read SQL Test Results').output.firstRow.Archived),1),equals(int(activity('Read SQL Test Results').output.firstRow.Completed),1))))
```

**True branch:** open this branch and add its activities below.

### 5.8-True.1 - Fail SQL Control Test

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate SQL Test Results > True branch |
| Activity to select | Fail |
| General > Name (exact) | Fail SQL Control Test |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_SQL_TEST_FAILED
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
Manifest/audit/checkpoint SQL did not match the expected isolated results.
```

**False branch:** leave empty.

### 5.9 - Remove Isolated SQL Fixtures

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Script |
| General > Name (exact) | Remove Isolated SQL Fixtures |
| Incoming dependency | Validate SQL Test Results [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Connection: **wh_control_framework** (Warehouse).

**Script block execution timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

Script block 1 > Type: **NonQuery**.

**Script block 1 > Text** - use Add dynamic content.

```sql
DROP TABLE dbo.CR01Test_47915723_CR01ControllerRun;
DROP TABLE dbo.CR01Test_47915723_CR01RefreshRun;
DROP TABLE dbo.CR01Test_47915723_CR01RefreshManifest;
DROP TABLE dbo.CR01Test_47915723_CR01AuditBefore;
DROP TABLE dbo.CR01Test_47915723_ProcessedFiles;
```

## 6. pl_CR01_IsolatedRefreshTest

Validated definition: [pipeline/pl_CR01_IsolatedRefreshTest.json](pipeline/pl_CR01_IsolatedRefreshTest.json).

### parameters

None.

### variables

None.

### Top-level activity order

| Order | Activity | Type |
| --- | --- | --- |
| 1 | Clone Schema DepositMovement | KustoQueryLanguage |
| 2 | Clone Schema DepositMovementClassified | KustoQueryLanguage |
| 3 | Clone Schema DepositMovementEarlyWarning | KustoQueryLanguage |
| 4 | Disable Test Streaming | KustoQueryLanguage |
| 5 | Create Clean Isolated Threshold Fixture | KustoQueryLanguage |
| 6 | Create Test Classification Function | KustoQueryLanguage |
| 7 | Create Test EWI Function | KustoQueryLanguage |
| 8 | Enable Test Classification Policy | KustoQueryLanguage |
| 9 | Create Test Visibility State | KustoQueryLanguage |
| 10 | Seed Original Test Data | KustoQueryLanguage |
| 11 | Seed mv_Summary_Product_Channel_Alert | KustoQueryLanguage |
| 12 | Seed mv_EarlyWarning_Base | KustoQueryLanguage |
| 13 | Seed Caching mv_EarlyWarning_Base | KustoQueryLanguage |
| 14 | Seed Old EWI Snapshots | KustoQueryLanguage |
| 15 | Create Corrected Staging Schema | KustoQueryLanguage |
| 16 | Seed Adjusted Overnight Version | KustoQueryLanguage |
| 17 | Create Intentional Verifier Mismatch | KustoQueryLanguage |
| 18 | Require Negative Verifier Detection | IfCondition |
| 19 | Compute Threshold Reference Keys | KustoQueryLanguage |
| 20 | Validate Threshold Reference Keys | IfCondition |
| 21 | Wait For Queryable Staging | Until |
| 22 | Compute Staged Source Contract | KustoQueryLanguage |
| 23 | Validate Staged Source Contract | IfCondition |
| 24 | Check Silver Transformation Version | KustoQueryLanguage |
| 25 | Validate Silver Transformation Version | IfCondition |
| 26 | Preview Existing Silver Classification | KustoQueryLanguage |
| 27 | Compute Preview Calendar Classification | KustoQueryLanguage |
| 28 | Validate Preview Calendar Classification | IfCondition |
| 29 | Compute Loaded File Coverage | KustoQueryLanguage |
| 30 | Validate Loaded File Coverage | IfCondition |
| 31 | Read Existing Gold Views | KustoQueryLanguage |
| 32 | Check Existing Gold Definitions | KustoQueryLanguage |
| 33 | Validate Gold Baseline | IfCondition |
| 34 | Check retention mv_Summary_Product_Channel_Alert | KustoQueryLanguage |
| 35 | Validate retention mv_Summary_Product_Channel_Alert | IfCondition |
| 36 | Check caching mv_Summary_Product_Channel_Alert | KustoQueryLanguage |
| 37 | Validate caching mv_Summary_Product_Channel_Alert | IfCondition |
| 38 | Check retention mv_EarlyWarning_Base | KustoQueryLanguage |
| 39 | Validate retention mv_EarlyWarning_Base | IfCondition |
| 40 | Check caching mv_EarlyWarning_Base | KustoQueryLanguage |
| 41 | Validate caching mv_EarlyWarning_Base | IfCondition |
| 42 | Backup Target Bronze | KustoQueryLanguage |
| 43 | Backup Target Silver | KustoQueryLanguage |
| 44 | Backup Both EWI Dates | KustoQueryLanguage |
| 45 | Snapshot Unrelated DepositMovement | KustoQueryLanguage |
| 46 | Snapshot Unrelated DepositMovementClassified | KustoQueryLanguage |
| 47 | Hold Serving Visibility | KustoQueryLanguage |
| 48 | Drop mv_Summary_Product_Channel_Alert | KustoQueryLanguage |
| 49 | Drop mv_EarlyWarning_Base | KustoQueryLanguage |
| 50 | Delete Only Manifest Bronze | KustoQueryLanguage |
| 51 | Delete Only Manifest Silver | KustoQueryLanguage |
| 52 | Compute Empty Replacement Scope | KustoQueryLanguage |
| 53 | Validate Empty Replacement Scope | IfCondition |
| 54 | Promote Frozen Overnight Snapshot | KustoQueryLanguage |
| 55 | Wait For Bronze And Silver | Until |
| 56 | Compute Silver Classification | KustoQueryLanguage |
| 57 | Validate Silver Classification | IfCondition |
| 58 | Compute Unrelated DepositMovement | KustoQueryLanguage |
| 59 | Validate Unrelated DepositMovement | IfCondition |
| 60 | Compute Unrelated DepositMovementClassified | KustoQueryLanguage |
| 61 | Validate Unrelated DepositMovementClassified | IfCondition |
| 62 | Rebuild mv_Summary_Product_Channel_Alert | KustoQueryLanguage |
| 63 | Compute Reconciled mv_Summary_Product_Channel_Alert | KustoQueryLanguage |
| 64 | Validate Reconciled mv_Summary_Product_Channel_Alert | IfCondition |
| 65 | Rebuild mv_EarlyWarning_Base | KustoQueryLanguage |
| 66 | Restore Caching mv_EarlyWarning_Base | KustoQueryLanguage |
| 67 | Compute Reconciled mv_EarlyWarning_Base | KustoQueryLanguage |
| 68 | Validate Reconciled mv_EarlyWarning_Base | IfCondition |
| 69 | Wait For Healthy Gold Views | Until |
| 70 | Compute EWI Level Contract | KustoQueryLanguage |
| 71 | Validate EWI Level Contract | IfCondition |
| 72 | Delete Affected Persisted EWI Dates | KustoQueryLanguage |
| 73 | Recompute Both Complete EWI Dates | KustoQueryLanguage |
| 74 | Compute Persisted EWI Grain | KustoQueryLanguage |
| 75 | Validate Persisted EWI Grain | IfCondition |
| 76 | Compute Reconciled Persisted EWI | KustoQueryLanguage |
| 77 | Validate Reconciled Persisted EWI | IfCondition |
| 78 | Assert Known Corrected Amounts | KustoQueryLanguage |
| 79 | Require Exact Test Pass | IfCondition |

### 6.1 - Clone Schema DepositMovement

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Clone Schema DepositMovement |
| Incoming dependency | None inside this canvas/branch |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set CR01Test_06622392_DepositMovement <| DepositMovement | take 0
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.2 - Clone Schema DepositMovementClassified

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Clone Schema DepositMovementClassified |
| Incoming dependency | Clone Schema DepositMovement [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set CR01Test_06622392_DepositMovementClassified <| DepositMovementClassified | take 0
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.3 - Clone Schema DepositMovementEarlyWarning

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Clone Schema DepositMovementEarlyWarning |
| Incoming dependency | Clone Schema DepositMovementClassified [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set CR01Test_06622392_DepositMovementEarlyWarning <| DepositMovementEarlyWarning | take 0
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.4 - Disable Test Streaming

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Disable Test Streaming |
| Incoming dependency | Clone Schema DepositMovementEarlyWarning [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.alter table CR01Test_06622392_DepositMovement policy streamingingestion disable
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.5 - Create Clean Isolated Threshold Fixture

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Create Clean Isolated Threshold Fixture |
| Incoming dependency | Disable Test Streaming [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set CR01Test_06622392_EWI_AlertThreshold <| EWI_AlertThreshold | distinct *
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.6 - Create Test Classification Function

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Create Test Classification Function |
| Incoming dependency | Create Clean Isolated Threshold Fixture [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.create function CR01Test_06622392_Transform_DepositMovementClassified() {
    // Note 1: The function has no parameters because the update policy supplies
    // the newly ingested rows through the CR01Test_06622392_DepositMovement source table below.
    //
    // Note 2: Reference tables are reduced to scalar dynamic values once per
    // function execution, then reused while every source row is classified.
    // A scalar property bag avoids a join in the update-policy query. Fabric
    // otherwise requires streaming ingestion to be disabled on the source table.
    //
    // Note 3: These boundaries form [January 1 this year, January 1 next year).
    // The half-open range includes every instant in the current execution year.
    let CurrentYearStart = startofyear(now());
    let NextYearStart = datetime_add("year", 1, CurrentYearStart);
    // Note 3b: The event-flag calendar spans a small pad on each side of the year
    // so long-weekend runs and payroll shifts that cross the boundary resolve
    // correctly. Padded dates outside the current year are never emitted.
    let CalendarStart = datetime_add("day", -3, CurrentYearStart);
    let CalendarEnd = datetime_add("day", 3, NextYearStart);
    // Note 4: HolidayByDate becomes a property bag such as
    // {"2026-01-01":"New Year's Day"}, enabling a lookup by local date key.
    let HolidayByDate = toscalar(
        ThailandFinancialInstitutionHoliday
        // Note 5: Filter before summarize so holidays outside the current year
        // do not consume aggregation memory or participate in classification.
        | where HolidayDate >= CalendarStart
            and HolidayDate < CalendarEnd
        // Note 6: Normalize timestamps to dates and choose one deterministic
        // name if the reference table contains duplicate rows for the same day.
        | summarize HolidayName = min(HolidayName)
            by HolidayDate = startofday(HolidayDate)
        | extend HolidayDateKey = format_datetime(HolidayDate, "yyyy-MM-dd")
        // Note 7: make_bag creates the date-to-name dictionary used later by
        // bag_has_key and indexed lookup operations.
        | summarize Holidays = make_bag(bag_pack(HolidayDateKey, HolidayName))
    );
    // Note 8: Windows becomes one ordered dynamic array containing all operating
    // window definitions. SortOrder keeps the reference-table sequence stable.
    let Windows = toscalar(
        OperatingWindowsTimes
        | order by SortOrder asc
        | summarize WindowDefinitions = make_list(pack(
            "WindowCode", WindowCode,
            "WindowName", WindowName,
            "StartTime", StartTime,
            "EndTime", EndTime,
            "SortOrder", SortOrder))
    );
    // Note 8b: YearCalendar enumerates every local date in the padded year and
    // flags weekends and holidays so business days can be derived deterministically.
    let YearCalendar =
        range _CalDay from CalendarStart to datetime_add("day", -1, CalendarEnd) step 1d
        | extend _CalKey = format_datetime(_CalDay, "yyyy-MM-dd")
        | extend _CalIsWeekend = dayofweek(_CalDay) in (0d, 6d)
        | extend _CalIsHoliday = bag_has_key(HolidayByDate, _CalKey)
        | extend _CalIsBusinessDay = not(_CalIsWeekend) and not(_CalIsHoliday);
    // Note 8c: PayrollDates resolves each scheduled payday (the 25th and the last
    // calendar day of the month) backward to the previous business day when it
    // falls on a weekend or holiday, then keeps the effective dates as a set.
    let PayrollDates = toscalar(
        YearCalendar
        | where dayofmonth(_CalDay) == 25 or _CalDay == startofday(endofmonth(_CalDay))
        | project _AnchorDate = _CalDay
        | mv-expand _Offset = range(0, 14, 1) to typeof(long)
        | extend _Candidate = datetime_add("day", -_Offset, _AnchorDate)
        | extend _CandKey = format_datetime(_Candidate, "yyyy-MM-dd")
        | extend _CandIsBusinessDay =
            not(dayofweek(_Candidate) in (0d, 6d))
            and not(bag_has_key(HolidayByDate, _CandKey))
        | where _CandIsBusinessDay
        | summarize arg_min(_Offset, _Candidate) by _AnchorDate
        | summarize PayrollSet = make_set(format_datetime(_Candidate, "yyyy-MM-dd"))
    );
    // Note 8d: LongWeekendDates finds maximal runs of consecutive non-business
    // days. A running count of business days holds one id across each gap, so a
    // run of three or more non-business days marks every date it contains.
    let LongWeekendDates = toscalar(
        YearCalendar
        | order by _CalDay asc
        | extend _BusinessRunId = row_cumsum(toint(_CalIsBusinessDay))
        | where not(_CalIsBusinessDay)
        | summarize _RunLength = count(), _RunDates = make_list(_CalKey) by _BusinessRunId
        | where _RunLength >= 3
        | mv-expand _RunDate = _RunDates to typeof(string)
        | summarize LongWeekendSet = make_set(_RunDate)
    );
    // Note 9: Processing starts with the Bronze rows supplied to this function.
    CR01Test_06622392_DepositMovement
    // Note 9b: Normalize Channel - source can carry leading/trailing whitespace,
    // which breaks exact matches (MSYG/SYSG exclusion, IsRetail, Channel_Group).
    | extend Channel = trim(@"\s", tostring(Channel))
    // Note 10: Date is interpreted as Bangkok local calendar time. Time stores
    // an interval, so only its HH:mm start value is extracted for classification.
    | extend
        LocalDate = startofday(Date),
        _TimeStartText = extract(@"^([0-9]{2}:[0-9]{2})-[0-9]{2}:[0-9]{2}$", 1, Time)
    // Note 11: Appending seconds converts HH:mm into a timespan that can be
    // compared with the StartTime and EndTime values from the window reference.
    | extend LocalTimeOfDay = totimespan(strcat(_TimeStartText, ":00"))
    | extend LocalDateTime = LocalDate + LocalTimeOfDay
    // Note 12: KQL dayofweek returns Sunday as 0d and Saturday as 6d.
    | extend
        IsWeekend = dayofweek(LocalDate) in (0d, 6d),
        _LocalDateKey = format_datetime(LocalDate, "yyyy-MM-dd")
    // Note 13: The date key checks holiday membership and retrieves its name
    // without joining each CR01Test_06622392_DepositMovement row to the holiday table.
    | extend
        IsFinancialInstitutionHoliday = bag_has_key(HolidayByDate, _LocalDateKey),
        HolidayName = tostring(HolidayByDate[_LocalDateKey])
    // Note 14: A business day must pass both calendar checks. Operating-window
    // assignment is independent and applies to every valid source row.
    | extend IsBusinessDay = not(IsWeekend)
        and not(IsFinancialInstitutionHoliday)
    // Note 15: Weekend has precedence when a date is both a weekend and a listed
    // holiday; otherwise the date is classified as holiday or business day.
    | extend DayClassification = case(
        IsWeekend, "WEEKEND",
        IsFinancialInstitutionHoliday, "HOLIDAY",
        "BUSINESS_DAY")
    // mv-apply evaluates all reference ranges inside each source row. The summarize
    // returns one result per input row, including malformed or unmatched rows.
    // Note 16: Window ranges are half-open [StartTime, EndTime), so a boundary
    // time belongs to the window that starts there and never to the previous one.
    | mv-apply _Window = Windows to typeof(dynamic) on (
        extend
            _WindowStart = totimespan(_Window["StartTime"]),
            _WindowEnd = totimespan(_Window["EndTime"])
        | extend _IsWindowMatch =
            isnotnull(LocalTimeOfDay)
            and LocalTimeOfDay >= _WindowStart
            and LocalTimeOfDay < _WindowEnd
        // Note 17: Counting matches detects missing and overlapping reference
        // windows. The matching definitions are retained for field extraction.
        | summarize
            WindowMatchCount = countif(_IsWindowMatch),
            _MatchedWindows = make_list_if(_Window, _IsWindowMatch)
    )
    // Note 18: Index zero is safe to inspect as a dynamic value. Output window
    // fields are populated only when exactly one definition matched.
    | extend _MatchedWindow = _MatchedWindows[0]
    | extend
        OperatingWindowCode = iff(WindowMatchCount == 1, tostring(_MatchedWindow["WindowCode"]), ""),
        OperatingWindowName = iff(WindowMatchCount == 1, tostring(_MatchedWindow["WindowName"]), ""),
        OperatingWindowStartTime = iff(WindowMatchCount == 1, totimespan(_MatchedWindow["StartTime"]), timespan(null)),
        OperatingWindowEndTime = iff(WindowMatchCount == 1, totimespan(_MatchedWindow["EndTime"]), timespan(null)),
        OperatingWindowSortOrder = iff(WindowMatchCount == 1, toint(_MatchedWindow["SortOrder"]), int(null)),
        // Note 19: Status precedence reports malformed time first, followed by
        // missing or overlapping window definitions for every day classification.
        ClassificationStatus = case(
            isempty(_TimeStartText), "INVALID_TIME_FORMAT",
            WindowMatchCount == 0, "NO_WINDOW_MATCH",
            WindowMatchCount > 1, "MULTIPLE_WINDOW_MATCHES",
            "CLASSIFIED")
    // Note 19b: Event flags mark calendar events that shift deposit behaviour.
    // Month-end is the last calendar day; payroll and long-weekend membership
    // come from the pre-computed sets. EventFlag joins the active events with a
    // comma, or reports NORMAL when none apply.
    | extend
        IsMonthEnd = LocalDate == startofday(endofmonth(LocalDate)),
        IsPayroll = set_has_element(PayrollDates, _LocalDateKey),
        IsLongWeekend = set_has_element(LongWeekendDates, _LocalDateKey)
    | extend _EventList = set_difference(pack_array(
            iff(IsMonthEnd, "MONTH_END", ""),
            iff(IsPayroll, "PAYROLL", ""),
            iff(IsLongWeekend, "LONG_WEEKEND", "")), dynamic([""]))
    | extend EventFlag = iff(array_length(_EventList) == 0, "NORMAL", strcat_array(_EventList, ","))
    // Note 20: The final projection removes temporary underscore-prefixed fields
    // and fixes the exact column order required by DepositMovementClassified.
    | project
        Date, Time, Product, Channel, Channel_Group,
        Credit_Amount, Debit_Amount, Net_Amount,
        Credit_Transaction, Debit_Transaction, Total_Transaction,
        load_ts, file_name, pipeline_name, pipeline_runid,
        LocalDate, LocalDateTime, LocalTimeOfDay,
        IsWeekend, IsFinancialInstitutionHoliday, IsBusinessDay,
        DayClassification, HolidayName,
        OperatingWindowCode, OperatingWindowName,
        OperatingWindowStartTime, OperatingWindowEndTime, OperatingWindowSortOrder,
        WindowMatchCount, ClassificationStatus,
        IsMonthEnd, IsPayroll, IsLongWeekend, EventFlag
}
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.7 - Create Test EWI Function

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Create Test EWI Function |
| Incoming dependency | Create Test Classification Function [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.create function CR01Test_06622392_Gold_EarlyWarning(TargetDate:datetime=datetime(null), VelocityN:int=4) {
    let _target = iff(isnull(TargetDate), startofday(now() + 7h), startofday(TargetDate));
    // Self-contained aggregation of Silver (folds in the former mv_EarlyWarning_Base):
    // exclude MSYG/SYSG, tag IsRetail, bin to 30-min, periodic sums per bucket x IsRetail.
    let base =
        CR01Test_06622392_DepositMovementClassified
        | where LocalDate == _target
        | where isnotnull(LocalDateTime)
        | where Channel !in ("MSYG", "SYSG")
        | extend IsRetail = Channel in ("ENET", "ATM", "CDM"), BucketStart = bin(LocalDateTime, 30m)
        | summarize
            GrossOutflow = sum(Debit_Amount),
            Net          = sum(Net_Amount),
            DebitTxn     = sum(Debit_Transaction)
            by LocalDate, BucketStart, DayClassification, EventFlag, IsMonthEnd, IsPayroll, IsLongWeekend, IsRetail;
    // Per-bucket cross-scope aggregates (Retails vs Non-Retails); cluster shares
    // need both clusters side by side, so compute them here before fan-out.
    let perBucket =
        base
        | summarize
            Gross_R  = sumif(GrossOutflow, IsRetail),
            Gross_NR = sumif(GrossOutflow, not(IsRetail)),
            Net_R    = sumif(Net, IsRetail),
            Net_NR   = sumif(Net, not(IsRetail)),
            Txn_R    = sumif(DebitTxn, IsRetail),
            Txn_NR   = sumif(DebitTxn, not(IsRetail))
            by LocalDate, BucketStart, DayClassification, EventFlag, IsMonthEnd, IsPayroll, IsLongWeekend
        | extend
            Gross_T = Gross_R + Gross_NR,
            Net_T   = Net_R + Net_NR,
            Txn_T   = Txn_R + Txn_NR
        // #7 Cluster Share on draining magnitude, so the value stays in 0-100%.
        | extend _OutR = max_of(0.0, todouble(-Net_R)), _OutNR = max_of(0.0, todouble(-Net_NR))
        | extend _Denom = _OutR + _OutNR
        | extend
            Share_R  = iff(_Denom > 0, 100.0 * _OutR  / _Denom, real(null)),
            Share_NR = iff(_Denom > 0, 100.0 * _OutNR / _Denom, real(null));
    // Fan out to the 3 scopes. TOTAL_BANK carries no cluster share (its share is 100%).
    let scopeRows =
        union
          ( perBucket | extend Scope = "TOTAL_BANK",  GrossOutflow = todouble(Gross_T),  NetOutflow = todouble(Net_T),  DebitTxn = Txn_T,  ClusterShare_Pct = real(null) ),
          ( perBucket | extend Scope = "RETAILS",     GrossOutflow = todouble(Gross_R),  NetOutflow = todouble(Net_R),  DebitTxn = Txn_R,  ClusterShare_Pct = Share_R ),
          ( perBucket | extend Scope = "NON_RETAILS", GrossOutflow = todouble(Gross_NR), NetOutflow = todouble(Net_NR), DebitTxn = Txn_NR, ClusterShare_Pct = Share_NR );
    let wide =
        scopeRows
        | order by Scope asc, BucketStart asc
        | extend _restart = (Scope != prev(Scope))
        // #3 Accumulated net outflow from 00:00, reset per scope.
        | extend AccumNet = row_cumsum(NetOutflow, _restart)
        // #5 Velocity. Fixed N: average of the prior 4 buckets (same scope). Expanding
        // (VelocityN = 0): average of all prior buckets that day.
        | extend _expSum   = row_cumsum(DebitTxn, _restart) - DebitTxn
        | extend _expCount = row_cumsum(1, _restart) - 1
        | extend _fixSum   = prev(DebitTxn, 1) + prev(DebitTxn, 2) + prev(DebitTxn, 3) + prev(DebitTxn, 4)
        | extend _has4Prior = (prev(Scope, 4) == Scope)
        | extend AvgPrior = iff(
            VelocityN == 0,
            iff(_expCount > 0, todouble(_expSum) / _expCount, real(null)),
            iff(_has4Prior, todouble(_fixSum) / 4.0, real(null)))
        | extend Velocity = iff(isnull(AvgPrior) or AvgPrior == 0, real(null), todouble(DebitTxn) / AvgPrior)
        // #8 Sudden share jump vs the prior 30-min bucket of the same scope.
        | extend ShareJump_Pct = iff(Scope == prev(Scope), ClusterShare_Pct - prev(ClusterShare_Pct), real(null))
        // Comparable-time window from the bucket start.
        | extend _tod = BucketStart - startofday(BucketStart)
        | extend WindowCode = case(
            _tod < timespan(08:30:00), "BEFORE_WORKING_HOUR",
            _tod < timespan(12:00:00), "MORNING_WORKING_HOUR",
            _tod < timespan(17:30:00), "AFTERNOON_WORKING_HOUR",
            "AFTER_WORKING_HOUR")
        | extend WindowName = case(
            _tod < timespan(08:30:00), "before working hour",
            _tod < timespan(12:00:00), "morning working hour",
            _tod < timespan(17:30:00), "afternoon working hour",
            "after working hour")
        | extend _bEnd = BucketStart + 30m
        | project
            Scope,
            LocalDate,
            BucketStart,
            Bucket_Label = strcat(format_datetime(BucketStart, "HH:mm"), "-", format_datetime(_bEnd, "HH:mm")),
            WindowCode, WindowName,
            DayType = DayClassification,
            EventFlag, IsMonthEnd, IsPayroll, IsLongWeekend,
            GrossOutflow_MB    = GrossOutflow / 1000000.0,
            NetOutflow_MB      = NetOutflow / 1000000.0,
            AccumNetOutflow_MB = AccumNet / 1000000.0,
            DebitTxnCount_M    = DebitTxn / 1000000.0,
            Velocity_X         = Velocity,
            AvgDebitAmount_MB  = iff(DebitTxn > 0, (GrossOutflow / DebitTxn) / 1000000.0, real(null)),
            ClusterShare_Pct,
            ShareJump_Pct;
    // Unpivot the 8 indicators to long form (one row per Scope x bucket x indicator).
    let melted =
        union
          ( wide | extend IndicatorKey = "GrossOutflow_MB",    IndicatorName = "Gross Outflow",        Unit = "MB",      Value = GrossOutflow_MB ),
          ( wide | extend IndicatorKey = "NetOutflow_MB",      IndicatorName = "Net Outflow",          Unit = "MB",      Value = NetOutflow_MB ),
          ( wide | extend IndicatorKey = "AccumNetOutflow_MB", IndicatorName = "Accum Net Outflow",    Unit = "MB",      Value = AccumNetOutflow_MB ),
          ( wide | extend IndicatorKey = "DebitTxnCount_M",    IndicatorName = "Debit Txn Count",      Unit = "Million", Value = DebitTxnCount_M ),
          ( wide | extend IndicatorKey = "Velocity_X",         IndicatorName = "Transaction Velocity", Unit = "X",       Value = Velocity_X ),
          ( wide | extend IndicatorKey = "AvgDebitAmount_MB",  IndicatorName = "Average Debit Amount", Unit = "MB",      Value = AvgDebitAmount_MB ),
          ( wide | extend IndicatorKey = "ClusterShare_Pct",   IndicatorName = "Cluster Share",        Unit = "%",       Value = ClusterShare_Pct ),
          ( wide | extend IndicatorKey = "ShareJump_Pct",      IndicatorName = "Sudden Share Jump",    Unit = "pp",      Value = ShareJump_Pct );
    melted
    // Attach the L1/L2/L3 amounts + Direction for this Scope x Indicator x Window x DayType.
    | lookup kind=leftouter CR01Test_06622392_EWI_AlertThreshold on Scope, IndicatorKey, WindowCode, DayType
    // Assign the level, honouring direction; blank thresholds (null) are skipped.
    | extend Alert_Level = case(
        isnull(Value), "L0",
        Direction == "LOW_IS_BAD",
            case(isnotnull(L3) and Value <= L3, "L3",
                 isnotnull(L2) and Value <= L2, "L2",
                 isnotnull(L1) and Value <= L1, "L1", "L0"),
            case(isnotnull(L3) and Value >= L3, "L3",
                 isnotnull(L2) and Value >= L2, "L2",
                 isnotnull(L1) and Value >= L1, "L1", "L0"))
    | extend Alert_Rank = case(Alert_Level == "L3", 3, Alert_Level == "L2", 2, Alert_Level == "L1", 1, 0)
    | extend Alert_Level_Name = case(Alert_Level == "L3", "Critical", Alert_Level == "L2", "Warning", Alert_Level == "L1", "Watch", "Normal")
    | project
        Object_Id     = strcat(Scope, "|", IndicatorKey),   // Activator identity: per Scope x Indicator
        Scope,
        Date_ICT      = format_datetime(LocalDate, "yyyy-MM-dd"),
        Bucket_Start  = BucketStart,
        Bucket_Label,
        Alert_Time    = now() + 7h,
        WindowCode, WindowName,
        DayType,
        EventFlag, IsMonthEnd, IsPayroll, IsLongWeekend,
        IndicatorId, IndicatorKey, IndicatorName, Unit,
        Value, Direction, L1, L2, L3,
        Alert_Level, Alert_Rank, Alert_Level_Name
    | order by Scope asc, Bucket_Start asc, IndicatorId asc
}
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.8 - Enable Test Classification Policy

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Enable Test Classification Policy |
| Incoming dependency | Create Test EWI Function [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.alter table CR01Test_06622392_DepositMovementClassified policy update '[{"IsEnabled":true,"IsTransactional":true,"Query":"CR01Test_06622392_Transform_DepositMovementClassified()","Source":"CR01Test_06622392_DepositMovement","PropagateIngestionProperties":true}]'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.9 - Create Test Visibility State

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Create Test Visibility State |
| Incoming dependency | Enable Test Classification Policy [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.create table CR01Test_06622392_CR01_PublishState (IsReady:bool,ChangedAtUtc:datetime,Owner:string)
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.10 - Seed Original Test Data

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Seed Original Test Data |
| Incoming dependency | Create Test Visibility State [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-append CR01Test_06622392_DepositMovement <| datatable(Date:datetime,Time:string,Product:string,Channel:string,Channel_Group:string,Credit_Amount:decimal,Debit_Amount:decimal,Net_Amount:decimal,Credit_Transaction:long,Debit_Transaction:long,Total_Transaction:long,load_ts:datetime,file_name:string,pipeline_name:string,pipeline_runid:string)[datetime(2026-11-17),"23:00-23:30","S","ENET","Retail",decimal(100),decimal(50),decimal(50),10,5,15,datetime(2026-11-18T03:00:00),"INTRADAY_SUMMARY_20261117_2300_2330.CSV","CR01Test","old1",
datetime(2026-11-18),"00:00-00:30","S","ENET","Retail",decimal(200),decimal(100),decimal(100),20,10,30,datetime(2026-11-18T03:00:00),"INTRADAY_SUMMARY_20261118_0000_0030.CSV","CR01Test","old2",
datetime(2026-11-17),"12:00-12:30","S","ENET","Retail",decimal(10),decimal(5),decimal(5),1,1,2,datetime(2026-11-17T12:30:00),"INTRADAY_SUMMARY_20261117_1200_1230.CSV","CR01Test","unrelated"]
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.11 - Seed mv_Summary_Product_Channel_Alert

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Seed mv_Summary_Product_Channel_Alert |
| Incoming dependency | Seed Original Test Data [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.create materialized-view with (backfill=true,folder="Gold",docstring="") CR01Test_06622392_mv_Summary_Product_Channel_Alert on table CR01Test_06622392_DepositMovement { CR01Test_06622392_DepositMovement
    | summarize
        Time               = max(Time),
        Credit_Amount      = sum(Credit_Amount),
        Debit_Amount       = sum(Debit_Amount),
        Net_Amount         = sum(Net_Amount),
        Credit_Transaction = sum(Credit_Transaction),
        Debit_Transaction  = sum(Debit_Transaction),
        Total_Transaction  = sum(Total_Transaction),
        UpdatedAtUtc       = max(load_ts)
        by Date, Product, Channel, Channel_Group }
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.12 - Seed mv_EarlyWarning_Base

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Seed mv_EarlyWarning_Base |
| Incoming dependency | Seed mv_Summary_Product_Channel_Alert [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.create materialized-view with (backfill=true,folder="Gold",docstring="") CR01Test_06622392_mv_EarlyWarning_Base on table CR01Test_06622392_DepositMovementClassified { CR01Test_06622392_DepositMovementClassified
    // Only rows with a valid local time can fall into a 30-minute bucket.
    | where isnotnull(LocalDateTime)
    // Main condition #1: exclude MSYG / SYSG from every calculation.
    | where Channel !in ("MSYG", "SYSG")
    | extend
        IsRetail    = Channel in ("ENET", "ATM", "CDM"),
        BucketStart = bin(LocalDateTime, 30m)
    | summarize
        GrossOutflow = sum(Debit_Amount),
        Credit       = sum(Credit_Amount),
        Net          = sum(Net_Amount),
        DebitTxn     = sum(Debit_Transaction),
        UpdatedAtUtc = max(load_ts)
        by LocalDate, BucketStart, DayClassification, EventFlag,
           IsMonthEnd, IsPayroll, IsLongWeekend, IsRetail }
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.13 - Seed Caching mv_EarlyWarning_Base

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Seed Caching mv_EarlyWarning_Base |
| Incoming dependency | Seed mv_EarlyWarning_Base [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.alter materialized-view CR01Test_06622392_mv_EarlyWarning_Base policy caching hot = 90d
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.14 - Seed Old EWI Snapshots

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Seed Old EWI Snapshots |
| Incoming dependency | Seed Caching mv_EarlyWarning_Base [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-append CR01Test_06622392_DepositMovementEarlyWarning <| union (CR01Test_06622392_Gold_EarlyWarning(datetime(2026-11-18)-1d)),(CR01Test_06622392_Gold_EarlyWarning(datetime(2026-11-18))) | project Object_Id,Scope,Date_ICT,Bucket_Start,Bucket_Label,Alert_Time,WindowCode,WindowName,DayType,EventFlag,IsMonthEnd,IsPayroll,IsLongWeekend,IndicatorId,IndicatorKey,IndicatorName,Unit,Value,Direction,L1,L2,L3,Alert_Level,Alert_Rank=toint(Alert_Rank)
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.15 - Create Corrected Staging Schema

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Create Corrected Staging Schema |
| Incoming dependency | Seed Old EWI Snapshots [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set CR01Test_06622392_CR01_Stage_20261118 <| DepositMovement | take 0
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.16 - Seed Adjusted Overnight Version

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Seed Adjusted Overnight Version |
| Incoming dependency | Create Corrected Staging Schema [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-append CR01Test_06622392_CR01_Stage_20261118 <| datatable(Date:datetime,Time:string,Product:string,Channel:string,Channel_Group:string,Credit_Amount:decimal,Debit_Amount:decimal,Net_Amount:decimal,Credit_Transaction:long,Debit_Transaction:long,Total_Transaction:long,load_ts:datetime,file_name:string,pipeline_name:string,pipeline_runid:string)[datetime(2026-11-17),"23:00-23:30","S","ENET","Retail",decimal(150),decimal(70),decimal(80),15,7,22,datetime(2026-11-18T03:30:00),"INTRADAY_SUMMARY_20261117_2300_2330.CSV","CR01Test","new1",
datetime(2026-11-18),"00:00-00:30","S","ENET","Retail",decimal(220),decimal(110),decimal(110),22,11,33,datetime(2026-11-18T03:30:00),"INTRADAY_SUMMARY_20261118_0000_0030.CSV","CR01Test","new2"]
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.17 - Create Intentional Verifier Mismatch

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Create Intentional Verifier Mismatch |
| Incoming dependency | Seed Adjusted Overnight Version [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set CR01Test_06622392_VerifierNegative <| print Problem='Intentional negative-test row'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.18 - Require Negative Verifier Detection

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Require Negative Verifier Detection |
| Incoming dependency | Create Intentional Verifier Mismatch [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@not(greater(int(activity('Create Intentional Verifier Mismatch').output.count),0))
```

**True branch:** open this branch and add its activities below.

### 6.18-True.1 - Fail Negative Verifier Test

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Require Negative Verifier Detection > True branch |
| Activity to select | Fail |
| General > Name (exact) | Fail Negative Verifier Test |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_VERIFIER_FAILED
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
A deliberate mismatch was not detected from the synchronous ingestion result.
```

**False branch:** leave empty.

### 6.19 - Compute Threshold Reference Keys

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Threshold Reference Keys |
| Incoming dependency | Require Negative Verifier Detection [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-replace CR01Test_06622392_CR01_Checks <| let expected=print Scope=dynamic(["TOTAL_BANK","RETAILS","NON_RETAILS"])
| mv-expand Scope to typeof(string)
| extend IndicatorKey=dynamic(["GrossOutflow_MB","NetOutflow_MB","AccumNetOutflow_MB","DebitTxnCount_M","Velocity_X","AvgDebitAmount_MB","ClusterShare_Pct","ShareJump_Pct"])
| mv-expand IndicatorKey to typeof(string)
| extend WindowCode=dynamic(["BEFORE_WORKING_HOUR","MORNING_WORKING_HOUR","AFTERNOON_WORKING_HOUR","AFTER_WORKING_HOUR"])
| mv-expand WindowCode to typeof(string)
| extend DayType=dynamic(["BUSINESS_DAY","WEEKEND","HOLIDAY"])
| mv-expand DayType to typeof(string) | extend Expected=true;
expected
| join kind=fullouter (
    CR01Test_06622392_EWI_AlertThreshold | summarize Copies=count() by Scope,IndicatorKey,WindowCode,DayType
) on Scope,IndicatorKey,WindowCode,DayType
| where isnull(Expected) or isnull(Copies) or Copies!=1
| project Problem='Missing, unexpected, or duplicate threshold reference key'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.20 - Validate Threshold Reference Keys

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Threshold Reference Keys |
| Incoming dependency | Compute Threshold Reference Keys [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Threshold Reference Keys').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 6.20-True.1 - Validate Threshold Reference Keys Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Threshold Reference Keys > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Threshold Reference Keys Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Threshold Reference Keys has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 6.21 - Wait For Queryable Staging

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Until |
| General > Name (exact) | Wait For Queryable Staging |
| Incoming dependency | Validate Threshold Reference Keys [Succeeded] |

**Settings > Expression (exit condition)** - use Add dynamic content.

```text
@equals(int(activity('Compute Staging Readiness').output.count),0)
```

**Settings > Timeout** - literal value; do not add an expression wrapper.

```text
0.00:30:00
```

Open the Activities canvas inside Until. The condition is evaluated after an iteration; retain the Wait activity.

### 6.21.1 - Compute Staging Readiness

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Wait For Queryable Staging > Activities |
| Activity to select | KQL |
| General > Name (exact) | Compute Staging Readiness |
| Incoming dependency | None inside this canvas/branch |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-replace CR01Test_06622392_CR01_Checks <| let expected=print items=parse_json(base64_decode_tostring("W3siRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE3XzIzMDBfMjMzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9LHsiRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE4XzAwMDBfMDAzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9XQ=="))
    | mv-expand items | project file_name=tostring(items.FileName), Expected=tolong(items.ExpectedRows); expected | join kind=fullouter (CR01Test_06622392_CR01_Stage_20261118 | summarize Actual=count() by file_name) on file_name | where isnull(Expected) or Expected!=coalesce(Actual,0) | project Problem=strcat(file_name,' stage count mismatch')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.21.2 - Wait For Staging

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Wait For Queryable Staging > Activities |
| Activity to select | Wait |
| General > Name (exact) | Wait For Staging |
| Incoming dependency | Compute Staging Readiness [Succeeded] |

**Settings > Wait time in seconds** - literal value; do not add an expression wrapper.

```text
5
```

### 6.22 - Compute Staged Source Contract

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Staged Source Contract |
| Incoming dependency | Wait For Queryable Staging [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-replace CR01Test_06622392_CR01_Checks <| CR01Test_06622392_CR01_Stage_20261118
| where isnull(Date) or isnull(Credit_Amount) or isnull(Debit_Amount) or isnull(Net_Amount)
    or isnull(Credit_Transaction) or isnull(Debit_Transaction) or isnull(Total_Transaction)
    or format_datetime(Date,'yyyyMMdd') != extract(@"^INTRADAY_SUMMARY_(\d{8})_",1,file_name)
    or replace_string(trim(@"\s",Time),':','') != strcat(
        extract(@"^INTRADAY_SUMMARY_\d{8}_(\d{4})_(\d{4})\.CSV$",1,file_name),'-',
        extract(@"^INTRADAY_SUMMARY_\d{8}_(\d{4})_(\d{4})\.CSV$",2,file_name))
| project Problem=strcat(file_name,' invalid source data or filename/business interval mismatch')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.23 - Validate Staged Source Contract

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Staged Source Contract |
| Incoming dependency | Compute Staged Source Contract [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Staged Source Contract').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 6.23-True.1 - Validate Staged Source Contract Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Staged Source Contract > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Staged Source Contract Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Staged Source Contract has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 6.24 - Check Silver Transformation Version

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Check Silver Transformation Version |
| Incoming dependency | Validate Staged Source Contract [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.show function Transform_DepositMovementClassified | where Body!=base64_decode_tostring('ewogICAgLy8gTm90ZSAxOiBUaGUgZnVuY3Rpb24gaGFzIG5vIHBhcmFtZXRlcnMgYmVjYXVzZSB0aGUgdXBkYXRlIHBvbGljeSBzdXBwbGllcwogICAgLy8gdGhlIG5ld2x5IGluZ2VzdGVkIHJvd3MgdGhyb3VnaCB0aGUgRGVwb3NpdE1vdmVtZW50IHNvdXJjZSB0YWJsZSBiZWxvdy4KICAgIC8vCiAgICAvLyBOb3RlIDI6IFJlZmVyZW5jZSB0YWJsZXMgYXJlIHJlZHVjZWQgdG8gc2NhbGFyIGR5bmFtaWMgdmFsdWVzIG9uY2UgcGVyCiAgICAvLyBmdW5jdGlvbiBleGVjdXRpb24sIHRoZW4gcmV1c2VkIHdoaWxlIGV2ZXJ5IHNvdXJjZSByb3cgaXMgY2xhc3NpZmllZC4KICAgIC8vIEEgc2NhbGFyIHByb3BlcnR5IGJhZyBhdm9pZHMgYSBqb2luIGluIHRoZSB1cGRhdGUtcG9saWN5IHF1ZXJ5LiBGYWJyaWMKICAgIC8vIG90aGVyd2lzZSByZXF1aXJlcyBzdHJlYW1pbmcgaW5nZXN0aW9uIHRvIGJlIGRpc2FibGVkIG9uIHRoZSBzb3VyY2UgdGFibGUuCiAgICAvLwogICAgLy8gTm90ZSAzOiBUaGVzZSBib3VuZGFyaWVzIGZvcm0gW0phbnVhcnkgMSB0aGlzIHllYXIsIEphbnVhcnkgMSBuZXh0IHllYXIpLgogICAgLy8gVGhlIGhhbGYtb3BlbiByYW5nZSBpbmNsdWRlcyBldmVyeSBpbnN0YW50IGluIHRoZSBjdXJyZW50IGV4ZWN1dGlvbiB5ZWFyLgogICAgbGV0IEN1cnJlbnRZZWFyU3RhcnQgPSBzdGFydG9meWVhcihub3coKSk7CiAgICBsZXQgTmV4dFllYXJTdGFydCA9IGRhdGV0aW1lX2FkZCgieWVhciIsIDEsIEN1cnJlbnRZZWFyU3RhcnQpOwogICAgLy8gTm90ZSAzYjogVGhlIGV2ZW50LWZsYWcgY2FsZW5kYXIgc3BhbnMgYSBzbWFsbCBwYWQgb24gZWFjaCBzaWRlIG9mIHRoZSB5ZWFyCiAgICAvLyBzbyBsb25nLXdlZWtlbmQgcnVucyBhbmQgcGF5cm9sbCBzaGlmdHMgdGhhdCBjcm9zcyB0aGUgYm91bmRhcnkgcmVzb2x2ZQogICAgLy8gY29ycmVjdGx5LiBQYWRkZWQgZGF0ZXMgb3V0c2lkZSB0aGUgY3VycmVudCB5ZWFyIGFyZSBuZXZlciBlbWl0dGVkLgogICAgbGV0IENhbGVuZGFyU3RhcnQgPSBkYXRldGltZV9hZGQoImRheSIsIC0zLCBDdXJyZW50WWVhclN0YXJ0KTsKICAgIGxldCBDYWxlbmRhckVuZCA9IGRhdGV0aW1lX2FkZCgiZGF5IiwgMywgTmV4dFllYXJTdGFydCk7CiAgICAvLyBOb3RlIDQ6IEhvbGlkYXlCeURhdGUgYmVjb21lcyBhIHByb3BlcnR5IGJhZyBzdWNoIGFzCiAgICAvLyB7IjIwMjYtMDEtMDEiOiJOZXcgWWVhcidzIERheSJ9LCBlbmFibGluZyBhIGxvb2t1cCBieSBsb2NhbCBkYXRlIGtleS4KICAgIGxldCBIb2xpZGF5QnlEYXRlID0gdG9zY2FsYXIoCiAgICAgICAgVGhhaWxhbmRGaW5hbmNpYWxJbnN0aXR1dGlvbkhvbGlkYXkKICAgICAgICAvLyBOb3RlIDU6IEZpbHRlciBiZWZvcmUgc3VtbWFyaXplIHNvIGhvbGlkYXlzIG91dHNpZGUgdGhlIGN1cnJlbnQgeWVhcgogICAgICAgIC8vIGRvIG5vdCBjb25zdW1lIGFnZ3JlZ2F0aW9uIG1lbW9yeSBvciBwYXJ0aWNpcGF0ZSBpbiBjbGFzc2lmaWNhdGlvbi4KICAgICAgICB8IHdoZXJlIEhvbGlkYXlEYXRlID49IENhbGVuZGFyU3RhcnQKICAgICAgICAgICAgYW5kIEhvbGlkYXlEYXRlIDwgQ2FsZW5kYXJFbmQKICAgICAgICAvLyBOb3RlIDY6IE5vcm1hbGl6ZSB0aW1lc3RhbXBzIHRvIGRhdGVzIGFuZCBjaG9vc2Ugb25lIGRldGVybWluaXN0aWMKICAgICAgICAvLyBuYW1lIGlmIHRoZSByZWZlcmVuY2UgdGFibGUgY29udGFpbnMgZHVwbGljYXRlIHJvd3MgZm9yIHRoZSBzYW1lIGRheS4KICAgICAgICB8IHN1bW1hcml6ZSBIb2xpZGF5TmFtZSA9IG1pbihIb2xpZGF5TmFtZSkKICAgICAgICAgICAgYnkgSG9saWRheURhdGUgPSBzdGFydG9mZGF5KEhvbGlkYXlEYXRlKQogICAgICAgIHwgZXh0ZW5kIEhvbGlkYXlEYXRlS2V5ID0gZm9ybWF0X2RhdGV0aW1lKEhvbGlkYXlEYXRlLCAieXl5eS1NTS1kZCIpCiAgICAgICAgLy8gTm90ZSA3OiBtYWtlX2JhZyBjcmVhdGVzIHRoZSBkYXRlLXRvLW5hbWUgZGljdGlvbmFyeSB1c2VkIGxhdGVyIGJ5CiAgICAgICAgLy8gYmFnX2hhc19rZXkgYW5kIGluZGV4ZWQgbG9va3VwIG9wZXJhdGlvbnMuCiAgICAgICAgfCBzdW1tYXJpemUgSG9saWRheXMgPSBtYWtlX2JhZyhiYWdfcGFjayhIb2xpZGF5RGF0ZUtleSwgSG9saWRheU5hbWUpKQogICAgKTsKICAgIC8vIE5vdGUgODogV2luZG93cyBiZWNvbWVzIG9uZSBvcmRlcmVkIGR5bmFtaWMgYXJyYXkgY29udGFpbmluZyBhbGwgb3BlcmF0aW5nCiAgICAvLyB3aW5kb3cgZGVmaW5pdGlvbnMuIFNvcnRPcmRlciBrZWVwcyB0aGUgcmVmZXJlbmNlLXRhYmxlIHNlcXVlbmNlIHN0YWJsZS4KICAgIGxldCBXaW5kb3dzID0gdG9zY2FsYXIoCiAgICAgICAgT3BlcmF0aW5nV2luZG93c1RpbWVzCiAgICAgICAgfCBvcmRlciBieSBTb3J0T3JkZXIgYXNjCiAgICAgICAgfCBzdW1tYXJpemUgV2luZG93RGVmaW5pdGlvbnMgPSBtYWtlX2xpc3QocGFjaygKICAgICAgICAgICAgIldpbmRvd0NvZGUiLCBXaW5kb3dDb2RlLAogICAgICAgICAgICAiV2luZG93TmFtZSIsIFdpbmRvd05hbWUsCiAgICAgICAgICAgICJTdGFydFRpbWUiLCBTdGFydFRpbWUsCiAgICAgICAgICAgICJFbmRUaW1lIiwgRW5kVGltZSwKICAgICAgICAgICAgIlNvcnRPcmRlciIsIFNvcnRPcmRlcikpCiAgICApOwogICAgLy8gTm90ZSA4YjogWWVhckNhbGVuZGFyIGVudW1lcmF0ZXMgZXZlcnkgbG9jYWwgZGF0ZSBpbiB0aGUgcGFkZGVkIHllYXIgYW5kCiAgICAvLyBmbGFncyB3ZWVrZW5kcyBhbmQgaG9saWRheXMgc28gYnVzaW5lc3MgZGF5cyBjYW4gYmUgZGVyaXZlZCBkZXRlcm1pbmlzdGljYWxseS4KICAgIGxldCBZZWFyQ2FsZW5kYXIgPQogICAgICAgIHJhbmdlIF9DYWxEYXkgZnJvbSBDYWxlbmRhclN0YXJ0IHRvIGRhdGV0aW1lX2FkZCgiZGF5IiwgLTEsIENhbGVuZGFyRW5kKSBzdGVwIDFkCiAgICAgICAgfCBleHRlbmQgX0NhbEtleSA9IGZvcm1hdF9kYXRldGltZShfQ2FsRGF5LCAieXl5eS1NTS1kZCIpCiAgICAgICAgfCBleHRlbmQgX0NhbElzV2Vla2VuZCA9IGRheW9md2VlayhfQ2FsRGF5KSBpbiAoMGQsIDZkKQogICAgICAgIHwgZXh0ZW5kIF9DYWxJc0hvbGlkYXkgPSBiYWdfaGFzX2tleShIb2xpZGF5QnlEYXRlLCBfQ2FsS2V5KQogICAgICAgIHwgZXh0ZW5kIF9DYWxJc0J1c2luZXNzRGF5ID0gbm90KF9DYWxJc1dlZWtlbmQpIGFuZCBub3QoX0NhbElzSG9saWRheSk7CiAgICAvLyBOb3RlIDhjOiBQYXlyb2xsRGF0ZXMgcmVzb2x2ZXMgZWFjaCBzY2hlZHVsZWQgcGF5ZGF5ICh0aGUgMjV0aCBhbmQgdGhlIGxhc3QKICAgIC8vIGNhbGVuZGFyIGRheSBvZiB0aGUgbW9udGgpIGJhY2t3YXJkIHRvIHRoZSBwcmV2aW91cyBidXNpbmVzcyBkYXkgd2hlbiBpdAogICAgLy8gZmFsbHMgb24gYSB3ZWVrZW5kIG9yIGhvbGlkYXksIHRoZW4ga2VlcHMgdGhlIGVmZmVjdGl2ZSBkYXRlcyBhcyBhIHNldC4KICAgIGxldCBQYXlyb2xsRGF0ZXMgPSB0b3NjYWxhcigKICAgICAgICBZZWFyQ2FsZW5kYXIKICAgICAgICB8IHdoZXJlIGRheW9mbW9udGgoX0NhbERheSkgPT0gMjUgb3IgX0NhbERheSA9PSBzdGFydG9mZGF5KGVuZG9mbW9udGgoX0NhbERheSkpCiAgICAgICAgfCBwcm9qZWN0IF9BbmNob3JEYXRlID0gX0NhbERheQogICAgICAgIHwgbXYtZXhwYW5kIF9PZmZzZXQgPSByYW5nZSgwLCAxNCwgMSkgdG8gdHlwZW9mKGxvbmcpCiAgICAgICAgfCBleHRlbmQgX0NhbmRpZGF0ZSA9IGRhdGV0aW1lX2FkZCgiZGF5IiwgLV9PZmZzZXQsIF9BbmNob3JEYXRlKQogICAgICAgIHwgZXh0ZW5kIF9DYW5kS2V5ID0gZm9ybWF0X2RhdGV0aW1lKF9DYW5kaWRhdGUsICJ5eXl5LU1NLWRkIikKICAgICAgICB8IGV4dGVuZCBfQ2FuZElzQnVzaW5lc3NEYXkgPQogICAgICAgICAgICBub3QoZGF5b2Z3ZWVrKF9DYW5kaWRhdGUpIGluICgwZCwgNmQpKQogICAgICAgICAgICBhbmQgbm90KGJhZ19oYXNfa2V5KEhvbGlkYXlCeURhdGUsIF9DYW5kS2V5KSkKICAgICAgICB8IHdoZXJlIF9DYW5kSXNCdXNpbmVzc0RheQogICAgICAgIHwgc3VtbWFyaXplIGFyZ19taW4oX09mZnNldCwgX0NhbmRpZGF0ZSkgYnkgX0FuY2hvckRhdGUKICAgICAgICB8IHN1bW1hcml6ZSBQYXlyb2xsU2V0ID0gbWFrZV9zZXQoZm9ybWF0X2RhdGV0aW1lKF9DYW5kaWRhdGUsICJ5eXl5LU1NLWRkIikpCiAgICApOwogICAgLy8gTm90ZSA4ZDogTG9uZ1dlZWtlbmREYXRlcyBmaW5kcyBtYXhpbWFsIHJ1bnMgb2YgY29uc2VjdXRpdmUgbm9uLWJ1c2luZXNzCiAgICAvLyBkYXlzLiBBIHJ1bm5pbmcgY291bnQgb2YgYnVzaW5lc3MgZGF5cyBob2xkcyBvbmUgaWQgYWNyb3NzIGVhY2ggZ2FwLCBzbyBhCiAgICAvLyBydW4gb2YgdGhyZWUgb3IgbW9yZSBub24tYnVzaW5lc3MgZGF5cyBtYXJrcyBldmVyeSBkYXRlIGl0IGNvbnRhaW5zLgogICAgbGV0IExvbmdXZWVrZW5kRGF0ZXMgPSB0b3NjYWxhcigKICAgICAgICBZZWFyQ2FsZW5kYXIKICAgICAgICB8IG9yZGVyIGJ5IF9DYWxEYXkgYXNjCiAgICAgICAgfCBleHRlbmQgX0J1c2luZXNzUnVuSWQgPSByb3dfY3Vtc3VtKHRvaW50KF9DYWxJc0J1c2luZXNzRGF5KSkKICAgICAgICB8IHdoZXJlIG5vdChfQ2FsSXNCdXNpbmVzc0RheSkKICAgICAgICB8IHN1bW1hcml6ZSBfUnVuTGVuZ3RoID0gY291bnQoKSwgX1J1bkRhdGVzID0gbWFrZV9saXN0KF9DYWxLZXkpIGJ5IF9CdXNpbmVzc1J1bklkCiAgICAgICAgfCB3aGVyZSBfUnVuTGVuZ3RoID49IDMKICAgICAgICB8IG12LWV4cGFuZCBfUnVuRGF0ZSA9IF9SdW5EYXRlcyB0byB0eXBlb2Yoc3RyaW5nKQogICAgICAgIHwgc3VtbWFyaXplIExvbmdXZWVrZW5kU2V0ID0gbWFrZV9zZXQoX1J1bkRhdGUpCiAgICApOwogICAgLy8gTm90ZSA5OiBQcm9jZXNzaW5nIHN0YXJ0cyB3aXRoIHRoZSBCcm9uemUgcm93cyBzdXBwbGllZCB0byB0aGlzIGZ1bmN0aW9uLgogICAgRGVwb3NpdE1vdmVtZW50CiAgICAvLyBOb3RlIDliOiBOb3JtYWxpemUgQ2hhbm5lbCAtIHNvdXJjZSBjYW4gY2FycnkgbGVhZGluZy90cmFpbGluZyB3aGl0ZXNwYWNlLAogICAgLy8gd2hpY2ggYnJlYWtzIGV4YWN0IG1hdGNoZXMgKE1TWUcvU1lTRyBleGNsdXNpb24sIElzUmV0YWlsLCBDaGFubmVsX0dyb3VwKS4KICAgIHwgZXh0ZW5kIENoYW5uZWwgPSB0cmltKEAiXHMiLCB0b3N0cmluZyhDaGFubmVsKSkKICAgIC8vIE5vdGUgMTA6IERhdGUgaXMgaW50ZXJwcmV0ZWQgYXMgQmFuZ2tvayBsb2NhbCBjYWxlbmRhciB0aW1lLiBUaW1lIHN0b3JlcwogICAgLy8gYW4gaW50ZXJ2YWwsIHNvIG9ubHkgaXRzIEhIOm1tIHN0YXJ0IHZhbHVlIGlzIGV4dHJhY3RlZCBmb3IgY2xhc3NpZmljYXRpb24uCiAgICB8IGV4dGVuZAogICAgICAgIExvY2FsRGF0ZSA9IHN0YXJ0b2ZkYXkoRGF0ZSksCiAgICAgICAgX1RpbWVTdGFydFRleHQgPSBleHRyYWN0KEAiXihbMC05XXsyfTpbMC05XXsyfSktWzAtOV17Mn06WzAtOV17Mn0kIiwgMSwgVGltZSkKICAgIC8vIE5vdGUgMTE6IEFwcGVuZGluZyBzZWNvbmRzIGNvbnZlcnRzIEhIOm1tIGludG8gYSB0aW1lc3BhbiB0aGF0IGNhbiBiZQogICAgLy8gY29tcGFyZWQgd2l0aCB0aGUgU3RhcnRUaW1lIGFuZCBFbmRUaW1lIHZhbHVlcyBmcm9tIHRoZSB3aW5kb3cgcmVmZXJlbmNlLgogICAgfCBleHRlbmQgTG9jYWxUaW1lT2ZEYXkgPSB0b3RpbWVzcGFuKHN0cmNhdChfVGltZVN0YXJ0VGV4dCwgIjowMCIpKQogICAgfCBleHRlbmQgTG9jYWxEYXRlVGltZSA9IExvY2FsRGF0ZSArIExvY2FsVGltZU9mRGF5CiAgICAvLyBOb3RlIDEyOiBLUUwgZGF5b2Z3ZWVrIHJldHVybnMgU3VuZGF5IGFzIDBkIGFuZCBTYXR1cmRheSBhcyA2ZC4KICAgIHwgZXh0ZW5kCiAgICAgICAgSXNXZWVrZW5kID0gZGF5b2Z3ZWVrKExvY2FsRGF0ZSkgaW4gKDBkLCA2ZCksCiAgICAgICAgX0xvY2FsRGF0ZUtleSA9IGZvcm1hdF9kYXRldGltZShMb2NhbERhdGUsICJ5eXl5LU1NLWRkIikKICAgIC8vIE5vdGUgMTM6IFRoZSBkYXRlIGtleSBjaGVja3MgaG9saWRheSBtZW1iZXJzaGlwIGFuZCByZXRyaWV2ZXMgaXRzIG5hbWUKICAgIC8vIHdpdGhvdXQgam9pbmluZyBlYWNoIERlcG9zaXRNb3ZlbWVudCByb3cgdG8gdGhlIGhvbGlkYXkgdGFibGUuCiAgICB8IGV4dGVuZAogICAgICAgIElzRmluYW5jaWFsSW5zdGl0dXRpb25Ib2xpZGF5ID0gYmFnX2hhc19rZXkoSG9saWRheUJ5RGF0ZSwgX0xvY2FsRGF0ZUtleSksCiAgICAgICAgSG9saWRheU5hbWUgPSB0b3N0cmluZyhIb2xpZGF5QnlEYXRlW19Mb2NhbERhdGVLZXldKQogICAgLy8gTm90ZSAxNDogQSBidXNpbmVzcyBkYXkgbXVzdCBwYXNzIGJvdGggY2FsZW5kYXIgY2hlY2tzLiBPcGVyYXRpbmctd2luZG93CiAgICAvLyBhc3NpZ25tZW50IGlzIGluZGVwZW5kZW50IGFuZCBhcHBsaWVzIHRvIGV2ZXJ5IHZhbGlkIHNvdXJjZSByb3cuCiAgICB8IGV4dGVuZCBJc0J1c2luZXNzRGF5ID0gbm90KElzV2Vla2VuZCkKICAgICAgICBhbmQgbm90KElzRmluYW5jaWFsSW5zdGl0dXRpb25Ib2xpZGF5KQogICAgLy8gTm90ZSAxNTogV2Vla2VuZCBoYXMgcHJlY2VkZW5jZSB3aGVuIGEgZGF0ZSBpcyBib3RoIGEgd2Vla2VuZCBhbmQgYSBsaXN0ZWQKICAgIC8vIGhvbGlkYXk7IG90aGVyd2lzZSB0aGUgZGF0ZSBpcyBjbGFzc2lmaWVkIGFzIGhvbGlkYXkgb3IgYnVzaW5lc3MgZGF5LgogICAgfCBleHRlbmQgRGF5Q2xhc3NpZmljYXRpb24gPSBjYXNlKAogICAgICAgIElzV2Vla2VuZCwgIldFRUtFTkQiLAogICAgICAgIElzRmluYW5jaWFsSW5zdGl0dXRpb25Ib2xpZGF5LCAiSE9MSURBWSIsCiAgICAgICAgIkJVU0lORVNTX0RBWSIpCiAgICAvLyBtdi1hcHBseSBldmFsdWF0ZXMgYWxsIHJlZmVyZW5jZSByYW5nZXMgaW5zaWRlIGVhY2ggc291cmNlIHJvdy4gVGhlIHN1bW1hcml6ZQogICAgLy8gcmV0dXJucyBvbmUgcmVzdWx0IHBlciBpbnB1dCByb3csIGluY2x1ZGluZyBtYWxmb3JtZWQgb3IgdW5tYXRjaGVkIHJvd3MuCiAgICAvLyBOb3RlIDE2OiBXaW5kb3cgcmFuZ2VzIGFyZSBoYWxmLW9wZW4gW1N0YXJ0VGltZSwgRW5kVGltZSksIHNvIGEgYm91bmRhcnkKICAgIC8vIHRpbWUgYmVsb25ncyB0byB0aGUgd2luZG93IHRoYXQgc3RhcnRzIHRoZXJlIGFuZCBuZXZlciB0byB0aGUgcHJldmlvdXMgb25lLgogICAgfCBtdi1hcHBseSBfV2luZG93ID0gV2luZG93cyB0byB0eXBlb2YoZHluYW1pYykgb24gKAogICAgICAgIGV4dGVuZAogICAgICAgICAgICBfV2luZG93U3RhcnQgPSB0b3RpbWVzcGFuKF9XaW5kb3dbIlN0YXJ0VGltZSJdKSwKICAgICAgICAgICAgX1dpbmRvd0VuZCA9IHRvdGltZXNwYW4oX1dpbmRvd1siRW5kVGltZSJdKQogICAgICAgIHwgZXh0ZW5kIF9Jc1dpbmRvd01hdGNoID0KICAgICAgICAgICAgaXNub3RudWxsKExvY2FsVGltZU9mRGF5KQogICAgICAgICAgICBhbmQgTG9jYWxUaW1lT2ZEYXkgPj0gX1dpbmRvd1N0YXJ0CiAgICAgICAgICAgIGFuZCBMb2NhbFRpbWVPZkRheSA8IF9XaW5kb3dFbmQKICAgICAgICAvLyBOb3RlIDE3OiBDb3VudGluZyBtYXRjaGVzIGRldGVjdHMgbWlzc2luZyBhbmQgb3ZlcmxhcHBpbmcgcmVmZXJlbmNlCiAgICAgICAgLy8gd2luZG93cy4gVGhlIG1hdGNoaW5nIGRlZmluaXRpb25zIGFyZSByZXRhaW5lZCBmb3IgZmllbGQgZXh0cmFjdGlvbi4KICAgICAgICB8IHN1bW1hcml6ZQogICAgICAgICAgICBXaW5kb3dNYXRjaENvdW50ID0gY291bnRpZihfSXNXaW5kb3dNYXRjaCksCiAgICAgICAgICAgIF9NYXRjaGVkV2luZG93cyA9IG1ha2VfbGlzdF9pZihfV2luZG93LCBfSXNXaW5kb3dNYXRjaCkKICAgICkKICAgIC8vIE5vdGUgMTg6IEluZGV4IHplcm8gaXMgc2FmZSB0byBpbnNwZWN0IGFzIGEgZHluYW1pYyB2YWx1ZS4gT3V0cHV0IHdpbmRvdwogICAgLy8gZmllbGRzIGFyZSBwb3B1bGF0ZWQgb25seSB3aGVuIGV4YWN0bHkgb25lIGRlZmluaXRpb24gbWF0Y2hlZC4KICAgIHwgZXh0ZW5kIF9NYXRjaGVkV2luZG93ID0gX01hdGNoZWRXaW5kb3dzWzBdCiAgICB8IGV4dGVuZAogICAgICAgIE9wZXJhdGluZ1dpbmRvd0NvZGUgPSBpZmYoV2luZG93TWF0Y2hDb3VudCA9PSAxLCB0b3N0cmluZyhfTWF0Y2hlZFdpbmRvd1siV2luZG93Q29kZSJdKSwgIiIpLAogICAgICAgIE9wZXJhdGluZ1dpbmRvd05hbWUgPSBpZmYoV2luZG93TWF0Y2hDb3VudCA9PSAxLCB0b3N0cmluZyhfTWF0Y2hlZFdpbmRvd1siV2luZG93TmFtZSJdKSwgIiIpLAogICAgICAgIE9wZXJhdGluZ1dpbmRvd1N0YXJ0VGltZSA9IGlmZihXaW5kb3dNYXRjaENvdW50ID09IDEsIHRvdGltZXNwYW4oX01hdGNoZWRXaW5kb3dbIlN0YXJ0VGltZSJdKSwgdGltZXNwYW4obnVsbCkpLAogICAgICAgIE9wZXJhdGluZ1dpbmRvd0VuZFRpbWUgPSBpZmYoV2luZG93TWF0Y2hDb3VudCA9PSAxLCB0b3RpbWVzcGFuKF9NYXRjaGVkV2luZG93WyJFbmRUaW1lIl0pLCB0aW1lc3BhbihudWxsKSksCiAgICAgICAgT3BlcmF0aW5nV2luZG93U29ydE9yZGVyID0gaWZmKFdpbmRvd01hdGNoQ291bnQgPT0gMSwgdG9pbnQoX01hdGNoZWRXaW5kb3dbIlNvcnRPcmRlciJdKSwgaW50KG51bGwpKSwKICAgICAgICAvLyBOb3RlIDE5OiBTdGF0dXMgcHJlY2VkZW5jZSByZXBvcnRzIG1hbGZvcm1lZCB0aW1lIGZpcnN0LCBmb2xsb3dlZCBieQogICAgICAgIC8vIG1pc3Npbmcgb3Igb3ZlcmxhcHBpbmcgd2luZG93IGRlZmluaXRpb25zIGZvciBldmVyeSBkYXkgY2xhc3NpZmljYXRpb24uCiAgICAgICAgQ2xhc3NpZmljYXRpb25TdGF0dXMgPSBjYXNlKAogICAgICAgICAgICBpc2VtcHR5KF9UaW1lU3RhcnRUZXh0KSwgIklOVkFMSURfVElNRV9GT1JNQVQiLAogICAgICAgICAgICBXaW5kb3dNYXRjaENvdW50ID09IDAsICJOT19XSU5ET1dfTUFUQ0giLAogICAgICAgICAgICBXaW5kb3dNYXRjaENvdW50ID4gMSwgIk1VTFRJUExFX1dJTkRPV19NQVRDSEVTIiwKICAgICAgICAgICAgIkNMQVNTSUZJRUQiKQogICAgLy8gTm90ZSAxOWI6IEV2ZW50IGZsYWdzIG1hcmsgY2FsZW5kYXIgZXZlbnRzIHRoYXQgc2hpZnQgZGVwb3NpdCBiZWhhdmlvdXIuCiAgICAvLyBNb250aC1lbmQgaXMgdGhlIGxhc3QgY2FsZW5kYXIgZGF5OyBwYXlyb2xsIGFuZCBsb25nLXdlZWtlbmQgbWVtYmVyc2hpcAogICAgLy8gY29tZSBmcm9tIHRoZSBwcmUtY29tcHV0ZWQgc2V0cy4gRXZlbnRGbGFnIGpvaW5zIHRoZSBhY3RpdmUgZXZlbnRzIHdpdGggYQogICAgLy8gY29tbWEsIG9yIHJlcG9ydHMgTk9STUFMIHdoZW4gbm9uZSBhcHBseS4KICAgIHwgZXh0ZW5kCiAgICAgICAgSXNNb250aEVuZCA9IExvY2FsRGF0ZSA9PSBzdGFydG9mZGF5KGVuZG9mbW9udGgoTG9jYWxEYXRlKSksCiAgICAgICAgSXNQYXlyb2xsID0gc2V0X2hhc19lbGVtZW50KFBheXJvbGxEYXRlcywgX0xvY2FsRGF0ZUtleSksCiAgICAgICAgSXNMb25nV2Vla2VuZCA9IHNldF9oYXNfZWxlbWVudChMb25nV2Vla2VuZERhdGVzLCBfTG9jYWxEYXRlS2V5KQogICAgfCBleHRlbmQgX0V2ZW50TGlzdCA9IHNldF9kaWZmZXJlbmNlKHBhY2tfYXJyYXkoCiAgICAgICAgICAgIGlmZihJc01vbnRoRW5kLCAiTU9OVEhfRU5EIiwgIiIpLAogICAgICAgICAgICBpZmYoSXNQYXlyb2xsLCAiUEFZUk9MTCIsICIiKSwKICAgICAgICAgICAgaWZmKElzTG9uZ1dlZWtlbmQsICJMT05HX1dFRUtFTkQiLCAiIikpLCBkeW5hbWljKFsiIl0pKQogICAgfCBleHRlbmQgRXZlbnRGbGFnID0gaWZmKGFycmF5X2xlbmd0aChfRXZlbnRMaXN0KSA9PSAwLCAiTk9STUFMIiwgc3RyY2F0X2FycmF5KF9FdmVudExpc3QsICIsIikpCiAgICAvLyBOb3RlIDIwOiBUaGUgZmluYWwgcHJvamVjdGlvbiByZW1vdmVzIHRlbXBvcmFyeSB1bmRlcnNjb3JlLXByZWZpeGVkIGZpZWxkcwogICAgLy8gYW5kIGZpeGVzIHRoZSBleGFjdCBjb2x1bW4gb3JkZXIgcmVxdWlyZWQgYnkgRGVwb3NpdE1vdmVtZW50Q2xhc3NpZmllZC4KICAgIHwgcHJvamVjdAogICAgICAgIERhdGUsIFRpbWUsIFByb2R1Y3QsIENoYW5uZWwsIENoYW5uZWxfR3JvdXAsCiAgICAgICAgQ3JlZGl0X0Ftb3VudCwgRGViaXRfQW1vdW50LCBOZXRfQW1vdW50LAogICAgICAgIENyZWRpdF9UcmFuc2FjdGlvbiwgRGViaXRfVHJhbnNhY3Rpb24sIFRvdGFsX1RyYW5zYWN0aW9uLAogICAgICAgIGxvYWRfdHMsIGZpbGVfbmFtZSwgcGlwZWxpbmVfbmFtZSwgcGlwZWxpbmVfcnVuaWQsCiAgICAgICAgTG9jYWxEYXRlLCBMb2NhbERhdGVUaW1lLCBMb2NhbFRpbWVPZkRheSwKICAgICAgICBJc1dlZWtlbmQsIElzRmluYW5jaWFsSW5zdGl0dXRpb25Ib2xpZGF5LCBJc0J1c2luZXNzRGF5LAogICAgICAgIERheUNsYXNzaWZpY2F0aW9uLCBIb2xpZGF5TmFtZSwKICAgICAgICBPcGVyYXRpbmdXaW5kb3dDb2RlLCBPcGVyYXRpbmdXaW5kb3dOYW1lLAogICAgICAgIE9wZXJhdGluZ1dpbmRvd1N0YXJ0VGltZSwgT3BlcmF0aW5nV2luZG93RW5kVGltZSwgT3BlcmF0aW5nV2luZG93U29ydE9yZGVyLAogICAgICAgIFdpbmRvd01hdGNoQ291bnQsIENsYXNzaWZpY2F0aW9uU3RhdHVzLAogICAgICAgIElzTW9udGhFbmQsIElzUGF5cm9sbCwgSXNMb25nV2Vla2VuZCwgRXZlbnRGbGFnCn0=')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.25 - Validate Silver Transformation Version

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Silver Transformation Version |
| Incoming dependency | Check Silver Transformation Version [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Check Silver Transformation Version').output.count),0)
```

**True branch:** open this branch and add its activities below.

### 6.25-True.1 - Validate Silver Transformation Version Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Silver Transformation Version > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Silver Transformation Version Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
Silver transformation changed since deployment. Regenerate the CR01 preview.
```

**False branch:** leave empty.

### 6.26 - Preview Existing Silver Classification

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Preview Existing Silver Classification |
| Incoming dependency | Validate Silver Transformation Version [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.create-or-alter function CR01Test_06622392_CR01_PreviewSilver(SourceRows:(Date:datetime,Time:string,Product:string,Channel:string,Channel_Group:string,Credit_Amount:decimal,Debit_Amount:decimal,Net_Amount:decimal,Credit_Transaction:long,Debit_Transaction:long,Total_Transaction:long,load_ts:datetime,file_name:string,pipeline_name:string,pipeline_runid:string)) {
    // Note 1: The function has no parameters because the update policy supplies
    // the newly ingested rows through the SourceRows source table below.
    //
    // Note 2: Reference tables are reduced to scalar dynamic values once per
    // function execution, then reused while every source row is classified.
    // A scalar property bag avoids a join in the update-policy query. Fabric
    // otherwise requires streaming ingestion to be disabled on the source table.
    //
    // Note 3: These boundaries form [January 1 this year, January 1 next year).
    // The half-open range includes every instant in the current execution year.
    let CurrentYearStart = startofyear(now());
    let NextYearStart = datetime_add("year", 1, CurrentYearStart);
    // Note 3b: The event-flag calendar spans a small pad on each side of the year
    // so long-weekend runs and payroll shifts that cross the boundary resolve
    // correctly. Padded dates outside the current year are never emitted.
    let CalendarStart = datetime_add("day", -3, CurrentYearStart);
    let CalendarEnd = datetime_add("day", 3, NextYearStart);
    // Note 4: HolidayByDate becomes a property bag such as
    // {"2026-01-01":"New Year's Day"}, enabling a lookup by local date key.
    let HolidayByDate = toscalar(
        ThailandFinancialInstitutionHoliday
        // Note 5: Filter before summarize so holidays outside the current year
        // do not consume aggregation memory or participate in classification.
        | where HolidayDate >= CalendarStart
            and HolidayDate < CalendarEnd
        // Note 6: Normalize timestamps to dates and choose one deterministic
        // name if the reference table contains duplicate rows for the same day.
        | summarize HolidayName = min(HolidayName)
            by HolidayDate = startofday(HolidayDate)
        | extend HolidayDateKey = format_datetime(HolidayDate, "yyyy-MM-dd")
        // Note 7: make_bag creates the date-to-name dictionary used later by
        // bag_has_key and indexed lookup operations.
        | summarize Holidays = make_bag(bag_pack(HolidayDateKey, HolidayName))
    );
    // Note 8: Windows becomes one ordered dynamic array containing all operating
    // window definitions. SortOrder keeps the reference-table sequence stable.
    let Windows = toscalar(
        OperatingWindowsTimes
        | order by SortOrder asc
        | summarize WindowDefinitions = make_list(pack(
            "WindowCode", WindowCode,
            "WindowName", WindowName,
            "StartTime", StartTime,
            "EndTime", EndTime,
            "SortOrder", SortOrder))
    );
    // Note 8b: YearCalendar enumerates every local date in the padded year and
    // flags weekends and holidays so business days can be derived deterministically.
    let YearCalendar =
        range _CalDay from CalendarStart to datetime_add("day", -1, CalendarEnd) step 1d
        | extend _CalKey = format_datetime(_CalDay, "yyyy-MM-dd")
        | extend _CalIsWeekend = dayofweek(_CalDay) in (0d, 6d)
        | extend _CalIsHoliday = bag_has_key(HolidayByDate, _CalKey)
        | extend _CalIsBusinessDay = not(_CalIsWeekend) and not(_CalIsHoliday);
    // Note 8c: PayrollDates resolves each scheduled payday (the 25th and the last
    // calendar day of the month) backward to the previous business day when it
    // falls on a weekend or holiday, then keeps the effective dates as a set.
    let PayrollDates = toscalar(
        YearCalendar
        | where dayofmonth(_CalDay) == 25 or _CalDay == startofday(endofmonth(_CalDay))
        | project _AnchorDate = _CalDay
        | mv-expand _Offset = range(0, 14, 1) to typeof(long)
        | extend _Candidate = datetime_add("day", -_Offset, _AnchorDate)
        | extend _CandKey = format_datetime(_Candidate, "yyyy-MM-dd")
        | extend _CandIsBusinessDay =
            not(dayofweek(_Candidate) in (0d, 6d))
            and not(bag_has_key(HolidayByDate, _CandKey))
        | where _CandIsBusinessDay
        | summarize arg_min(_Offset, _Candidate) by _AnchorDate
        | summarize PayrollSet = make_set(format_datetime(_Candidate, "yyyy-MM-dd"))
    );
    // Note 8d: LongWeekendDates finds maximal runs of consecutive non-business
    // days. A running count of business days holds one id across each gap, so a
    // run of three or more non-business days marks every date it contains.
    let LongWeekendDates = toscalar(
        YearCalendar
        | order by _CalDay asc
        | extend _BusinessRunId = row_cumsum(toint(_CalIsBusinessDay))
        | where not(_CalIsBusinessDay)
        | summarize _RunLength = count(), _RunDates = make_list(_CalKey) by _BusinessRunId
        | where _RunLength >= 3
        | mv-expand _RunDate = _RunDates to typeof(string)
        | summarize LongWeekendSet = make_set(_RunDate)
    );
    // Note 9: Processing starts with the Bronze rows supplied to this function.
    SourceRows
    // Note 9b: Normalize Channel - source can carry leading/trailing whitespace,
    // which breaks exact matches (MSYG/SYSG exclusion, IsRetail, Channel_Group).
    | extend Channel = trim(@"\s", tostring(Channel))
    // Note 10: Date is interpreted as Bangkok local calendar time. Time stores
    // an interval, so only its HH:mm start value is extracted for classification.
    | extend
        LocalDate = startofday(Date),
        _TimeStartText = extract(@"^([0-9]{2}:[0-9]{2})-[0-9]{2}:[0-9]{2}$", 1, Time)
    // Note 11: Appending seconds converts HH:mm into a timespan that can be
    // compared with the StartTime and EndTime values from the window reference.
    | extend LocalTimeOfDay = totimespan(strcat(_TimeStartText, ":00"))
    | extend LocalDateTime = LocalDate + LocalTimeOfDay
    // Note 12: KQL dayofweek returns Sunday as 0d and Saturday as 6d.
    | extend
        IsWeekend = dayofweek(LocalDate) in (0d, 6d),
        _LocalDateKey = format_datetime(LocalDate, "yyyy-MM-dd")
    // Note 13: The date key checks holiday membership and retrieves its name
    // without joining each SourceRows row to the holiday table.
    | extend
        IsFinancialInstitutionHoliday = bag_has_key(HolidayByDate, _LocalDateKey),
        HolidayName = tostring(HolidayByDate[_LocalDateKey])
    // Note 14: A business day must pass both calendar checks. Operating-window
    // assignment is independent and applies to every valid source row.
    | extend IsBusinessDay = not(IsWeekend)
        and not(IsFinancialInstitutionHoliday)
    // Note 15: Weekend has precedence when a date is both a weekend and a listed
    // holiday; otherwise the date is classified as holiday or business day.
    | extend DayClassification = case(
        IsWeekend, "WEEKEND",
        IsFinancialInstitutionHoliday, "HOLIDAY",
        "BUSINESS_DAY")
    // mv-apply evaluates all reference ranges inside each source row. The summarize
    // returns one result per input row, including malformed or unmatched rows.
    // Note 16: Window ranges are half-open [StartTime, EndTime), so a boundary
    // time belongs to the window that starts there and never to the previous one.
    | mv-apply _Window = Windows to typeof(dynamic) on (
        extend
            _WindowStart = totimespan(_Window["StartTime"]),
            _WindowEnd = totimespan(_Window["EndTime"])
        | extend _IsWindowMatch =
            isnotnull(LocalTimeOfDay)
            and LocalTimeOfDay >= _WindowStart
            and LocalTimeOfDay < _WindowEnd
        // Note 17: Counting matches detects missing and overlapping reference
        // windows. The matching definitions are retained for field extraction.
        | summarize
            WindowMatchCount = countif(_IsWindowMatch),
            _MatchedWindows = make_list_if(_Window, _IsWindowMatch)
    )
    // Note 18: Index zero is safe to inspect as a dynamic value. Output window
    // fields are populated only when exactly one definition matched.
    | extend _MatchedWindow = _MatchedWindows[0]
    | extend
        OperatingWindowCode = iff(WindowMatchCount == 1, tostring(_MatchedWindow["WindowCode"]), ""),
        OperatingWindowName = iff(WindowMatchCount == 1, tostring(_MatchedWindow["WindowName"]), ""),
        OperatingWindowStartTime = iff(WindowMatchCount == 1, totimespan(_MatchedWindow["StartTime"]), timespan(null)),
        OperatingWindowEndTime = iff(WindowMatchCount == 1, totimespan(_MatchedWindow["EndTime"]), timespan(null)),
        OperatingWindowSortOrder = iff(WindowMatchCount == 1, toint(_MatchedWindow["SortOrder"]), int(null)),
        // Note 19: Status precedence reports malformed time first, followed by
        // missing or overlapping window definitions for every day classification.
        ClassificationStatus = case(
            isempty(_TimeStartText), "INVALID_TIME_FORMAT",
            WindowMatchCount == 0, "NO_WINDOW_MATCH",
            WindowMatchCount > 1, "MULTIPLE_WINDOW_MATCHES",
            "CLASSIFIED")
    // Note 19b: Event flags mark calendar events that shift deposit behaviour.
    // Month-end is the last calendar day; payroll and long-weekend membership
    // come from the pre-computed sets. EventFlag joins the active events with a
    // comma, or reports NORMAL when none apply.
    | extend
        IsMonthEnd = LocalDate == startofday(endofmonth(LocalDate)),
        IsPayroll = set_has_element(PayrollDates, _LocalDateKey),
        IsLongWeekend = set_has_element(LongWeekendDates, _LocalDateKey)
    | extend _EventList = set_difference(pack_array(
            iff(IsMonthEnd, "MONTH_END", ""),
            iff(IsPayroll, "PAYROLL", ""),
            iff(IsLongWeekend, "LONG_WEEKEND", "")), dynamic([""]))
    | extend EventFlag = iff(array_length(_EventList) == 0, "NORMAL", strcat_array(_EventList, ","))
    // Note 20: The final projection removes temporary underscore-prefixed fields
    // and fixes the exact column order required by CR01Test_06622392_DepositMovementClassified.
    | project
        Date, Time, Product, Channel, Channel_Group,
        Credit_Amount, Debit_Amount, Net_Amount,
        Credit_Transaction, Debit_Transaction, Total_Transaction,
        load_ts, file_name, pipeline_name, pipeline_runid,
        LocalDate, LocalDateTime, LocalTimeOfDay,
        IsWeekend, IsFinancialInstitutionHoliday, IsBusinessDay,
        DayClassification, HolidayName,
        OperatingWindowCode, OperatingWindowName,
        OperatingWindowStartTime, OperatingWindowEndTime, OperatingWindowSortOrder,
        WindowMatchCount, ClassificationStatus,
        IsMonthEnd, IsPayroll, IsLongWeekend, EventFlag
}
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.27 - Compute Preview Calendar Classification

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Preview Calendar Classification |
| Incoming dependency | Preview Existing Silver Classification [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-replace CR01Test_06622392_CR01_Checks <| let preview=CR01Test_06622392_CR01_PreviewSilver(CR01Test_06622392_CR01_Stage_20261118);
let holidayDates=toscalar(ThailandFinancialInstitutionHoliday | summarize make_set(format_datetime(HolidayDate,'yyyy-MM-dd')));
let knownYears=toscalar(ThailandFinancialInstitutionHoliday | summarize make_set(getyear(HolidayDate)));
union
    (preview | where ClassificationStatus!='CLASSIFIED' | project Problem=strcat(file_name,' ',ClassificationStatus)),
    (preview | where IsFinancialInstitutionHoliday!=set_has_element(holidayDates,format_datetime(LocalDate,'yyyy-MM-dd'))
        | project Problem=strcat(file_name,' holiday classification disagrees with reference')),
    (CR01Test_06622392_CR01_Stage_20261118 | distinct Year=getyear(Date) | where not(set_has_element(knownYears,Year))
        | project Problem=strcat('Holiday reference year missing: ',Year)),
    (print StageRows=toscalar(CR01Test_06622392_CR01_Stage_20261118 | count),PreviewRows=toscalar(preview | count)
        | where StageRows!=PreviewRows | project Problem='Silver preview is not row preserving')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.28 - Validate Preview Calendar Classification

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Preview Calendar Classification |
| Incoming dependency | Compute Preview Calendar Classification [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Preview Calendar Classification').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 6.28-True.1 - Validate Preview Calendar Classification Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Preview Calendar Classification > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Preview Calendar Classification Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Preview Calendar Classification has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 6.29 - Compute Loaded File Coverage

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Loaded File Coverage |
| Incoming dependency | Validate Preview Calendar Classification [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-replace CR01Test_06622392_CR01_Checks <| let names=toscalar(print items=parse_json(base64_decode_tostring("W3siRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE3XzIzMDBfMjMzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9LHsiRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE4XzAwMDBfMDAzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9XQ=="))
    | mv-expand items | summarize make_set(tostring(items.FileName)));
union (CR01Test_06622392_DepositMovement | project file_name), (CR01Test_06622392_DepositMovementClassified | project file_name)
| where file_name startswith strcat('INTRADAY_SUMMARY_',format_datetime(datetime(2026-11-18)-1d,'yyyyMMdd'))
    or file_name startswith strcat('INTRADAY_SUMMARY_',format_datetime(datetime(2026-11-18),'yyyyMMdd'))
| extend t=toint(extract(@"^INTRADAY_SUMMARY_\d{8}_(\d{4})_",1,file_name)),
    d=extract(@"^INTRADAY_SUMMARY_(\d{8})_",1,file_name)
| where isnull(t) or (d==format_datetime(datetime(2026-11-18)-1d,'yyyyMMdd') and t>=2230)
    or (d==format_datetime(datetime(2026-11-18),'yyyyMMdd') and t<330)
| where file_name !in (names)
| distinct Problem=strcat(file_name,' is loaded but absent from the frozen manifest')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.30 - Validate Loaded File Coverage

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Loaded File Coverage |
| Incoming dependency | Compute Loaded File Coverage [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Loaded File Coverage').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 6.30-True.1 - Validate Loaded File Coverage Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Loaded File Coverage > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Loaded File Coverage Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Loaded File Coverage has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 6.31 - Read Existing Gold Views

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Read Existing Gold Views |
| Incoming dependency | Validate Loaded File Coverage [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.show materialized-views | where Name in ("CR01Test_06622392_mv_Summary_Product_Channel_Alert","CR01Test_06622392_mv_EarlyWarning_Base") | project Name,Query,SourceTable
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.32 - Check Existing Gold Definitions

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Check Existing Gold Definitions |
| Incoming dependency | Read Existing Gold Views [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.show materialized-views | where SourceTable in ('CR01Test_06622392_DepositMovement','CR01Test_06622392_DepositMovementClassified') | summarize Present=count(),Mismatch=countif(Name !in ("CR01Test_06622392_mv_Summary_Product_Channel_Alert","CR01Test_06622392_mv_EarlyWarning_Base") or (Name=='CR01Test_06622392_mv_Summary_Product_Channel_Alert' and Query!=base64_decode_tostring('Q1IwMVRlc3RfMDY2MjIzOTJfRGVwb3NpdE1vdmVtZW50DQogICAgfCBzdW1tYXJpemUNCiAgICAgICAgVGltZSAgICAgICAgICAgICAgID0gbWF4KFRpbWUpLA0KICAgICAgICBDcmVkaXRfQW1vdW50ICAgICAgPSBzdW0oQ3JlZGl0X0Ftb3VudCksDQogICAgICAgIERlYml0X0Ftb3VudCAgICAgICA9IHN1bShEZWJpdF9BbW91bnQpLA0KICAgICAgICBOZXRfQW1vdW50ICAgICAgICAgPSBzdW0oTmV0X0Ftb3VudCksDQogICAgICAgIENyZWRpdF9UcmFuc2FjdGlvbiA9IHN1bShDcmVkaXRfVHJhbnNhY3Rpb24pLA0KICAgICAgICBEZWJpdF9UcmFuc2FjdGlvbiAgPSBzdW0oRGViaXRfVHJhbnNhY3Rpb24pLA0KICAgICAgICBUb3RhbF9UcmFuc2FjdGlvbiAgPSBzdW0oVG90YWxfVHJhbnNhY3Rpb24pLA0KICAgICAgICBVcGRhdGVkQXRVdGMgICAgICAgPSBtYXgobG9hZF90cykNCiAgICAgICAgYnkgRGF0ZSwgUHJvZHVjdCwgQ2hhbm5lbCwgQ2hhbm5lbF9Hcm91cA==')) or (Name=='CR01Test_06622392_mv_EarlyWarning_Base' and Query!=base64_decode_tostring('Q1IwMVRlc3RfMDY2MjIzOTJfRGVwb3NpdE1vdmVtZW50Q2xhc3NpZmllZAogICAgLy8gT25seSByb3dzIHdpdGggYSB2YWxpZCBsb2NhbCB0aW1lIGNhbiBmYWxsIGludG8gYSAzMC1taW51dGUgYnVja2V0LgogICAgfCB3aGVyZSBpc25vdG51bGwoTG9jYWxEYXRlVGltZSkKICAgIC8vIE1haW4gY29uZGl0aW9uICMxOiBleGNsdWRlIE1TWUcgLyBTWVNHIGZyb20gZXZlcnkgY2FsY3VsYXRpb24uCiAgICB8IHdoZXJlIENoYW5uZWwgIWluICgiTVNZRyIsICJTWVNHIikKICAgIHwgZXh0ZW5kCiAgICAgICAgSXNSZXRhaWwgICAgPSBDaGFubmVsIGluICgiRU5FVCIsICJBVE0iLCAiQ0RNIiksCiAgICAgICAgQnVja2V0U3RhcnQgPSBiaW4oTG9jYWxEYXRlVGltZSwgMzBtKQogICAgfCBzdW1tYXJpemUKICAgICAgICBHcm9zc091dGZsb3cgPSBzdW0oRGViaXRfQW1vdW50KSwKICAgICAgICBDcmVkaXQgICAgICAgPSBzdW0oQ3JlZGl0X0Ftb3VudCksCiAgICAgICAgTmV0ICAgICAgICAgID0gc3VtKE5ldF9BbW91bnQpLAogICAgICAgIERlYml0VHhuICAgICA9IHN1bShEZWJpdF9UcmFuc2FjdGlvbiksCiAgICAgICAgVXBkYXRlZEF0VXRjID0gbWF4KGxvYWRfdHMpCiAgICAgICAgYnkgTG9jYWxEYXRlLCBCdWNrZXRTdGFydCwgRGF5Q2xhc3NpZmljYXRpb24sIEV2ZW50RmxhZywKICAgICAgICAgICBJc01vbnRoRW5kLCBJc1BheXJvbGwsIElzTG9uZ1dlZWtlbmQsIElzUmV0YWls')) or IsEnabled!=true or AutoUpdateSchema!=false or isnotnull(Lookback) or Folder!='Gold' or DocString!='')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.33 - Validate Gold Baseline

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Gold Baseline |
| Incoming dependency | Check Existing Gold Definitions [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@or(not(equals(int(activity('Check Existing Gold Definitions').output.value[0].Present),2)),not(equals(int(activity('Check Existing Gold Definitions').output.value[0].Mismatch),0)))
```

**True branch:** open this branch and add its activities below.

### 6.33-True.1 - Validate Gold Baseline Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Gold Baseline > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Gold Baseline Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
Gold definitions changed since deployment. Regenerate and review the CR01 artifacts.
```

**False branch:** leave empty.

### 6.34 - Check retention mv_Summary_Product_Channel_Alert

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Check retention mv_Summary_Product_Channel_Alert |
| Incoming dependency | Validate Gold Baseline [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.show materialized-view CR01Test_06622392_mv_Summary_Product_Channel_Alert policy retention | where Policy!=base64_decode_tostring('bnVsbA==')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.35 - Validate retention mv_Summary_Product_Channel_Alert

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate retention mv_Summary_Product_Channel_Alert |
| Incoming dependency | Check retention mv_Summary_Product_Channel_Alert [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Check retention mv_Summary_Product_Channel_Alert').output.count),0)
```

**True branch:** open this branch and add its activities below.

### 6.35-True.1 - Validate retention mv_Summary_Product_Channel_Al Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate retention mv_Summary_Product_Channel_Alert > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate retention mv_Summary_Product_Channel_Al Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
A Gold policy changed since deployment. Stop and regenerate the restoration baseline.
```

**False branch:** leave empty.

### 6.36 - Check caching mv_Summary_Product_Channel_Alert

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Check caching mv_Summary_Product_Channel_Alert |
| Incoming dependency | Validate retention mv_Summary_Product_Channel_Alert [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.show materialized-view CR01Test_06622392_mv_Summary_Product_Channel_Alert policy caching | where Policy!=base64_decode_tostring('bnVsbA==')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.37 - Validate caching mv_Summary_Product_Channel_Alert

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate caching mv_Summary_Product_Channel_Alert |
| Incoming dependency | Check caching mv_Summary_Product_Channel_Alert [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Check caching mv_Summary_Product_Channel_Alert').output.count),0)
```

**True branch:** open this branch and add its activities below.

### 6.37-True.1 - Validate caching mv_Summary_Product_Channel_Aler Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate caching mv_Summary_Product_Channel_Alert > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate caching mv_Summary_Product_Channel_Aler Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
A Gold policy changed since deployment. Stop and regenerate the restoration baseline.
```

**False branch:** leave empty.

### 6.38 - Check retention mv_EarlyWarning_Base

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Check retention mv_EarlyWarning_Base |
| Incoming dependency | Validate caching mv_Summary_Product_Channel_Alert [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.show materialized-view CR01Test_06622392_mv_EarlyWarning_Base policy retention | where Policy!=base64_decode_tostring('bnVsbA==')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.39 - Validate retention mv_EarlyWarning_Base

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate retention mv_EarlyWarning_Base |
| Incoming dependency | Check retention mv_EarlyWarning_Base [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Check retention mv_EarlyWarning_Base').output.count),0)
```

**True branch:** open this branch and add its activities below.

### 6.39-True.1 - Validate retention mv_EarlyWarning_Base Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate retention mv_EarlyWarning_Base > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate retention mv_EarlyWarning_Base Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
A Gold policy changed since deployment. Stop and regenerate the restoration baseline.
```

**False branch:** leave empty.

### 6.40 - Check caching mv_EarlyWarning_Base

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Check caching mv_EarlyWarning_Base |
| Incoming dependency | Validate retention mv_EarlyWarning_Base [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.show materialized-view CR01Test_06622392_mv_EarlyWarning_Base policy caching | where Policy!=base64_decode_tostring('ew0KICAiRGF0YUhvdFNwYW4iOiB7DQogICAgIlZhbHVlIjogIjkwLjAwOjAwOjAwIg0KICB9LA0KICAiSW5kZXhIb3RTcGFuIjogew0KICAgICJWYWx1ZSI6ICI5MC4wMDowMDowMCINCiAgfQ0KfQ==')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.41 - Validate caching mv_EarlyWarning_Base

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate caching mv_EarlyWarning_Base |
| Incoming dependency | Check caching mv_EarlyWarning_Base [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Check caching mv_EarlyWarning_Base').output.count),0)
```

**True branch:** open this branch and add its activities below.

### 6.41-True.1 - Validate caching mv_EarlyWarning_Base Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate caching mv_EarlyWarning_Base > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate caching mv_EarlyWarning_Base Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
A Gold policy changed since deployment. Stop and regenerate the restoration baseline.
```

**False branch:** leave empty.

### 6.42 - Backup Target Bronze

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Backup Target Bronze |
| Incoming dependency | Validate caching mv_EarlyWarning_Base [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set CR01Test_06622392_CR01_BackupBronze_20261118 <| let names=toscalar(print items=parse_json(base64_decode_tostring("W3siRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE3XzIzMDBfMjMzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9LHsiRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE4XzAwMDBfMDAzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9XQ=="))
    | mv-expand items | summarize make_set(tostring(items.FileName))); CR01Test_06622392_DepositMovement | where file_name in (names)
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.43 - Backup Target Silver

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Backup Target Silver |
| Incoming dependency | Backup Target Bronze [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set CR01Test_06622392_CR01_BackupSilver_20261118 <| let names=toscalar(print items=parse_json(base64_decode_tostring("W3siRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE3XzIzMDBfMjMzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9LHsiRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE4XzAwMDBfMDAzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9XQ=="))
    | mv-expand items | summarize make_set(tostring(items.FileName))); CR01Test_06622392_DepositMovementClassified | where file_name in (names)
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.44 - Backup Both EWI Dates

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Backup Both EWI Dates |
| Incoming dependency | Backup Target Silver [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set CR01Test_06622392_CR01_BackupEwi_20261118 <| let names=toscalar(print items=parse_json(base64_decode_tostring("W3siRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE3XzIzMDBfMjMzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9LHsiRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE4XzAwMDBfMDAzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9XQ=="))
    | mv-expand items | summarize make_set(tostring(items.FileName))); CR01Test_06622392_DepositMovementEarlyWarning | where Date_ICT in (format_datetime(datetime(2026-11-18)-1d,'yyyy-MM-dd'),'2026-11-18')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.45 - Snapshot Unrelated DepositMovement

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Snapshot Unrelated DepositMovement |
| Incoming dependency | Backup Both EWI Dates [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set CR01Test_06622392_CR01_UnrelatedBronze_20261118 <| let names=toscalar(print items=parse_json(base64_decode_tostring("W3siRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE3XzIzMDBfMjMzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9LHsiRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE4XzAwMDBfMDAzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9XQ=="))
    | mv-expand items | summarize make_set(tostring(items.FileName))); CR01Test_06622392_DepositMovement | where file_name !in (names) | summarize Copies=count() by Fingerprint=hash_sha256(tostring(pack_array(Date,Time,Product,Channel,Channel_Group,Credit_Amount,Debit_Amount,Net_Amount,Credit_Transaction,Debit_Transaction,Total_Transaction,load_ts,file_name,pipeline_name,pipeline_runid)))
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.46 - Snapshot Unrelated DepositMovementClassified

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Snapshot Unrelated DepositMovementClassified |
| Incoming dependency | Snapshot Unrelated DepositMovement [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set CR01Test_06622392_CR01_UnrelatedSilver_20261118 <| let names=toscalar(print items=parse_json(base64_decode_tostring("W3siRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE3XzIzMDBfMjMzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9LHsiRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE4XzAwMDBfMDAzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9XQ=="))
    | mv-expand items | summarize make_set(tostring(items.FileName))); CR01Test_06622392_DepositMovementClassified | where file_name !in (names) | summarize Copies=count() by Fingerprint=hash_sha256(tostring(pack_array(Date,Time,Product,Channel,Channel_Group,Credit_Amount,Debit_Amount,Net_Amount,Credit_Transaction,Debit_Transaction,Total_Transaction,load_ts,file_name,pipeline_name,pipeline_runid,LocalDate,LocalDateTime,LocalTimeOfDay,IsWeekend,IsFinancialInstitutionHoliday,IsBusinessDay,DayClassification,HolidayName,OperatingWindowCode,OperatingWindowName,OperatingWindowStartTime,OperatingWindowEndTime,OperatingWindowSortOrder,WindowMatchCount,ClassificationStatus,IsMonthEnd,IsPayroll,IsLongWeekend,EventFlag)))
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.47 - Hold Serving Visibility

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Hold Serving Visibility |
| Incoming dependency | Snapshot Unrelated DepositMovementClassified [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-append CR01Test_06622392_CR01_PublishState <| print IsReady=false, ChangedAtUtc=now(), Owner='63ebb1ad-068d-47a1-b6ad-d0c4aff54892'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.48 - Drop mv_Summary_Product_Channel_Alert

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Drop mv_Summary_Product_Channel_Alert |
| Incoming dependency | Hold Serving Visibility [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.drop materialized-view CR01Test_06622392_mv_Summary_Product_Channel_Alert
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.49 - Drop mv_EarlyWarning_Base

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Drop mv_EarlyWarning_Base |
| Incoming dependency | Drop mv_Summary_Product_Channel_Alert [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.drop materialized-view CR01Test_06622392_mv_EarlyWarning_Base
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.50 - Delete Only Manifest Bronze

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Delete Only Manifest Bronze |
| Incoming dependency | Drop mv_EarlyWarning_Base [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.delete table CR01Test_06622392_DepositMovement records <| CR01Test_06622392_DepositMovement | where file_name in ("INTRADAY_SUMMARY_20261117_2300_2330.CSV","INTRADAY_SUMMARY_20261118_0000_0030.CSV")
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.51 - Delete Only Manifest Silver

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Delete Only Manifest Silver |
| Incoming dependency | Delete Only Manifest Bronze [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.delete table CR01Test_06622392_DepositMovementClassified records <| CR01Test_06622392_DepositMovementClassified | where file_name in ("INTRADAY_SUMMARY_20261117_2300_2330.CSV","INTRADAY_SUMMARY_20261118_0000_0030.CSV")
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.52 - Compute Empty Replacement Scope

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Empty Replacement Scope |
| Incoming dependency | Delete Only Manifest Silver [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-replace CR01Test_06622392_CR01_Checks <| let names=toscalar(print items=parse_json(base64_decode_tostring("W3siRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE3XzIzMDBfMjMzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9LHsiRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE4XzAwMDBfMDAzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9XQ=="))
    | mv-expand items | summarize make_set(tostring(items.FileName))); union (CR01Test_06622392_DepositMovement | project file_name),(CR01Test_06622392_DepositMovementClassified | project file_name) | where file_name in (names) | project Problem=file_name
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.53 - Validate Empty Replacement Scope

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Empty Replacement Scope |
| Incoming dependency | Compute Empty Replacement Scope [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Empty Replacement Scope').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 6.53-True.1 - Validate Empty Replacement Scope Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Empty Replacement Scope > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Empty Replacement Scope Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Empty Replacement Scope has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 6.54 - Promote Frozen Overnight Snapshot

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Promote Frozen Overnight Snapshot |
| Incoming dependency | Validate Empty Replacement Scope [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-append CR01Test_06622392_DepositMovement <| CR01Test_06622392_CR01_Stage_20261118
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.55 - Wait For Bronze And Silver

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Until |
| General > Name (exact) | Wait For Bronze And Silver |
| Incoming dependency | Promote Frozen Overnight Snapshot [Succeeded] |

**Settings > Expression (exit condition)** - use Add dynamic content.

```text
@equals(int(activity('Compute Replayed Row Mismatches').output.count),0)
```

**Settings > Timeout** - literal value; do not add an expression wrapper.

```text
0.00:30:00
```

Open the Activities canvas inside Until. The condition is evaluated after an iteration; retain the Wait activity.

### 6.55.1 - Compute Replayed Row Mismatches

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Wait For Bronze And Silver > Activities |
| Activity to select | KQL |
| General > Name (exact) | Compute Replayed Row Mismatches |
| Incoming dependency | None inside this canvas/branch |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-replace CR01Test_06622392_CR01_Checks <| let names=toscalar(print items=parse_json(base64_decode_tostring("W3siRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE3XzIzMDBfMjMzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9LHsiRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE4XzAwMDBfMDAzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9XQ=="))
    | mv-expand items | summarize make_set(tostring(items.FileName))); union (CR01Test_06622392_CR01_Stage_20261118 | summarize Expected=count() by file_name,Fingerprint=tostring(pack_array(Date,Time,Product,trim(@"\s",Channel),Channel_Group,Credit_Amount,Debit_Amount,Net_Amount,Credit_Transaction,Debit_Transaction,Total_Transaction)) | join kind=fullouter (CR01Test_06622392_DepositMovement | where file_name in (names) | summarize Actual=count() by file_name,Fingerprint=tostring(pack_array(Date,Time,Product,trim(@"\s",Channel),Channel_Group,Credit_Amount,Debit_Amount,Net_Amount,Credit_Transaction,Debit_Transaction,Total_Transaction))) on file_name,Fingerprint | where coalesce(Expected,0)!=coalesce(Actual,0) | project Problem=strcat('CR01Test_06622392_DepositMovement ',file_name,' business-row mismatch')),(CR01Test_06622392_CR01_Stage_20261118 | summarize Expected=count() by file_name,Fingerprint=tostring(pack_array(Date,Time,Product,trim(@"\s",Channel),Channel_Group,Credit_Amount,Debit_Amount,Net_Amount,Credit_Transaction,Debit_Transaction,Total_Transaction)) | join kind=fullouter (CR01Test_06622392_DepositMovementClassified | where file_name in (names) | summarize Actual=count() by file_name,Fingerprint=tostring(pack_array(Date,Time,Product,trim(@"\s",Channel),Channel_Group,Credit_Amount,Debit_Amount,Net_Amount,Credit_Transaction,Debit_Transaction,Total_Transaction))) on file_name,Fingerprint | where coalesce(Expected,0)!=coalesce(Actual,0) | project Problem=strcat('CR01Test_06622392_DepositMovementClassified ',file_name,' business-row mismatch'))
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.55.2 - Wait For Replay

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Wait For Bronze And Silver > Activities |
| Activity to select | Wait |
| General > Name (exact) | Wait For Replay |
| Incoming dependency | Compute Replayed Row Mismatches [Succeeded] |

**Settings > Wait time in seconds** - literal value; do not add an expression wrapper.

```text
5
```

### 6.56 - Compute Silver Classification

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Silver Classification |
| Incoming dependency | Wait For Bronze And Silver [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-replace CR01Test_06622392_CR01_Checks <| let names=toscalar(print items=parse_json(base64_decode_tostring("W3siRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE3XzIzMDBfMjMzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9LHsiRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE4XzAwMDBfMDAzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9XQ=="))
    | mv-expand items | summarize make_set(tostring(items.FileName))); CR01Test_06622392_DepositMovementClassified | where file_name in (names) and ClassificationStatus!='CLASSIFIED' | project Problem=strcat(file_name,' ',ClassificationStatus)
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.57 - Validate Silver Classification

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Silver Classification |
| Incoming dependency | Compute Silver Classification [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Silver Classification').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 6.57-True.1 - Validate Silver Classification Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Silver Classification > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Silver Classification Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Silver Classification has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 6.58 - Compute Unrelated DepositMovement

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Unrelated DepositMovement |
| Incoming dependency | Validate Silver Classification [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-replace CR01Test_06622392_CR01_Checks <| let names=toscalar(print items=parse_json(base64_decode_tostring("W3siRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE3XzIzMDBfMjMzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9LHsiRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE4XzAwMDBfMDAzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9XQ=="))
    | mv-expand items | summarize make_set(tostring(items.FileName))); CR01Test_06622392_CR01_UnrelatedBronze_20261118 | project Fingerprint,Before=Copies | join kind=fullouter (CR01Test_06622392_DepositMovement | where file_name !in (names) | summarize After=count() by Fingerprint=hash_sha256(tostring(pack_array(Date,Time,Product,Channel,Channel_Group,Credit_Amount,Debit_Amount,Net_Amount,Credit_Transaction,Debit_Transaction,Total_Transaction,load_ts,file_name,pipeline_name,pipeline_runid)))) on Fingerprint | where coalesce(Before,0)!=coalesce(After,0) | project Problem='Unrelated source rows changed'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.59 - Validate Unrelated DepositMovement

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Unrelated DepositMovement |
| Incoming dependency | Compute Unrelated DepositMovement [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Unrelated DepositMovement').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 6.59-True.1 - Validate Unrelated DepositMovement Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Unrelated DepositMovement > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Unrelated DepositMovement Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Unrelated DepositMovement has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 6.60 - Compute Unrelated DepositMovementClassified

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Unrelated DepositMovementClassified |
| Incoming dependency | Validate Unrelated DepositMovement [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-replace CR01Test_06622392_CR01_Checks <| let names=toscalar(print items=parse_json(base64_decode_tostring("W3siRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE3XzIzMDBfMjMzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9LHsiRmlsZU5hbWUiOiJJTlRSQURBWV9TVU1NQVJZXzIwMjYxMTE4XzAwMDBfMDAzMC5DU1YiLCJFeHBlY3RlZFJvd3MiOjF9XQ=="))
    | mv-expand items | summarize make_set(tostring(items.FileName))); CR01Test_06622392_CR01_UnrelatedSilver_20261118 | project Fingerprint,Before=Copies | join kind=fullouter (CR01Test_06622392_DepositMovementClassified | where file_name !in (names) | summarize After=count() by Fingerprint=hash_sha256(tostring(pack_array(Date,Time,Product,Channel,Channel_Group,Credit_Amount,Debit_Amount,Net_Amount,Credit_Transaction,Debit_Transaction,Total_Transaction,load_ts,file_name,pipeline_name,pipeline_runid,LocalDate,LocalDateTime,LocalTimeOfDay,IsWeekend,IsFinancialInstitutionHoliday,IsBusinessDay,DayClassification,HolidayName,OperatingWindowCode,OperatingWindowName,OperatingWindowStartTime,OperatingWindowEndTime,OperatingWindowSortOrder,WindowMatchCount,ClassificationStatus,IsMonthEnd,IsPayroll,IsLongWeekend,EventFlag)))) on Fingerprint | where coalesce(Before,0)!=coalesce(After,0) | project Problem='Unrelated source rows changed'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.61 - Validate Unrelated DepositMovementClassified

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Unrelated DepositMovementClassified |
| Incoming dependency | Compute Unrelated DepositMovementClassified [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Unrelated DepositMovementClassified').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 6.61-True.1 - Validate Unrelated DepositMovementClassified Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Unrelated DepositMovementClassified > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Unrelated DepositMovementClassified Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Unrelated DepositMovementClassified has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 6.62 - Rebuild mv_Summary_Product_Channel_Alert

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Rebuild mv_Summary_Product_Channel_Alert |
| Incoming dependency | Validate Unrelated DepositMovementClassified [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.create materialized-view with (backfill=true,folder="Gold",docstring="") CR01Test_06622392_mv_Summary_Product_Channel_Alert on table CR01Test_06622392_DepositMovement { CR01Test_06622392_DepositMovement
    | summarize
        Time               = max(Time),
        Credit_Amount      = sum(Credit_Amount),
        Debit_Amount       = sum(Debit_Amount),
        Net_Amount         = sum(Net_Amount),
        Credit_Transaction = sum(Credit_Transaction),
        Debit_Transaction  = sum(Debit_Transaction),
        Total_Transaction  = sum(Total_Transaction),
        UpdatedAtUtc       = max(load_ts)
        by Date, Product, Channel, Channel_Group }
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.63 - Compute Reconciled mv_Summary_Product_Channel_Alert

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Reconciled mv_Summary_Product_Channel_Alert |
| Incoming dependency | Rebuild mv_Summary_Product_Channel_Alert [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-replace CR01Test_06622392_CR01_Checks <| let expected=CR01Test_06622392_DepositMovement
    | summarize
        Time               = max(Time),
        Credit_Amount      = sum(Credit_Amount),
        Debit_Amount       = sum(Debit_Amount),
        Net_Amount         = sum(Net_Amount),
        Credit_Transaction = sum(Credit_Transaction),
        Debit_Transaction  = sum(Debit_Transaction),
        Total_Transaction  = sum(Total_Transaction),
        UpdatedAtUtc       = max(load_ts)
        by Date, Product, Channel, Channel_Group | summarize Expected=count() by Fingerprint=tostring(pack_array(Date,Product,Channel,Channel_Group,Time,Credit_Amount,Debit_Amount,Net_Amount,Credit_Transaction,Debit_Transaction,Total_Transaction,UpdatedAtUtc)); expected | join kind=fullouter (CR01Test_06622392_mv_Summary_Product_Channel_Alert | summarize Actual=count() by Fingerprint=tostring(pack_array(Date,Product,Channel,Channel_Group,Time,Credit_Amount,Debit_Amount,Net_Amount,Credit_Transaction,Debit_Transaction,Total_Transaction,UpdatedAtUtc))) on Fingerprint | where coalesce(Expected,0)!=coalesce(Actual,0) | project Problem='Gold MV does not reconcile with corrected source'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.64 - Validate Reconciled mv_Summary_Product_Channel_Alert

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Reconciled mv_Summary_Product_Channel_Alert |
| Incoming dependency | Compute Reconciled mv_Summary_Product_Channel_Alert [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Reconciled mv_Summary_Product_Channel_Alert').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 6.64-True.1 - Validate Reconciled mv_Summary_Product_Channel_A Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Reconciled mv_Summary_Product_Channel_Alert > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Reconciled mv_Summary_Product_Channel_A Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Reconciled mv_Summary_Product_Channel_Alert has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 6.65 - Rebuild mv_EarlyWarning_Base

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Rebuild mv_EarlyWarning_Base |
| Incoming dependency | Validate Reconciled mv_Summary_Product_Channel_Alert [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.create materialized-view with (backfill=true,folder="Gold",docstring="") CR01Test_06622392_mv_EarlyWarning_Base on table CR01Test_06622392_DepositMovementClassified { CR01Test_06622392_DepositMovementClassified
    // Only rows with a valid local time can fall into a 30-minute bucket.
    | where isnotnull(LocalDateTime)
    // Main condition #1: exclude MSYG / SYSG from every calculation.
    | where Channel !in ("MSYG", "SYSG")
    | extend
        IsRetail    = Channel in ("ENET", "ATM", "CDM"),
        BucketStart = bin(LocalDateTime, 30m)
    | summarize
        GrossOutflow = sum(Debit_Amount),
        Credit       = sum(Credit_Amount),
        Net          = sum(Net_Amount),
        DebitTxn     = sum(Debit_Transaction),
        UpdatedAtUtc = max(load_ts)
        by LocalDate, BucketStart, DayClassification, EventFlag,
           IsMonthEnd, IsPayroll, IsLongWeekend, IsRetail }
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.66 - Restore Caching mv_EarlyWarning_Base

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Restore Caching mv_EarlyWarning_Base |
| Incoming dependency | Rebuild mv_EarlyWarning_Base [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.alter materialized-view CR01Test_06622392_mv_EarlyWarning_Base policy caching hot = 90d
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.67 - Compute Reconciled mv_EarlyWarning_Base

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Reconciled mv_EarlyWarning_Base |
| Incoming dependency | Restore Caching mv_EarlyWarning_Base [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-replace CR01Test_06622392_CR01_Checks <| let expected=CR01Test_06622392_DepositMovementClassified
    // Only rows with a valid local time can fall into a 30-minute bucket.
    | where isnotnull(LocalDateTime)
    // Main condition #1: exclude MSYG / SYSG from every calculation.
    | where Channel !in ("MSYG", "SYSG")
    | extend
        IsRetail    = Channel in ("ENET", "ATM", "CDM"),
        BucketStart = bin(LocalDateTime, 30m)
    | summarize
        GrossOutflow = sum(Debit_Amount),
        Credit       = sum(Credit_Amount),
        Net          = sum(Net_Amount),
        DebitTxn     = sum(Debit_Transaction),
        UpdatedAtUtc = max(load_ts)
        by LocalDate, BucketStart, DayClassification, EventFlag,
           IsMonthEnd, IsPayroll, IsLongWeekend, IsRetail | summarize Expected=count() by Fingerprint=tostring(pack_array(LocalDate,BucketStart,DayClassification,EventFlag,IsMonthEnd,IsPayroll,IsLongWeekend,IsRetail,GrossOutflow,Credit,Net,DebitTxn,UpdatedAtUtc)); expected | join kind=fullouter (CR01Test_06622392_mv_EarlyWarning_Base | summarize Actual=count() by Fingerprint=tostring(pack_array(LocalDate,BucketStart,DayClassification,EventFlag,IsMonthEnd,IsPayroll,IsLongWeekend,IsRetail,GrossOutflow,Credit,Net,DebitTxn,UpdatedAtUtc))) on Fingerprint | where coalesce(Expected,0)!=coalesce(Actual,0) | project Problem='Gold MV does not reconcile with corrected source'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.68 - Validate Reconciled mv_EarlyWarning_Base

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Reconciled mv_EarlyWarning_Base |
| Incoming dependency | Compute Reconciled mv_EarlyWarning_Base [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Reconciled mv_EarlyWarning_Base').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 6.68-True.1 - Validate Reconciled mv_EarlyWarning_Base Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Reconciled mv_EarlyWarning_Base > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Reconciled mv_EarlyWarning_Base Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Reconciled mv_EarlyWarning_Base has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 6.69 - Wait For Healthy Gold Views

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | Until |
| General > Name (exact) | Wait For Healthy Gold Views |
| Incoming dependency | Validate Reconciled mv_EarlyWarning_Base [Succeeded] |

**Settings > Expression (exit condition)** - use Add dynamic content.

```text
@and(equals(int(activity('Read Gold Health').output.value[0].Present),2),equals(int(activity('Read Gold Health').output.value[0].Unhealthy),0))
```

**Settings > Timeout** - literal value; do not add an expression wrapper.

```text
0.01:00:00
```

Open the Activities canvas inside Until. The condition is evaluated after an iteration; retain the Wait activity.

### 6.69.1 - Read Gold Health

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Wait For Healthy Gold Views > Activities |
| Activity to select | KQL |
| General > Name (exact) | Read Gold Health |
| Incoming dependency | None inside this canvas/branch |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.show materialized-views | where Name in ("CR01Test_06622392_mv_Summary_Product_Channel_Alert","CR01Test_06622392_mv_EarlyWarning_Base") | summarize Present=count(),Unhealthy=countif(IsHealthy!=true or IsEnabled!=true)
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.69.2 - Wait For Materialization

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Wait For Healthy Gold Views > Activities |
| Activity to select | Wait |
| General > Name (exact) | Wait For Materialization |
| Incoming dependency | Read Gold Health [Succeeded] |

**Settings > Wait time in seconds** - literal value; do not add an expression wrapper.

```text
5
```

### 6.70 - Compute EWI Level Contract

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute EWI Level Contract |
| Incoming dependency | Wait For Healthy Gold Views [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-replace CR01Test_06622392_CR01_Checks <| union (CR01Test_06622392_Gold_EarlyWarning(datetime(2026-11-18)-1d)),(CR01Test_06622392_Gold_EarlyWarning(datetime(2026-11-18))) | where isnull(Alert_Rank) or Alert_Rank<0 or Alert_Rank>3 or Alert_Level !in ('L0','L1','L2','L3') | project Problem='Invalid EWI level/rank before persistence'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.71 - Validate EWI Level Contract

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate EWI Level Contract |
| Incoming dependency | Compute EWI Level Contract [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute EWI Level Contract').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 6.71-True.1 - Validate EWI Level Contract Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate EWI Level Contract > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate EWI Level Contract Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 EWI Level Contract has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 6.72 - Delete Affected Persisted EWI Dates

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Delete Affected Persisted EWI Dates |
| Incoming dependency | Validate EWI Level Contract [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.delete table CR01Test_06622392_DepositMovementEarlyWarning records <| CR01Test_06622392_DepositMovementEarlyWarning | where Date_ICT in (format_datetime(datetime(2026-11-18)-1d,'yyyy-MM-dd'),'2026-11-18')
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.73 - Recompute Both Complete EWI Dates

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Recompute Both Complete EWI Dates |
| Incoming dependency | Delete Affected Persisted EWI Dates [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-append CR01Test_06622392_DepositMovementEarlyWarning <| union (CR01Test_06622392_Gold_EarlyWarning(datetime(2026-11-18)-1d)),(CR01Test_06622392_Gold_EarlyWarning(datetime(2026-11-18))) | project Object_Id,Scope,Date_ICT,Bucket_Start,Bucket_Label,Alert_Time,WindowCode,WindowName,DayType,EventFlag,IsMonthEnd,IsPayroll,IsLongWeekend,IndicatorId,IndicatorKey,IndicatorName,Unit,Value,Direction,L1,L2,L3,Alert_Level,Alert_Rank=toint(Alert_Rank)
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.74 - Compute Persisted EWI Grain

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Persisted EWI Grain |
| Incoming dependency | Recompute Both Complete EWI Dates [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-replace CR01Test_06622392_CR01_Checks <| CR01Test_06622392_DepositMovementEarlyWarning | where Date_ICT in (format_datetime(datetime(2026-11-18)-1d,'yyyy-MM-dd'),'2026-11-18') | summarize Copies=count() by Object_Id,Bucket_Start | where Copies!=1 | project Problem='Stored EWI grain is not one row per scope/indicator/bucket'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.75 - Validate Persisted EWI Grain

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Persisted EWI Grain |
| Incoming dependency | Compute Persisted EWI Grain [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Persisted EWI Grain').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 6.75-True.1 - Validate Persisted EWI Grain Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Persisted EWI Grain > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Persisted EWI Grain Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Persisted EWI Grain has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 6.76 - Compute Reconciled Persisted EWI

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Compute Reconciled Persisted EWI |
| Incoming dependency | Validate Persisted EWI Grain [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-replace CR01Test_06622392_CR01_Checks <| let e=union (CR01Test_06622392_Gold_EarlyWarning(datetime(2026-11-18)-1d)),(CR01Test_06622392_Gold_EarlyWarning(datetime(2026-11-18))) | project Object_Id,Scope,Date_ICT,Bucket_Start,Bucket_Label,Alert_Time,WindowCode,WindowName,DayType,EventFlag,IsMonthEnd,IsPayroll,IsLongWeekend,IndicatorId,IndicatorKey,IndicatorName,Unit,Value,Direction,L1,L2,L3,Alert_Level,Alert_Rank=toint(Alert_Rank); e | summarize Expected=count() by Fingerprint=tostring(pack_array(Object_Id,Scope,Date_ICT,Bucket_Start,Bucket_Label,WindowCode,WindowName,DayType,EventFlag,IsMonthEnd,IsPayroll,IsLongWeekend,IndicatorId,IndicatorKey,IndicatorName,Unit,Value,Direction,L1,L2,L3,Alert_Level,Alert_Rank)) | join kind=fullouter (CR01Test_06622392_DepositMovementEarlyWarning | where Date_ICT in (format_datetime(datetime(2026-11-18)-1d,'yyyy-MM-dd'),'2026-11-18') | summarize Actual=count() by Fingerprint=tostring(pack_array(Object_Id,Scope,Date_ICT,Bucket_Start,Bucket_Label,WindowCode,WindowName,DayType,EventFlag,IsMonthEnd,IsPayroll,IsLongWeekend,IndicatorId,IndicatorKey,IndicatorName,Unit,Value,Direction,L1,L2,L3,Alert_Level,Alert_Rank))) on Fingerprint | where coalesce(Expected,0)!=coalesce(Actual,0) | project Problem='Persisted EWI mismatch'
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.77 - Validate Reconciled Persisted EWI

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Validate Reconciled Persisted EWI |
| Incoming dependency | Compute Reconciled Persisted EWI [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Compute Reconciled Persisted EWI').output.count), 0)
```

**True branch:** open this branch and add its activities below.

### 6.77-True.1 - Validate Reconciled Persisted EWI Failed

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Validate Reconciled Persisted EWI > True branch |
| Activity to select | Fail |
| General > Name (exact) | Validate Reconciled Persisted EWI Failed |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_GUARD
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
CR01 Reconciled Persisted EWI has mismatches. Keep the controller lock and investigate.
```

**False branch:** leave empty.

### 6.78 - Assert Known Corrected Amounts

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | KQL |
| General > Name (exact) | Assert Known Corrected Amounts |
| Incoming dependency | Validate Reconciled Persisted EWI [Succeeded] |
| General > timeout | 0.01:00:00 |
| General > retry | 0 |
| General > secureInput | False |
| General > secureOutput | False |

Settings > Workspace data store / KQL Database: **DepositMovement**, in **RTI-IDM-PRD**.

**Settings > Command** - literal value; do not add an expression wrapper.

```kusto
.set-or-replace CR01Test_06622392_FinalChecks <|
    let b=toscalar(CR01Test_06622392_DepositMovement | summarize sum(Net_Amount));
    let n=toscalar(CR01Test_06622392_DepositMovement | count);
    let s=toscalar(CR01Test_06622392_DepositMovementClassified | count);
    let e=toscalar(CR01Test_06622392_DepositMovementEarlyWarning | count);
    union
        (print Problem="Wrong corrected Bronze/Silver/EWI total/count" | where b!=decimal(195) or n!=3 or s!=3 or e!=72),
        (CR01Test_06622392_Gold_EarlyWarning(datetime(2026-11-17))
            | where Scope=="TOTAL_BANK" and IndicatorKey=="AccumNetOutflow_MB"
            | summarize arg_max(Bucket_Start,Value),Rows=count()
            | where Rows!=2 or abs(Value-0.000085)>1e-12 | project Problem="Previous-day cumulative EWI is stale"),
        (CR01Test_06622392_Gold_EarlyWarning(datetime(2026-11-18))
            | where Scope=="TOTAL_BANK" and IndicatorKey=="AccumNetOutflow_MB"
            | summarize arg_max(Bucket_Start,Value),Rows=count()
            | where Rows!=1 or abs(Value-0.000110)>1e-12 | project Problem="Current-day cumulative EWI is stale")
```

**Settings > Command timeout** - literal value; do not add an expression wrapper.

```text
01:00:00
```

### 6.79 - Require Exact Test Pass

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas |
| Activity to select | If condition |
| General > Name (exact) | Require Exact Test Pass |
| Incoming dependency | Assert Known Corrected Amounts [Succeeded] |

**Activities / Settings > Expression** - use Add dynamic content.

```text
@greater(int(activity('Assert Known Corrected Amounts').output.count),0)
```

**True branch:** open this branch and add its activities below.

### 6.79-True.1 - Fail Isolated Refresh Test

| UI field | Setting |
| --- | --- |
| Where to add it | Main pipeline canvas > Require Exact Test Pass > True branch |
| Activity to select | Fail |
| General > Name (exact) | Fail Isolated Refresh Test |
| Incoming dependency | None inside this canvas/branch |

**Settings > Error code** - literal value; do not add an expression wrapper.

```text
CR01_TEST_FAILED
```

**Settings > Message** - literal value; do not add an expression wrapper.

```text
Isolated corrected amounts or cumulative EWI did not match expectations.
```

**False branch:** leave empty.

## UI authoring verification

Save every pipeline. Recheck parameter types, exact activity names, green success dependencies, nested branch placement, all Retry=0 settings, child wait-on-completion, and the disabled controller flags. Use the main guide for supervised tests and cutover; creating these activities is not production approval.

## Test cleanup through the Fabric editors

**Only after the test job is terminal and the exact namespace is confirmed as your isolated fixture.** These names are extracted from the supplied test definition. Skip objects that were never created. Do not remove the prefix, substitute production names, or use these commands for another test version.

Recorded KQL fixture prefix: `CR01Test_06622392_`.

In the KQL Queryset, run these inventory commands separately and review every returned name:

```kusto
.show tables | where TableName startswith 'CR01Test_06622392_'
.show materialized-views | where Name startswith 'CR01Test_06622392_'
.show functions | where Name startswith 'CR01Test_06622392_'
```

Run the following drop commands **one at a time**, in this order, only for objects confirmed present and owned by this test:

```kusto
.drop materialized-view CR01Test_06622392_mv_EarlyWarning_Base
.drop materialized-view CR01Test_06622392_mv_Summary_Product_Channel_Alert
.drop table CR01Test_06622392_DepositMovementClassified
.drop table CR01Test_06622392_CR01_BackupBronze_20261118
.drop table CR01Test_06622392_CR01_BackupEwi_20261118
.drop table CR01Test_06622392_CR01_BackupSilver_20261118
.drop table CR01Test_06622392_CR01_Checks
.drop table CR01Test_06622392_CR01_PublishState
.drop table CR01Test_06622392_CR01_Stage_20261118
.drop table CR01Test_06622392_CR01_UnrelatedBronze_20261118
.drop table CR01Test_06622392_CR01_UnrelatedSilver_20261118
.drop table CR01Test_06622392_DepositMovement
.drop table CR01Test_06622392_DepositMovementEarlyWarning
.drop table CR01Test_06622392_EWI_AlertThreshold
.drop table CR01Test_06622392_FinalChecks
.drop table CR01Test_06622392_VerifierNegative
.drop function CR01Test_06622392_CR01_PreviewSilver
.drop function CR01Test_06622392_Gold_EarlyWarning
.drop function CR01Test_06622392_Transform_DepositMovementClassified
```

Refresh the explorer and rerun the three inventory commands; each must return no objects for this exact prefix.

For the SQL fixture, its last activity normally performs cleanup. If a failure left its test tables behind, open **wh_control_framework > New SQL query**, review the exact names, and run:

```sql
IF OBJECT_ID('dbo.CR01Test_47915723_CR01ControllerRun','U') IS NOT NULL DROP TABLE dbo.CR01Test_47915723_CR01ControllerRun;
IF OBJECT_ID('dbo.CR01Test_47915723_CR01RefreshRun','U') IS NOT NULL DROP TABLE dbo.CR01Test_47915723_CR01RefreshRun;
IF OBJECT_ID('dbo.CR01Test_47915723_CR01RefreshManifest','U') IS NOT NULL DROP TABLE dbo.CR01Test_47915723_CR01RefreshManifest;
IF OBJECT_ID('dbo.CR01Test_47915723_CR01AuditBefore','U') IS NOT NULL DROP TABLE dbo.CR01Test_47915723_CR01AuditBefore;
IF OBJECT_ID('dbo.CR01Test_47915723_ProcessedFiles','U') IS NOT NULL DROP TABLE dbo.CR01Test_47915723_ProcessedFiles;
```

Do not drop or change the unprefixed production tables. Keep the validation pipeline/run history if required. The next fresh test must use a reviewed empty namespace.
