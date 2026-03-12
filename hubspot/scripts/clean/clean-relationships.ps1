<#
.SYNOPSIS
    Deduplicates and filters association metadata across all HubSpot objects.

.DESCRIPTION
    Input:  data/raw/relationships/<objectName>.json  (one per object)
    Output: data/clean/relationships.json

    Rules:
      - Collects all associations from each object's raw file.
      - Deduplicates by fromObject + toObject pair.
      - Only keeps associations where BOTH objects are in the discovered set.
      - Maps cardinality to Mermaid notation:
          OneToMany   ||--|{   (parent to one-or-many; child required)
          ManyToMany  }o--o{   (many-to-many; both sides optional)
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
               ForEach-Object { $_.name }

$objectSet = [System.Collections.Generic.HashSet[string]]([System.StringComparer]::OrdinalIgnoreCase)
foreach ($n in $objectNames) { $objectSet.Add($n) | Out-Null }

$seen   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$result = [System.Collections.Generic.List[object]]::new()

foreach ($objectName in $objectNames) {
    $rawFile = Join-Path $rawDir "relationships/$objectName.json"
    if (-not (Test-Path $rawFile)) { continue }

    $rels = Get-Content $rawFile -Raw | ConvertFrom-Json

    foreach ($r in $rels) {
        $from = $r.fromObject
        $to   = $r.toObject
        $key  = "$from|$to"

        if ($seen.Contains($key)) { continue }
        if (-not ($objectSet.Contains($from) -and $objectSet.Contains($to))) { continue }

        $seen.Add($key) | Out-Null
        $result.Add([PSCustomObject]@{
            type         = $r.cardinality
            label        = $r.label ?? "$from to $to"
            fromObject   = $from
            toObject     = $to
            category     = $r.category ?? 'HUBSPOT_DEFINED'
        })
    }
}

$otm = ($result | Where-Object type -eq 'OneToMany').Count
$mtm = ($result | Where-Object type -eq 'ManyToMany').Count

$outFile = Join-Path $cleanDir 'relationships.json'
$result | ConvertTo-Json -Depth 5 | Set-Content $outFile -Encoding UTF8
Write-Host "Cleaned $($result.Count) associations (OneToMany: $otm, ManyToMany: $mtm) → $outFile" -ForegroundColor Green
