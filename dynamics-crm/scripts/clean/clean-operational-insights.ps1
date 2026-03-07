<#
.SYNOPSIS
    Cleans and consolidates raw operational-insights data into a single JSON file.

.DESCRIPTION
    Input:  data/raw/operational-insights/<entity>.json  (per-entity files)
            data/raw/operational-insights/_global.json   (org-wide summary)
    Output: data/clean/operational-insights.json

    Cleaning steps:
      - Normalise all property names to camelCase
      - Compute derived metrics (active %, inactive %, null-name %)
      - Replace error entries with null (e.g. failed duplicate detection)
      - Drop system/internal plugin steps (keep only custom/business-relevant)
      - Classify workflows by active vs inactive
      - Compute relationship fill-rate summaries per entity
      - Cap row counts at API page limit (5000) with an isCapped flag
      - Sort entities by row count descending
      - Embed the global summary at the top level
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

$insightsDir = Join-Path $rawDir 'operational-insights'
if (-not (Test-Path $insightsDir)) {
    Write-Error "operational-insights/ not found at $insightsDir. Run the gather stage first."
    exit 1
}

# ── Load clean entity list for display-name lookup ───────────────────────────
$cleanEntitiesFile = Join-Path $cleanDir 'entities.json'
$displayNames = @{}
if (Test-Path $cleanEntitiesFile) {
    $cleanEntities = Get-Content $cleanEntitiesFile -Raw | ConvertFrom-Json
    foreach ($e in $cleanEntities) {
        $displayNames[$e.logicalName] = $e.displayName
    }
}

# ── Load global summary ─────────────────────────────────────────────────────
$globalFile = Join-Path $insightsDir '_global.json'
$globalRaw = if (Test-Path $globalFile) {
    Get-Content $globalFile -Raw | ConvertFrom-Json
} else { $null }

# ── Known system/internal plugin prefixes to filter out ──────────────────────
$systemPluginPrefixes = @(
    'Microsoft.Crm.'
    'ActivityFeeds.'
    'ClassificationOnEntityEvent'
    'Microsoft.Dynamics.'
)

function Test-SystemPlugin([string]$name) {
    foreach ($prefix in $systemPluginPrefixes) {
        if ($name.StartsWith($prefix)) { return $true }
    }
    return $false
}

# ── Process per-entity files ─────────────────────────────────────────────────
$entityFiles = Get-ChildItem $insightsDir -Filter '*.json' | Where-Object { $_.Name -ne '_global.json' }
$cleanEntries = [System.Collections.Generic.List[object]]::new()

