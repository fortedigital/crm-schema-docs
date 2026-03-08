<#
.SYNOPSIS
    Generates Mermaid erDiagram files from clean association data.

.DESCRIPTION
    Input:  data/clean/relationships.json
            config.json  (diagrams section defines object groups per diagram)
    Output: diagrams/<diagram-name>.mmd  (one per group, overwrites existing)

    Each diagram shows object names and associations only — no properties.

    Association notation:
      OneToMany   ||--|{   (one parent to one-or-many children; child required)
      ManyToMany  }o--o{   (many-to-many; both sides optional)
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/../gather/config.json"
)

$config      = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$cleanDir    = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.cleanDir))
$diagramsDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.diagramsDir))
New-Item -ItemType Directory -Path $diagramsDir -Force | Out-Null

$allRels = Get-Content (Join-Path $cleanDir 'relationships.json') -Raw | ConvertFrom-Json

# ── Helpers ───────────────────────────────────────────────────────────────────
function Get-DiagramTitle($name) {
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $words   = ($name -replace '-', ' ') -split ' '
    return ($words | ForEach-Object {
        $_.Substring(0,1).ToUpper($culture) + $_.Substring(1)
    }) -join ' '
}

# ── Generate one file per diagram group ──────────────────────────────────────
foreach ($diagramName in $config.diagrams.PSObject.Properties.Name) {
    $groupObjects = [System.Collections.Generic.HashSet[string]](
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($o in $config.diagrams.$diagramName) { $groupObjects.Add($o) | Out-Null }

    # Filter associations where both sides are in this diagram's object set
    $rels = $allRels | Where-Object {
        $groupObjects.Contains($_.fromObject) -and $groupObjects.Contains($_.toObject)
    }

    $maxLen = ($groupObjects | Measure-Object -Property Length -Maximum).Maximum

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('---')
    $lines.Add("title: HubSpot — $(Get-DiagramTitle $diagramName)")
    $lines.Add('---')
    $lines.Add('erDiagram')
    $lines.Add('')

    foreach ($r in $rels) {
        $from      = $r.fromObject.PadRight($maxLen)
        $to        = $r.toObject
        $label     = ($r.label ?? "$($r.fromObject) to $($r.toObject)").ToLower()
        $connector = if ($r.type -eq 'OneToMany') { '||--|{' } else { '}o--o{' }
        $lines.Add("    $from $connector $to : `"$label`"")
    }

    $outFile = Join-Path $diagramsDir "$diagramName.mmd"
    $lines | Set-Content $outFile -Encoding UTF8
    Write-Host "$diagramName.mmd — $($rels.Count) associations" -ForegroundColor Green
}

Write-Host "Diagrams written → $diagramsDir" -ForegroundColor Green
