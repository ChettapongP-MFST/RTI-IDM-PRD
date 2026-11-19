[CmdletBinding()]
param([Parameter(Mandatory)][string]$ManifestPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$prefix = 'CR01Test_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '_'
$owner = [guid]::NewGuid().ToString()
$root = Join-Path $PSScriptRoot '..\pipeline'
$refresh = Get-Content -LiteralPath (Join-Path $root 'pl_CR01_DepositMovement_OvernightRefresh.json') -Raw | ConvertFrom-Json -AsHashtable
$scriptTemplate = @($refresh.properties.activities | Where-Object type -EQ 'Script')[0]
$lookupTemplate = @($refresh.properties.activities | Where-Object type -EQ 'Lookup')[0]
$tableNames = @('CR01ControllerRun','CR01RefreshRun','CR01RefreshManifest','CR01AuditBefore','ProcessedFiles')
$sqlTables = @($tableNames | ForEach-Object { "dbo.$prefix$_" })
$nodes = [Collections.Generic.List[object]]::new()
$last = ''
function Rewrite-Sql([string]$Text) {
    foreach ($table in $tableNames) { $Text = $Text.Replace("dbo.$table", "dbo.$prefix$table") }
    $Text
}
function Add-Sql([string]$Name, [string]$Text) {
    $node = $scriptTemplate | ConvertTo-Json -Depth 40 | ConvertFrom-Json -AsHashtable
    $node.name = $Name
    $node.dependsOn = @(if ($script:last) { @{ activity=$script:last; dependencyConditions=@('Succeeded') } })
    $node.typeProperties.scripts = @(@{ type='NonQuery'; text=@{ value=(Rewrite-Sql $Text); type='Expression' } })
    $nodes.Add($node); $script:last = $Name
}
function Add-RealSql([string]$SourceName) {
    $node = @($refresh.properties.activities | Where-Object name -EQ $SourceName)[0] |
        ConvertTo-Json -Depth 40 | ConvertFrom-Json -AsHashtable
    $node.dependsOn = @(@{ activity=$script:last; dependencyConditions=@('Succeeded') })
    $text = $node.typeProperties.scripts[0].text
    if ($text -is [string]) { $node.typeProperties.scripts[0].text = Rewrite-Sql $text }
    else { $node.typeProperties.scripts[0].text.value = Rewrite-Sql $text.value }
    $nodes.Add($node); $script:last = $SourceName
}
$ddl = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\sql\01-create-CR01-control.sql') -Raw
$assertEmpty = @($sqlTables | ForEach-Object {
    "IF OBJECT_ID('$_','U') IS NOT NULL THROW 51200,'Isolated SQL namespace is not empty.',1;"
}) -join "`n"
$ddl += @'

CREATE TABLE dbo.ProcessedFiles (
    FileName VARCHAR(260) NOT NULL, IngestedAtUtc DATETIME2(3) NOT NULL,
    RowCount_ BIGINT NOT NULL, Status VARCHAR(32) NOT NULL,
    PipelineName VARCHAR(200) NULL, PipelineRunId VARCHAR(64) NULL,
    RunAsUser VARCHAR(200) NULL, ErrorMsg VARCHAR(4000) NULL
);
INSERT INTO dbo.CR01ControllerRun
VALUES('@{pipeline().parameters.pControllerRunId}','Running',SYSUTCDATETIME(),NULL);
'@
Add-Sql 'Initialize Isolated SQL Fixtures' ($assertEmpty + "`n" + $ddl)
Add-RealSql 'Validate Controller Owner'
Add-RealSql 'Register Frozen Manifest'
Add-Sql 'Seed Prior Audit And Staged Totals' @'
INSERT INTO dbo.ProcessedFiles
SELECT TOP(1) FileName,SYSUTCDATETIME(),1,'Success','PreviousPipeline','previous-run','CR01Test',NULL
FROM dbo.CR01RefreshManifest
WHERE RefreshDate='@{variables('vRefreshDate')}' ORDER BY FileName;
UPDATE dbo.CR01RefreshManifest SET ExpectedRows=1,SourceBytes=100,
    SourceLastModified='2026-11-18T03:30:00'
WHERE RefreshDate='@{variables('vRefreshDate')}';
'@
Add-RealSql 'Preserve And Supersede Audit'
Add-RealSql 'Commit Verified Refresh'
$lookup = $lookupTemplate | ConvertTo-Json -Depth 40 | ConvertFrom-Json -AsHashtable
$lookup.name = 'Read SQL Test Results'
$lookup.dependsOn = @(@{ activity=$last; dependencyConditions=@('Succeeded') })
$lookup.typeProperties.firstRowOnly = $true
$lookup.typeProperties.source.sqlReaderQuery = Rewrite-Sql @'
SELECT
    (SELECT COUNT(*) FROM dbo.ProcessedFiles WHERE Status='Success') AS Successful,
    (SELECT COUNT(*) FROM dbo.ProcessedFiles WHERE Status='Superseded-CR01') AS Superseded,
    (SELECT COUNT(*) FROM dbo.CR01AuditBefore WHERE Status='Success') AS Archived,
    (SELECT COUNT(*) FROM dbo.CR01RefreshRun WHERE Status='Completed') AS Completed;
'@
$nodes.Add($lookup)
$nodes.Add(@{
    name='Validate SQL Test Results'; type='IfCondition'
    dependsOn=@(@{ activity='Read SQL Test Results'; dependencyConditions=@('Succeeded') })
    typeProperties=@{
        expression=@{ type='Expression'; value="@not(and(and(equals(int(activity('Read SQL Test Results').output.firstRow.Successful),div(300,pipeline().parameters.pSourceIntervalMinutes)),equals(int(activity('Read SQL Test Results').output.firstRow.Superseded),1)),and(equals(int(activity('Read SQL Test Results').output.firstRow.Archived),1),equals(int(activity('Read SQL Test Results').output.firstRow.Completed),1))))" }
        ifTrueActivities=@(@{ name='Fail SQL Control Test'; type='Fail'; dependsOn=@(); typeProperties=@{
            errorCode='CR01_SQL_TEST_FAILED'; message='Manifest/audit/checkpoint SQL did not match the expected isolated results.' } })
        ifFalseActivities=@()
    }
})
$last = 'Validate SQL Test Results'
Add-Sql 'Remove Isolated SQL Fixtures' (@($tableNames | ForEach-Object { "DROP TABLE dbo.$_;" }) -join "`n")
$path = Join-Path $root 'pl_CR01_SQLControlTest.json'
@{ properties=@{
    activities=@($nodes.ToArray())
    parameters=@{ pControllerRunId=@{ type='string';defaultValue=$owner };pSourceIntervalMinutes=@{ type='int';defaultValue=15 } }
    variables=@{ vRefreshDate=@{ type='String';defaultValue='2026-11-18' } }
} } | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $path -Encoding utf8
@{
    TestPrefix=$prefix; Tables=@(); Functions=@(); MaterializedViews=@(); SqlTables=$sqlTables
    DefinitionPath=[IO.Path]::GetFullPath($path)
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ManifestPath -Encoding utf8
Write-Output "Generated $path"
