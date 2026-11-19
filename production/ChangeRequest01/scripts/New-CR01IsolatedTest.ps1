[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AzureConfigDirectory,
    [Parameter(Mandatory)][string]$ManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:AZURE_CONFIG_DIR = $AzureConfigDirectory
$token = az account get-access-token --resource 'https://kusto.kusto.windows.net' --query accessToken -o tsv
if ($LASTEXITCODE -ne 0) { throw 'Kusto authentication failed.' }
$headers = @{ Authorization = "Bearer $token"; Accept = 'application/json' }
$prefix = 'CR01Test_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '_'
$pipelineName = 'pl_CR01_IsolatedRefreshTest'
$root = Join-Path $PSScriptRoot '..\pipeline'
$refresh = Get-Content -LiteralPath (Join-Path $root 'pl_CR01_DepositMovement_OvernightRefresh.json') -Raw | ConvertFrom-Json -AsHashtable
$views = @(Get-Content -LiteralPath (Join-Path $root 'CR01-materialized-view-baseline.json') -Raw | ConvertFrom-Json)
$date = '2026-11-18'
$owner = [guid]::NewGuid().ToString()
$sourceNames = @('INTRADAY_SUMMARY_20261117_2300_2330.CSV', 'INTRADAY_SUMMARY_20261118_0000_0030.CSV')
$manifest = @($sourceNames | ForEach-Object { @{ FileName = $_; ExpectedRows = 1 } }) | ConvertTo-Json -Compress
$encodedManifest = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($manifest))
$literalNames = @($sourceNames | ForEach-Object { $_ | ConvertTo-Json -Compress }) -join ','
$kqlTemplate = @($refresh.properties.activities | Where-Object type -EQ 'KustoQueryLanguage')[0]
$activities = [Collections.Generic.List[object]]::new()
$createdTables = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$createdFunctions = @("${prefix}Transform_DepositMovementClassified", "${prefix}Gold_EarlyWarning", "${prefix}CR01_PreviewSilver")
$last = ''

function Read-Metadata([string]$Command) {
    $r = Invoke-RestMethod -Uri 'https://trd-k344krpm42xbxq2184.z5.kusto.fabric.microsoft.com/v1/rest/mgmt' `
        -Method Post -Headers $headers -ContentType 'application/json' `
        -Body (@{ db = 'DepositMovement'; csl = $Command } | ConvertTo-Json) -TimeoutSec 90
    $t = $r.Tables[0]
    foreach ($row in $t.Rows) {
        $o = [ordered]@{}
        for ($i = 0; $i -lt $t.Columns.Count; $i++) { $o[$t.Columns[$i].ColumnName] = $row[$i] }
        [pscustomobject]$o
    }
}
function Copy-Node($Node) { $Node | ConvertTo-Json -Depth 80 | ConvertFrom-Json -AsHashtable }
function Remap([string]$Text) {
    foreach ($view in $views) {
        $old = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($view.Query))
        $newQuery = $view.Query
        foreach ($name in @('DepositMovementClassified', 'DepositMovement')) {
            $newQuery = [regex]::Replace($newQuery, "\b$name\b", "$prefix$name")
        }
        $new = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($newQuery))
        $Text = $Text.Replace($old, $new)
    }
    $Text = $Text.Replace("@{base64(string(activity('Read Manifest').output.value))}", $encodedManifest).
        Replace("@{base64(string(activity('Read Staged Manifest').output.value))}", $encodedManifest).
        Replace("@{activity('Read Manifest Predicate').output.firstRow.KqlFileList}", $literalNames).
        Replace("@{formatDateTime(variables('vRefreshDate'),'yyyyMMdd')}", '20261118').
        Replace("@{variables('vRefreshDate')}", $date).
        Replace("@{pipeline().parameters.pControllerRunId}", $owner)
    $Text = [regex]::Replace($Text, '\bCR01_([A-Za-z0-9_]+)', "${prefix}CR01_`$1")
    foreach ($name in @('DepositMovementEarlyWarning','DepositMovementClassified','DepositMovement','Gold_EarlyWarning','EWI_AlertThreshold','mv_Summary_Product_Channel_Alert','mv_EarlyWarning_Base')) {
        $Text = [regex]::Replace($Text, "\b$name\b", "$prefix$name")
    }
    if ($Text.Contains('@{')) { throw "Unresolved pipeline interpolation in test command: $Text" }
    $Text
}
function Add-Kql([string]$Name, [string]$Command) {
    $node = Copy-Node $kqlTemplate
    $node.name = $Name
    $node.dependsOn = @(if ($script:last) { @{ activity = $script:last; dependencyConditions = @('Succeeded') } })
    $node.typeProperties.command = $Command
    $activities.Add($node)
    $script:last = $Name
    if ($Command -match '^\.(?:set|set-or-replace|set-or-append)\s+([A-Za-z0-9_]+)') {
        [void]$createdTables.Add($Matches[1])
    }
}

