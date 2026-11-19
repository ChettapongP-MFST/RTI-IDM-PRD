[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AzureConfigDirectory,
    [string]$RefreshPipelineId,
    [string]$DiscoveryPipelineId,
    [string]$WorkspaceId = 'f0cb703b-2ceb-4a73-a302-813057c06412'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:AZURE_CONFIG_DIR = $AzureConfigDirectory
$output = Join-Path $PSScriptRoot '..\pipeline'
$fabricToken = az account get-access-token --resource 'https://api.fabric.microsoft.com' --query accessToken -o tsv
if ($LASTEXITCODE -ne 0) { throw 'Fabric authentication failed.' }
$kustoToken = az account get-access-token --resource 'https://kusto.kusto.windows.net' --query accessToken -o tsv
if ($LASTEXITCODE -ne 0) { throw 'Kusto authentication failed.' }
$fabricHeaders = @{ Authorization = "Bearer $fabricToken" }
$base = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId"
$cluster = 'https://trd-k344krpm42xbxq2184.z5.kusto.fabric.microsoft.com'

function Read-Kql {
    param([string]$Query, [switch]$Management)
    $endpoint = if ($Management) { 'mgmt' } else { 'query' }
    $result = Invoke-RestMethod -Uri "$cluster/v1/rest/$endpoint" -Method Post `
        -Headers @{ Authorization = "Bearer $kustoToken"; Accept = 'application/json' } -ContentType 'application/json' `
        -Body (@{ db = 'DepositMovement'; csl = $Query } | ConvertTo-Json) -TimeoutSec 120
    foreach ($table in $result.Tables) {
        if ('Severity' -in $table.Columns.ColumnName -and 'StatusDescription' -in $table.Columns.ColumnName) {
            $severity = [array]::IndexOf(@($table.Columns.ColumnName), 'Severity')
            if ($severity -ge 0 -and @($table.Rows | Where-Object { $_[$severity] -le 2 }).Count) {
                throw 'Kusto returned a partial query failure. Do not generate deployment artifacts.'
            }
        }
    }
    $table = $result.Tables[0]
    foreach ($row in $table.Rows) {
        $record = [ordered]@{}
        for ($i = 0; $i -lt $table.Columns.Count; $i++) { $record[$table.Columns[$i].ColumnName] = $row[$i] }
        [pscustomobject]$record
    }
}

function Read-Pipeline {
    param([string]$Id)
    $definition = Invoke-RestMethod -Uri "$base/items/$Id/getDefinition" -Method Post -Headers $fabricHeaders -TimeoutSec 120
    $part = @($definition.definition.parts | Where-Object path -EQ 'pipeline-content.json')[0]
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part.payload)) | ConvertFrom-Json -AsHashtable
}

function Copy-Object($Value) { $Value | ConvertTo-Json -Depth 80 | ConvertFrom-Json -AsHashtable }
function Expression([string]$Value) { @{ value = $Value; type = 'Expression' } }
function Dependencies([string]$Name) {
    if ($Name) { @{ activity = $Name; dependencyConditions = @('Succeeded') } }
}
function Policy { @{ timeout = '0.01:00:00'; retry = 0; secureInput = $false; secureOutput = $false } }
function Kql([string]$Name, [string]$Command, [string]$After) {
    @{
        name = $Name; type = 'KustoQueryLanguage'; dependsOn = @(Dependencies $After)
        policy = Policy; linkedService = Copy-Object $kqlService
        typeProperties = @{
            command = if ($Command.Contains('@{')) { Expression $Command } else { $Command }
            commandTimeout = '01:00:00'
        }
    }
}
function Sql([string]$Name, [string]$Text, [string]$After) {
    $node = @{
        name = $Name; type = 'Script'; dependsOn = @(Dependencies $After)
        policy = Policy; linkedService = Copy-Object $sqlService
        typeProperties = @{
            scripts = @(@{ type = 'NonQuery'; text = if ($Text.Contains('@{')) { Expression $Text } else { $Text } })
            scriptBlockExecutionTimeout = '01:00:00'
        }
    }
    if ($Name -eq 'Validate Controller Owner') {
        $node.typeProperties.scripts[0].parameters = @(@{
            name = 'ControllerRunId'; type = 'String'; direction = 'Input'
            value = Expression '@pipeline().parameters.pControllerRunId'
        })
    }
    $node
}
function Lookup([string]$Name, [string]$Text, [string]$After, [bool]$First = $true) {
    $node = Copy-Object $lookupTemplate
    $node.name = $Name
    $node.dependsOn = @(Dependencies $After)
    $node.policy.retry = 0
    $node.typeProperties.firstRowOnly = $First
    $node.typeProperties.source.sqlReaderQuery = if ($Text.Contains('@{')) { Expression $Text } else { $Text }
    $node
}
function Fail([string]$Name, [string]$Message) {
    if ($Name.Length -gt 55) { $Name = $Name.Substring(0, 48) + ' Failed' }
    @{ name = $Name; type = 'Fail'; dependsOn = @(); typeProperties = @{ message = $Message; errorCode = 'CR01_GUARD' } }
}
function Guard([string]$Name, [string]$Condition, [string]$Message, [string]$After) {
    @{
        name = $Name; type = 'IfCondition'; dependsOn = @(Dependencies $After)
        typeProperties = @{
            expression = Expression $Condition
            ifTrueActivities = @((Fail "$Name Failed" $Message)); ifFalseActivities = @()
        }
    }
}
function Invoke-Child([string]$Name, [string]$Id, [hashtable]$Parameters, [string]$After) {
    $node = Copy-Object $invokeTemplate
    $node.name = $Name
    $node.dependsOn = @(Dependencies $After)
    $node.policy.retry = 0
    $node.typeProperties.pipelineId = $Id
    $node.typeProperties.parameters = $Parameters
    $node
}
function Add-Check([Collections.Generic.List[object]]$Activities, [string]$Name, [string]$Query, [string]$After) {
    $Activities.Add((Kql "Compute $Name" ".set-or-replace CR01_Checks <| $Query" $After))
    # Synchronous ingestion returns an extent for nonempty results; table statistics can lag.
    $condition = "@greater(int(activity('Compute $Name').output.count), 0)"
    $Activities.Add((Guard "Validate $Name" $condition "CR01 $Name has mismatches. Keep the controller lock and investigate." "Compute $Name"))
    "Validate $Name"
}
function Save-Pipeline([string]$Name, [object[]]$Activities, [hashtable]$Parameters, [hashtable]$Variables = @{}) {
    $nodes = [Collections.Generic.List[object]]::new()
    function Validate-Value($Value) {
        if ($Value -is [Collections.IDictionary]) {
            if ($Value.Contains('name') -and $Value.Contains('dependsOn')) {
                if ($Value.name.Length -gt 55) { throw "Activity name exceeds 55 characters: $($Value.name)" }
                if ($Value.dependsOn -isnot [array]) { throw "Activity dependency must be an array: $($Value.name)" }
                $nodes.Add($Value)
            }
            if ($Value.Contains('type') -and $Value.type -eq 'Expression' -and $Value.value.Length -gt 8192) {
                throw "Expression exceeds the Fabric 8192-character limit in $Name."
            }
            foreach ($key in $Value.Keys) { Validate-Value $Value[$key] }
        }
        elseif ($Value -is [array]) { foreach ($entry in $Value) { Validate-Value $entry } }
    }
    $document = @{ properties = @{ activities = $Activities; parameters = $Parameters; variables = $Variables } }
    Validate-Value $document
    if ($nodes.Count -gt 120 -or @($nodes | Group-Object name | Where-Object Count -GT 1).Count) {
        throw "Too many activities or duplicate activity names in $Name."
    }
    $json = $document | ConvertTo-Json -Depth 90
    if ([Text.Encoding]::UTF8.GetByteCount($json) -gt 200KB) { throw "Pipeline $Name exceeds 200 KB." }
    $json | Set-Content -LiteralPath (Join-Path $output "$Name.json") -Encoding utf8
}

