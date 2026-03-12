<#
.SYNOPSIS
    Generates Mermaid erDiagram files from clean relationship data.

.DESCRIPTION
    Input:  data/clean/relationships.json
            config.json  (diagrams section defines object groups per diagram)
    Output: diagrams/<diagram-name>.mmd  (one per group, overwrites existing)

    Each diagram shows object names and relationships only — no fields.
    Relationship labels are the Salesforce relationshipName (human-readable).

    Relationship notation:
      Lookup       ||--o{   (parent to zero-or-many children; child optional)
      MasterDetail ||--|{   (parent to one-or-many children; child required)
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
function Get-RelLabel($schemaName) {
    # relationshipName is already human-readable in Salesforce (e.g. "Contacts")
    # Convert PascalCase to space-separated lowercase for readability
    $spaced = $schemaName -creplace '([A-Z])', ' $1'
    return $spaced.Trim().ToLower()
}

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

    # Filter relationships where both sides are in this diagram's object set
    $rels = $allRels | Where-Object {
        $groupObjects.Contains($_.parentObject) -and $groupObjects.Contains($_.childObject)
    }

    $maxLen = ($groupObjects | Measure-Object -Property Length -Maximum).Maximum

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('---')
    $lines.Add("title: Salesforce — $(Get-DiagramTitle $diagramName)")
    $lines.Add('---')
    $lines.Add('erDiagram')
    $lines.Add('')

    foreach ($r in $rels) {
        $parent    = $r.parentObject.PadRight($maxLen)
        $child     = $r.childObject
        $label     = Get-RelLabel $r.schemaName
        $connector = if ($r.type -eq 'MasterDetail') { '||--|{' } else { '||--o{' }
        $lines.Add("    $parent $connector $child : `"$label`"")
    }

    $outFile = Join-Path $diagramsDir "$diagramName.mmd"
    $lines | Set-Content $outFile -Encoding UTF8
    Write-Host "$diagramName.mmd — $($rels.Count) relationships" -ForegroundColor Green
}

Write-Host "Diagrams written → $diagramsDir" -ForegroundColor Green