foreach ($command in @(
    ".show tables | where TableName startswith '$prefix'",
    ".show materialized-views | where Name startswith '$prefix'",
    ".show functions | where Name startswith '$prefix'"
)) {
    if (@(Read-Metadata $command).Count) { throw 'Generated test namespace is not empty. Refusing to reuse it.' }
}
foreach ($table in @('DepositMovement', 'DepositMovementClassified', 'DepositMovementEarlyWarning')) {
    Add-Kql "Clone Schema $table" ".set $prefix$table <| $table | take 0"
}
Add-Kql 'Disable Test Streaming' ".alter table ${prefix}DepositMovement policy streamingingestion disable"
Add-Kql 'Create Clean Isolated Threshold Fixture' ".set ${prefix}EWI_AlertThreshold <| EWI_AlertThreshold | distinct *"
$transform = @(Read-Metadata '.show function Transform_DepositMovementClassified')[0]
$transformBody = [regex]::Replace($transform.Body, '\bDepositMovement\b', "${prefix}DepositMovement")
Add-Kql 'Create Test Classification Function' ".create function ${prefix}Transform_DepositMovementClassified() $transformBody"
$gold = @(Read-Metadata '.show function Gold_EarlyWarning')[0]
$goldBody = [regex]::Replace($gold.Body, '\bDepositMovementClassified\b', "${prefix}DepositMovementClassified")
$goldBody = [regex]::Replace($goldBody, '\bEWI_AlertThreshold\b', "${prefix}EWI_AlertThreshold")
Add-Kql 'Create Test EWI Function' ".create function ${prefix}Gold_EarlyWarning$($gold.Parameters) $goldBody"
$policy = ConvertTo-Json -InputObject @(@{
    IsEnabled = $true; Source = "${prefix}DepositMovement"
    Query = "${prefix}Transform_DepositMovementClassified()"
    IsTransactional = $true; PropagateIngestionProperties = $true
}) -Compress
Add-Kql 'Enable Test Classification Policy' ".alter table ${prefix}DepositMovementClassified policy update '$policy'"
Add-Kql 'Create Test Visibility State' ".create table ${prefix}CR01_PublishState (IsReady:bool,ChangedAtUtc:datetime,Owner:string)"
[void]$createdTables.Add("${prefix}CR01_PublishState")
$schema = 'Date:datetime,Time:string,Product:string,Channel:string,Channel_Group:string,Credit_Amount:decimal,Debit_Amount:decimal,Net_Amount:decimal,Credit_Transaction:long,Debit_Transaction:long,Total_Transaction:long,load_ts:datetime,file_name:string,pipeline_name:string,pipeline_runid:string'
$oldRows = @"
datetime(2026-11-17),"23:00-23:30","S","ENET","Retail",decimal(100),decimal(50),decimal(50),10,5,15,datetime(2026-11-18T03:00:00),"$($sourceNames[0])","CR01Test","old1",
datetime(2026-11-18),"00:00-00:30","S","ENET","Retail",decimal(200),decimal(100),decimal(100),20,10,30,datetime(2026-11-18T03:00:00),"$($sourceNames[1])","CR01Test","old2",
datetime(2026-11-17),"12:00-12:30","S","ENET","Retail",decimal(10),decimal(5),decimal(5),1,1,2,datetime(2026-11-17T12:30:00),"INTRADAY_SUMMARY_20261117_1200_1230.CSV","CR01Test","unrelated"
"@
Add-Kql 'Seed Original Test Data' ".set-or-append ${prefix}DepositMovement <| datatable($schema)[$oldRows]"
foreach ($view in $views) {
    $create = @($refresh.properties.activities | Where-Object name -EQ "Rebuild $($view.Name)")[0].typeProperties.command
    if ($create -is [hashtable]) { $create = $create.value }
    Add-Kql "Seed $($view.Name)" (Remap $create)
    if ($view.CachingPolicy -ne 'null') {
        Add-Kql "Seed Caching $($view.Name)" ".alter materialized-view $prefix$($view.Name) policy caching hot = 90d"
    }
}
$seedEwi = @($refresh.properties.activities | Where-Object name -EQ 'Recompute Both Complete EWI Dates')[0].typeProperties.command
if ($seedEwi -is [hashtable]) { $seedEwi = $seedEwi.value }
Add-Kql 'Seed Old EWI Snapshots' (Remap $seedEwi)
$testStage = "${prefix}CR01_Stage_20261118"
Add-Kql 'Create Corrected Staging Schema' ".set $testStage <| DepositMovement | take 0"
$newRows = @"
datetime(2026-11-17),"23:00-23:30","S","ENET","Retail",decimal(150),decimal(70),decimal(80),15,7,22,datetime(2026-11-18T03:30:00),"$($sourceNames[0])","CR01Test","new1",
datetime(2026-11-18),"00:00-00:30","S","ENET","Retail",decimal(220),decimal(110),decimal(110),22,11,33,datetime(2026-11-18T03:30:00),"$($sourceNames[1])","CR01Test","new2"
"@
Add-Kql 'Seed Adjusted Overnight Version' ".set-or-append $testStage <| datatable($schema)[$newRows]"
Add-Kql 'Create Intentional Verifier Mismatch' ".set ${prefix}VerifierNegative <| print Problem='Intentional negative-test row'"
$activities.Add(@{
    name = 'Require Negative Verifier Detection'; type = 'IfCondition'
    dependsOn = @(@{ activity=$last; dependencyConditions=@('Succeeded') })
    typeProperties = @{
        expression = @{ type='Expression'; value="@not(greater(int(activity('Create Intentional Verifier Mismatch').output.count),0))" }
        ifTrueActivities = @(@{ name='Fail Negative Verifier Test'; type='Fail'; dependsOn=@(); typeProperties=@{
            errorCode='CR01_VERIFIER_FAILED'; message='A deliberate mismatch was not detected from the synchronous ingestion result.' } })
        ifFalseActivities = @()
    }
})
$last = 'Require Negative Verifier Detection'
$start = $false
foreach ($original in $refresh.properties.activities) {
    if ($original.name -eq 'Wait For Queryable Staging') { $start = $true }
    if ((-not $start -and $original.name -notin @('Compute Threshold Reference Keys','Validate Threshold Reference Keys')) -or
        $original.type -notin @('KustoQueryLanguage', 'IfCondition', 'Until')) { continue }
    $node = Copy-Node $original
    # Remap command strings, not expression/JSON escaping.
    function Rewrite-Commands($Value) {
        if ($Value -is [Collections.IDictionary]) {
            if ($Value.Contains('command')) {
                $command = $Value.command
                if ($command -is [Collections.IDictionary]) { $command = $command.value }
                $Value.command = Remap ([string]$command)
                $mapped = [string]$Value.command
                if ($mapped -match '^\.(?:set|set-or-replace|set-or-append)\s+([A-Za-z0-9_]+)') {
                    [void]$createdTables.Add($Matches[1])
                }
            }
            foreach ($key in @($Value.Keys)) { Rewrite-Commands $Value[$key] }
        }
        elseif ($Value -is [array]) { foreach ($entry in $Value) { Rewrite-Commands $entry } }
    }
    Rewrite-Commands $node
    $node.dependsOn = @(@{ activity = $last; dependencyConditions = @('Succeeded') })
    $activities.Add($node)
    $last = $node.name
}
$finalCheck = @"
.set-or-replace ${prefix}FinalChecks <|
    let b=toscalar(${prefix}DepositMovement | summarize sum(Net_Amount));
    let n=toscalar(${prefix}DepositMovement | count);
    let s=toscalar(${prefix}DepositMovementClassified | count);
    let e=toscalar(${prefix}DepositMovementEarlyWarning | count);
    union
        (print Problem="Wrong corrected Bronze/Silver/EWI total/count" | where b!=decimal(195) or n!=3 or s!=3 or e!=72),
        (${prefix}Gold_EarlyWarning(datetime(2026-11-17))
            | where Scope=="TOTAL_BANK" and IndicatorKey=="AccumNetOutflow_MB"
            | summarize arg_max(Bucket_Start,Value),Rows=count()
            | where Rows!=2 or abs(Value-0.000085)>1e-12 | project Problem="Previous-day cumulative EWI is stale"),
        (${prefix}Gold_EarlyWarning(datetime(2026-11-18))
            | where Scope=="TOTAL_BANK" and IndicatorKey=="AccumNetOutflow_MB"
            | summarize arg_max(Bucket_Start,Value),Rows=count()
            | where Rows!=1 or abs(Value-0.000110)>1e-12 | project Problem="Current-day cumulative EWI is stale")