$ingest = Read-Pipeline '0a74b40a-6e71-4a66-9cb1-d49a6d405d01'
$discovery = Read-Pipeline '9ec17f10-cda1-498c-97fe-68a189f2f7fe'
$copyTemplate = @(@($ingest.properties.activities | Where-Object type -EQ 'IfCondition')[0].typeProperties.ifTrueActivities | Where-Object type -EQ 'Copy')[0]
$sqlService = @(@($ingest.properties.activities | Where-Object type -EQ 'IfCondition')[0].typeProperties.ifTrueActivities | Where-Object name -EQ 'Append Success')[0].linkedService
$kqlService = $copyTemplate.typeProperties.sink.datasetSettings.linkedService
$lookupTemplate = @($ingest.properties.activities | Where-Object type -EQ 'Lookup')[0]
$invokeTemplate = @(@($discovery.properties.activities | Where-Object type -EQ 'ForEach')[0].typeProperties.activities)[0]
$metadataTemplate = @($ingest.properties.activities | Where-Object type -EQ 'GetMetadata')[0]
$views = @(Read-Kql '.show materialized-views | where SourceTable in ("DepositMovement", "DepositMovementClassified")' -Management)
if ($views.Count -ne 2 -or @($views.Name | Where-Object { $_ -notin @('mv_Summary_Product_Channel_Alert', 'mv_EarlyWarning_Base') }).Count) {
    throw 'The dependent MV inventory changed. Review it before generating a destructive refresh.'
}
foreach ($view in $views) {
    if (-not $view.IsEnabled -or $view.AutoUpdateSchema -or $null -ne $view.Lookback) {
        throw "Non-default MV creation options on $($view.Name) require an explicitly reviewed restoration procedure."
    }
    $retention = @(Read-Kql ".show materialized-view $($view.Name) policy retention" -Management)[0].Policy
    $caching = @(Read-Kql ".show materialized-view $($view.Name) policy caching" -Management)[0].Policy
    if ($retention -ne 'null') { throw "Custom retention on $($view.Name) needs an explicitly reviewed restoration procedure." }
    if ($caching -ne 'null') {
        $parsed = $caching | ConvertFrom-Json
        if ($parsed.DataHotSpan.Value -ne '90.00:00:00' -or $parsed.IndexHotSpan.Value -ne '90.00:00:00') {
            throw "Custom caching on $($view.Name) is not supported by this restoration template."
        }
    }
    $view | Add-Member -NotePropertyName RetentionPolicy -NotePropertyValue $retention
    $view | Add-Member -NotePropertyName CachingPolicy -NotePropertyValue $caching
}
$schemas = @{}
$schemaDetails = @{}
foreach ($table in @('DepositMovement', 'DepositMovementClassified', 'DepositMovementEarlyWarning') + @($views.Name)) {
    $schemaDetails[$table] = @(Read-Kql "$table | getschema")
    $schemas[$table] = @($schemaDetails[$table].ColumnName)
}
$functionSchema = @(Read-Kql 'Gold_EarlyWarning() | getschema')
$ewiProjection = @(
    foreach ($column in $schemaDetails.DepositMovementEarlyWarning) {
        $source = @($functionSchema | Where-Object ColumnName -EQ $column.ColumnName)
        if ($source.Count -ne 1) { throw "EWI output cannot populate stored column $($column.ColumnName)." }
        if ($source[0].ColumnType -eq $column.ColumnType) { $column.ColumnName }
        elseif ($column.ColumnName -eq 'Alert_Rank' -and $source[0].ColumnType -eq 'long' -and $column.ColumnType -eq 'int') {
            'Alert_Rank=toint(Alert_Rank)'
        }
        else { throw "Unsupported EWI schema conversion for $($column.ColumnName)." }
    }
) -join ','
$views | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'CR01-materialized-view-baseline.json') -Encoding utf8
$ownerCheck = @'
IF (SELECT COUNT(*) FROM dbo.CR01ControllerRun
    WHERE RunId=@ControllerRunId AND Status='Running') <> 1
    THROW 51100, 'CR01 internal pipeline requires an active controller owner.', 1;
