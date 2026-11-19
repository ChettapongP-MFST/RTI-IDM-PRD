[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PipelineId,
    [Parameter(Mandatory)][string]$AzureConfigDirectory,
    [Parameter(Mandatory)][string]$EvidencePath,
    [string]$DefinitionPath,
    [hashtable]$Parameters = @{},
    [int]$TimeoutMinutes = 15,
    [string]$WorkspaceId = 'f0cb703b-2ceb-4a73-a302-813057c06412'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:AZURE_CONFIG_DIR = $AzureConfigDirectory
$token = az account get-access-token --resource 'https://api.fabric.microsoft.com' --query accessToken -o tsv
if ($LASTEXITCODE -ne 0) { throw 'Fabric authentication failed.' }
$headers = @{ Authorization = "Bearer $token" }
$base = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId"
$itemUrl = "$base/items/$PipelineId"
$item = Invoke-RestMethod -Uri $itemUrl -Headers $headers -TimeoutSec 90
if ($item.displayName -notmatch '^pl_CR01_') { throw 'This test runner only operates on separate pl_CR01_* pipelines.' }
if ($DefinitionPath) {
    if ([IO.Path]::GetFileNameWithoutExtension($DefinitionPath) -cne $item.displayName) {
        throw 'Definition filename does not match the CR01 pipeline being updated.'
    }
    $text = Get-Content -LiteralPath $DefinitionPath -Raw
    $null = $text | ConvertFrom-Json
    $body = @{ definition = @{ parts = @(@{
        path = 'pipeline-content.json'
        payloadType = 'InlineBase64'
        payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text))
    }) } } | ConvertTo-Json -Depth 7
    $response = Invoke-WebRequest -Method Post -Uri "$itemUrl/updateDefinition" -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 90
    if ($response.StatusCode -eq 202) { throw 'Definition update is pending. Wait for its operation to finish before starting a test.' }
}
$started = [datetime]::UtcNow
$body = @{ executionData = @{ parameters = $Parameters } } | ConvertTo-Json -Depth 8
$response = Invoke-WebRequest -Method Post -Uri "$itemUrl/jobs/instances?jobType=Pipeline" -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 90
$jobUrl = [string]$response.Headers.Location[0]
if (-not $jobUrl.StartsWith("$itemUrl/jobs/instances/")) { throw 'Unexpected Fabric job URL.' }
$deadline = $started.AddMinutes($TimeoutMinutes)
do {
    Start-Sleep -Seconds 10
    $job = Invoke-RestMethod -Uri $jobUrl -Headers $headers -TimeoutSec 90
    if ([datetime]::UtcNow -gt $deadline) {
        throw "Job remains pending: $jobUrl. Do not resubmit a destructive run."
    }
} while ($job.status -notin @('Completed', 'Failed', 'Cancelled', 'Deduped'))
$activityFilter = @{
    filters = @()
    orderBy = @(@{ orderBy = 'ActivityRunStart'; order = 'ASC' })
    lastUpdatedAfter = $started.AddMinutes(-5).ToString('o')
    lastUpdatedBefore = [datetime]::UtcNow.AddMinutes(5).ToString('o')
}
$activityRows = [Collections.Generic.List[object]]::new()
$tokens = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
do {
    $activityBody = $activityFilter | ConvertTo-Json -Depth 5
    $page = Invoke-RestMethod -Method Post -Uri "$base/datapipelines/pipelineruns/$($job.id)/queryactivityruns" -Headers $headers -ContentType 'application/json' -Body $activityBody -TimeoutSec 90
    if ($page.PSObject.Properties.Name -notcontains 'value') { throw 'Unexpected Fabric activity-run response shape.' }
    foreach ($activity in $page.value) { $activityRows.Add($activity) }
    $continuation = if ($page.PSObject.Properties.Name -contains 'continuationToken') { [string]$page.continuationToken } else { '' }
    if ($continuation) {
        if (-not $tokens.Add($continuation)) { throw 'Fabric repeated an activity continuation token.' }
        $activityFilter.continuationToken = $continuation
    }
} while ($continuation)
$activities = @{ value = @($activityRows.ToArray()) }
@{ PipelineName = $item.displayName; Job = $job; Activities = $activities } |
    ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $EvidencePath -Encoding utf8
$job | Select-Object id, itemId, status, startTimeUtc, endTimeUtc
if ($job.status -ne 'Completed') {
    throw "Live test $($job.status). Inspect the recorded activity evidence: $EvidencePath"
}