"@
Add-Kql 'Assert Known Corrected Amounts' $finalCheck
$activities.Add(@{
    name = 'Require Exact Test Pass'; type = 'IfCondition'
    dependsOn = @(@{ activity = $last; dependencyConditions = @('Succeeded') })
    typeProperties = @{
        expression = @{ value = "@greater(int(activity('Assert Known Corrected Amounts').output.count),0)"; type = 'Expression' }
        ifTrueActivities = @(@{ name = 'Fail Isolated Refresh Test'; type = 'Fail'; typeProperties = @{
            errorCode = 'CR01_TEST_FAILED'; message = 'Isolated corrected amounts or cumulative EWI did not match expectations.' } })
        ifFalseActivities = @()
    }
})
$path = Join-Path $root "$pipelineName.json"
@{ properties = @{ activities = @($activities.ToArray()) } } | ConvertTo-Json -Depth 90 |
    Set-Content -LiteralPath $path -Encoding utf8
@{
    TestPrefix = $prefix
    PipelineName = $pipelineName
    DefinitionPath = [IO.Path]::GetFullPath($path)
    Tables = @($createdTables)
    Functions = $createdFunctions
    MaterializedViews = @($views.Name | ForEach-Object { "$prefix$_" })
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ManifestPath -Encoding utf8
[pscustomobject]@{ DefinitionPath = $path; ManifestPath = $ManifestPath; TestPrefix = $prefix }
