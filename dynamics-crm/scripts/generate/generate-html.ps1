<#
.SYNOPSIS
    Generates self-contained HTML reference documents with client-side Mermaid
    diagrams and entity tables.

.DESCRIPTION
    Output:
      dynamics-crm-entity-reference.html  — business / migration-relevant entities + diagrams
      dynamics-crm-system-entities.html    — system & built-in entities

    Entity classification is derived from the diagram groups in config.json:
      Entities referenced in any diagram group EXCEPT "system-administration"
      and "all-entities" are considered business-relevant.
      Everything else goes into the system entities document.

    No external tools required — Mermaid diagrams are rendered in the browser.
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/../gather/config.json"
)

$config      = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$cleanDir    = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.cleanDir))
$diagramsDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.diagramsDir))
$entitiesDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.entitiesDir))
$outputDir   = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../output'))

# Entity list from clean output
$entitiesFile = Join-Path $cleanDir 'entities.json'
if (-not (Test-Path $entitiesFile)) {
    Write-Error "data/clean/entities.json not found. Run the clean stage first."
    exit 1
}
$entityNames = (Get-Content $entitiesFile -Raw | ConvertFrom-Json) |
               ForEach-Object { $_.logicalName ?? $_.LogicalName }

# ── Classify entities from diagram groups ────────────────────────────────────
$systemDiagramGroups = @('system-administration', 'all-entities')
$businessEntities = [System.Collections.Generic.HashSet[string]]::new()

foreach ($groupName in $config.diagrams.PSObject.Properties.Name) {
    if ($groupName -in $systemDiagramGroups) { continue }
    foreach ($eName in $config.diagrams.$groupName) {
        if ($eName -ne '*') { $businessEntities.Add($eName) | Out-Null }
    }
}

$primaryEntities = @($entityNames | Where-Object { $businessEntities.Contains($_) })
$systemEntities  = @($entityNames | Where-Object { -not $businessEntities.Contains($_) })

Write-Host "Entity classification: $($primaryEntities.Count) business, $($systemEntities.Count) system" -ForegroundColor Cyan

# ── Helpers ───────────────────────────────────────────────────────────────────
function ConvertTo-HtmlCell($value) {
    return [System.Net.WebUtility]::HtmlEncode(([string]$value).Trim())
}

function ConvertTo-SortableTable($rows, $headers) {
    $sb = [System.Text.StringBuilder]::new()
    $sb.AppendLine('<table class="sortable">') | Out-Null
    $sb.AppendLine('  <thead><tr>') | Out-Null
    foreach ($h in $headers) {
        $sb.AppendLine("    <th data-sort-col>$(ConvertTo-HtmlCell $h) <span class=`"sort-arrow`"></span></th>") | Out-Null
    }
    $sb.AppendLine('  </tr></thead>') | Out-Null
    $sb.AppendLine('  <tbody>') | Out-Null
    foreach ($row in $rows) {
        $sb.AppendLine('  <tr>') | Out-Null
        foreach ($h in $headers) {
            $val = ConvertTo-HtmlCell $row.$h
            $raw = ([string]$row.$h).Trim()
            if ($raw -match '^\d+$') {
                $sb.AppendLine("    <td data-sort-value=`"$raw`">$val</td>") | Out-Null
            } else {
                $sb.AppendLine("    <td>$val</td>") | Out-Null
            }
        }
        $sb.AppendLine('  </tr>') | Out-Null
    }
    $sb.AppendLine('  </tbody>') | Out-Null
    $sb.AppendLine('</table>') | Out-Null
    return $sb.ToString()
}

function Get-MermaidContent($mmdFile) {
    $lines = Get-Content $mmdFile.FullName
    $inFront = $false; $body = @(); $firstLine = $true
    foreach ($line in $lines) {
        if ($firstLine -and $line -match '^---\s*$') { $inFront = $true; $firstLine = $false; continue }
        $firstLine = $false
        if ($inFront) { if ($line -match '^---\s*$') { $inFront = $false }; continue }
        $body += $line
    }
    return [System.Net.WebUtility]::HtmlEncode(($body -join "`n").Trim())
}

function Get-MermaidTitle($mmdFile) {
    $frontMatter = Get-Content $mmdFile.FullName | Select-Object -First 5
    $titleLine   = $frontMatter | Where-Object { $_ -match '^title:' } | Select-Object -First 1
    $name = [IO.Path]::GetFileNameWithoutExtension($mmdFile.Name)
    if ($titleLine) { ($titleLine -replace '^title:\s*', '').Trim() } else { $name }
}