'@

# New discovery pipeline: reuse the existing ingestion child, not its definition.
$d = Copy-Object $discovery.properties.activities
$d[0].dependsOn = @(Dependencies 'Validate Controller Owner')
$d[0].typeProperties.value = Expression "@concat('INTRADAY_SUMMARY_', formatDateTime(pipeline().parameters.pRunICT, 'yyyyMMdd'))"
$yesterday = @{
    name = 'Set vYesterday'; type = 'SetVariable'; dependsOn = @(Dependencies 'Set vToday')
    typeProperties = @{ variableName = 'vYesterday'; value = Expression "@concat('INTRADAY_SUMMARY_', formatDateTime(addDays(pipeline().parameters.pRunICT,-1),'yyyyMMdd'))" }
}
@($d | Where-Object type -EQ 'GetMetadata')[0].dependsOn = @(Dependencies 'Set vYesterday')
$read = @($d | Where-Object type -EQ 'Lookup')[0]
$read.typeProperties.source.sqlReaderQuery.value = $read.typeProperties.source.sqlReaderQuery.value.Replace(
    "AND FileName LIKE '@{variables('vToday')}%';",
    "AND (FileName LIKE '@{variables('vToday')}%' OR FileName LIKE '@{variables('vYesterday')}%');")
$filter = @($d | Where-Object type -EQ 'Filter')[0]
$filter.typeProperties.condition = Expression @'
@and(and(equals(item().type,'File'),or(startswith(item().name,variables('vToday')),startswith(item().name,variables('vYesterday')))),and(endswith(toLower(item().name),'.csv'),not(contains(activity('Lookup Processed Files').output.firstRow.ProcessedList,concat('|',item().name,'|')))))
'@
$invoke = @(@($d | Where-Object type -EQ 'ForEach')[0].typeProperties.activities)[0]
$invoke.policy.retry = 0
$invoke.typeProperties.parameters.Subject = Expression "@concat('/blobServices/default/containers/inflowoutflow/blobs/inbound/statement/', item().name)"
$discoverActivities = @((Sql 'Validate Controller Owner' $ownerCheck '')) + @($d[0], $yesterday) + @($d | Select-Object -Skip 1)
Save-Pipeline 'pl_CR01_DepositMovement_Discover' $discoverActivities @{
    pControllerRunId = @{ type = 'string' }; pRunICT = @{ type = 'string' }
} @{ vToday = @{ type = 'String' }; vYesterday = @{ type = 'String' } }

# The refresh stages a complete immutable KQL snapshot before deleting anything.
$r = [Collections.Generic.List[object]]::new()
$r.Add((Guard 'Require Finalized Source' '@not(pipeline().parameters.pSourceFinalized)' 'Producer finalization must be confirmed before a refresh.' ''))
$r.Add(@{ name = 'Freeze Refresh Date'; type = 'SetVariable'; dependsOn = @(Dependencies 'Require Finalized Source'); typeProperties = @{
    variableName = 'vRefreshDate'; value = Expression "@formatDateTime(pipeline().parameters.pRefreshDate,'yyyy-MM-dd')" } })
$r.Add(@{ name = 'Freeze Load Time'; type = 'SetVariable'; dependsOn = @(Dependencies 'Freeze Refresh Date'); typeProperties = @{
    variableName = 'vLoadTs'; value = Expression "@convertFromUtc(utcNow(),'SE Asia Standard Time')" } })
$r.Add((Sql 'Validate Controller Owner' $ownerCheck 'Freeze Load Time'))
$schemaAfter = 'Validate Controller Owner'
foreach ($table in @('DepositMovement', 'DepositMovementClassified', 'DepositMovementEarlyWarning')) {
    $signature = @($schemaDetails[$table] | ForEach-Object { "$($_.ColumnName):$($_.ColumnType)" }) -join '|'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($signature))
    $name = "Check Schema $table"
    $command = ".show table $table schema as json | mv-expand with_itemindex=i c=todynamic(Schema).OrderedColumns | order by i asc | summarize Signature=strcat_array(make_list(strcat(tostring(c.Name),':',tostring(c.CslType))),'|') | where Signature!=base64_decode_tostring('$encoded')"
    $r.Add((Kql $name $command $schemaAfter))
    $guardName = "Validate Schema $table"
    $r.Add((Guard $guardName "@greater(int(activity('$name').output.count),0)" 'A source/output schema changed. Regenerate and review CR01 before replacing data.' $name))
    $schemaAfter = $guardName
}
$thresholdCheck = @'
let expected=print Scope=dynamic(["TOTAL_BANK","RETAILS","NON_RETAILS"])
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
'@
$schemaAfter = Add-Check $r 'Threshold Reference Keys' $thresholdCheck $schemaAfter
$register = @'
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
'@
$r.Add((Sql 'Register Frozen Manifest' $register $schemaAfter))
$r.Add((Lookup 'Read Manifest' "SELECT FileName FROM dbo.CR01RefreshManifest WHERE RefreshDate='@{variables('vRefreshDate')}' ORDER BY FileName;" 'Register Frozen Manifest' $false))
$literalPredicate = @'
IF EXISTS(SELECT 1 FROM dbo.CR01RefreshManifest
    WHERE RefreshDate='@{variables('vRefreshDate')}' AND FileName LIKE '%[^A-Z0-9_.]%')
    THROW 51107,'Unsafe filename in the frozen manifest.',1;
