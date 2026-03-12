<#
.SYNOPSIS
    Cleans and consolidates raw operational-insights data into a single JSON file.

.DESCRIPTION
    Input:  data/raw/operational-insights/<apiName>.json  (per-object files)
            data/raw/operational-insights/_global.json   (org-wide summary)
    Output: data/clean/operational-insights.json

    Cleaning steps:
      - Normalise all property names to camelCase
      - Compute derived metrics (null-name %)
      - Replace error entries with null (e.g. failed duplicate detection)
      - Classify automation by active vs inactive
      - Sort objects by row count descending (nulls last)
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

# ── Load clean object list for label lookup ───────────────────────────────────
$cleanObjectsFile = Join-Path $cleanDir 'objects.json'
$labels = @{}
if (Test-Path $cleanObjectsFile) {
    $cleanObjects = Get-Content $cleanObjectsFile -Raw | ConvertFrom-Json
    foreach ($o in $cleanObjects) {
        $labels[$o.apiName] = $o.label
    }
}

# ── Load global summary ──────────────────────────────────────────────────────
$globalFile = Join-Path $insightsDir '_global.json'
$globalRaw = if (Test-Path $globalFile) {
    Get-Content $globalFile -Raw | ConvertFrom-Json
} else { $null }

# ── Process per-object files ──────────────────────────────────────────────────
$objectFiles  = Get-ChildItem $insightsDir -Filter '*.json' | Where-Object { $_.Name -ne '_global.json' }
$cleanEntries = [System.Collections.Generic.List[object]]::new()

foreach ($file in $objectFiles) {
    $raw      = Get-Content $file.FullName -Raw | ConvertFrom-Json
    $apiName  = $raw.apiName
    $rowCount = $raw.rowCount

    # Data quality — passthrough, normalise nulls
    $dq = $raw.dataQuality
    $dataQuality = if ($dq) {
        [ordered]@{
            primaryNameField    = $dq.primaryNameField
            recordsWithNullName = $dq.recordsWithNullName
            nullNamePct         = $dq.nullNamePct
        }
    } else { $null }

    # Duplicates — if there was an error, report cleanly
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

    # Transformations — passthrough with active/inactive counts
    $tx = $raw.transformations
    $transformations = if ($tx) {
        [ordered]@{
            triggerTotal          = $tx.triggerTotal          ?? 0
            triggersActive        = $tx.triggersActive        ?? 0
            triggersInactive      = $tx.triggersInactive      ?? 0
            triggers              = @($tx.triggers)
            validationRuleTotal   = $tx.validationRuleTotal   ?? 0
            validationRulesActive = $tx.validationRulesActive ?? 0
            validationRules       = @($tx.validationRules)
        }
    } else {
        [ordered]@{
            triggerTotal = 0; triggersActive = 0; triggersInactive = 0; triggers = @()
            validationRuleTotal = 0; validationRulesActive = 0; validationRules = @()
        }
    }

    $cleanEntry = [ordered]@{
        apiName             = $apiName
        label               = $labels[$apiName] ?? ''
        rowCount            = $rowCount
        usageClassification = $raw.usageClassification
        activity            = $raw.activity
        dataQuality         = $dataQuality
        duplicates          = $duplicates
        transformations     = $transformations
    }

    $cleanEntries.Add($cleanEntry)
}

# Sort by row count descending (nulls last)
$sorted = $cleanEntries | Sort-Object { if ($null -ne $_.rowCount) { -$_.rowCount } else { [int]::MaxValue } }

# ── Build output ──────────────────────────────────────────────────────────────
$output = [ordered]@{
    generatedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    objectCount = $sorted.Count
    summary     = [ordered]@{
        activeObjects      = ($sorted | Where-Object { $_.usageClassification -eq 'active' }).Count
        lowActivityObjects = ($sorted | Where-Object { $_.usageClassification -eq 'low-activity' }).Count
        legacyObjects      = ($sorted | Where-Object { $_.usageClassification -eq 'legacy' }).Count
        emptyObjects       = ($sorted | Where-Object { $_.usageClassification -eq 'empty' }).Count
    }
    global      = if ($globalRaw) {
        [ordered]@{
            apexTriggerCount     = $globalRaw.apexTriggerCount
            apexTriggersByStatus = $globalRaw.apexTriggersByStatus
            validationRuleCount  = $globalRaw.validationRuleCount
            validationRulesActive = $globalRaw.validationRulesActive
        }
    } else { $null }
    objects     = @($sorted)
}

$outFile = Join-Path $cleanDir 'operational-insights.json'
$output | ConvertTo-Json -Depth 15 | Set-Content $outFile -Encoding UTF8
Write-Host "Cleaned $($sorted.Count) object insights → $outFile" -ForegroundColor Green

$active = $output.summary.activeObjects
$legacy = $output.summary.legacyObjects
$empty  = $output.summary.emptyObjects
Write-Host "  Active: $active | Low-activity: $($output.summary.lowActivityObjects) | Legacy: $legacy | Empty: $empty" -ForegroundColor DarkGray
