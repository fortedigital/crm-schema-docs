<#
.SYNOPSIS
    Generates self-contained HTML reference documents with client-side Mermaid
    diagrams and object property tables.

.DESCRIPTION
    Output:
      hubspot-object-reference.html    — objects referenced in at least one diagram group
      hubspot-uncategorized-objects.html — discovered objects not in any diagram group

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

$config      = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$cleanDir    = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.cleanDir))
$diagramsDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.diagramsDir))
$objectsDir  = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.objectsDir))
$outputDir   = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../output'))

# Object list from clean output
$objectsFile = Join-Path $cleanDir 'objects.json'
if (-not (Test-Path $objectsFile)) {
    Write-Error "data/clean/objects.json not found. Run the clean stage first."
    exit 1
}
$allObjects  = Get-Content $objectsFile -Raw | ConvertFrom-Json
$objectNames = $allObjects | ForEach-Object { $_.name }

# ── Classify objects from diagram groups ──────────────────────────────────────
$diagramObjects = [System.Collections.Generic.HashSet[string]]::new()
foreach ($group in $config.diagrams.PSObject.Properties) {
    foreach ($o in $group.Value) { $diagramObjects.Add($o) | Out-Null }
}

$primaryObjects       = $objectNames | Where-Object { $diagramObjects.Contains($_) }
$uncategorizedObjects = $objectNames | Where-Object { -not $diagramObjects.Contains($_) }

Write-Host "Objects: $($primaryObjects.Count) in-scope, $($uncategorizedObjects.Count) uncategorized" -ForegroundColor Cyan

# ── Load operational insights ─────────────────────────────────────────────────
$insightsFile = Join-Path $cleanDir 'operational-insights.json'
$insights     = if (Test-Path $insightsFile) {
    Get-Content $insightsFile -Raw | ConvertFrom-Json
} else { $null }

$insightsByName = @{}
if ($insights) {
    foreach ($o in $insights.objects) { $insightsByName[$o.objectType] = $o }
}

# ── Load relationships ─────────────────────────────────────────────────────────
$relsFile     = Join-Path $cleanDir 'relationships.json'
$allRels      = if (Test-Path $relsFile) {
    Get-Content $relsFile -Raw | ConvertFrom-Json
} else { @() }

# ── Helpers ───────────────────────────────────────────────────────────────────
function Get-ObjectLabel($name) {
    $obj = $allObjects | Where-Object { $_.name -eq $name } | Select-Object -First 1
    return $obj?.label ?? $name
}

function Get-ObjectInsight($name) {
    return $insightsByName[$name]
}

function Get-DomainSummary($names) {
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($groupName in $config.diagrams.PSObject.Properties.Name) {
        $groupMembers = @($config.diagrams.$groupName) | Where-Object { $names -contains $_ }
        if ($groupMembers.Count -eq 0) { continue }

        $objCount    = $groupMembers.Count
        $totalRows   = 0
        $active = $lowAct = $legacy = $empty = 0
        $workflows = 0

        foreach ($n in $groupMembers) {
            $ins = Get-ObjectInsight $n
            if ($ins) {
                if ($ins.rowCount) { $totalRows += $ins.rowCount }
                switch ($ins.usageClassification) {
                    'active'       { $active++ }
                    'low-activity' { $lowAct++ }
                    'legacy'       { $legacy++ }
                    'empty'        { $empty++ }
                }
                if ($ins.automation) { $workflows += $ins.automation.workflowTotal ?? 0 }
            }
        }

        $rows.Add([PSCustomObject]@{
            Domain      = $groupName
            Objects     = $objCount
            TotalRows   = $totalRows
            Active      = $active
            LowActivity = $lowAct
            Legacy      = $legacy
            Empty       = $empty
            Workflows   = $workflows
        })
    }
    return $rows
}