SELECT STRING_AGG(CONCAT('"',FileName,'"'),',') AS KqlFileList
FROM dbo.CR01RefreshManifest WHERE RefreshDate='@{variables('vRefreshDate')}';
'@
$r.Add((Lookup 'Read Manifest Predicate' $literalPredicate 'Read Manifest' $true))
$deleteNames = '@{activity(''Read Manifest Predicate'').output.firstRow.KqlFileList}'
$stage = 'CR01_Stage_@{formatDateTime(variables(''vRefreshDate''),''yyyyMMdd'')}'
$backupBronze = 'CR01_BackupBronze_@{formatDateTime(variables(''vRefreshDate''),''yyyyMMdd'')}'
$backupSilver = 'CR01_BackupSilver_@{formatDateTime(variables(''vRefreshDate''),''yyyyMMdd'')}'
$backupEwi = 'CR01_BackupEwi_@{formatDateTime(variables(''vRefreshDate''),''yyyyMMdd'')}'
$unrelatedBronze = 'CR01_UnrelatedBronze_@{formatDateTime(variables(''vRefreshDate''),''yyyyMMdd'')}'
$unrelatedSilver = 'CR01_UnrelatedSilver_@{formatDateTime(variables(''vRefreshDate''),''yyyyMMdd'')}'
$manifestKql = @'
let names=toscalar(print items=parse_json(base64_decode_tostring("@{base64(string(activity('Read Manifest').output.value))}"))
    | mv-expand items | summarize make_set(tostring(items.FileName)));
'@
$r.Add((Kql 'Create Frozen Staging Table' ".set $stage <| DepositMovement | take 0" 'Read Manifest Predicate'))
$mapping = @(
    for ($i = 0; $i -lt $schemas.DepositMovement.Count; $i++) {
        @{ Column = $schemas.DepositMovement[$i]; Properties = @{ Ordinal = $i.ToString() } }
    }
) | ConvertTo-Json -Depth 5 -Compress
$r.Add((Kql 'Create Staging Mapping' ".create-or-alter table $stage ingestion csv mapping 'DepositMovement_mapping' '$mapping'" 'Create Frozen Staging Table'))
$metadata = Copy-Object $metadataTemplate
$metadata.name = 'Read Source Version'
$metadata.dependsOn = @()
$metadata.policy.retry = 0
$metadata.typeProperties.fieldList = @('size', 'lastModified')
$metadata.typeProperties.datasetSettings.typeProperties.location.fileName = Expression '@item().FileName'
$metadata.typeProperties.datasetSettings.typeProperties.location.folderPath = 'inbound/statement'
$stageCopy = Copy-Object $copyTemplate
$stageCopy.name = 'Stage Source File'
$stageCopy.dependsOn = @(Dependencies 'Read Source Version')
$stageCopy.policy.retry = 0
$stageCopy.typeProperties.source.datasetSettings.typeProperties.location.fileName = Expression '@item().FileName'
$stageCopy.typeProperties.source.datasetSettings.typeProperties.location.folderPath = 'inbound/statement'
@($stageCopy.typeProperties.source.additionalColumns | Where-Object name -EQ 'file_name')[0].value = Expression '@item().FileName'
$stageCopy.typeProperties.sink.datasetSettings.typeProperties.table = Expression $stage
$capture = Sql 'Capture Source Control Totals' @'
UPDATE dbo.CR01RefreshManifest
SET SourceBytes=@{activity('Read Source Version').output.size},
    SourceLastModified='@{formatDateTime(activity('Read Source Version').output.lastModified,'yyyy-MM-ddTHH:mm:ss.ffffff')}',
    ExpectedRows=@{activity('Stage Source File').output.rowsCopied}
WHERE RefreshDate='@{variables('vRefreshDate')}' AND FileName='@{item().FileName}';
'@ 'Stage Source File'
$r.Add(@{ name = 'Stage All Overnight Files'; type = 'ForEach'; dependsOn = @(Dependencies 'Create Staging Mapping'); typeProperties = @{
    isSequential = $false; batchCount = 10; items = Expression "@activity('Read Manifest').output.value"
    activities = @($metadata, $stageCopy, $capture) } })
$r.Add((Lookup 'Read Staged Manifest' "SELECT FileName,ExpectedRows FROM dbo.CR01RefreshManifest WHERE RefreshDate='@{variables('vRefreshDate')}' ORDER BY FileName;" 'Stage All Overnight Files' $false))
$expectedCounts = @'
let expected=print items=parse_json(base64_decode_tostring("@{base64(string(activity('Read Staged Manifest').output.value))}"))
    | mv-expand items | project file_name=tostring(items.FileName), Expected=tolong(items.ExpectedRows);
'@
$stageCheck = "$expectedCounts expected | join kind=fullouter ($stage | summarize Actual=count() by file_name) on file_name | where isnull(Expected) or Expected!=coalesce(Actual,0) | project Problem=strcat(file_name,' stage count mismatch')"
$waitStage = @(
    (Kql 'Compute Staging Readiness' ".set-or-replace CR01_Checks <| $stageCheck" '')
    @{ name = 'Wait For Staging'; type = 'Wait'; dependsOn = @(Dependencies 'Compute Staging Readiness'); typeProperties = @{ waitTimeInSeconds = 5 } }
)
$r.Add(@{ name = 'Wait For Queryable Staging'; type = 'Until'; dependsOn = @(Dependencies 'Read Staged Manifest'); typeProperties = @{
    expression = Expression "@equals(int(activity('Compute Staging Readiness').output.count),0)"
    timeout = '0.00:30:00'; activities = $waitStage } })
$invalidSource = @"
$stage
| where isnull(Date) or isnull(Credit_Amount) or isnull(Debit_Amount) or isnull(Net_Amount)
    or isnull(Credit_Transaction) or isnull(Debit_Transaction) or isnull(Total_Transaction)
    or format_datetime(Date,'yyyyMMdd') != extract(@"^INTRADAY_SUMMARY_(\d{8})_",1,file_name)
    or replace_string(trim(@"\s",Time),':','') != strcat(
        extract(@"^INTRADAY_SUMMARY_\d{8}_(\d{4})_(\d{4})\.CSV$",1,file_name),'-',
        extract(@"^INTRADAY_SUMMARY_\d{8}_(\d{4})_(\d{4})\.CSV$",2,file_name))