foreach ($file in $entityFiles) {
    $raw = Get-Content $file.FullName -Raw | ConvertFrom-Json
    $entity = $raw.entity
    $rowCount = $raw.rowCount

    # Detect if row count was capped at the API page limit
    $isCapped = ($null -ne $rowCount -and $rowCount -eq 5000)

    # Active/inactive percentages
    $active   = $raw.statecodeBreakdown.active
    $inactive = $raw.statecodeBreakdown.inactive
    $activePct  = $null
    $inactivePct = $null
    if ($null -ne $active -and $null -ne $inactive) {
        $total = $active + $inactive
        if ($total -gt 0) {
            $activePct   = [math]::Round($active / $total * 100, 1)
            $inactivePct = [math]::Round($inactive / $total * 100, 1)
        }
    }

    # Data quality — clean up nulls
    $dq = $raw.dataQuality
    $dataQuality = if ($dq) {
        [ordered]@{
            primaryNameAttribute = $dq.primaryNameAttribute
            recordsWithNullName  = $dq.recordsWithNullName
            nullNamePct          = $dq.nullNamePct
        }
    } else { $null }

    # Duplicates — if there was an error, report it cleanly
    $dups = $raw.duplicates
    $duplicates = if ($dups -and $dups.error) {
        [ordered]@{ status = 'failed'; error = $dups.error }
    } elseif ($dups) {
        [ordered]@{
            status           = 'ok'
            distinctDupNames = $dups.distinctDupNames
            topRepeatedNames = $dups.topRepeatedNames
        }
    } else { $null }

    # Relationship cardinalities — passthrough, already clean
    $relationships = @($raw.relationshipCardinalities | ForEach-Object {
        [ordered]@{
            relationship     = $_.relationship
            referencedEntity = $_.referencedEntity
            lookupAttribute  = $_.lookupAttribute
            recordsWithValue = $_.recordsWithValue
            recordsNull      = $_.recordsNull
            fillRate         = $_.fillRate
        }
    })

    # Transformations — split into custom vs system, count active/inactive
    $plugins       = @($raw.transformations.pluginSteps)
    $customPlugins = @($plugins | Where-Object { $_ -and -not (Test-SystemPlugin $_.name) })
    $systemPlugins = @($plugins | Where-Object { $_ -and (Test-SystemPlugin $_.name) })
    $workflows     = @($raw.transformations.workflows)

    $transformations = [ordered]@{
        pluginStepTotal   = $plugins.Count
        pluginStepCustom  = $customPlugins.Count
        pluginStepSystem  = $systemPlugins.Count
        customPluginSteps = @($customPlugins | ForEach-Object {
            [ordered]@{
                name   = $_.name
                stage  = switch ($_.stage) { 10 { 'PreValidation' }; 20 { 'PreOperation' }; 40 { 'PostOperation' }; default { $_.stage } }
                mode   = switch ($_.mode)  { 0 { 'Sync' }; 1 { 'Async' }; default { $_.mode } }
                active = ($_.statecode -eq 0)
            }
        })
        workflowTotal     = $workflows.Count
        workflowsActive   = ($workflows | Where-Object { $_.statecode -eq 0 }).Count
        workflowsInactive = ($workflows | Where-Object { $_.statecode -ne 0 }).Count
        workflowsByCategory = @{}
        workflows = @($workflows | ForEach-Object {
            [ordered]@{
                name     = $_.name
                category = $_.category
                active   = ($_.statecode -eq 0)
            }
        })
    }

    # Count workflows by category
    foreach ($wf in $workflows) {
        $cat = $wf.category ?? 'Unknown'
        $transformations.workflowsByCategory[$cat] = ($transformations.workflowsByCategory[$cat] ?? 0) + 1
    }

    # Integration signals
    $integ = $raw.integrationSignals
    $integrationSignals = [ordered]@{
        asyncOperationsFailed    = $integ.asyncOperationsFailed
        asyncOperationsSucceeded = $integ.asyncOperationsSucceeded
    }

    $cleanEntry = [ordered]@{
        entity               = $entity
        displayName          = $displayNames[$entity] ?? ''
        rowCount             = $rowCount
        rowCountCapped       = $isCapped
        usageClassification  = $raw.usageClassification
        statecodeBreakdown   = [ordered]@{
            active       = $active
            inactive     = $inactive
            activePct    = $activePct
            inactivePct  = $inactivePct
        }
        activity             = $raw.activity
        dataQuality          = $dataQuality
        duplicates           = $duplicates
        relationshipFillRates = $relationships
        transformations      = $transformations
        integrationSignals   = $integrationSignals
    }

    $cleanEntries.Add($cleanEntry)
}

# Sort by row count descending (nulls last)
$sorted = $cleanEntries | Sort-Object { if ($null -ne $_.rowCount) { -$_.rowCount } else { [int]::MaxValue } }

# ── Build output ─────────────────────────────────────────────────────────────
$output = [ordered]@{
    generatedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    entityCount = $sorted.Count
    summary     = [ordered]@{
        activeEntities      = ($sorted | Where-Object { $_.usageClassification -eq 'active' }).Count
        lowActivityEntities = ($sorted | Where-Object { $_.usageClassification -eq 'low-activity' }).Count
        legacyEntities      = ($sorted | Where-Object { $_.usageClassification -eq 'legacy' }).Count
        emptyEntities       = ($sorted | Where-Object { $_.usageClassification -eq 'empty' }).Count
    }
    global      = if ($globalRaw) {
        [ordered]@{
            pluginStepCount    = $globalRaw.pluginStepCount
            pluginStepsByState = $globalRaw.pluginStepsByState
            workflowCount      = $globalRaw.workflowCount
            workflowsByCategory = $globalRaw.workflowsByCategory
            dataSyncProfileCount = $globalRaw.dataSyncProfileCount
            connectionRoleCount  = $globalRaw.connectionRoleCount
        }
    } else { $null }
    entities    = @($sorted)
}

$outFile = Join-Path $cleanDir 'operational-insights.json'
$output | ConvertTo-Json -Depth 15 | Set-Content $outFile -Encoding UTF8
Write-Host "Cleaned $($sorted.Count) entity insights → $outFile" -ForegroundColor Green

# Quick stats
$active = $output.summary.activeEntities
$legacy = $output.summary.legacyEntities
$empty  = $output.summary.emptyEntities
Write-Host "  Active: $active | Low-activity: $($output.summary.lowActivityEntities) | Legacy: $legacy | Empty: $empty" -ForegroundColor DarkGray
