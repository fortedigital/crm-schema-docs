<#
.SYNOPSIS
    Generates Mermaid erDiagram files from clean relationship data.

.DESCRIPTION
    Input:  data/clean/relationships.json
            config.json  (diagrams section defines entity groups per diagram)
    Output: diagrams/<diagram-name>.mmd  (one per group, overwrites existing)

    Each diagram shows entity names and relationships only — no attributes.
    Relationship labels are derived from the relationship SchemaName.
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
function Get-RelLabel($schemaName, $entity1, $entity2) {
    # Strip leading entity name(s) from schema name, replace underscores with spaces
    $label = $schemaName -replace "(?i)^${entity1}_?", '' -replace "(?i)^${entity2}_?", ''
    $label = $label -replace '_', ' '
    return if ($label.Trim()) { $label.Trim().ToLower() } else { $schemaName.ToLower() }
}

function Get-DiagramTitle($name) {
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $words = ($name -replace '-', ' ') -split ' '
    return ($words | ForEach-Object {
        $_.Substring(0,1).ToUpper($culture) + $_.Substring(1)
    }) -join ' '
}

# ── Generate one file per diagram group ──────────────────────────────────────
foreach ($diagramName in $config.diagrams.PSObject.Properties.Name) {
    $groupEntities = [System.Collections.Generic.HashSet[string]]($config.diagrams.$diagramName)

    # Filter relationships where both sides are in this diagram's entity set
    $rels = $allRels | Where-Object {
        switch ($_.type) {
            'OneToMany'  { $groupEntities.Contains($_.referencedEntity) -and $groupEntities.Contains($_.referencingEntity) }
            'ManyToMany' { $groupEntities.Contains($_.entity1) -and $groupEntities.Contains($_.entity2) }
            default      { $false }
        }
    }

    # Pad entity names for column alignment
    $maxLen = ($groupEntities | Measure-Object -Property Length -Maximum).Maximum

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('---')
    $lines.Add("title: Dynamics 365 — $(Get-DiagramTitle $diagramName)")
    $lines.Add('---')
    $lines.Add('erDiagram')
    $lines.Add('')

    foreach ($r in $rels) {
        switch ($r.type) {
            'OneToMany' {
                $parent = $r.referencedEntity.ToUpper().PadRight($maxLen)
                $child  = $r.referencingEntity.ToUpper()
                $label  = Get-RelLabel $r.schemaName $r.referencedEntity $r.referencingEntity
                $lines.Add("    $parent ||--o{ $child : `"$label`"")
            }
            'ManyToMany' {
                $e1    = $r.entity1.ToUpper().PadRight($maxLen)
                $e2    = $r.entity2.ToUpper()
                $label = Get-RelLabel $r.schemaName $r.entity1 $r.entity2
                $lines.Add("    $e1 }o--o{ $e2 : `"$label`"")
            }
        }
    }

    $outFile = Join-Path $diagramsDir "$diagramName.mmd"
    $lines | Set-Content $outFile -Encoding UTF8
    Write-Host "$diagramName.mmd — $($rels.Count) relationships" -ForegroundColor Green
}

Write-Host "Diagrams written → $diagramsDir" -ForegroundColor Green
