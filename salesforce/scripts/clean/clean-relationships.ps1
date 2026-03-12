<#
.SYNOPSIS
    Deduplicates and filters child relationship metadata across all objects.

.DESCRIPTION
    Input:  data/raw/relationships/<Object>.json  (one per object)
    Output: data/clean/relationships.json

    Rules:
      - Collects all childRelationships from each parent object's raw file.
      - Deduplicates by relationshipName.
      - Only keeps relationships where BOTH parent and child objects are in the
        discovered object set (drops system/standard-only relationships).
      - Maps cascadeDelete to type: MasterDetail (true) or Lookup (false).
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/../gather/config.json"
)

$config   = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rawDir   = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.rawDir))
$cleanDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.cleanDir))
New-Item -ItemType Directory -Path $cleanDir -Force | Out-Null

# Object set from clean output
$objectsFile = Join-Path $cleanDir 'objects.json'
if (-not (Test-Path $objectsFile)) {
    Write-Error "data/clean/objects.json not found. Run clean-objects.ps1 first."
    exit 1
}
$objectNames = (Get-Content $objectsFile -Raw | ConvertFrom-Json) |
               ForEach-Object { $_.apiName }

$objectSet = [System.Collections.Generic.HashSet[string]]([System.StringComparer]::OrdinalIgnoreCase)
foreach ($n in $objectNames) { $objectSet.Add($n) | Out-Null }

$seen   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$result = [System.Collections.Generic.List[object]]::new()

foreach ($parentObject in $objectNames) {
    $rawFile = Join-Path $rawDir "relationships/$parentObject.json"
    if (-not (Test-Path $rawFile)) { continue }

    $rels = Get-Content $rawFile -Raw | ConvertFrom-Json

    foreach ($r in $rels) {
        $key = "$parentObject|$($r.childSObject)|$($r.field)"
        if ($seen.Contains($key)) { continue }
        # Both ends must be in the discovered object set
        if (-not ($objectSet.Contains($parentObject) -and $objectSet.Contains($r.childSObject))) { continue }

        $seen.Add($key) | Out-Null
        $result.Add([PSCustomObject]@{
            type         = if ($r.cascadeDelete) { 'MasterDetail' } else { 'Lookup' }
            schemaName   = $r.relationshipName
            parentObject = $parentObject
            childObject  = $r.childSObject
            childField   = $r.field
        })
    }
}

$lookup = ($result | Where-Object type -eq 'Lookup').Count
$md     = ($result | Where-Object type -eq 'MasterDetail').Count

$outFile = Join-Path $cleanDir 'relationships.json'
$result | ConvertTo-Json -Depth 5 | Set-Content $outFile -Encoding UTF8
Write-Host "Cleaned $($result.Count) relationships (Lookup: $lookup, MasterDetail: $md) → $outFile" -ForegroundColor Green
