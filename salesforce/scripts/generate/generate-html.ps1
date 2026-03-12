<#
.SYNOPSIS
    Generates self-contained HTML reference documents with client-side Mermaid
    diagrams and object field tables.

.DESCRIPTION
    Output:
      salesforce-object-reference.html    — objects referenced in at least one diagram group
      salesforce-uncategorized-objects.html — discovered custom objects not in any diagram group

    Object classification is derived from the diagram groups in config.json:
      Objects referenced in any diagram group are considered in-scope.
      Everything else goes into the uncategorized document.

    No external tools required — Mermaid diagrams are rendered in the browser.
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/../gather/config.json"
)

$config     = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$cleanDir   = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.cleanDir))
$diagramsDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.diagramsDir))
$objectsDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.objectsDir))
$outputDir  = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../output'))

# Object list from clean output
$objectsFile = Join-Path $cleanDir 'objects.json'
if (-not (Test-Path $objectsFile)) {
    Write-Error "data/clean/objects.json not found. Run the clean stage first."
    exit 1
}
$objectNames = (Get-Content $objectsFile -Raw | ConvertFrom-Json) |
               ForEach-Object { $_.apiName }

# ── Classify objects from diagram groups ──────────────────────────────────────
$diagramObjects = [System.Collections.Generic.HashSet[string]]::new()

foreach ($groupName in $config.diagrams.PSObject.Properties.Name) {
    foreach ($oName in $config.diagrams.$groupName) {
        if ($oName -ne '*') { $diagramObjects.Add($oName) | Out-Null }
    }
}

$primaryObjects      = @($objectNames | Where-Object { $diagramObjects.Contains($_) })
$uncategorizedObjects = @($objectNames | Where-Object { -not $diagramObjects.Contains($_) })

Write-Host "Object classification: $($primaryObjects.Count) in diagrams, $($uncategorizedObjects.Count) uncategorized" -ForegroundColor Cyan

# ── Load operational insights ─────────────────────────────────────────────────
$insightsFile = Join-Path $cleanDir 'operational-insights.json'
$insights = @{}
$insightsSummary = $null
if (Test-Path $insightsFile) {
    $insightsRaw = Get-Content $insightsFile -Raw | ConvertFrom-Json
    $insightsSummary = $insightsRaw.summary
    foreach ($o in $insightsRaw.objects) {
        $insights[$o.apiName] = $o
    }
    Write-Host "Loaded operational insights for $($insights.Count) objects" -ForegroundColor Cyan
}

# Filter out empty objects
if ($insights.Count -gt 0) {
    $primaryObjects = @($primaryObjects | Where-Object {
        $cls = if ($insights.ContainsKey($_)) { $insights[$_].usageClassification } else { 'unknown' }
        $cls -ne 'empty'
    })
    $uncategorizedObjects = @($uncategorizedObjects | Where-Object {
        $cls = if ($insights.ContainsKey($_)) { $insights[$_].usageClassification } else { 'unknown' }
        $cls -ne 'empty'
    })
    Write-Host "After filtering empty: $($primaryObjects.Count) in diagrams, $($uncategorizedObjects.Count) uncategorized" -ForegroundColor Cyan
}

# ── Domain summary helper ─────────────────────────────────────────────────────
function Get-DomainSummary($groupName, [string[]]$groupObjects, [hashtable]$insightsMap) {
    $found   = @($groupObjects | Where-Object { $insightsMap.ContainsKey($_) })
    $data    = @($found | ForEach-Object { $insightsMap[$_] })
    $total   = ($data | Measure-Object -Property rowCount -Sum).Sum
    $trigSum = ($data | ForEach-Object { $_.transformations.triggerTotal }          | Measure-Object -Sum).Sum
    $vrSum   = ($data | ForEach-Object { $_.transformations.validationRuleTotal }   | Measure-Object -Sum).Sum
    [PSCustomObject]@{
        Domain          = ($groupName -replace '-', ' ')
        ObjectCount     = $found.Count
        TotalRows       = [long]($total ?? 0)
        Active          = @($data | Where-Object { $_.usageClassification -eq 'active' }).Count
        LowActivity     = @($data | Where-Object { $_.usageClassification -eq 'low-activity' }).Count
        Legacy          = @($data | Where-Object { $_.usageClassification -eq 'legacy' }).Count
        Empty           = @($data | Where-Object { $_.usageClassification -eq 'empty' }).Count
        ApexTriggers    = [int]($trigSum ?? 0)
        ValidationRules = [int]($vrSum   ?? 0)
    }
}

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

# ── Field rendering helpers ───────────────────────────────────────────────────

function Get-TypeClass($type) {
    switch ($type) {
        'guid'     { 'type-guid' }
        'string'   { 'type-string' }
        'int'      { 'type-int' }
        'decimal'  { 'type-decimal' }
        'bool'     { 'type-bool' }
        'datetime' { 'type-datetime' }
        'picklist' { 'type-picklist' }
        default    { 'type-other' }
    }
}

function Get-ObjectComplexity([object[]]$rows) {
    if (-not $rows -or $rows.Count -eq 0) {
        return [PSCustomObject]@{ Required=0; Lookups=0; OptionSets=0; Custom=0; Total=0; Score=0 }
    }
    $req  = @($rows | Where-Object { $_.required  -eq 'yes' }).Count
    $look = @($rows | Where-Object { $_.type      -eq 'guid' }).Count
    $opts = @($rows | Where-Object { $_.type      -eq 'picklist' }).Count
    $cust = @($rows | Where-Object { $_.is_custom -eq 'yes' }).Count
    [PSCustomObject]@{
        Required   = $req
        Lookups    = $look
        OptionSets = $opts
        Custom     = $cust
        Total      = $rows.Count
        Score      = $req + $look + $opts + $cust
    }
}

