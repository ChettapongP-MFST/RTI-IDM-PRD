[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DefinitionPath,
    [Parameter(Mandatory)][string]$AzureConfigDirectory,
    [string]$WorkspaceId = 'f0cb703b-2ceb-4a73-a302-813057c06412'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:AZURE_CONFIG_DIR = $AzureConfigDirectory
$name = [IO.Path]::GetFileNameWithoutExtension($DefinitionPath)
if ($name -notmatch '^pl_CR01_[A-Za-z0-9_]+$') {
    throw 'Only new pl_CR01_* pipelines may be created by this script.'
}
$content = Get-Content -LiteralPath $DefinitionPath -Raw
$null = $content | ConvertFrom-Json
$token = az account get-access-token --resource 'https://api.fabric.microsoft.com' --query accessToken -o tsv
if ($LASTEXITCODE -ne 0) { throw 'Fabric authentication failed.' }
$headers = @{ Authorization = "Bearer $token" }
$base = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId"
$items = Invoke-RestMethod -Uri "$base/items?type=DataPipeline" -Headers $headers -TimeoutSec 90
if ($items.PSObject.Properties.Name -contains 'continuationToken' -and $items.continuationToken) {
    throw 'Workspace inventory is paginated. Resolve all pages before deploying to avoid a name collision.'
}
if (@($items.value | Where-Object displayName -EQ $name).Count -gt 0) {
    throw "Pipeline $name already exists. This create-only script never overwrites a pipeline."
}
$body = @{
    displayName = $name
    type = 'DataPipeline'
    description = 'CR01: separate change-request artifact. Existing pipeline definitions are not modified. No schedule is enabled by deployment.'
    definition = @{
        parts = @(@{
            path = 'pipeline-content.json'
            payloadType = 'InlineBase64'
            payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($content))
        })
    }
} | ConvertTo-Json -Depth 8
$response = Invoke-WebRequest -Uri "$base/items" -Method Post -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 120
if ($response.StatusCode -eq 202) {
    $location = [string]$response.Headers.Location[0]
    if (-not $location.StartsWith('https://api.fabric.microsoft.com/')) {
        throw 'Unexpected Fabric operation URL.'
    }
    $deadline = [datetime]::UtcNow.AddMinutes(5)
    do {
        Start-Sleep -Seconds 5
        $operation = Invoke-RestMethod -Uri $location -Headers $headers -TimeoutSec 90
        if ($operation.status -in @('Failed', 'Cancelled')) { throw ($operation | ConvertTo-Json -Depth 8) }
        if ([datetime]::UtcNow -gt $deadline) { throw "Creation is still pending. Inspect $location; do not resubmit blindly." }
    } while ($operation.status -ne 'Succeeded')
    Invoke-RestMethod -Uri "$location/result" -Headers $headers -TimeoutSec 90
}
else {
    $response.Content | ConvertFrom-Json
}