function Get-ObjectComplexity($name) {
    $csvFile = Join-Path $objectsDir "$name.csv"
    if (-not (Test-Path $csvFile)) { return $null }

    $fields  = Import-Csv $csvFile
    $total   = $fields.Count
    if ($total -eq 0) { return $null }

    $required   = ($fields | Where-Object { $_.required -eq 'yes' }).Count
    $optionSets = ($fields | Where-Object { $_.type -eq 'picklist' }).Count
    $custom     = ($fields | Where-Object { $_.is_custom -eq 'yes' }).Count
    $customPct  = [math]::Round($custom / $total * 100)
    $score      = $required + $optionSets + $custom

    $ins      = Get-ObjectInsight $name
    $dataRows = if ($ins?.rowCount) { $ins.rowCount } else { $null }
    $status   = $ins?.usageClassification ?? ''

    $recommend = if ($status -eq 'empty') {
        'Evaluate for removal'
    } elseif ($score -ge 30) {
        'High complexity — review carefully'
    } elseif ($score -ge 15) {
        'Moderate complexity'
    } else {
        'Low complexity'
    }

    return [PSCustomObject]@{
        Object    = $name
        Fields    = $total
        Required  = $required
        OptionSets = $optionSets
        Custom    = $custom
        CustomPct = $customPct
        Score     = $score
        DataRows  = $dataRows
        Status    = $status
        Recommend = $recommend
    }
}

