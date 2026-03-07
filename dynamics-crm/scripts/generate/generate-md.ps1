<#
.SYNOPSIS
    Generates a Markdown reference document with rendered diagram images and entity tables.

.DESCRIPTION
    Output:
      dynamics-crm-entity-reference.md   — the document
      diagrams-rendered/<name>.png        — one PNG per .mmd file (committed alongside the .md)

    Document structure:
      Title + date
      ## Diagrams        — one subsection per .mmd, with embedded PNG
      ## Entity Definitions — one subsection per entity, with a Markdown table

    Diagram rendering requires mmdc (Mermaid CLI):
      npm install -g @mermaid-js/mermaid-cli

.PARAMETER OutputPath
    Full path for the output .md file.
    Defaults to dynamics-crm-entity-reference.md inside the dynamics-crm folder.
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/../gather/config.json",
    [string]$OutputPath = ''
)

$config      = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$cleanDir    = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.cleanDir))
$diagramsDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.diagramsDir))
$entitiesDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.entitiesDir))

# Entity list from clean output
$entitiesFile = Join-Path $cleanDir 'entities.json'
if (-not (Test-Path $entitiesFile)) {
    Write-Error "data/clean/entities.json not found. Run the clean stage first."
    exit 1
}
$entityNames = (Get-Content $entitiesFile -Raw | ConvertFrom-Json) |
               ForEach-Object { $_.logicalName ?? $_.LogicalName }

if (-not $OutputPath) {
    $OutputPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../output/dynamics-crm-entity-reference.md'))
}

$renderedDir = Join-Path ([IO.Path]::GetDirectoryName($OutputPath)) 'diagrams-rendered'
New-Item -ItemType Directory -Path $renderedDir -Force | Out-Null

# ── Require mmdc ──────────────────────────────────────────────────────────────
if (-not (Get-Command mmdc -ErrorAction SilentlyContinue)) {
    Write-Error "mmdc is required to render diagrams. Install: npm install -g @mermaid-js/mermaid-cli"
    exit 1
}

# ── Helpers ───────────────────────────────────────────────────────────────────
function ConvertTo-MdCell($value) {
    # Escape pipes; collapse internal newlines to a space
    return ([string]$value).Trim() -replace '\r?\n', ' ' -replace '\|', '\|'
}

function ConvertTo-MdTable($csvPath) {
    $rows = Import-Csv $csvPath
    if (-not $rows) { return '_No data._' }

    $headers = $rows[0].PSObject.Properties.Name
    $sep     = $headers | ForEach-Object { '---' }

    $lines = @(
        '| ' + (($headers | ForEach-Object { ConvertTo-MdCell $_ }) -join ' | ') + ' |'
        '| ' + ($sep -join ' | ') + ' |'
    )
    foreach ($row in $rows) {
        $cells = $headers | ForEach-Object { ConvertTo-MdCell $row.$_ }
        $lines += '| ' + ($cells -join ' | ') + ' |'
    }
    return $lines -join "`n"
}

# ── Render diagrams to PNG ────────────────────────────────────────────────────
$mmdFiles = Get-ChildItem $diagramsDir -Filter '*.mmd' | Sort-Object Name
$pngMap   = [ordered]@{}   # name → relative path from .md

foreach ($mmd in $mmdFiles) {
    $name    = [IO.Path]::GetFileNameWithoutExtension($mmd.Name)
    $pngPath = Join-Path $renderedDir "$name.png"

    Write-Host "Rendering $($mmd.Name) → $name.png..." -NoNewline
    mmdc -i $mmd.FullName -o $pngPath -w 1600 -b white 2>$null

    if (Test-Path $pngPath) {
        $pngMap[$name] = "diagrams-rendered/$name.png"
        Write-Host " OK" -ForegroundColor Green
    } else {
        Write-Warning " mmdc produced no output for $name"
    }
}

# ── Build Markdown document ───────────────────────────────────────────────────
$doc = [System.Text.StringBuilder]::new()

$doc.AppendLine("# Dynamics 365 CRM — Entity Reference")          | Out-Null
$doc.AppendLine("")                                                 | Out-Null
$doc.AppendLine("_Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')_") | Out-Null
$doc.AppendLine("")                                                 | Out-Null
$doc.AppendLine("---")                                              | Out-Null

# ── Section 1: Diagrams ───────────────────────────────────────────────────────
$doc.AppendLine("")             | Out-Null
$doc.AppendLine("## Diagrams")  | Out-Null

foreach ($mmd in $mmdFiles) {
    $name = [IO.Path]::GetFileNameWithoutExtension($mmd.Name)

    # Derive title from YAML front-matter if present
    $frontMatter = Get-Content $mmd.FullName | Select-Object -First 5
    $titleLine   = $frontMatter | Where-Object { $_ -match '^title:' } | Select-Object -First 1
    $title       = if ($titleLine) { ($titleLine -replace '^title:\s*', '').Trim() } else { $name }

    $doc.AppendLine("")           | Out-Null
    $doc.AppendLine("### $title") | Out-Null
    $doc.AppendLine("")           | Out-Null

    if ($pngMap.Contains($name)) {
        $doc.AppendLine("![$title]($($pngMap[$name]))") | Out-Null
    } else {
        $doc.AppendLine("_Diagram image not available._") | Out-Null
    }
}

$doc.AppendLine("")    | Out-Null
$doc.AppendLine("---") | Out-Null

# ── Section 2: Entity tables ──────────────────────────────────────────────────
$doc.AppendLine("")                        | Out-Null
$doc.AppendLine("## Entity Definitions")   | Out-Null

foreach ($entity in $entityNames) {
    $csvFile = Join-Path $entitiesDir "$entity.csv"
    if (-not (Test-Path $csvFile)) {
        Write-Warning "$entity.csv not found, skipping"
        continue
    }

    $doc.AppendLine("")              | Out-Null
    $doc.AppendLine("### $entity")   | Out-Null
    $doc.AppendLine("")              | Out-Null
    $doc.AppendLine((ConvertTo-MdTable $csvFile)) | Out-Null
    Write-Host "Table: $entity" -ForegroundColor DarkGray
}

# ── Write file ────────────────────────────────────────────────────────────────
$doc.ToString() | Set-Content $OutputPath -Encoding UTF8
Write-Host "Document saved → $OutputPath" -ForegroundColor Green
