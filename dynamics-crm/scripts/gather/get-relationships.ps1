<#
.SYNOPSIS
    Fetches relationship metadata for each entity listed in config.json.

.DESCRIPTION
    For each entity, collects:
      OneToMany    — where this entity is the parent (referenced)
      ManyToOne    — where this entity holds the foreign key (referencing)
      ManyToMany   — intersect relationships

.OUTPUTS
    data/raw/relationships/<entity>.json — one file per entity
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/config.json"
)

. "$PSScriptRoot/connect.ps1"

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$outDir = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.rawDir))) 'relationships'
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

$selectO2M = @(
    'SchemaName'
    'ReferencedEntity'
    'ReferencedAttribute'
    'ReferencingEntity'
    'ReferencingAttribute'
    'CascadeConfiguration'
) -join ','

$selectM2O = $selectO2M   # same fields, opposite perspective

$selectM2M = @(
    'SchemaName'
    'Entity1LogicalName'
    'Entity2LogicalName'
    'IntersectEntityName'
) -join ','

$total   = $entityNames.Count
$current = 0

foreach ($entity in $entityNames) {
    $current++
    Write-Host "[$current/$total] $entity..." -NoNewline

    $o2m = Invoke-DataverseGet -RelativeUrl "EntityDefinitions(LogicalName='$entity')/OneToManyRelationships?`$select=$selectO2M"
    $m2o = Invoke-DataverseGet -RelativeUrl "EntityDefinitions(LogicalName='$entity')/ManyToOneRelationships?`$select=$selectM2O"
    $m2m = Invoke-DataverseGet -RelativeUrl "EntityDefinitions(LogicalName='$entity')/ManyToManyRelationships?`$select=$selectM2M"

    $result = [PSCustomObject]@{
        entity      = $entity
        oneToMany   = $o2m
        manyToOne   = $m2o
        manyToMany  = $m2m
    }

    $outFile = Join-Path $outDir "$entity.json"
    $result | ConvertTo-Json -Depth 10 | Set-Content $outFile -Encoding UTF8

    Write-Host " o2m=$($o2m.Count)  m2o=$($m2o.Count)  m2m=$($m2m.Count)" -ForegroundColor Green
}

Write-Host "Relationships saved → $outDir" -ForegroundColor Green