function Format-FieldTable($name) {
    $csvFile = Join-Path $objectsDir "$name.csv"
    if (-not (Test-Path $csvFile)) { return '<p><em>No property data.</em></p>' }

    $fields = Import-Csv $csvFile
    if ($fields.Count -eq 0) { return '<p><em>No properties.</em></p>' }

    $sb = [System.Text.StringBuilder]::new()
    $sb.Append('<table class="field-table sortable">') | Out-Null
    $sb.Append('<thead><tr>') | Out-Null
    $sb.Append('<th>API Name</th><th>Label</th><th>Type</th><th>Flags</th><th>Group</th><th>BU Usage</th><th>Comment</th>') | Out-Null
    $sb.Append('</tr></thead><tbody>') | Out-Null

    foreach ($f in $fields) {
        $badges = ''
        if ($f.required -eq 'yes') { $badges += '<span class="badge req-badge">REQ</span>' }
        if ($f.is_custom -eq 'yes') { $badges += '<span class="badge custom-badge">CUSTOM</span>' }

        $sb.Append('<tr>') | Out-Null
        $sb.Append("<td><code>$([System.Web.HttpUtility]::HtmlEncode($f.api_name))</code></td>") | Out-Null
        $sb.Append("<td>$([System.Web.HttpUtility]::HtmlEncode($f.label))</td>") | Out-Null
        $sb.Append("<td><span class=`"type-tag`">$([System.Web.HttpUtility]::HtmlEncode($f.type))</span></td>") | Out-Null
        $sb.Append("<td>$badges</td>") | Out-Null
        $sb.Append("<td>$([System.Web.HttpUtility]::HtmlEncode($f.group))</td>") | Out-Null
        $sb.Append("<td>$([System.Web.HttpUtility]::HtmlEncode($f.bu_usage))</td>") | Out-Null
        $sb.Append("<td>$([System.Web.HttpUtility]::HtmlEncode($f.comment))</td>") | Out-Null
        $sb.Append('</tr>') | Out-Null
    }

    $sb.Append('</tbody></table>') | Out-Null
    return $sb.ToString()
}

function Format-ComplexityTable($names) {
    $rows = $names | ForEach-Object { Get-ObjectComplexity $_ } | Where-Object { $_ }
    $rows = $rows | Sort-Object Score -Descending

    $sb = [System.Text.StringBuilder]::new()
    $sb.Append('<table class="complexity-table sortable">') | Out-Null
    $sb.Append('<thead><tr>') | Out-Null
    $sb.Append('<th>Object</th><th>Fields</th><th>Required</th><th>OptionSets</th><th>Custom</th><th>Custom%</th><th>Score</th><th>Data Rows</th><th>Recommendation</th>') | Out-Null
    $sb.Append('</tr></thead><tbody>') | Out-Null

    foreach ($r in $rows) {
        $rowsDisplay = if ($null -ne $r.DataRows) { '{0:N0}' -f $r.DataRows } else { '—' }
        $statusBadge = switch ($r.Status) {
            'active'       { '<span class="status-badge status-active">Active</span>' }
            'low-activity' { '<span class="status-badge status-low">Low Activity</span>' }
            'legacy'       { '<span class="status-badge status-legacy">Legacy</span>' }
            'empty'        { '<span class="status-badge status-empty">Empty</span>' }
            default        { '' }
        }
        $sb.Append('<tr>') | Out-Null
        $sb.Append("<td><strong>$([System.Web.HttpUtility]::HtmlEncode($r.Object))</strong> $statusBadge</td>") | Out-Null
        $sb.Append("<td>$($r.Fields)</td>") | Out-Null
        $sb.Append("<td>$($r.Required)</td>") | Out-Null
        $sb.Append("<td>$($r.OptionSets)</td>") | Out-Null
        $sb.Append("<td>$($r.Custom)</td>") | Out-Null
        $sb.Append("<td>$($r.CustomPct)%</td>") | Out-Null
        $sb.Append("<td><strong>$($r.Score)</strong></td>") | Out-Null
        $sb.Append("<td>$rowsDisplay</td>") | Out-Null
        $sb.Append("<td>$([System.Web.HttpUtility]::HtmlEncode($r.Recommend))</td>") | Out-Null
        $sb.Append('</tr>') | Out-Null
    }

    $sb.Append('</tbody></table>') | Out-Null
    return $sb.ToString()
}

function Get-StatusBadge($name) {
    $ins = Get-ObjectInsight $name
    if (-not $ins) { return '' }
    return switch ($ins.usageClassification) {
        'active'       { '<span class="status-badge status-active">Active</span>' }
        'low-activity' { '<span class="status-badge status-low">Low Activity</span>' }
        'legacy'       { '<span class="status-badge status-legacy">Legacy</span>' }
        'empty'        { '<span class="status-badge status-empty">Empty</span>' }
        default        { '' }
    }
}

function Get-ComplexityBar($score) {
    $pct   = [math]::Min($score, 50) * 2   # cap at 100%
    $color = if ($score -ge 30) { '#e74c3c' } elseif ($score -ge 15) { '#f39c12' } else { '#27ae60' }
    return "<div class=`"complexity-bar`"><div class=`"complexity-fill`" style=`"width:${pct}%;background:$color`"></div><span class=`"complexity-score`">$score</span></div>"
}

function Build-HtmlDocument($title, $objectList, $diagramGroups, $includeGlobal) {
    # Load .mmd files
    $mmdFiles = Get-ChildItem $diagramsDir -Filter '*.mmd' -ErrorAction SilentlyContinue | Sort-Object Name

    # Operational stats
    $statsHtml = ''
    if ($insights -and $includeGlobal) {
        $totalRecords  = ($objectList | ForEach-Object { (Get-ObjectInsight $_)?.rowCount ?? 0 } | Measure-Object -Sum).Sum
        $activeCount   = ($objectList | Where-Object { (Get-ObjectInsight $_)?.usageClassification -eq 'active' }).Count
        $emptyCount    = ($objectList | Where-Object { (Get-ObjectInsight $_)?.usageClassification -eq 'empty' }).Count
        $workflowTotal = $insights.global?.workflowCount ?? 0
        $workflowActive = $insights.global?.workflowsByStatus?.active ?? 0

        $statsHtml = @"
<div class="stats-bar">
  <div class="stat-item"><div class="stat-value">{0:N0}</div><div class="stat-label">Total Records</div></div>
  <div class="stat-item"><div class="stat-value">$($objectList.Count)</div><div class="stat-label">Objects</div></div>
  <div class="stat-item"><div class="stat-value">$activeCount</div><div class="stat-label">Active Objects</div></div>
  <div class="stat-item"><div class="stat-value">$emptyCount</div><div class="stat-label">Empty Objects</div></div>
  <div class="stat-item"><div class="stat-value">$workflowActive / $workflowTotal</div><div class="stat-label">Active / Total Workflows</div></div>
</div>
"@ -f $totalRecords
    }

    # Executive summary
    $execSummaryHtml = ''
    if ($includeGlobal -and $objectList.Count -gt 0) {
        $allCsvFields  = $objectList | ForEach-Object {
            $f = Join-Path $objectsDir "$_.csv"
            if (Test-Path $f) { Import-Csv $f } else { @() }
        }
        $totalFields  = ($allCsvFields | Measure-Object).Count
        $customFields = ($allCsvFields | Where-Object { $_.is_custom -eq 'yes' } | Measure-Object).Count
        $customPct    = if ($totalFields -gt 0) { [math]::Round($customFields / $totalFields * 100) } else { 0 }
        $top5 = $objectList | ForEach-Object { Get-ObjectComplexity $_ } |
                Where-Object { $_ } | Sort-Object Score -Descending | Select-Object -First 5

        $top5Html = ($top5 | ForEach-Object { "<li><strong>$($_.Object)</strong> — score $($_.Score) ($($_.Fields) fields)</li>" }) -join ''
        $execSummaryHtml = @"
<div class="exec-summary">
  <h3>Executive Summary</h3>
  <ul>
    <li><strong>$($objectList.Count) objects</strong> analysed; $totalFields total properties ($customPct% custom)</li>
    <li><strong>$activeCount</strong> active objects (modified in last 90 days)</li>
    <li><strong>$emptyCount</strong> empty objects — candidates for removal</li>
    <li><strong>$workflowActive workflows active</strong> out of $workflowTotal configured</li>
  </ul>
  <p><strong>Top 5 by complexity score:</strong></p>
  <ol>$top5Html</ol>
</div>
"@
    }

    # Domain summary table
    $domainSummaryHtml = ''
    if ($includeGlobal) {
        $domainRows = Get-DomainSummary $objectList
        if ($domainRows.Count -gt 0) {
            $tbl = [System.Text.StringBuilder]::new()
            $tbl.Append('<table class="domain-table sortable"><thead><tr>') | Out-Null
            $tbl.Append('<th>Diagram Group</th><th>Objects</th><th>Total Records</th><th>Active</th><th>Low Activity</th><th>Legacy</th><th>Empty</th><th>Workflows</th>') | Out-Null
            $tbl.Append('</tr></thead><tbody>') | Out-Null
            foreach ($dr in $domainRows) {
                $tbl.Append('<tr>') | Out-Null
                $tbl.Append("<td>$([System.Web.HttpUtility]::HtmlEncode($dr.Domain))</td>") | Out-Null
                $tbl.Append("<td>$($dr.Objects)</td>") | Out-Null
                $tbl.Append("<td>{0:N0}</td>" -f $dr.TotalRows) | Out-Null
                $tbl.Append("<td>$($dr.Active)</td>") | Out-Null
                $tbl.Append("<td>$($dr.LowActivity)</td>") | Out-Null
                $tbl.Append("<td>$($dr.Legacy)</td>") | Out-Null
                $tbl.Append("<td>$($dr.Empty)</td>") | Out-Null
                $tbl.Append("<td>$($dr.Workflows)</td>") | Out-Null
                $tbl.Append('</tr>') | Out-Null
            }
            $tbl.Append('</tbody></table>') | Out-Null
            $domainSummaryHtml = @"
<section class="domain-summary">
  <h2>Diagram Group Summary</h2>
  $($tbl.ToString())
</section>
"@
        }
    }

    # Build diagrams section
    $diagramsHtml = ''
    if ($mmdFiles.Count -gt 0 -and $includeGlobal) {
        $dSb = [System.Text.StringBuilder]::new()
        $dSb.Append('<section class="diagrams-section"><h2>Diagrams</h2>') | Out-Null

        foreach ($mmd in $mmdFiles) {
            $dName       = [IO.Path]::GetFileNameWithoutExtension($mmd.Name)
            $frontMatter = Get-Content $mmd.FullName | Select-Object -First 5
            $titleLine   = $frontMatter | Where-Object { $_ -match '^title:' } | Select-Object -First 1
            $dTitle      = if ($titleLine) { ($titleLine -replace '^title:\s*', '').Trim() } else { $dName }
            $mmdContent  = (Get-Content $mmd.FullName -Raw) -replace '^---.*?---\s*', '' -replace '(?ms)^---.*?---\s*', ''
            $mmdContent  = $mmdContent.Trim()

            $dSb.Append("<div class=`"diagram-block`"><h3>$([System.Web.HttpUtility]::HtmlEncode($dTitle))</h3>") | Out-Null
            $dSb.Append("<div class=`"mermaid`">$([System.Web.HttpUtility]::HtmlEncode($mmdContent))</div>") | Out-Null
            $dSb.Append('</div>') | Out-Null
        }

        $dSb.Append('</section>') | Out-Null
        $diagramsHtml = $dSb.ToString()
    }

    # ToC and object sections, grouped by status
    $tocHtml    = [System.Text.StringBuilder]::new()
    $objectsHtml = [System.Text.StringBuilder]::new()

    $statusOrder = @('active', 'low-activity', 'legacy', 'empty', '')
    $statusLabels = @{
        'active'       = 'Active Objects'
        'low-activity' = 'Low-Activity Objects'
        'legacy'       = 'Legacy Objects'
        'empty'        = 'Empty Objects'
        ''             = 'Uncategorised'
    }

    $grouped = @{}
    foreach ($s in $statusOrder) { $grouped[$s] = [System.Collections.Generic.List[string]]::new() }

    foreach ($n in $objectList) {
        $ins = Get-ObjectInsight $n
        $s   = $ins?.usageClassification ?? ''
        $grouped[$s].Add($n)
    }

    $tocHtml.Append('<nav class="toc"><h3>Contents</h3><ul>') | Out-Null
    if ($includeGlobal) {
        $tocHtml.Append('<li><a href="#domain-summary">Diagram Group Summary</a></li>') | Out-Null
        $tocHtml.Append('<li><a href="#complexity">Complexity Summary</a></li>') | Out-Null
        if ($mmdFiles.Count -gt 0) { $tocHtml.Append('<li><a href="#diagrams">Diagrams</a></li>') | Out-Null }
    }
    $tocHtml.Append('<li><a href="#objects">Object Definitions</a><ul>') | Out-Null

    foreach ($s in $statusOrder) {
        $group = $grouped[$s]
        if ($group.Count -eq 0) { continue }
        $slabel = $statusLabels[$s]
        $tocHtml.Append("<li><strong>$slabel</strong><ul>") | Out-Null
        foreach ($n in ($group | Sort-Object)) {
            $lbl = Get-ObjectLabel $n
            $tocHtml.Append("<li><a href=`"#obj-$n`">$([System.Web.HttpUtility]::HtmlEncode($lbl)) ($n)</a></li>") | Out-Null
        }
        $tocHtml.Append('</ul></li>') | Out-Null
    }
    $tocHtml.Append('</ul></li></ul></nav>') | Out-Null

    $objectsHtml.Append('<section id="objects"><h2>Object Definitions</h2>') | Out-Null

    foreach ($s in $statusOrder) {
        $group = $grouped[$s]
        if ($group.Count -eq 0) { continue }
        $slabel = $statusLabels[$s]
        $objectsHtml.Append("<h3 class=`"status-heading status-heading-$s`">$slabel</h3>") | Out-Null

        foreach ($n in ($group | Sort-Object)) {
            $lbl     = Get-ObjectLabel $n
            $ins     = Get-ObjectInsight $n
            $badge   = Get-StatusBadge $n
            $cx      = Get-ObjectComplexity $n
            $cxBar   = if ($cx) { Get-ComplexityBar $cx.Score } else { '' }
            $rowsStr = if ($ins?.rowCount) { '{0:N0} records' -f $ins.rowCount } else { 'No data' }

            $objectsHtml.Append("<details id=`"obj-$n`" class=`"object-details`">") | Out-Null
            $objectsHtml.Append("<summary><span class=`"obj-name`">$([System.Web.HttpUtility]::HtmlEncode($lbl))</span> <code class=`"obj-api`">$n</code> $badge <span class=`"obj-rows`">$rowsStr</span> $cxBar</summary>") | Out-Null
            $objectsHtml.Append('<div class="object-content">') | Out-Null

            # Active/unused field split
            if ($cx) {
                $objectsHtml.Append("<p class=`"field-summary`">$($cx.Fields) properties &bull; $($cx.Required) required &bull; $($cx.OptionSets) picklists &bull; $($cx.Custom) custom ($($cx.CustomPct)%)</p>") | Out-Null
            }

            $objectsHtml.Append($(Format-FieldTable $n)) | Out-Null
            $objectsHtml.Append('</div></details>') | Out-Null
        }
    }

    $objectsHtml.Append('</section>') | Out-Null

    # Complexity section
    $complexityHtml = ''
    if ($includeGlobal) {
        $complexityHtml = @"
<section id="complexity">
  <h2>Complexity Summary</h2>
  <p>Score = Required + OptionSets + Custom fields. Higher score = more migration effort.</p>
  $(Format-ComplexityTable $objectList)
</section>
"@
    }

    # CSS
    $css = @'
:root {
  --bg: #1a1d21; --surface: #22262c; --surface2: #2a2f38;
  --border: #3a3f4a; --text: #e0e4ef; --text-dim: #7a8099;
  --accent: #4f8ef7; --green: #27ae60; --yellow: #f39c12;
  --red: #e74c3c; --purple: #9b59b6;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: 'Segoe UI', system-ui, sans-serif; background: var(--bg); color: var(--text); line-height: 1.6; }
.container { max-width: 1400px; margin: 0 auto; padding: 2rem; }
h1 { font-size: 2rem; color: var(--accent); margin-bottom: 0.5rem; }
h2 { font-size: 1.4rem; border-bottom: 1px solid var(--border); padding-bottom: 0.5rem; margin: 2rem 0 1rem; color: var(--accent); }
h3 { font-size: 1.1rem; margin: 1.5rem 0 0.75rem; color: var(--text); }
.stats-bar { display: flex; gap: 1rem; flex-wrap: wrap; margin: 1.5rem 0; }
.stat-item { background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 1rem 1.5rem; text-align: center; min-width: 140px; }
.stat-value { font-size: 1.8rem; font-weight: 700; color: var(--accent); }
.stat-label { font-size: 0.8rem; color: var(--text-dim); text-transform: uppercase; letter-spacing: 0.05em; }
.exec-summary { background: var(--surface); border: 1px solid var(--border); border-left: 4px solid var(--accent); border-radius: 6px; padding: 1.5rem; margin: 1.5rem 0; }
.exec-summary h3 { margin-top: 0; color: var(--accent); }
.exec-summary ul, .exec-summary ol { padding-left: 1.5rem; }
.exec-summary li { margin: 0.4rem 0; }
.toc { background: var(--surface); border: 1px solid var(--border); border-radius: 6px; padding: 1.5rem; margin: 1.5rem 0; }
.toc h3 { margin-top: 0; }
.toc ul { padding-left: 1.2rem; list-style: none; }
.toc li { margin: 0.3rem 0; }
.toc a { color: var(--accent); text-decoration: none; }
.toc a:hover { text-decoration: underline; }
table { width: 100%; border-collapse: collapse; font-size: 0.85rem; margin: 1rem 0; }
th { background: var(--surface2); text-align: left; padding: 0.6rem 0.8rem; border-bottom: 2px solid var(--border); cursor: pointer; user-select: none; white-space: nowrap; }
th:hover { background: var(--border); }
td { padding: 0.5rem 0.8rem; border-bottom: 1px solid var(--border); vertical-align: top; }
tr:hover td { background: var(--surface2); }
code { background: var(--surface2); border-radius: 3px; padding: 0.1rem 0.4rem; font-size: 0.82em; color: #a8d8ff; }
.badge { display: inline-block; font-size: 0.65rem; font-weight: 700; padding: 0.15rem 0.4rem; border-radius: 3px; margin: 0 0.1rem; letter-spacing: 0.03em; }
.req-badge    { background: #7f3a3a; color: #ffb3b3; }
.custom-badge { background: #3a5a7f; color: #b3d8ff; }
.type-tag { display: inline-block; background: var(--surface2); border: 1px solid var(--border); border-radius: 3px; padding: 0.1rem 0.4rem; font-size: 0.75rem; color: var(--text-dim); }
.status-badge { display: inline-block; font-size: 0.7rem; font-weight: 600; padding: 0.15rem 0.5rem; border-radius: 3px; text-transform: uppercase; letter-spacing: 0.04em; margin-left: 0.3rem; }
.status-active { background: #1e4a2e; color: #6ee98a; }
.status-low    { background: #4a3a1e; color: #f0c060; }
.status-legacy { background: #4a2020; color: #f08080; }
.status-empty  { background: #2a2a3a; color: #9090b0; }
.status-heading { margin: 2rem 0 0.75rem; font-size: 1rem; color: var(--text-dim); text-transform: uppercase; letter-spacing: 0.07em; }
.object-details { background: var(--surface); border: 1px solid var(--border); border-radius: 6px; margin: 0.75rem 0; overflow: hidden; }
.object-details > summary { cursor: pointer; padding: 0.9rem 1.2rem; display: flex; align-items: center; gap: 0.6rem; flex-wrap: wrap; list-style: none; }
.object-details > summary::-webkit-details-marker { display: none; }
.object-details > summary:hover { background: var(--surface2); }
.obj-name { font-weight: 700; font-size: 1rem; }
.obj-api { font-size: 0.8rem; }
.obj-rows { font-size: 0.8rem; color: var(--text-dim); margin-left: auto; }
.object-content { padding: 1rem 1.2rem; border-top: 1px solid var(--border); }
.field-summary { font-size: 0.85rem; color: var(--text-dim); margin-bottom: 0.75rem; }
.complexity-bar { display: flex; align-items: center; gap: 0.5rem; min-width: 120px; }
.complexity-fill { height: 6px; border-radius: 3px; min-width: 2px; }
.complexity-score { font-size: 0.8rem; color: var(--text-dim); white-space: nowrap; }
.diagram-block { margin: 1.5rem 0; background: var(--surface); border: 1px solid var(--border); border-radius: 6px; padding: 1.5rem; }
.mermaid { background: #fff; border-radius: 4px; padding: 1rem; overflow-x: auto; }
.domain-summary { margin: 1.5rem 0; }
.legend { display: flex; flex-wrap: wrap; gap: 0.75rem; margin: 1rem 0; font-size: 0.82rem; }
.legend-item { display: flex; align-items: center; gap: 0.4rem; }
.meta { color: var(--text-dim); font-size: 0.85rem; margin-bottom: 1.5rem; }
'@

    # JS
    $js = @'
// Sortable tables
document.querySelectorAll('table.sortable').forEach(tbl => {
  const headers = tbl.querySelectorAll('thead th');
  headers.forEach((th, col) => {
    let asc = true;
    th.addEventListener('click', () => {
      const rows = Array.from(tbl.querySelectorAll('tbody tr'));
      rows.sort((a, b) => {
        const av = a.cells[col]?.textContent.trim() ?? '';
        const bv = b.cells[col]?.textContent.trim() ?? '';
        const an = parseFloat(av.replace(/[^0-9.-]/g,'')), bn = parseFloat(bv.replace(/[^0-9.-]/g,''));
        if (!isNaN(an) && !isNaN(bn)) return asc ? an - bn : bn - an;
        return asc ? av.localeCompare(bv) : bv.localeCompare(av);
      });
      rows.forEach(r => tbl.tBodies[0].append(r));
      asc = !asc;
    });
  });
});
'@

    # object classification map for Mermaid coloring
    $classMap = @{}
    foreach ($n in $objectList) {
        $ins = Get-ObjectInsight $n
        $classMap[$n] = $ins?.usageClassification ?? 'unknown'
    }
    $classJson = $classMap | ConvertTo-Json -Compress

    $generatedAt = Get-Date -Format 'yyyy-MM-dd HH:mm'

    return @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$([System.Web.HttpUtility]::HtmlEncode($title))</title>
<style>$css</style>
<script type="module">
import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
mermaid.initialize({ startOnLoad: true, theme: 'default', securityLevel: 'loose' });
</script>
</head>
<body>
<div class="container">
<h1>$([System.Web.HttpUtility]::HtmlEncode($title))</h1>
<p class="meta">Generated: $generatedAt &bull; HubSpot Portal: $($script:Connection?.PortalId ?? $config.environment.portalId)</p>
$statsHtml
$execSummaryHtml
$($tocHtml.ToString())
$(if ($domainSummaryHtml) { '<div id="domain-summary">' + $domainSummaryHtml + '</div>' })
$complexityHtml
$diagramsHtml
$($objectsHtml.ToString())
</div>
<script>window.__objectClassifications = $classJson;</script>
<script>$js</script>
</body>
</html>
"@
}

# ── Generate primary document ─────────────────────────────────────────────────
Write-Host "`nGenerating primary document..." -ForegroundColor Yellow

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$primaryHtml = Build-HtmlDocument `
    -title        'HubSpot — Object Reference' `
    -objectList   $primaryObjects `
    -diagramGroups $config.diagrams `
    -includeGlobal $true

$primaryPath = Join-Path $outputDir 'hubspot-object-reference.html'
$primaryHtml | Set-Content $primaryPath -Encoding UTF8
Write-Host "Primary document → $primaryPath ($($primaryObjects.Count) objects)" -ForegroundColor Green

# ── Generate uncategorized document ──────────────────────────────────────────
if ($uncategorizedObjects.Count -gt 0) {
    Write-Host "`nGenerating uncategorized document..." -ForegroundColor Yellow

    $uncatHtml = Build-HtmlDocument `
        -title        'HubSpot — Uncategorized Objects' `
        -objectList   $uncategorizedObjects `
        -diagramGroups @{} `
        -includeGlobal $false

    $uncatPath = Join-Path $outputDir 'hubspot-uncategorized-objects.html'
    $uncatHtml | Set-Content $uncatPath -Encoding UTF8
    Write-Host "Uncategorized document → $uncatPath ($($uncategorizedObjects.Count) objects)" -ForegroundColor Green
} else {
    Write-Host "No uncategorized objects — secondary document skipped." -ForegroundColor DarkGray
}