| project Problem=strcat(file_name,' invalid source data or filename/business interval mismatch')
"@
$last = Add-Check $r 'Staged Source Contract' $invalidSource 'Wait For Queryable Staging'
$transform = @(Read-Kql '.show function Transform_DepositMovementClassified' -Management)[0]
$previewBody = [regex]::Replace($transform.Body, '\bDepositMovement\b', 'SourceRows')
$previewInput = @($schemaDetails.DepositMovement | ForEach-Object { "$($_.ColumnName):$($_.ColumnType)" }) -join ','
$transformEncoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($transform.Body))
$r.Add((Kql 'Check Silver Transformation Version' ".show function Transform_DepositMovementClassified | where Body!=base64_decode_tostring('$transformEncoded')" $last))
$r.Add((Guard 'Validate Silver Transformation Version' "@greater(int(activity('Check Silver Transformation Version').output.count),0)" 'Silver transformation changed since deployment. Regenerate the CR01 preview.' 'Check Silver Transformation Version'))
$r.Add((Kql 'Preview Existing Silver Classification' ".create-or-alter function CR01_PreviewSilver(SourceRows:($previewInput)) $previewBody" 'Validate Silver Transformation Version'))
$previewCheck = @"
let preview=CR01_PreviewSilver($stage);
let holidayDates=toscalar(ThailandFinancialInstitutionHoliday | summarize make_set(format_datetime(HolidayDate,'yyyy-MM-dd')));
let knownYears=toscalar(ThailandFinancialInstitutionHoliday | summarize make_set(getyear(HolidayDate)));
union
    (preview | where ClassificationStatus!='CLASSIFIED' | project Problem=strcat(file_name,' ',ClassificationStatus)),
    (preview | where IsFinancialInstitutionHoliday!=set_has_element(holidayDates,format_datetime(LocalDate,'yyyy-MM-dd'))
        | project Problem=strcat(file_name,' holiday classification disagrees with reference')),
    ($stage | distinct Year=getyear(Date) | where not(set_has_element(knownYears,Year))
        | project Problem=strcat('Holiday reference year missing: ',Year)),
    (print StageRows=toscalar($stage | count),PreviewRows=toscalar(preview | count)
        | where StageRows!=PreviewRows | project Problem='Silver preview is not row preserving')
"@
$last = Add-Check $r 'Preview Calendar Classification' $previewCheck 'Preview Existing Silver Classification'
$versionMetadata = Copy-Object $metadata
$versionMetadata.name = 'Recheck Source Version'
$versionCheck = Sql 'Reject Changed Source' @'
IF NOT EXISTS(SELECT 1 FROM dbo.CR01RefreshManifest
    WHERE RefreshDate='@{variables('vRefreshDate')}' AND FileName='@{item().FileName}'
    AND SourceBytes=@{activity('Recheck Source Version').output.size}
    AND SourceLastModified='@{formatDateTime(activity('Recheck Source Version').output.lastModified,'yyyy-MM-ddTHH:mm:ss.ffffff')}')
    THROW 51103, 'Source changed while staging. No live deposit rows may be deleted.', 1;
'@ 'Recheck Source Version'
$r.Add(@{ name = 'Validate Frozen Source Versions'; type = 'ForEach'; dependsOn = @(Dependencies $last); typeProperties = @{
    isSequential = $false; batchCount = 10; items = Expression "@activity('Read Manifest').output.value"
    activities = @($versionMetadata, $versionCheck) } })
$windowGuard = @"
$manifestKql
union (DepositMovement | project file_name), (DepositMovementClassified | project file_name)
| where file_name startswith strcat('INTRADAY_SUMMARY_',format_datetime(datetime(@{variables('vRefreshDate')})-1d,'yyyyMMdd'))
    or file_name startswith strcat('INTRADAY_SUMMARY_',format_datetime(datetime(@{variables('vRefreshDate')}),'yyyyMMdd'))
| extend t=toint(extract(@"^INTRADAY_SUMMARY_\d{8}_(\d{4})_",1,file_name)),
    d=extract(@"^INTRADAY_SUMMARY_(\d{8})_",1,file_name)
| where isnull(t) or (d==format_datetime(datetime(@{variables('vRefreshDate')})-1d,'yyyyMMdd') and t>=2230)
    or (d==format_datetime(datetime(@{variables('vRefreshDate')}),'yyyyMMdd') and t<330)
