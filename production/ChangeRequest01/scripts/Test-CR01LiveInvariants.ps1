[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AzureConfigDirectory,
    [Parameter(Mandatory)][string]$EvidencePath,
    [string]$OriginalSnapshotDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:AZURE_CONFIG_DIR = $AzureConfigDirectory
$evidence = [Collections.Generic.List[object]]::new()
$root = Join-Path $PSScriptRoot '..\pipeline'
$refresh = Get-Content -LiteralPath (Join-Path $root 'pl_CR01_DepositMovement_OvernightRefresh.json') -Raw | ConvertFrom-Json
$sql = @($refresh.properties.activities | Where-Object name -EQ 'Register Frozen Manifest')[0].typeProperties.scripts[0].text.value
$select = [regex]::Match($sql, '(?s)SELECT @d, CONCAT.*$').Value
if (-not $select -or $select -match '\b(INSERT|UPDATE|DELETE|CREATE|DROP|ALTER|MERGE)\b') {
    throw 'Cannot isolate the read-only manifest SELECT from the actual refresh definition.'
}
$sqlToken = az account get-access-token --resource 'https://database.windows.net/' --query accessToken -o tsv
if ($LASTEXITCODE -ne 0) { throw 'SQL authentication failed.' }
$connection = [Data.SqlClient.SqlConnection]::new(
    'Server=tcp:k35aq6omcxkejht6cuywxdyb4q-hnymx4hlfrzuviycqeyfpqdeci.datawarehouse.fabric.microsoft.com,1433;Database=wh_control_framework;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;')
$connection.AccessToken = $sqlToken
$dueTable = 'dbo.CR01Test_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '_DueState'
$dueCreated = $false
try {
    $connection.Open()
    foreach ($case in @(
        @('2026-11-18', 30), @('2026-11-18', 15), @('2027-01-01', 30), @('2028-03-01', 15)
    )) {
        $date = [datetime]::ParseExact($case[0], 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        $step = [int]$case[1]
        $command = $connection.CreateCommand()
        $command.CommandText = "DECLARE @d DATE='$($case[0])'; DECLARE @step INT=$step; $select"
        $command.CommandTimeout = 90
        $table = [Data.DataTable]::new()
        $table.Load($command.ExecuteReader())
        $actual = @($table.Rows | ForEach-Object { [string]$_[1] } | Sort-Object)
        $expected = @(
            for ($cursor = $date.AddMinutes(-90); $cursor -lt $date.AddMinutes(210); $cursor = $cursor.AddMinutes($step)) {
                $end = $cursor.AddMinutes($step)
                $endLabel = if ($end.Date -gt $cursor.Date) { '2400' } else { $end.ToString('HHmm') }
                'INTRADAY_SUMMARY_{0}_{1}_{2}.CSV' -f $cursor.ToString('yyyyMMdd'), $cursor.ToString('HHmm'), $endLabel
            }
        ) | Sort-Object
        if ($actual.Count -ne 300 / $step -or @(Compare-Object $actual $expected).Count) {
            throw "Live Warehouse manifest boundaries failed: $($case[0]), interval $step."
        }
        $evidence.Add(@{ Test = "Manifest $($case[0]) / ${step}min"; Status = 'Passed'; FileCount = $actual.Count })
        Write-Output "PASS live SQL manifest: $($case[0]), ${step}-minute files, $($actual.Count) exact filenames."
    }
    $controller = Get-Content -LiteralPath (Join-Path $root 'pl_CR01_DepositMovement_24x7.json') -Raw | ConvertFrom-Json
    $loop = @($controller.properties.activities | Where-Object name -EQ 'Finish All Due Refreshes')[0]
    $dueSql = @($loop.typeProperties.activities | Where-Object name -EQ 'Lookup Next Refresh')[0].typeProperties.source.sqlReaderQuery.value
    $dueSql = $dueSql.Replace('dbo.CR01RefreshRun', $dueTable).
        Replace("@{variables('vFirstRefreshDate')}", '2026-11-18')
    $command = $connection.CreateCommand()
    $command.CommandText = "CREATE TABLE $dueTable (RefreshDate DATE NOT NULL,Status VARCHAR(20) NOT NULL);"
    [void]$command.ExecuteNonQuery()
    $dueCreated = $true
    foreach ($phase in @('Empty', 'Completed')) {
        if ($phase -eq 'Completed') {
            $command.CommandText = "INSERT INTO $dueTable VALUES('2026-11-18','Completed');"
            [void]$command.ExecuteNonQuery()
        }
        $cases = if ($phase -eq 'Empty') {
            @(@('2026-11-18T03:00:00', 0, '2026-11-18'), @('2026-11-18T03:30:00', 1, '2026-11-18'))
        }
        else {
            @(@('2026-11-19T03:00:00', 0, '2026-11-19'), @('2026-11-19T03:30:00', 1, '2026-11-19'),
              @('2026-11-19T04:00:00', 1, '2026-11-19'), @('2026-11-21T04:00:00', 1, '2026-11-19'))
        }
        foreach ($case in $cases) {
            $command.CommandText = $dueSql.Replace("@{variables('vRunICT')}", $case[0])
            $table = [Data.DataTable]::new()
            $table.Load($command.ExecuteReader())
            if ($table.Rows.Count -ne 1 -or [int]$table.Rows[0].HasDue -ne $case[1] -or
                [string]$table.Rows[0].RefreshDate -cne $case[2]) {
                throw "Due-date/catch-up SQL failed: $phase / $($case[0])."
            }
            $evidence.Add(@{ Test = "Due date $phase / $($case[0])"; Status = 'Passed' })
            Write-Output "PASS live SQL due-date/catch-up: $phase / $($case[0])."
        }
    }
    $command.CommandText = "INSERT INTO $dueTable VALUES('2026-11-19','Running');"
    [void]$command.ExecuteNonQuery()
    $blocked = $false
    try {
        $command.CommandText = $dueSql.Replace("@{variables('vRunICT')}", '2026-11-19T04:00:00')
        $reader = $command.ExecuteReader()
        $reader.Dispose()
    }
    catch [Data.SqlClient.SqlException] {
        if ($_.Exception.Number -ne 51106) { throw }
        $blocked = $true
    }
    if (-not $blocked) { throw 'Incomplete-refresh SQL did not block normal processing.' }
    $evidence.Add(@{ Test = 'Incomplete correction blocks normal processing'; Status = 'Passed' })
    Write-Output 'PASS live SQL incomplete-refresh guard.'
}
finally {
    try {
        if ($dueCreated) {
            $command = $connection.CreateCommand()
            $command.CommandText = "DROP TABLE $dueTable;"
            [void]$command.ExecuteNonQuery()
        }
    }
    finally { $connection.Dispose() }
}

$kustoToken = az account get-access-token --resource 'https://kusto.kusto.windows.net' --query accessToken -o tsv
if ($LASTEXITCODE -ne 0) { throw 'Kusto authentication failed.' }
function Invoke-Kusto([string]$Query, [string]$Endpoint = 'mgmt') {
    Invoke-RestMethod -Uri "https://trd-k344krpm42xbxq2184.z5.kusto.fabric.microsoft.com/v1/rest/$Endpoint" `
        -Method Post -Headers @{ Authorization = "Bearer $kustoToken"; Accept = 'application/json' } -ContentType 'application/json' `
        -Body (@{ db = 'DepositMovement'; csl = $Query } | ConvertTo-Json) -TimeoutSec 90
}
$owner = [guid]::NewGuid().ToString()
$lock = 'CR01Test_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '_Mutex'
$created = $false
try {
    $null = Invoke-Kusto ".set $lock <| print Owner='$owner'"
    $created = $true
    $rejected = $false
    $secondOwner = [guid]::NewGuid().ToString()
    try { $null = Invoke-Kusto ".set $lock <| print Owner='$secondOwner'" }
    catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        if ([int]$_.Exception.Response.StatusCode -ne 400) { throw }
        $rejected = $true
    }
    $result = Invoke-Kusto "$lock | project Owner" 'query'
    if (-not $rejected -or $result.Tables[0].Rows.Count -ne 1 -or $result.Tables[0].Rows[0][0] -cne $owner) {
        throw 'The live KQL create-only lock did not reject a second owner.'
    }
    $evidence.Add(@{ Test = 'Create-only KQL global mutex primitive'; Status = 'Passed' })
    Write-Output 'PASS live KQL mutex: second acquisition rejected; first owner preserved.'
}
finally {
    if ($created) {
        $result = Invoke-Kusto "$lock | project Owner" 'query'
        if ($result.Tables[0].Rows.Count -ne 1 -or $result.Tables[0].Rows[0][0] -cne $owner) {
            throw "Refusing to delete the isolated mutex because ownership changed: $lock"
        }
        $null = Invoke-Kusto ".drop table $lock"
    }
}
if ($OriginalSnapshotDirectory) {
    $fabricToken = az account get-access-token --resource 'https://api.fabric.microsoft.com' --query accessToken -o tsv
    if ($LASTEXITCODE -ne 0) { throw 'Fabric authentication failed.' }
    foreach ($item in @(
        @('0a74b40a-6e71-4a66-9cb1-d49a6d405d01', 'ingest-pipeline-content.json'),
        @('9ec17f10-cda1-498c-97fe-68a189f2f7fe', 'discovery-pipeline-content.json')
    )) {
        $definition = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/f0cb703b-2ceb-4a73-a302-813057c06412/items/$($item[0])/getDefinition" `
            -Method Post -Headers @{ Authorization = "Bearer $fabricToken" } -TimeoutSec 90
        $part = @($definition.definition.parts | Where-Object path -EQ 'pipeline-content.json')[0]
        $live = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part.payload)) |
            ConvertFrom-Json | ConvertTo-Json -Depth 80 -Compress
        $before = Get-Content -LiteralPath (Join-Path $OriginalSnapshotDirectory $item[1]) -Raw |
            ConvertFrom-Json | ConvertTo-Json -Depth 80 -Compress
        if ($live -cne $before) { throw "Original pipeline definition changed: $($item[0]). Do not overwrite another contributor's changes." }
        $evidence.Add(@{ Test = "Original pipeline unchanged: $($item[0])"; Status = 'Passed' })
        Write-Output "PASS original pipeline unchanged: $($item[0])."
    }
}
$evidence | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $EvidencePath -Encoding utf8
