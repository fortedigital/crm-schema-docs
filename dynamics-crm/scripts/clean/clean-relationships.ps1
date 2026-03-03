<#
.SYNOPSIS
    Deduplicates and filters relationship metadata across all entities.

.DESCRIPTION
    Input:  data/raw/relationships/<entity>.json  (one per entity)
    Output: data/clean/relationships.json

    Rules:
      - OneToMany and ManyToMany are collected and deduplicated by SchemaName.
      - ManyToOne is skipped — it is the inverse view of some entity's OneToMany.
      - Only relationships where BOTH entities are in the configured entity list
        are kept (drops system/owner/team relationships etc.).
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/../gather/config.json"
)

$config    = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rawDir    = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.rawDir))
$cleanDir  = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.cleanDir))
New-Item -ItemType Directory -Path $cleanDir -Force | Out-Null

# Entity list from gather output
$entitiesFile = Join-Path $rawDir 'entities.json'
if (-not (Test-Path $entitiesFile)) {
    Write-Error "entities.json not found at $entitiesFile. Run the gather stage first."
    exit 1
}
$entityNames = (Get-Content $entitiesFile -Raw | ConvertFrom-Json) |
               ForEach-Object { $_.LogicalName ?? $_.logicalName }

$entitySet = [System.Collections.Generic.HashSet[string]]($entityNames)
$seen      = [System.Collections.Generic.HashSet[string]]::new()
$result    = [System.Collections.Generic.List[object]]::new()

foreach ($entity in $entityNames) {
    $rawFile = Join-Path $rawDir "relationships/$entity.json"
    if (-not (Test-Path $rawFile)) { continue }

    $raw = Get-Content $rawFile -Raw | ConvertFrom-Json

    # ── One-to-Many ──────────────────────────────────────────────────────────
    foreach ($r in $raw.oneToMany) {
        if ($seen.Contains($r.SchemaName)) { continue }
        if (-not ($entitySet.Contains($r.ReferencedEntity) -and
                  $entitySet.Contains($r.ReferencingEntity))) { continue }
        $seen.Add($r.SchemaName) | Out-Null
        $result.Add([PSCustomObject]@{
            type                 = 'OneToMany'
            schemaName           = $r.SchemaName
            referencedEntity     = $r.ReferencedEntity
            referencedAttribute  = $r.ReferencedAttribute
            referencingEntity    = $r.ReferencingEntity
            referencingAttribute = $r.ReferencingAttribute
        })
    }

    # ── Many-to-Many ─────────────────────────────────────────────────────────
    foreach ($r in $raw.manyToMany) {
        if ($seen.Contains($r.SchemaName)) { continue }
        if (-not ($entitySet.Contains($r.Entity1LogicalName) -and
                  $entitySet.Contains($r.Entity2LogicalName))) { continue }
        $seen.Add($r.SchemaName) | Out-Null
        $result.Add([PSCustomObject]@{
            type           = 'ManyToMany'
            schemaName     = $r.SchemaName
            entity1        = $r.Entity1LogicalName
            entity2        = $r.Entity2LogicalName
            intersectEntity = $r.IntersectEntityName
        })
    }

    # ManyToOne — inverse view of O2M from the parent entity; skip to avoid duplicates
}

$o2m = ($result | Where-Object type -eq 'OneToMany').Count
$m2m = ($result | Where-Object type -eq 'ManyToMany').Count

$outFile = Join-Path $cleanDir 'relationships.json'
$result | ConvertTo-Json -Depth 5 | Set-Content $outFile -Encoding UTF8
Write-Host "Cleaned $($result.Count) relationships (O2M: $o2m, M2M: $m2m) → $outFile" -ForegroundColor Green