| where file_name !in (names)
| distinct Problem=strcat(file_name,' is loaded but absent from the frozen manifest')
"@
$last = Add-Check $r 'Loaded File Coverage' $windowGuard 'Validate Frozen Source Versions'
$viewNames = ($views.Name | ForEach-Object { $_ | ConvertTo-Json -Compress }) -join ','
$r.Add((Kql 'Read Existing Gold Views' ".show materialized-views | where Name in ($viewNames) | project Name,Query,SourceTable" $last))
$viewMismatch = @($views | ForEach-Object {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($_.Query))
    "(Name=='$($_.Name)' and Query!=base64_decode_tostring('$encoded'))"
}) -join ' or '
$r.Add((Kql 'Check Existing Gold Definitions' ".show materialized-views | where SourceTable in ('DepositMovement','DepositMovementClassified') | summarize Present=count(),Mismatch=countif(Name !in ($viewNames) or $viewMismatch or IsEnabled!=true or AutoUpdateSchema!=false or isnotnull(Lookback) or Folder!='Gold' or DocString!='')" 'Read Existing Gold Views'))
$r.Add((Guard 'Validate Gold Baseline' "@or(not(equals(int(activity('Check Existing Gold Definitions').output.value[0].Present),2)),not(equals(int(activity('Check Existing Gold Definitions').output.value[0].Mismatch),0)))" 'Gold definitions changed since deployment. Regenerate and review the CR01 artifacts.' 'Check Existing Gold Definitions'))
$last = 'Validate Gold Baseline'
foreach ($view in $views) {
    foreach ($policyName in @('retention', 'caching')) {
        $baseline = if ($policyName -eq 'retention') { $view.RetentionPolicy } else { $view.CachingPolicy }
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($baseline))
        $name = "Check $policyName $($view.Name)"
        $r.Add((Kql $name ".show materialized-view $($view.Name) policy $policyName | where Policy!=base64_decode_tostring('$encoded')" $last))
        $guardName = "Validate $policyName $($view.Name)"
        $r.Add((Guard $guardName "@greater(int(activity('$name').output.count),0)" 'A Gold policy changed since deployment. Stop and regenerate the restoration baseline.' $name))
        $last = $guardName
    }
}
foreach ($entry in @(
    @('Backup Target Bronze', $backupBronze, "DepositMovement | where file_name in (names)"),
    @('Backup Target Silver', $backupSilver, "DepositMovementClassified | where file_name in (names)"),
    @('Backup Both EWI Dates', $backupEwi, "DepositMovementEarlyWarning | where Date_ICT in (format_datetime(datetime(@{variables('vRefreshDate')})-1d,'yyyy-MM-dd'),'@{variables('vRefreshDate')}')")
)) {
    $r.Add((Kql $entry[0] ".set $($entry[1]) <| $manifestKql $($entry[2])" $last))
    $last = $entry[0]
}
foreach ($pair in @(@('DepositMovement', $unrelatedBronze), @('DepositMovementClassified', $unrelatedSilver))) {
    $columns = $schemas[$pair[0]] -join ','
    $query = "$manifestKql $($pair[0]) | where file_name !in (names) | summarize Copies=count() by Fingerprint=hash_sha256(tostring(pack_array($columns)))"
    $name = "Snapshot Unrelated $($pair[0])"
    $r.Add((Kql $name ".set $($pair[1]) <| $query" $last))
    $last = $name
}
$r.Add((Kql 'Hold Serving Visibility' ".set-or-append CR01_PublishState <| print IsReady=false, ChangedAtUtc=now(), Owner='@{pipeline().parameters.pControllerRunId}'" $last))
$last = 'Hold Serving Visibility'
foreach ($view in $views) {
    $name = "Drop $($view.Name)"
    $r.Add((Kql $name ".drop materialized-view $($view.Name)" $last)); $last = $name
}
$r.Add((Kql 'Delete Only Manifest Bronze' ".delete table DepositMovement records <| DepositMovement | where file_name in ($deleteNames)" $last))
$r.Add((Kql 'Delete Only Manifest Silver' ".delete table DepositMovementClassified records <| DepositMovementClassified | where file_name in ($deleteNames)" 'Delete Only Manifest Bronze'))
$last = Add-Check $r 'Empty Replacement Scope' "$manifestKql union (DepositMovement | project file_name),(DepositMovementClassified | project file_name) | where file_name in (names) | project Problem=file_name" 'Delete Only Manifest Silver'
$supersede = @'
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
'@
$r.Add((Sql 'Preserve And Supersede Audit' $supersede $last))
$r.Add((Kql 'Promote Frozen Overnight Snapshot' ".set-or-append DepositMovement <| $stage" 'Preserve And Supersede Audit'))
$businessColumns = @('Date','Time','Product','trim(@"\s",Channel)','Channel_Group','Credit_Amount','Debit_Amount','Net_Amount','Credit_Transaction','Debit_Transaction','Total_Transaction') -join ','
$signature = "file_name,Fingerprint=tostring(pack_array($businessColumns))"
$stageRows = "$stage | summarize Expected=count() by $signature"
$compare = @(
    foreach ($table in @('DepositMovement', 'DepositMovementClassified')) {
        "($stageRows | join kind=fullouter ($table | where file_name in (names) | summarize Actual=count() by $signature) on file_name,Fingerprint | where coalesce(Expected,0)!=coalesce(Actual,0) | project Problem=strcat('$table ',file_name,' business-row mismatch'))"
    }
) -join ','
$queryableQuery = "$manifestKql union $compare"
$r.Add(@{ name = 'Wait For Bronze And Silver'; type = 'Until'; dependsOn = @(Dependencies 'Promote Frozen Overnight Snapshot'); typeProperties = @{
    expression = Expression "@equals(int(activity('Compute Replayed Row Mismatches').output.count),0)"
    timeout = '0.00:30:00'; activities = @(
        (Kql 'Compute Replayed Row Mismatches' ".set-or-replace CR01_Checks <| $queryableQuery" '')
        @{ name = 'Wait For Replay'; type = 'Wait'; dependsOn = @(Dependencies 'Compute Replayed Row Mismatches'); typeProperties = @{ waitTimeInSeconds = 5 } }
    ) } })
