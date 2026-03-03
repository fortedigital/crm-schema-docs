<#
.SYNOPSIS
    Fetches attribute (field) metadata for each entity listed in config.json.

.OUTPUTS
    data/raw/attributes/<entity>.json — one file per entity
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/config.json"
)

. "$PSScriptRoot/connect.ps1"

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$outDir = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.rawDir))) 'attributes'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

Connect-Dataverse -ConfigPath $ConfigPath

# Entity list is produced by get-entities.ps1 — must run first
$entitiesFile = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.rawDir))) 'entities.json'
if (-not (Test-Path $entitiesFile)) {
    Write-Error "entities.json not found. Run get-entities.ps1 first."
    exit 1
}
$entityNames = (Get-Content $entitiesFile -Raw | ConvertFrom-Json) |
               ForEach-Object { $_.LogicalName ?? $_.logicalName }

$select = @(
    'LogicalName'
    'SchemaName'
    'DisplayName'
    'Description'
    'AttributeType'
    'AttributeTypeName'
    'RequiredLevel'
    'IsPrimaryId'
    'IsPrimaryName'
    'IsCustomAttribute'
    'AttributeOf'         # virtual/calculation parent field
) -join ','

$total   = $entityNames.Count
$current = 0

foreach ($entity in $entityNames) {
    $current++
    Write-Host "[$current/$total] $entity..." -NoNewline

    $url   = "EntityDefinitions(LogicalName='$entity')/Attributes?`$select=$select"
    $attrs = Invoke-DataverseGet -RelativeUrl $url

    $outFile = Join-Path $outDir "$entity.json"
    $attrs | ConvertTo-Json -Depth 10 | Set-Content $outFile -Encoding UTF8

    Write-Host " $($attrs.Count) attributes" -ForegroundColor Green
}

Write-Host "Attributes saved → $outDir" -ForegroundColor Green
