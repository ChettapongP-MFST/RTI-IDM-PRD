[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$AzureConfigDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($manifest.TestPrefix -notmatch '^CR01Test_[a-f0-9]{8}_$') { throw 'Invalid isolated-test namespace.' }
$kqlNames = @($manifest.Tables) + @($manifest.Functions) + @($manifest.MaterializedViews)
foreach ($name in $kqlNames) {
    if (-not $name.StartsWith($manifest.TestPrefix, [StringComparison]::Ordinal) -or $name -notmatch '^[A-Za-z0-9_]+$') {
        throw "Refusing to delete an object outside the recorded isolated test: $name"
    }
}
$sqlNames = @()
if ($manifest.PSObject.Properties.Name -contains 'SqlTables') { $sqlNames = @($manifest.SqlTables) }
foreach ($name in $sqlNames) {
    if (-not $name.StartsWith("dbo.$($manifest.TestPrefix)", [StringComparison]::Ordinal) -or
        $name -notmatch '^dbo\.[A-Za-z0-9_]+$') {
        throw "Refusing to delete an SQL object outside the recorded isolated test: $name"
    }
}
$env:AZURE_CONFIG_DIR = $AzureConfigDirectory
if ($kqlNames.Count) {
    $token = az account get-access-token --resource 'https://kusto.kusto.windows.net' --query accessToken -o tsv
    if ($LASTEXITCODE -ne 0) { throw 'Kusto authentication failed.' }
    function Invoke-Management([string]$Command) {
        Invoke-RestMethod -Uri 'https://trd-k344krpm42xbxq2184.z5.kusto.fabric.microsoft.com/v1/rest/mgmt' `
            -Method Post -Headers @{ Authorization = "Bearer $token"; Accept = 'application/json' } -ContentType 'application/json' `
            -Body (@{ db = 'DepositMovement'; csl = $Command } | ConvertTo-Json) -TimeoutSec 120
    }
    foreach ($kind in @('MaterializedViews', 'Tables', 'Functions')) {
        $listCommand = switch ($kind) {
            'MaterializedViews' { '.show materialized-views | project Name' }
            'Tables' { '.show tables | project Name=TableName' }
            'Functions' { '.show functions | project Name' }
        }
        $existing = @((Invoke-Management $listCommand).Tables[0].Rows | ForEach-Object { [string]$_[0] })
        $names = @($manifest.$kind)
        if ($kind -eq 'Tables') {
            $names = @($names | Sort-Object @{ Expression = { if ($_ -eq "$($manifest.TestPrefix)DepositMovementClassified") { 0 } else { 1 } } })
        }
        $removed = [Collections.Generic.List[string]]::new()
        foreach ($name in $names) {
            if ($name -notin $existing) { continue }
            $command = switch ($kind) {
                'MaterializedViews' { ".drop materialized-view $name" }
                'Tables' { ".drop table $name" }
                'Functions' { ".drop function $name" }
            }
            if ($PSCmdlet.ShouldProcess("DepositMovement/$name", $command)) {
                $null = Invoke-Management $command
                $removed.Add($name)
                Write-Output "Removed isolated object: $name"
            }
        }
        if ($removed.Count) {
            $remaining = @((Invoke-Management $listCommand).Tables[0].Rows |
                ForEach-Object { [string]$_[0] } | Where-Object { $_ -in $removed })
            if ($remaining.Count) { throw "Isolated cleanup did not persist: $($remaining -join ', ')" }
        }
    }
}
if ($sqlNames.Count) {
    $sqlToken = az account get-access-token --resource 'https://database.windows.net/' --query accessToken -o tsv
    if ($LASTEXITCODE -ne 0) { throw 'SQL authentication failed.' }
    $connection = [Data.SqlClient.SqlConnection]::new(
        'Server=tcp:k35aq6omcxkejht6cuywxdyb4q-hnymx4hlfrzuviycqeyfpqdeci.datawarehouse.fabric.microsoft.com,1433;Database=wh_control_framework;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;')
    $connection.AccessToken = $sqlToken
    try {
        $connection.Open()
        foreach ($name in $sqlNames) {
            if ($PSCmdlet.ShouldProcess("wh_control_framework/$name", 'Drop isolated SQL test table if it exists')) {
                $command = $connection.CreateCommand()
                $command.CommandText = "IF OBJECT_ID('$name','U') IS NOT NULL DROP TABLE $name;"
                [void]$command.ExecuteNonQuery()
                $command.CommandText = "SELECT CASE WHEN OBJECT_ID('$name','U') IS NULL THEN 0 ELSE 1 END;"
                if ([int]$command.ExecuteScalar() -ne 0) { throw "Isolated SQL cleanup did not persist: $name" }
                Write-Output "Removed isolated SQL object if present: $name"
            }
        }
    }
    finally { $connection.Dispose() }
}