$last = Add-Check $r 'Silver Classification' "$manifestKql DepositMovementClassified | where file_name in (names) and ClassificationStatus!='CLASSIFIED' | project Problem=strcat(file_name,' ',ClassificationStatus)" 'Wait For Bronze And Silver'
foreach ($pair in @(@('DepositMovement', $unrelatedBronze), @('DepositMovementClassified', $unrelatedSilver))) {
    $columns = $schemas[$pair[0]] -join ','
    $query = "$manifestKql $($pair[1]) | project Fingerprint,Before=Copies | join kind=fullouter ($($pair[0]) | where file_name !in (names) | summarize After=count() by Fingerprint=hash_sha256(tostring(pack_array($columns)))) on Fingerprint | where coalesce(Before,0)!=coalesce(After,0) | project Problem='Unrelated source rows changed'"
    $last = Add-Check $r "Unrelated $($pair[0])" $query $last
}
foreach ($view in $views) {
    $name = "Rebuild $($view.Name)"
    $folder = $view.Folder | ConvertTo-Json -Compress
    $doc = $view.DocString | ConvertTo-Json -Compress
    $create = ".create materialized-view with (backfill=true,folder=$folder,docstring=$doc) $($view.Name) on table $($view.SourceTable) { $($view.Query) }"
    $r.Add((Kql $name $create $last)); $last = $name
    if ($view.CachingPolicy -ne 'null') {
        $name = "Restore Caching $($view.Name)"
        $r.Add((Kql $name ".alter materialized-view $($view.Name) policy caching hot = 90d" $last)); $last = $name
    }
    $columns = $schemas[$view.Name] -join ','
    $query = "let expected=$($view.Query) | summarize Expected=count() by Fingerprint=tostring(pack_array($columns)); expected | join kind=fullouter ($($view.Name) | summarize Actual=count() by Fingerprint=tostring(pack_array($columns))) on Fingerprint | where coalesce(Expected,0)!=coalesce(Actual,0) | project Problem='Gold MV does not reconcile with corrected source'"
    $last = Add-Check $r "Reconciled $($view.Name)" $query $last
}
$r.Add(@{ name = 'Wait For Healthy Gold Views'; type = 'Until'; dependsOn = @(Dependencies $last); typeProperties = @{
    expression = Expression "@and(equals(int(activity('Read Gold Health').output.value[0].Present),2),equals(int(activity('Read Gold Health').output.value[0].Unhealthy),0))"
    timeout = '0.01:00:00'; activities = @(
        (Kql 'Read Gold Health' ".show materialized-views | where Name in ($viewNames) | summarize Present=count(),Unhealthy=countif(IsHealthy!=true or IsEnabled!=true)" '')
        @{ name = 'Wait For Materialization'; type = 'Wait'; dependsOn = @(Dependencies 'Read Gold Health'); typeProperties = @{ waitTimeInSeconds = 5 } }
    ) } })
$last = 'Wait For Healthy Gold Views'
$levelCheck = "union (Gold_EarlyWarning(datetime(@{variables('vRefreshDate')})-1d)),(Gold_EarlyWarning(datetime(@{variables('vRefreshDate')}))) | where isnull(Alert_Rank) or Alert_Rank<0 or Alert_Rank>3 or Alert_Level !in ('L0','L1','L2','L3') | project Problem='Invalid EWI level/rank before persistence'"
$last = Add-Check $r 'EWI Level Contract' $levelCheck $last
$dateFilter = "Date_ICT in (format_datetime(datetime(@{variables('vRefreshDate')})-1d,'yyyy-MM-dd'),'@{variables('vRefreshDate')}')"
$r.Add((Kql 'Delete Affected Persisted EWI Dates' ".delete table DepositMovementEarlyWarning records <| DepositMovementEarlyWarning | where $dateFilter" $last))
$r.Add((Kql 'Recompute Both Complete EWI Dates' ".set-or-append DepositMovementEarlyWarning <| union (Gold_EarlyWarning(datetime(@{variables('vRefreshDate')})-1d)),(Gold_EarlyWarning(datetime(@{variables('vRefreshDate')}))) | project $ewiProjection" 'Delete Affected Persisted EWI Dates'))
$grainQuery = "DepositMovementEarlyWarning | where $dateFilter | summarize Copies=count() by Object_Id,Bucket_Start | where Copies!=1 | project Problem='Stored EWI grain is not one row per scope/indicator/bucket'"
$grainAfter = Add-Check $r 'Persisted EWI Grain' $grainQuery 'Recompute Both Complete EWI Dates'
$ewiColumns = @($schemas.DepositMovementEarlyWarning | Where-Object { $_ -ne 'Alert_Time' }) -join ','
$ewiQuery = "let e=union (Gold_EarlyWarning(datetime(@{variables('vRefreshDate')})-1d)),(Gold_EarlyWarning(datetime(@{variables('vRefreshDate')}))) | project $ewiProjection; e | summarize Expected=count() by Fingerprint=tostring(pack_array($ewiColumns)) | join kind=fullouter (DepositMovementEarlyWarning | where $dateFilter | summarize Actual=count() by Fingerprint=tostring(pack_array($ewiColumns))) on Fingerprint | where coalesce(Expected,0)!=coalesce(Actual,0) | project Problem='Persisted EWI mismatch'"
$last = Add-Check $r 'Reconciled Persisted EWI' $ewiQuery $grainAfter
$complete = @'
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
'@
$r.Add((Sql 'Commit Verified Refresh' $complete $last))
Save-Pipeline 'pl_CR01_DepositMovement_OvernightRefresh' @($r.ToArray()) @{
    pRefreshDate = @{ type = 'string' }; pControllerRunId = @{ type = 'string' }
    pSourceIntervalMinutes = @{ type = 'int'; defaultValue = 15 }
    pSourceFinalized = @{ type = 'bool'; defaultValue = $false }
} @{ vRefreshDate = @{ type = 'String' }; vLoadTs = @{ type = 'String' } }