function Format-FieldTable([object[]]$rows) {
    $sb = [System.Text.StringBuilder]::new()
    $sb.AppendLine('<table class="sortable">') | Out-Null
    $sb.AppendLine('  <thead><tr>') | Out-Null
    foreach ($h in @('API Name','Label','Type','Flags','View Usage','BU Usage','Comment')) {
        $sb.AppendLine("    <th data-sort-col>$h <span class=`"sort-arrow`"></span></th>") | Out-Null
    }
    $sb.AppendLine('  </tr></thead>') | Out-Null
    $sb.AppendLine('  <tbody>') | Out-Null
    foreach ($row in $rows) {
        $typeCls  = Get-TypeClass $row.type
        $typeCell = "<span class=`"type-chip $typeCls`">$([System.Net.WebUtility]::HtmlEncode($row.type))</span>"

        $flags = [System.Collections.Generic.List[string]]::new()
        if ($row.required  -eq 'yes') { $flags.Add("<span class=`"req-badge`">required</span>") }
        if ($row.is_custom -eq 'yes') { $flags.Add("<span class=`"custom-badge`">custom</span>") }
        $flagsCell = if ($flags.Count -gt 0) { $flags -join ' ' } else { '' }

        $usageVal  = [int]($row.usage ?? 0)
        $nameCell  = [System.Net.WebUtility]::HtmlEncode($row.api_name)
        $labelCell = [System.Net.WebUtility]::HtmlEncode($row.label)
        $buCell    = [System.Net.WebUtility]::HtmlEncode($row.bu_usage ?? '')
        $cmtCell   = [System.Net.WebUtility]::HtmlEncode($row.comment  ?? '')

        $sb.AppendLine("  <tr><td>$nameCell</td><td>$labelCell</td><td>$typeCell</td><td>$flagsCell</td><td data-sort-value=`"$usageVal`">$usageVal</td><td>$buCell</td><td>$cmtCell</td></tr>") | Out-Null
    }
    $sb.AppendLine('  </tbody>') | Out-Null
    $sb.AppendLine('</table>') | Out-Null
    return $sb.ToString()
}

# ── Complexity table renderer ─────────────────────────────────────────────────
function Format-ComplexityTable($rows) {
    $sb = [System.Text.StringBuilder]::new()
    $sb.AppendLine('<table class="sortable">') | Out-Null
    $sb.AppendLine('  <thead><tr>') | Out-Null
    foreach ($h in @('Object','Fields','Required','Lookups','OptionSets','Custom','Custom%','Score','DataRows','Recommend')) {
        $sb.AppendLine("    <th data-sort-col>$h <span class=`"sort-arrow`"></span></th>") | Out-Null
    }
    $sb.AppendLine('  </tr></thead>') | Out-Null
    $sb.AppendLine('  <tbody>') | Out-Null
    foreach ($row in $rows) {
        $safeObject = [System.Net.WebUtility]::HtmlEncode($row.Object)
        $objectCell = "<a href=`"#object-$safeObject`">$safeObject</a>"
        $recClass   = switch ($row.Recommendation) {
            'Migrate' { 'rec-migrate' }
            'Verify'  { 'rec-verify' }
            'Archive' { 'rec-archive' }
            default   { 'rec-assess' }
        }
        $recCell   = "<span class=`"$recClass`">$([System.Net.WebUtility]::HtmlEncode($row.Recommendation))</span>"
        $drDisplay = $row.DataRows.ToString('N0')
        $sb.AppendLine("  <tr>") | Out-Null
        $sb.AppendLine("    <td>$objectCell</td>") | Out-Null
        $sb.AppendLine("    <td data-sort-value=`"$($row.Fields)`">$($row.Fields)</td>") | Out-Null
        $sb.AppendLine("    <td data-sort-value=`"$($row.Required)`">$($row.Required)</td>") | Out-Null
        $sb.AppendLine("    <td data-sort-value=`"$($row.Lookups)`">$($row.Lookups)</td>") | Out-Null
        $sb.AppendLine("    <td data-sort-value=`"$($row.OptionSets)`">$($row.OptionSets)</td>") | Out-Null
        $sb.AppendLine("    <td data-sort-value=`"$($row.Custom)`">$($row.Custom)</td>") | Out-Null
        $sb.AppendLine("    <td data-sort-value=`"$($row.CustomPct)`">$($row.CustomPct)%</td>") | Out-Null
        $sb.AppendLine("    <td data-sort-value=`"$($row.Score)`">$($row.Score)</td>") | Out-Null
        $sb.AppendLine("    <td data-sort-value=`"$($row.DataRows)`">$drDisplay</td>") | Out-Null
        $sb.AppendLine("    <td>$recCell</td>") | Out-Null
        $sb.AppendLine("  </tr>") | Out-Null
    }
    $sb.AppendLine('  </tbody>') | Out-Null
    $sb.AppendLine('</table>') | Out-Null
    return $sb.ToString()
}

# ── HTML document generator ───────────────────────────────────────────────────
function Build-HtmlDocument {
    param(
        [string]$Title,
        [string]$Subtitle,
        [string[]]$ObjectList,
        [System.IO.FileInfo[]]$Diagrams,
        [string]$CrossLinkHtml,
        [hashtable]$Insights = @{},
        [PSCustomObject]$InsightsSummary = $null,
        [PSCustomObject[]]$DomainSummaries = @(),
        [string]$ExecutiveSummaryHtml = '',
        [string]$DisclaimerHtml = ''
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

    /* Object section */
    .object-section details { border: 1px solid var(--border); border-radius: 6px; margin: 1rem 0; }
    .object-section details summary { cursor: pointer; padding: .6rem 1rem; background: var(--header-bg); font-weight: 600; border-radius: 6px; }
    .object-section details[open] summary { border-bottom: 1px solid var(--border); border-radius: 6px 6px 0 0; }
    .object-section details .table-wrap { overflow-x: auto; padding: .5rem; }

    /* Operational insight badges */
    .badge { display: inline-block; font-size: 0.75em; padding: 2px 8px; border-radius: 12px; font-weight: 600; margin-left: 0.5em; vertical-align: middle; }
    .badge-active     { background: #dafbe1; color: #1a7f37; }
    .badge-low        { background: #fff8c5; color: #9a6700; }
    .badge-legacy     { background: #ffebe9; color: #cf222e; }
    .badge-unknown    { background: #eaeef2; color: #656d76; }
    @media (prefers-color-scheme: dark) {
      .badge-active   { background: #1a3d27; color: #7ee787; }
      .badge-low      { background: #3d2e00; color: #e3b341; }
      .badge-legacy   { background: #3d1418; color: #f85149; }
      .badge-unknown  { background: #21262d; color: #8b949e; }
    }

    /* Stats bar */
    .stats-bar  { display: flex; gap: 1rem; margin: 1.5rem 0; flex-wrap: wrap; }
    .stat       { flex: 1; min-width: 120px; text-align: center; padding: 1rem;
                  border: 1px solid var(--border); border-radius: 8px; background: var(--section-bg); }
    .stat-value { display: block; font-size: 2em; font-weight: 700; }
    .stat-label { display: block; font-size: 0.85em; color: #656d76; margin-top: .2em; }

    /* Domain summary table */
    .domain-summary { margin: 1.5rem 0; }

    /* Field type chips */
    .type-chip { display: inline-block; font-size: 0.8em; padding: 1px 7px; border-radius: 4px; font-weight: 600; white-space: nowrap; }
    .type-guid     { background: #dbeafe; color: #1d4ed8; }
    .type-string   { background: #dcfce7; color: #166534; }
    .type-int,
    .type-decimal  { background: #ecfdf5; color: #065f46; }
    .type-bool     { background: #f5f3ff; color: #6d28d9; }
    .type-datetime { background: #eff6ff; color: #1e40af; }
    .type-picklist { background: #fff7ed; color: #9a3412; }
    .type-other    { background: #f1f5f9; color: #475569; }
    /* Field flag badges */
    .req-badge    { display: inline-block; font-size: 0.75em; padding: 1px 6px; border-radius: 4px; font-weight: 700; background: #fee2e2; color: #b91c1c; margin-right: 2px; }
    .custom-badge { display: inline-block; font-size: 0.75em; padding: 1px 6px; border-radius: 4px; background: #ede9fe; color: #5b21b6; font-weight: 600; margin-right: 2px; }
    @media (prefers-color-scheme: dark) {
      .type-guid     { background: #1e3a5f; color: #93c5fd; }
      .type-string   { background: #14402a; color: #86efac; }
      .type-int,
      .type-decimal  { background: #14402a; color: #86efac; }
      .type-bool     { background: #2e1065; color: #c4b5fd; }
      .type-datetime { background: #1e3a5f; color: #93c5fd; }
      .type-picklist { background: #431407; color: #fdba74; }
      .type-other    { background: #21262d; color: #8b949e; }
      .req-badge    { background: #7f1d1d; color: #fca5a5; }
      .custom-badge { background: #2e1065; color: #c4b5fd; }
    }
    /* Complexity bar */
    .complexity-bar { display: flex; gap: .4rem; margin: .4rem 0 .8rem; flex-wrap: wrap; }
    .cx-stat { font-size: 0.72em; padding: 2px 8px; border-radius: 10px; background: var(--section-bg); border: 1px solid var(--border); }
    .cx-req  { background: #fee2e2; color: #b91c1c; border-color: #fca5a5; }
    .cx-look { background: #dbeafe; color: #1d4ed8; border-color: #93c5fd; }
    .cx-opts { background: #fff7ed; color: #9a3412; border-color: #fdba74; }
    .cx-cust { background: #ede9fe; color: #5b21b6; border-color: #c4b5fd; }
    @media (prefers-color-scheme: dark) {
      .cx-req  { background: #7f1d1d; color: #fca5a5; border-color: #b91c1c; }
      .cx-look { background: #1e3a5f; color: #93c5fd; border-color: #1d4ed8; }
      .cx-opts { background: #431407; color: #fdba74; border-color: #9a3412; }
      .cx-cust { background: #2e1065; color: #c4b5fd; border-color: #5b21b6; }
    }

    /* Legend */
    .legend { border: 1px solid var(--border); border-radius: 6px; margin: 1.5rem 0; }
    .legend > summary { cursor: pointer; padding: .6rem 1rem; font-weight: 600; background: var(--section-bg); border-radius: 6px; list-style: none; display: flex; align-items: center; gap: .5rem; }
    .legend > summary::before { content: '\25B6'; font-size: .7em; opacity: .6; transition: transform .15s; }
    .legend[open] > summary::before { transform: rotate(90deg); }
    .legend[open] > summary { border-bottom: 1px solid var(--border); border-radius: 6px 6px 0 0; }
    .legend-body { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 1.5rem; padding: 1.2rem 1.5rem; }
    .legend-section h4 { margin: 0 0 .6rem; font-size: 0.8em; text-transform: uppercase; letter-spacing: .06em; color: #656d76; border-bottom: 1px solid var(--border); padding-bottom: .3rem; }
    .legend-section p { margin: .3rem 0; font-size: 0.85em; line-height: 1.5; }
    .legend-section p strong { font-family: monospace; }
    .legend-item { display: flex; align-items: baseline; gap: .5rem; margin: .35rem 0; font-size: 0.85em; }
    .legend-item > span:first-child { flex-shrink: 0; }
    /* Object group headings */
    .object-group-heading { margin: 2rem 0 .5rem; padding-bottom: .3rem; border-bottom: 1px solid var(--border); font-size: 1em; color: #656d76; }
    /* Executive summary callout */
    .callout { border: 1px solid #0969da; border-left: 4px solid #0969da; border-radius: 6px; background: #f0f6ff; padding: 1rem 1.5rem; margin: 1.5rem 0; }
    .callout-title { margin: 0 0 .6rem; font-size: 1em; }
    .callout-list { margin: .4rem 0; padding-left: 1.5rem; }
    .callout-list li { margin: .3rem 0; }
    .callout-note { margin: .8rem 0 0; font-size: 0.85em; color: #656d76; }
    @media (prefers-color-scheme: dark) {
      .callout { border-color: #58a6ff; background: #0d2045; }
    }
    /* Disclaimer banner */
    .disclaimer { border: 1px solid #d29922; background: #fff8c5; border-radius: 6px; padding: .8rem 1.2rem; margin: 1rem 0; font-size: 0.9em; }
    @media (prefers-color-scheme: dark) {
      .disclaimer { background: #3d2e00; border-color: #e3b341; color: var(--fg); }
    }
    /* Recommendation badges */
    .rec-migrate { display: inline-block; font-size: 0.75em; padding: 1px 7px; border-radius: 4px; background: #dafbe1; color: #1a7f37; font-weight: 600; }
    .rec-verify  { display: inline-block; font-size: 0.75em; padding: 1px 7px; border-radius: 4px; background: #fff8c5; color: #9a6700; font-weight: 600; }
    .rec-archive { display: inline-block; font-size: 0.75em; padding: 1px 7px; border-radius: 4px; background: #ffebe9; color: #cf222e; font-weight: 600; }
    .rec-assess  { display: inline-block; font-size: 0.75em; padding: 1px 7px; border-radius: 4px; background: #eaeef2; color: #656d76; font-weight: 600; }
    @media (prefers-color-scheme: dark) {
      .rec-migrate { background: #1a3d27; color: #7ee787; }
      .rec-verify  { background: #3d2e00; color: #e3b341; }
      .rec-archive { background: #3d1418; color: #f85149; }
      .rec-assess  { background: #21262d; color: #8b949e; }
    }
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
    if ($DisclaimerHtml) {
        $doc.AppendLine("  $DisclaimerHtml") | Out-Null
    }
    if ($ExecutiveSummaryHtml) {
        $doc.AppendLine($ExecutiveSummaryHtml) | Out-Null
    }

    # ── Legend ────────────────────────────────────────────────────────────────
    $doc.AppendLine(@'
  <details class="legend">
    <summary>How to read this document</summary>
    <div class="legend-body">

      <div class="legend-section">
        <h4>Field Type</h4>
        <div class="legend-item"><span class="type-chip type-string">string</span> Free text (text, textarea, email, phone, URL)</div>
        <div class="legend-item"><span class="type-chip type-guid">guid</span> Unique identifier or reference (lookup/master-detail) field pointing to another object</div>
        <div class="legend-item"><span class="type-chip type-int">int</span> Whole number</div>
        <div class="legend-item"><span class="type-chip type-decimal">decimal</span> Decimal, currency, or percentage</div>
        <div class="legend-item"><span class="type-chip type-bool">bool</span> Checkbox (true / false)</div>
        <div class="legend-item"><span class="type-chip type-datetime">datetime</span> Date, datetime, or time</div>
        <div class="legend-item"><span class="type-chip type-picklist">picklist</span> Single-select or multi-select picklist</div>
      </div>

      <div class="legend-section">
        <h4>Field Flags</h4>
        <div class="legend-item"><span class="req-badge">required</span> Field must have a value (nillable=false and createable=true). Target system must provide equivalent validation.</div>
        <div class="legend-item"><span class="custom-badge">custom</span> Field added outside the standard Salesforce schema (API name ends in __c). Org-specific; has no built-in equivalent in any target system.</div>
      </div>

      <div class="legend-section">
        <h4>Object Status</h4>
        <div class="legend-item"><span class="badge badge-active">active</span> Records exist and are regularly created or modified &mdash; high migration priority.</div>
        <div class="legend-item"><span class="badge badge-low">low-activity</span> Records exist but are rarely touched &mdash; verify whether data is still needed.</div>
        <div class="legend-item"><span class="badge badge-legacy">legacy</span> Data present but no recent activity &mdash; candidate for archival rather than full migration.</div>
        <div class="legend-item"><span class="badge badge-unknown">unknown</span> No operational insight data available.</div>
        <p>The row count shown next to the object name is the current record count in Salesforce.</p>
      </div>

      <div class="legend-section">
        <h4>View Usage</h4>
        <p>Number of saved list views that display this field as a visible column. A higher count is a proxy for business importance. <strong>Zero does not mean unused</strong> &mdash; fields may appear in page layouts, flow in automation, or be consumed by integrations without ever appearing in a list view.</p>
        <p>Fields are split into <em>Active</em> (used in at least one list view) and <em>Fields Not Used in Any View</em> to help prioritise mapping effort.</p>
      </div>

      <div class="legend-section">
        <h4>Migration Complexity Score</h4>
        <p><strong>Score = Required + Lookups + OptionSets + Custom</strong></p>
        <p>A relative indicator of migration effort per object. Lookup fields (guid type) require relationship mapping. Picklist fields require option value mapping. Custom fields have no built-in equivalent in any target system. Sort the complexity table by Score to prioritise which objects need the most design work.</p>
        <p>The coloured pills inside each object (e.g. <em>3 required</em>, <em>5 lookups</em>) are a quick visual breakdown of that score.</p>
      </div>

    </div>
  </details>
'@) | Out-Null

    # ── Operational Overview ──────────────────────────────────────────────────
    if ($InsightsSummary) {
        $doc.AppendLine('  <h2 id="operational-overview">Operational Overview</h2>') | Out-Null
        $doc.AppendLine('  <div class="stats-bar">') | Out-Null
        $doc.AppendLine("    <div class=`"stat`"><span class=`"stat-value`">$($InsightsSummary.activeObjects)</span><span class=`"stat-label`">Active</span></div>") | Out-Null
        $doc.AppendLine("    <div class=`"stat`"><span class=`"stat-value`">$($InsightsSummary.lowActivityObjects)</span><span class=`"stat-label`">Low Activity</span></div>") | Out-Null
        $doc.AppendLine("    <div class=`"stat`"><span class=`"stat-value`">$($InsightsSummary.legacyObjects)</span><span class=`"stat-label`">Legacy</span></div>") | Out-Null
        $doc.AppendLine("    <div class=`"stat`"><span class=`"stat-value`">$($InsightsSummary.emptyObjects)</span><span class=`"stat-label`">Empty (excluded)</span></div>") | Out-Null
        $doc.AppendLine('  </div>') | Out-Null

        if ($DomainSummaries.Count -gt 0) {
            $doc.AppendLine('  <div class="domain-summary">') | Out-Null
            $doc.AppendLine('  <h3>Domain Summary</h3>') | Out-Null
            $dHeaders = @('Domain','ObjectCount','TotalRows','Active','LowActivity','Legacy','Empty','ApexTriggers','ValidationRules')
            $doc.AppendLine((ConvertTo-SortableTable $DomainSummaries $dHeaders)) | Out-Null
            $doc.AppendLine('  </div>') | Out-Null
        }
    }

    # ── Table of Contents ─────────────────────────────────────────────────────
    $doc.AppendLine('  <nav>') | Out-Null
    $doc.AppendLine('    <details open>') | Out-Null
    $doc.AppendLine('      <summary>Table of Contents</summary>') | Out-Null

    if ($InsightsSummary) {
        $doc.AppendLine('      <h4><a href="#operational-overview">Operational Overview</a></h4>') | Out-Null
    }

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

    $doc.AppendLine('      <h4><a href="#migration-complexity">Migration Complexity</a></h4>') | Out-Null
    $doc.AppendLine('      <h4>Object Definitions</h4>') | Out-Null

    # TOC object links grouped by status, alphabetically within each group
    $tocStatusOrder = @('active', 'low-activity', 'legacy', 'unknown')
    $tocGrouped = $ObjectList |
        Sort-Object @(
            { $cls = if ($Insights.ContainsKey($_)) { $Insights[$_].usageClassification ?? 'unknown' } else { 'unknown' }
              $tocStatusOrder.IndexOf($cls) -ge 0 ? $tocStatusOrder.IndexOf($cls) : 99 },
            { $_ }
        )
    $tocCurrentGroup = $null
    foreach ($obj in $tocGrouped) {
        $csvFile = Join-Path $objectsDir "$obj.csv"
        if (-not (Test-Path $csvFile)) { continue }
        $tocCls = if ($Insights.ContainsKey($obj)) { $Insights[$obj].usageClassification ?? 'unknown' } else { 'unknown' }
        if ($tocCls -ne $tocCurrentGroup) {
            if ($tocCurrentGroup -ne $null) { $doc.AppendLine('      </ul>') | Out-Null }
            $tocCurrentGroup = $tocCls
            $tocLabel = switch ($tocCls) {
                'active'       { 'Active' }
                'low-activity' { 'Low Activity' }
                'legacy'       { 'Legacy' }
                default        { 'Unknown' }
            }
            $doc.AppendLine("      <p style=`"margin:.6rem 0 .2rem;font-size:.8em;font-weight:600;color:#656d76;text-transform:uppercase;letter-spacing:.05em`">$tocLabel</p>") | Out-Null
            $doc.AppendLine('      <ul>') | Out-Null
        }
        $doc.AppendLine("        <li><a href=`"#object-$obj`">$([System.Net.WebUtility]::HtmlEncode($obj))</a></li>") | Out-Null
    }
    if ($tocCurrentGroup -ne $null) { $doc.AppendLine('      </ul>') | Out-Null }
    $doc.AppendLine('    </details>') | Out-Null
    $doc.AppendLine('  </nav>') | Out-Null

    # ── Diagrams ──────────────────────────────────────────────────────────────
    if ($Diagrams -and $Diagrams.Count -gt 0) {
        $doc.AppendLine('  <hr>') | Out-Null
        $doc.AppendLine('  <h2>Diagrams</h2>') | Out-Null
        foreach ($mmd in $Diagrams) {
            $name         = [IO.Path]::GetFileNameWithoutExtension($mmd.Name)
            $mmdTitle     = Get-MermaidTitle $mmd
            $safeMmdTitle = [System.Net.WebUtility]::HtmlEncode($mmdTitle)
            $mermaidSrc   = Get-MermaidContent $mmd
            $doc.AppendLine("  <h3 id=`"diagram-$name`">$safeMmdTitle</h3>") | Out-Null
            $doc.AppendLine('  <div class="diagram-container">') | Out-Null
            $doc.AppendLine("    <pre class=`"mermaid`">$mermaidSrc</pre>") | Out-Null
            $doc.AppendLine('  </div>') | Out-Null
            Write-Host "  Diagram: $name" -ForegroundColor DarkGray
        }
    }

    $doc.AppendLine('  <hr>') | Out-Null

    # ── Object tables ─────────────────────────────────────────────────────────
    $doc.AppendLine('  <h2>Object Definitions</h2>') | Out-Null

    # ── Migration Complexity Summary ──────────────────────────────────────────
    $complexityRows = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($obj in $ObjectList) {
        $csvFile = Join-Path $objectsDir "$obj.csv"
        if (-not (Test-Path $csvFile)) { continue }
        $allRowsCx = @(Import-Csv $csvFile)
        if (-not $allRowsCx -or $allRowsCx.Count -eq 0) { continue }
        $cx   = Get-ObjectComplexity $allRowsCx
        $eiCx = if ($Insights.ContainsKey($obj)) { $Insights[$obj] } else { $null }
        $cls  = if ($eiCx) { $eiCx.usageClassification ?? 'unknown' } else { 'unknown' }
        $drRaw = if ($eiCx -and $eiCx.rowCount) { [long]$eiCx.rowCount } else { 0 }
        $complexityRows.Add([PSCustomObject]@{
            Object         = $obj
            Fields         = $cx.Total
            Required       = $cx.Required
            Lookups        = $cx.Lookups
            OptionSets     = $cx.OptionSets
            Custom         = $cx.Custom
            CustomPct      = [int]([Math]::Round($cx.Custom * 100.0 / [Math]::Max($cx.Total, 1)))
            Score          = $cx.Score
            DataRows       = $drRaw
            Recommendation = switch ($cls) {
                'active'       { 'Migrate' }
                'low-activity' { 'Verify'  }
                'legacy'       { 'Archive' }
                default        { 'Assess'  }
            }
        })
    }
    if ($complexityRows.Count -gt 0) {
        $doc.AppendLine('  <h3 id="migration-complexity">Migration Complexity Summary</h3>') | Out-Null
        $doc.AppendLine('  <p style="font-size:0.9em;color:#656d76;">Score&nbsp;=&nbsp;Required&nbsp;+&nbsp;Lookups&nbsp;+&nbsp;OptionSets&nbsp;+&nbsp;Custom. Custom% is the share of org-specific fields (ending in __c). Recommend is derived from object activity status. Sort by Score to prioritise migration effort.</p>') | Out-Null
        $doc.AppendLine((Format-ComplexityTable $complexityRows)) | Out-Null
    }

    $doc.AppendLine('  <div class="object-section">') | Out-Null

    # Group by status, then alphabetically within each group
    $statusOrder = @('active', 'low-activity', 'legacy', 'unknown')
    $groupedObjects = $ObjectList |
        Sort-Object @(
            { $cls = if ($Insights.ContainsKey($_)) { $Insights[$_].usageClassification ?? 'unknown' } else { 'unknown' }
              $statusOrder.IndexOf($cls) -ge 0 ? $statusOrder.IndexOf($cls) : 99 },
            { $_ }
        )

    $currentGroup = $null

    foreach ($obj in $groupedObjects) {
        $csvFile = Join-Path $objectsDir "$obj.csv"
        if (-not (Test-Path $csvFile)) {
            Write-Warning "$obj.csv not found, skipping"
            continue
        }

        $ei = if ($Insights.ContainsKey($obj)) { $Insights[$obj] } else { $null }
        $classification = if ($ei) { $ei.usageClassification } else { 'unknown' }
        $classification = $classification ?? 'unknown'

        # Emit group header when status changes
        if ($classification -ne $currentGroup) {
            $currentGroup = $classification
            $groupLabel = switch ($classification) {
                'active'       { 'Active' }
                'low-activity' { 'Low Activity' }
                'legacy'       { 'Legacy' }
                default        { 'Unknown' }
            }
            $groupBadgeClass = switch ($classification) {
                'active'       { 'badge-active' }
                'low-activity' { 'badge-low' }
                'legacy'       { 'badge-legacy' }
                default        { 'badge-unknown' }
            }
            $doc.AppendLine("  <h3 class=`"object-group-heading`"><span class=`"badge $groupBadgeClass`">$groupLabel</span></h3>") | Out-Null
        }
        $badgeClass = switch ($classification) {
            'active'       { 'badge-active' }
            'low-activity' { 'badge-low' }
            'legacy'       { 'badge-legacy' }
            default        { 'badge-unknown' }
        }
        $badgeHtml     = "<span class=`"badge $badgeClass`">$classification</span>"
        $rowCountLabel = if ($ei -and $ei.rowCount) { " &mdash; $($ei.rowCount.ToString('N0')) rows" } else { '' }

        $displayName = [System.Net.WebUtility]::HtmlEncode($obj)
        if ($ei -and $ei.label -and $ei.label -ne $obj) {
            $displayName += " ($([System.Net.WebUtility]::HtmlEncode($ei.label)))"
        }

        $allRows = @(Import-Csv $csvFile)
        if (-not $allRows -or $allRows.Count -eq 0) {
            $doc.AppendLine("  <details id=`"object-$obj`">") | Out-Null
            $doc.AppendLine("    <summary>$displayName $badgeHtml$rowCountLabel</summary>") | Out-Null
            $doc.AppendLine('    <div class="table-wrap"><p><em>No data.</em></p></div>') | Out-Null
            $doc.AppendLine('  </details>') | Out-Null
        } else {
            $cx         = Get-ObjectComplexity $allRows
            $usedRows   = @($allRows | Where-Object { [int]($_.usage) -gt 0 })
            $unusedRows = @($allRows | Where-Object { [int]($_.usage) -eq 0 })
            $usedCount  = $usedRows.Count

            # Complexity bar
            $cxParts = [System.Collections.Generic.List[string]]::new()
            if ($cx.Required   -gt 0) { $cxParts.Add("<span class=`"cx-stat cx-req`">$($cx.Required) required</span>") }
            if ($cx.Lookups    -gt 0) { $cxParts.Add("<span class=`"cx-stat cx-look`">$($cx.Lookups) lookups</span>") }
            if ($cx.OptionSets -gt 0) { $cxParts.Add("<span class=`"cx-stat cx-opts`">$($cx.OptionSets) option sets</span>") }
            if ($cx.Custom     -gt 0) { $cxParts.Add("<span class=`"cx-stat cx-cust`">$($cx.Custom) custom</span>") }
            $cxBar = if ($cxParts.Count -gt 0) { '<div class="complexity-bar">' + ($cxParts -join '') + '</div>' } else { '' }

            $doc.AppendLine("  <details id=`"object-$obj`">") | Out-Null
            $doc.AppendLine("    <summary>$displayName $badgeHtml$rowCountLabel &mdash; $($cx.Total) fields, $usedCount active</summary>") | Out-Null
            $doc.AppendLine('    <div class="table-wrap">') | Out-Null
            if ($cxBar) { $doc.AppendLine("    $cxBar") | Out-Null }

            if ($usedCount -gt 0) {
                $doc.AppendLine('    <h4>Active Fields</h4>') | Out-Null
                $doc.AppendLine((Format-FieldTable $usedRows)) | Out-Null
            }

            if ($unusedRows.Count -gt 0) {
                $doc.AppendLine('    <details class="unused-section">') | Out-Null
                $doc.AppendLine("      <summary>Fields Not Used in Any View ($($unusedRows.Count))</summary>") | Out-Null
                $doc.AppendLine('      <p style="font-size:0.82em;color:#656d76;margin:.4rem .5rem .6rem;">View usage = 0 does not mean these fields are empty or irrelevant &mdash; they may be populated, used in page layouts, referenced by automation, or consumed by integrations. Verify before excluding from migration scope.</p>') | Out-Null
                $doc.AppendLine((Format-FieldTable $unusedRows)) | Out-Null
                $doc.AppendLine('    </details>') | Out-Null
            }

            $doc.AppendLine('    </div>') | Out-Null
            $doc.AppendLine('  </details>') | Out-Null
        }

        Write-Host "  Table: $obj" -ForegroundColor DarkGray
    }

    $doc.AppendLine('  </div>') | Out-Null

    # ── Scripts (Mermaid + sorting) ───────────────────────────────────────────

    # Inject object classification data for diagram coloring
    if ($Insights.Count -gt 0) {
        $classMap = [ordered]@{}
        foreach ($k in $Insights.Keys) {
            $safeName = $k -replace '[^a-zA-Z0-9_]', ''
            $safeCls  = if ($Insights[$k].usageClassification) { $Insights[$k].usageClassification } else { 'unknown' }
            if ($safeCls -match '^(active|low-activity|legacy|empty|unknown)$') {
                $classMap[$safeName] = $safeCls
            }
        }
        $classJson = ($classMap | ConvertTo-Json -Compress) -replace '</', '<\/'
        $doc.AppendLine("  <script>window.__objectClassifications=$classJson;</script>") | Out-Null
    }

    $doc.AppendLine(@'
  <script type="module">
    import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
    mermaid.initialize({
      startOnLoad: false,
      theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default',
      securityLevel: 'strict',
      maxTextSize: 100000,
      er: { useMaxWidth: true }
    });
    await mermaid.run({ querySelector: '.mermaid' });

    // Color-code object boxes by operational classification
    if (window.__objectClassifications) {
      const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
      const palette = {
        active:         isDark ? '#1a3d27' : '#dafbe1',
        'low-activity': isDark ? '#3d2e00' : '#fff8c5',
        legacy:         isDark ? '#3d1418' : '#ffebe9'
      };
      document.querySelectorAll('.mermaid svg text').forEach(text => {
        const name = text.textContent.trim().toLowerCase();
        const cls = window.__objectClassifications[name];
        if (!cls || !palette[cls]) return;
        const g = text.closest('g');
        const rect = g && g.querySelector('rect');
        if (rect) rect.setAttribute('fill', palette[cls]);
      });
    }
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

# ── Compute domain summaries ──────────────────────────────────────────────────
$domainSummaries = @()
if ($insights.Count -gt 0) {
    foreach ($gName in $config.diagrams.PSObject.Properties.Name) {
        $gObjects = @($config.diagrams.$gName | Where-Object { $_ -ne '*' })
        $domainSummaries += Get-DomainSummary $gName $gObjects $insights
    }
}

# ── Collect diagram files ─────────────────────────────────────────────────────
$allMmdFiles = Get-ChildItem $diagramsDir -Filter '*.mmd' | Sort-Object Name

# ── Pre-compute executive summary stats ───────────────────────────────────────
$totalTriggers  = ($domainSummaries | Measure-Object -Property ApexTriggers    -Sum).Sum ?? 0
$totalVrules    = ($domainSummaries | Measure-Object -Property ValidationRules -Sum).Sum ?? 0
$totalAutomation = [int]$totalTriggers + [int]$totalVrules

$execActiveCount = @($primaryObjects | Where-Object { ($insights[$_]?.usageClassification ?? 'unknown') -eq 'active'       }).Count
$execLowCount    = @($primaryObjects | Where-Object { ($insights[$_]?.usageClassification ?? 'unknown') -eq 'low-activity'  }).Count
$execLegacyCount = @($primaryObjects | Where-Object { ($insights[$_]?.usageClassification ?? 'unknown') -eq 'legacy'        }).Count

$execCxRows = foreach ($obj in $primaryObjects) {
    $csvPath = Join-Path $objectsDir "$obj.csv"
    if (-not (Test-Path $csvPath)) { continue }
    $allRowsEx = @(Import-Csv $csvPath)
    if (-not $allRowsEx -or $allRowsEx.Count -eq 0) { continue }
    $cxEx = Get-ObjectComplexity $allRowsEx
    [PSCustomObject]@{ Object = $obj; Score = $cxEx.Score; Custom = $cxEx.Custom; Total = $cxEx.Total }
}
$totalCustomFields = ($execCxRows | Measure-Object -Property Custom -Sum).Sum ?? 0
$totalAllFields    = ($execCxRows | Measure-Object -Property Total  -Sum).Sum ?? 0
$customPct         = [int]([Math]::Round($totalCustomFields * 100.0 / [Math]::Max($totalAllFields, 1)))
$topByScore        = @($execCxRows | Sort-Object Score -Descending | Select-Object -First 5)
$topItemsHtml      = ($topByScore | ForEach-Object {
    "        <li><strong>$([System.Net.WebUtility]::HtmlEncode($_.Object))</strong> &mdash; score $($_.Score), $($_.Custom) custom fields</li>"
}) -join "`n"

$execSummaryHtml = @"
  <div class="callout">
    <h3 class="callout-title">At a Glance &mdash; Migration Snapshot</h3>
    <ul class="callout-list">
      <li><strong>$($primaryObjects.Count) objects in scope</strong> across $($domainSummaries.Count) domains &mdash; $execActiveCount active, $execLowCount low-activity, $execLegacyCount legacy</li>
      <li><strong>$totalCustomFields custom fields</strong> out of $totalAllFields total ($customPct%) &mdash; org-specific fields with no built-in equivalent in any target system</li>
      <li><strong>$totalAutomation automation items</strong> to re-implement ($totalTriggers Apex triggers + $totalVrules validation rules across all domains)</li>
      <li>Highest-complexity objects by migration score:
        <ol>
$topItemsHtml
        </ol>
      </li>
    </ul>
  </div>
"@

# ── Generate primary document (objects in diagram groups) ─────────────────────
Write-Host "`nGenerating primary object reference..." -ForegroundColor Cyan
$primaryHtml = Build-HtmlDocument `
    -Title                'Salesforce — Object Reference' `
    -Subtitle             "Custom objects in diagram scope ($($primaryObjects.Count) objects)" `
    -ObjectList           $primaryObjects `
    -Diagrams             $allMmdFiles `
    -CrossLinkHtml        (if ($uncategorizedObjects.Count -gt 0) { 'See also: <a href="salesforce-uncategorized-objects.html">Uncategorized Custom Objects</a>' } else { '' }) `
    -Insights             $insights `
    -InsightsSummary      $insightsSummary `
    -DomainSummaries      $domainSummaries `
    -ExecutiveSummaryHtml $execSummaryHtml

$primaryPath = Join-Path $outputDir 'salesforce-object-reference.html'
$primaryHtml | Set-Content $primaryPath -Encoding UTF8
Write-Host "Saved → $primaryPath" -ForegroundColor Green

# ── Generate uncategorized objects document (if any) ─────────────────────────
if ($uncategorizedObjects.Count -gt 0) {
    $uncatDisclaimerHtml = '<div class="disclaimer"><strong>Scope note:</strong> This document lists custom objects discovered in your Salesforce org that are not referenced in any diagram group. They may still be migration candidates &mdash; review and add to config.json diagram groups as appropriate. Use the <a href="salesforce-object-reference.html">Object Reference</a> for in-scope objects.</div>'

    Write-Host "`nGenerating uncategorized objects reference..." -ForegroundColor Cyan
    $uncatHtml = Build-HtmlDocument `
        -Title          'Salesforce — Uncategorized Custom Objects' `
        -Subtitle       "Discovered custom objects not assigned to any diagram group ($($uncategorizedObjects.Count) objects)" `
        -ObjectList     $uncategorizedObjects `
        -Diagrams       @() `
        -CrossLinkHtml  'See also: <a href="salesforce-object-reference.html">Object Reference</a>' `
        -Insights       $insights `
        -InsightsSummary $insightsSummary `
        -DisclaimerHtml $uncatDisclaimerHtml

    $uncatPath = Join-Path $outputDir 'salesforce-uncategorized-objects.html'
    $uncatHtml | Set-Content $uncatPath -Encoding UTF8
    Write-Host "Saved → $uncatPath" -ForegroundColor Green
} else {
    Write-Host "No uncategorized objects — skipping secondary document" -ForegroundColor DarkGray
}