# ── HTML document generator ──────────────────────────────────────────────────
function Build-HtmlDocument {
    param(
        [string]$Title,
        [string]$Subtitle,
        [string[]]$EntityList,
        [System.IO.FileInfo[]]$Diagrams,
        [string]$CrossLinkHtml
    )

    $doc = [System.Text.StringBuilder]::new()

    $doc.AppendLine(@'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
'@) | Out-Null
    $doc.AppendLine("  <title>$([System.Net.WebUtility]::HtmlEncode($Title))</title>") | Out-Null
    $doc.AppendLine(@'
  <style>
    :root {
      --bg: #ffffff;
      --fg: #1a1a1a;
      --border: #d0d7de;
      --header-bg: #f6f8fa;
      --accent: #0969da;
      --section-bg: #f0f4f8;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #0d1117;
        --fg: #e6edf3;
        --border: #30363d;
        --header-bg: #161b22;
        --accent: #58a6ff;
        --section-bg: #161b22;
      }
    }
    * { box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
      line-height: 1.6;
      color: var(--fg);
      background: var(--bg);
      max-width: 1200px;
      margin: 0 auto;
      padding: 2rem;
    }
    h1 { border-bottom: 2px solid var(--border); padding-bottom: .5rem; }
    h2 { border-bottom: 1px solid var(--border); padding-bottom: .3rem; margin-top: 2.5rem; }
    h3 { margin-top: 2rem; }
    .generated-date { color: #656d76; font-style: italic; }
    .cross-link { margin: 1rem 0; padding: .6rem 1rem; background: var(--section-bg); border: 1px solid var(--border); border-radius: 6px; }
    .cross-link a { color: var(--accent); text-decoration: none; font-weight: 600; }
    .cross-link a:hover { text-decoration: underline; }
    hr { border: none; border-top: 1px solid var(--border); margin: 2rem 0; }

    /* Navigation */
    nav {
      background: var(--section-bg);
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 1rem 1.5rem;
      margin-bottom: 2rem;
    }
    nav summary { cursor: pointer; font-weight: 600; font-size: 1.1em; }
    nav ul { columns: 3; column-gap: 2rem; list-style: none; padding: 0; margin: .5rem 0 0 0; }
    nav li { break-inside: avoid; padding: .15rem 0; }
    nav a { color: var(--accent); text-decoration: none; }
    nav a:hover { text-decoration: underline; }

    /* Diagrams — full viewport width */
    .diagram-container {
      width: 100vw;
      position: relative;
      left: 50%;
      transform: translateX(-50%);
      overflow-x: auto;
      background: var(--section-bg);
      border-top: 1px solid var(--border);
      border-bottom: 1px solid var(--border);
      padding: 1rem 2rem;
      margin: 1rem 0;
    }
    .mermaid { text-align: center; }
    .mermaid svg { max-width: 100%; height: auto; }

    /* Tables */
    table { border-collapse: collapse; width: 100%; font-size: 0.875rem; margin: 1rem 0; }
    th, td { border: 1px solid var(--border); padding: .4rem .6rem; text-align: left; }
    th { background: var(--header-bg); font-weight: 600; position: sticky; top: 0; }
    th[data-sort-col] { cursor: pointer; user-select: none; }
    th[data-sort-col]:hover { background: var(--section-bg); }
    .sort-arrow { font-size: 0.7em; margin-left: .3em; opacity: 0.4; }
    .sort-arrow.asc::after { content: '\25B2'; opacity: 1; }
    .sort-arrow.desc::after { content: '\25BC'; opacity: 1; }
    tr:hover td { background: var(--section-bg); }

    /* Unused properties sub-section */
    .unused-section { margin-top: 1rem; }
    .unused-section summary { cursor: pointer; font-weight: 600; color: #656d76; padding: .4rem 0; }

    /* Entity section */
    .entity-section details { border: 1px solid var(--border); border-radius: 6px; margin: 1rem 0; }
    .entity-section details summary { cursor: pointer; padding: .6rem 1rem; background: var(--header-bg); font-weight: 600; border-radius: 6px; }
    .entity-section details[open] summary { border-bottom: 1px solid var(--border); border-radius: 6px 6px 0 0; }
    .entity-section details .table-wrap { overflow-x: auto; padding: .5rem; }
  </style>
</head>
<body>
'@) | Out-Null

    $safeTitle = [System.Net.WebUtility]::HtmlEncode($Title)
    $doc.AppendLine("  <h1>$safeTitle</h1>") | Out-Null
    $doc.AppendLine("  <p class=`"generated-date`">Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')</p>") | Out-Null
    if ($Subtitle) {
        $doc.AppendLine("  <p>$([System.Net.WebUtility]::HtmlEncode($Subtitle))</p>") | Out-Null
    }
    if ($CrossLinkHtml) {
        $doc.AppendLine("  <div class=`"cross-link`">$CrossLinkHtml</div>") | Out-Null
    }

    # ── Table of Contents ────────────────────────────────────────────────────
    $doc.AppendLine('  <nav>') | Out-Null
    $doc.AppendLine('    <details open>') | Out-Null
    $doc.AppendLine('      <summary>Table of Contents</summary>') | Out-Null

    if ($Diagrams -and $Diagrams.Count -gt 0) {
        $doc.AppendLine('      <h4>Diagrams</h4>') | Out-Null
        $doc.AppendLine('      <ul>') | Out-Null
        foreach ($mmd in $Diagrams) {
            $name      = [IO.Path]::GetFileNameWithoutExtension($mmd.Name)
            $mmdTitle  = Get-MermaidTitle $mmd
            $safeMmdTitle = [System.Net.WebUtility]::HtmlEncode($mmdTitle)
            $doc.AppendLine("        <li><a href=`"#diagram-$name`">$safeMmdTitle</a></li>") | Out-Null
        }
        $doc.AppendLine('      </ul>') | Out-Null
    }

    $doc.AppendLine('      <h4>Entity Definitions</h4>') | Out-Null
    $doc.AppendLine('      <ul>') | Out-Null
    foreach ($entity in $EntityList) {
        $csvFile = Join-Path $entitiesDir "$entity.csv"
        if (Test-Path $csvFile) {
            $doc.AppendLine("        <li><a href=`"#entity-$entity`">$([System.Net.WebUtility]::HtmlEncode($entity))</a></li>") | Out-Null
        }
    }
    $doc.AppendLine('      </ul>') | Out-Null
    $doc.AppendLine('    </details>') | Out-Null
    $doc.AppendLine('  </nav>') | Out-Null

    # ── Diagrams ─────────────────────────────────────────────────────────────
    if ($Diagrams -and $Diagrams.Count -gt 0) {
        $doc.AppendLine('  <hr>') | Out-Null
        $doc.AppendLine('  <h2>Diagrams</h2>') | Out-Null
        foreach ($mmd in $Diagrams) {
            $name       = [IO.Path]::GetFileNameWithoutExtension($mmd.Name)
            $mmdTitle   = Get-MermaidTitle $mmd
            $safeMmdTitle = [System.Net.WebUtility]::HtmlEncode($mmdTitle)
            $mermaidSrc = Get-MermaidContent $mmd
            $doc.AppendLine("  <h3 id=`"diagram-$name`">$safeMmdTitle</h3>") | Out-Null
            $doc.AppendLine('  <div class="diagram-container">') | Out-Null
            $doc.AppendLine("    <pre class=`"mermaid`">$mermaidSrc</pre>") | Out-Null
            $doc.AppendLine('  </div>') | Out-Null
            Write-Host "  Diagram: $name" -ForegroundColor DarkGray
        }
    }

    $doc.AppendLine('  <hr>') | Out-Null

    # ── Entity tables ────────────────────────────────────────────────────────
    $doc.AppendLine('  <h2>Entity Definitions</h2>') | Out-Null
    $doc.AppendLine('  <div class="entity-section">') | Out-Null

    foreach ($entity in $EntityList) {
        $csvFile = Join-Path $entitiesDir "$entity.csv"
        if (-not (Test-Path $csvFile)) {
            Write-Warning "$entity.csv not found, skipping"
            continue
        }

        $safeEntity = [System.Net.WebUtility]::HtmlEncode($entity)
        $allRows = Import-Csv $csvFile
        if (-not $allRows) {
            $doc.AppendLine("  <details id=`"entity-$entity`">") | Out-Null
            $doc.AppendLine("    <summary>$safeEntity</summary>") | Out-Null
            $doc.AppendLine('    <div class="table-wrap"><p><em>No data.</em></p></div>') | Out-Null
            $doc.AppendLine('  </details>') | Out-Null
        } else {
            $headers    = $allRows[0].PSObject.Properties.Name
            $usedRows   = $allRows | Where-Object { [int]($_.usage) -gt 0 }
            $unusedRows = $allRows | Where-Object { [int]($_.usage) -eq 0 }

            $usedCount   = @($usedRows).Count
            $unusedCount = @($unusedRows).Count

            $doc.AppendLine("  <details id=`"entity-$entity`">") | Out-Null
            $doc.AppendLine("    <summary>$safeEntity &mdash; $usedCount used, $unusedCount unused</summary>") | Out-Null
            $doc.AppendLine('    <div class="table-wrap">') | Out-Null

            if ($usedCount -gt 0) {
                $doc.AppendLine('    <h4>Active Properties</h4>') | Out-Null
                $doc.AppendLine((ConvertTo-SortableTable $usedRows $headers)) | Out-Null
            }

            if ($unusedCount -gt 0) {
                $doc.AppendLine('    <details class="unused-section">') | Out-Null
                $doc.AppendLine("      <summary>Unused Properties ($unusedCount)</summary>") | Out-Null
                $doc.AppendLine((ConvertTo-SortableTable $unusedRows $headers)) | Out-Null
                $doc.AppendLine('    </details>') | Out-Null
            }

            $doc.AppendLine('    </div>') | Out-Null
            $doc.AppendLine('  </details>') | Out-Null
        }

        Write-Host "  Table: $entity" -ForegroundColor DarkGray
    }

    $doc.AppendLine('  </div>') | Out-Null

    # ── Scripts (Mermaid + sorting) ──────────────────────────────────────────
    $doc.AppendLine(@'
  <script type="module">
    import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
    mermaid.initialize({
      startOnLoad: true,
      theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default',
      securityLevel: 'strict',
      maxTextSize: 100000,
      er: { useMaxWidth: true }
    });
  </script>
  <script>
    document.addEventListener('click', function(e) {
      const th = e.target.closest('th[data-sort-col]');
      if (!th) return;
      const table = th.closest('table');
      const idx = Array.from(th.parentNode.children).indexOf(th);
      const tbody = table.querySelector('tbody');
      const rows = Array.from(tbody.querySelectorAll('tr'));
      const arrow = th.querySelector('.sort-arrow');
      th.closest('tr').querySelectorAll('.sort-arrow').forEach(a => {
        if (a !== arrow) { a.className = 'sort-arrow'; }
      });
      const asc = !arrow.classList.contains('asc') || arrow.classList.contains('desc');
      arrow.className = 'sort-arrow ' + (asc ? 'asc' : 'desc');
      rows.sort(function(a, b) {
        const cellA = a.children[idx];
        const cellB = b.children[idx];
        const valA = cellA.dataset.sortValue;
        const valB = cellB.dataset.sortValue;
        let cmp;
        if (valA !== undefined && valB !== undefined) {
          cmp = Number(valA) - Number(valB);
        } else {
          cmp = cellA.textContent.localeCompare(cellB.textContent, undefined, { sensitivity: 'base' });
        }
        return asc ? cmp : -cmp;
      });
      rows.forEach(function(r) { tbody.appendChild(r); });
    });
  </script>
</body>
</html>
'@) | Out-Null

    return $doc.ToString()
}

# ── Collect diagram files ────────────────────────────────────────────────────
$allMmdFiles = Get-ChildItem $diagramsDir -Filter '*.mmd' | Sort-Object Name

# Split diagrams: business diagrams → primary doc; system/all → system doc
$primaryDiagrams = @($allMmdFiles | Where-Object {
    [IO.Path]::GetFileNameWithoutExtension($_.Name) -ne 'system-administration'
})
$systemDiagrams = @($allMmdFiles | Where-Object {
    $n = [IO.Path]::GetFileNameWithoutExtension($_.Name)
    $n -eq 'system-administration' -or $n -eq 'all-entities'
})

# ── Generate primary document (business / migration entities) ────────────────
Write-Host "`nGenerating primary entity reference..." -ForegroundColor Cyan
$primaryHtml = Build-HtmlDocument `
    -Title      'Dynamics 365 CRM — Entity Reference' `
    -Subtitle   "Business and migration-relevant entities ($($primaryEntities.Count) entities)" `
    -EntityList $primaryEntities `
    -Diagrams   $primaryDiagrams `
    -CrossLinkHtml 'See also: <a href="dynamics-crm-system-entities.html">System &amp; Built-in Entities</a>'

$primaryPath = Join-Path $outputDir 'dynamics-crm-entity-reference.html'
$primaryHtml | Set-Content $primaryPath -Encoding UTF8
Write-Host "Saved → $primaryPath" -ForegroundColor Green

# ── Generate system entities document ────────────────────────────────────────
Write-Host "`nGenerating system entities reference..." -ForegroundColor Cyan
$systemHtml = Build-HtmlDocument `
    -Title      'Dynamics 365 CRM — System & Built-in Entities' `
    -Subtitle   "System, platform, and built-in entities ($($systemEntities.Count) entities)" `
    -EntityList $systemEntities `
    -Diagrams   $systemDiagrams `
    -CrossLinkHtml 'See also: <a href="dynamics-crm-entity-reference.html">Business Entity Reference</a>'

$systemPath = Join-Path $outputDir 'dynamics-crm-system-entities.html'
$systemHtml | Set-Content $systemPath -Encoding UTF8
Write-Host "Saved → $systemPath" -ForegroundColor Green