if ($RefreshPipelineId -and $DiscoveryPipelineId) {
    $c = [Collections.Generic.List[object]]::new()
    $c.Add((Guard 'Require Approved Cutover' '@not(and(pipeline().parameters.pEnableProcessing,pipeline().parameters.pCutoverConfirmed))' 'CR01 processing is disabled until storage, consumers, and writer cutover are approved.' ''))
    $c.Add(@{ name = 'Freeze Run ICT'; type = 'SetVariable'; dependsOn = @(Dependencies 'Require Approved Cutover'); typeProperties = @{
        variableName = 'vRunICT'; value = Expression "@convertFromUtc(utcNow(),'SE Asia Standard Time')" } })
    $c.Add((Guard 'Require First Refresh Date' "@empty(pipeline().parameters.pFirstRefreshDate)" 'Set the first approved refresh date; no historical date is assumed.' 'Freeze Run ICT'))
    $c.Add(@{ name = 'Normalize First Refresh Date'; type = 'SetVariable'; dependsOn = @(Dependencies 'Require First Refresh Date'); typeProperties = @{
        variableName = 'vFirstRefreshDate'; value = Expression "@formatDateTime(pipeline().parameters.pFirstRefreshDate,'yyyy-MM-dd')" } })
    $c.Add((Kql 'Acquire Global Controller Lock' ".set CR01_ControllerLock <| print Owner='@{pipeline().RunId}',StartedAtUtc=now()" 'Normalize First Refresh Date'))
    $controlSql = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\sql\01-create-CR01-control.sql') -Raw
    $c.Add((Sql 'Initialize CR01 Control Tables' $controlSql 'Acquire Global Controller Lock'))
    $c.Add((Sql 'Register Controller Owner' "INSERT INTO dbo.CR01ControllerRun VALUES('@{pipeline().RunId}','Running',SYSUTCDATETIME(),NULL);" 'Initialize CR01 Control Tables'))
    $c.Add((Kql 'Initialize Serving State' '.create-merge table CR01_PublishState (IsReady:bool,ChangedAtUtc:datetime,Owner:string)' 'Register Controller Owner'))
    $controllerReferenceGuard = Add-Check $c 'Threshold Reference Keys' $thresholdCheck 'Initialize Serving State'
    $nextDate = @'
DECLARE @first DATE=TRY_CONVERT(DATE,'@{variables('vFirstRefreshDate')}',23);
IF @first IS NULL THROW 51105,'Invalid first refresh date.',1;
DECLARE @now DATETIME2(6)='@{variables('vRunICT')}';
DECLARE @due DATE=CAST(DATEADD(DAY,CASE WHEN CAST(@now AS TIME)<'03:30' THEN -1 ELSE 0 END,@now) AS DATE);
DECLARE @last DATE=(SELECT MAX(RefreshDate) FROM dbo.CR01RefreshRun WHERE Status='Completed');
DECLARE @next DATE=CASE WHEN @last IS NULL THEN @first ELSE DATEADD(DAY,1,@last) END;
IF EXISTS(SELECT 1 FROM dbo.CR01RefreshRun WHERE Status<>'Completed')
    THROW 51106,'An incomplete refresh requires recovery with its original manifest.',1;
SELECT CASE WHEN @next<=@due THEN 1 ELSE 0 END AS HasDue,CONVERT(VARCHAR(10),@next,23) AS RefreshDate;
'@
    $dueLookup = Lookup 'Lookup Next Refresh' $nextDate '' $true
    $runRefresh = Invoke-Child 'Invoke Overnight Refresh' $RefreshPipelineId @{
        pRefreshDate = Expression "@activity('Lookup Next Refresh').output.firstRow.RefreshDate"
        pControllerRunId = Expression '@pipeline().RunId'
        pSourceIntervalMinutes = Expression '@pipeline().parameters.pSourceIntervalMinutes'
        pSourceFinalized = Expression '@pipeline().parameters.pSourceFinalized'
    } ''
    $dueBranch = @{
        name = 'Run Due Refresh'; type = 'IfCondition'; dependsOn = @(Dependencies 'Lookup Next Refresh')
        typeProperties = @{ expression = Expression "@equals(int(activity('Lookup Next Refresh').output.firstRow.HasDue),1)"
            ifTrueActivities = @($runRefresh); ifFalseActivities = @() }
    }
    $c.Add(@{ name = 'Finish All Due Refreshes'; type = 'Until'; dependsOn = @(Dependencies $controllerReferenceGuard); typeProperties = @{
        expression = Expression "@equals(int(activity('Lookup Next Refresh').output.firstRow.HasDue),0)"
        timeout = '0.12:00:00'; activities = @($dueLookup, $dueBranch) } })
    $c.Add((Invoke-Child 'Invoke Normal Discovery' $DiscoveryPipelineId @{
        pControllerRunId = Expression '@pipeline().RunId'; pRunICT = Expression "@variables('vRunICT')"
    } 'Finish All Due Refreshes'))
    $append = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\04-gold-summary-table\kql\15-append-DepositMovementEarlyWarning.kql') -Raw
    $append = [regex]::Match($append, '(?s)\.set-or-append DepositMovementEarlyWarning <\|.*?(?=\r?\n//)').Value.Trim()
    if (-not $append) { throw 'Cannot extract the existing idempotent EWI append command.' }
    $append = $append.Replace('startofday(now() + 7h)', 'startofday(datetime(@{variables(''vRunICT'')}))').
        Replace('Gold_EarlyWarning()', 'Gold_EarlyWarning(datetime(@{variables(''vRunICT'')}))')
    $append += "`n| project $ewiProjection"
    $c.Add((Kql 'Append Normal EWI Buckets' $append 'Invoke Normal Discovery'))
    $c.Add((Kql 'Publish Verified Data' ".set-or-append CR01_PublishState <| print IsReady=true,ChangedAtUtc=now(),Owner='@{pipeline().RunId}'" 'Append Normal EWI Buckets'))
    $c.Add((Sql 'Complete Controller Owner' "UPDATE dbo.CR01ControllerRun SET Status='Completed',CompletedAtUtc=SYSUTCDATETIME() WHERE RunId='@{pipeline().RunId}' AND Status='Running';" 'Publish Verified Data'))
    $c.Add((Kql 'Release Owned Controller Lock' '.drop table CR01_ControllerLock' 'Complete Controller Owner'))
    Save-Pipeline 'pl_CR01_DepositMovement_24x7' @($c.ToArray()) @{
        pEnableProcessing = @{ type = 'bool'; defaultValue = $false }
        pCutoverConfirmed = @{ type = 'bool'; defaultValue = $false }
        pFirstRefreshDate = @{ type = 'string'; defaultValue = '' }
        pSourceFinalized = @{ type = 'bool'; defaultValue = $false }
        pSourceIntervalMinutes = @{ type = 'int'; defaultValue = 15 }
    } @{ vRunICT = @{ type = 'String' }; vFirstRefreshDate = @{ type = 'String' } }
}
Write-Output 'Generated separate CR01 definitions. Existing pipeline definitions and schedules were not changed.'
