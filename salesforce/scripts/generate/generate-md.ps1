<#
.SYNOPSIS
    Generates a Markdown reference document with rendered diagram images and object tables.

.DESCRIPTION
    Output:
      salesforce-object-reference.md   — the document
      diagrams-rendered/<name>.png     — one PNG per .mmd file (committed alongside the .md)

    Document structure:
      Title + date
      ## Diagrams        — one subsection per .mmd, with embedded PNG
      ## Object Definitions — one subsection per object, with a Markdown table

    Diagram rendering requires mmdc (Mermaid CLI):
      npm install -g @mermaid-js/mermaid-cli

.PARAMETER OutputPath
    Full path for the output .md file.
    Defaults to salesforce-object-reference.md inside the salesforce folder.
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
$objectsDir  = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.objectsDir))

# Object list from clean output
$objectsFile = Join-Path $cleanDir 'objects.json'
if (-not (Test-Path $objectsFile)) {
    Write-Error "data/clean/objects.json not found. Run the clean stage first."
    exit 1
}
$objectNames = (Get-Content $objectsFile -Raw | ConvertFrom-Json) |
               ForEach-Object { $_.apiName }

if (-not $OutputPath) {
    $OutputPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../output/salesforce-object-reference.md'))
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
        $cells  = $headers | ForEach-Object { ConvertTo-MdCell $row.$_ }
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

$doc.AppendLine("# Salesforce — Object Reference")              | Out-Null
$doc.AppendLine("")                                              | Out-Null
$doc.AppendLine("_Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')_") | Out-Null
$doc.AppendLine("")                                              | Out-Null
$doc.AppendLine("---")                                           | Out-Null

# ── Section 1: Diagrams ───────────────────────────────────────────────────────
$doc.AppendLine("")            | Out-Null
$doc.AppendLine("## Diagrams") | Out-Null

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

# ── Section 2: Object tables ──────────────────────────────────────────────────
$doc.AppendLine("")                          | Out-Null
$doc.AppendLine("## Object Definitions")    | Out-Null

foreach ($apiName in $objectNames) {
    $csvFile = Join-Path $objectsDir "$apiName.csv"
    if (-not (Test-Path $csvFile)) {
        Write-Warning "$apiName.csv not found, skipping"
        continue
    }

    $doc.AppendLine("")               | Out-Null
    $doc.AppendLine("### $apiName")   | Out-Null
    $doc.AppendLine("")               | Out-Null
    $doc.AppendLine((ConvertTo-MdTable $csvFile)) | Out-Null
    Write-Host "Table: $apiName" -ForegroundColor DarkGray
}

# ── Write file ────────────────────────────────────────────────────────────────
$doc.ToString() | Set-Content $OutputPath -Encoding UTF8
Write-Host "Document saved → $OutputPath" -ForegroundColor Green
