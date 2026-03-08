<#
.SYNOPSIS
    Cleans and consolidates raw operational-insights data into a single JSON file.

.DESCRIPTION
    Input:  data/raw/operational-insights/<objectName>.json  (per-object files)
            data/raw/operational-insights/_global.json       (portal-wide summary)
    Output: data/clean/operational-insights.json

    Cleaning steps:
      - Normalise all property names to camelCase
      - Compute derived metrics (null-name %)
      - Classify automation by active vs inactive
      - Sort objects by record count descending (nulls last)
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
        $labels[$o.name] = $o.label
    }
}

# ── Load global summary ──────────────────────────────────────────────────────
$globalFile = Join-Path $insightsDir '_global.json'
$globalRaw  = if (Test-Path $globalFile) {
    Get-Content $globalFile -Raw | ConvertFrom-Json
} else { $null }

# ── Process per-object files ──────────────────────────────────────────────────
$objectFiles  = Get-ChildItem $insightsDir -Filter '*.json' | Where-Object { $_.Name -ne '_global.json' }
$cleanEntries = [System.Collections.Generic.List[object]]::new()

foreach ($file in $objectFiles) {
    $raw        = Get-Content $file.FullName -Raw | ConvertFrom-Json
    $objectType = $raw.objectType
    $rowCount   = $raw.rowCount

    # Data quality — passthrough, normalise nulls
    $dq = $raw.dataQuality
    $dataQuality = if ($dq) {
        [ordered]@{
            primaryNameProperty = $dq.primaryNameProperty
            recordsWithNullName = $dq.recordsWithNullName
            nullNamePct         = $dq.nullNamePct
        }
    } else { $null }

    # Automation — normalise with active/inactive counts
    $auto = $raw.automation
    $automation = if ($auto) {
        [ordered]@{
            workflowTotal     = $auto.workflowTotal     ?? 0
            workflowsActive   = $auto.workflowsActive   ?? 0
            workflowsInactive = $auto.workflowsInactive ?? 0
            workflows         = @($auto.workflows)
        }
    } else {
        [ordered]@{
            workflowTotal = 0; workflowsActive = 0; workflowsInactive = 0; workflows = @()
        }
    }

    $cleanEntry = [ordered]@{
        objectType          = $objectType
        label               = $labels[$objectType] ?? ''
        rowCount            = $rowCount
        usageClassification = $raw.usageClassification
        activity            = $raw.activity
        dataQuality         = $dataQuality
        automation          = $automation
    }

    $cleanEntries.Add($cleanEntry)
}

# Sort by row count descending (nulls last)
$sorted = $cleanEntries | Sort-Object { if ($null -ne $_.rowCount) { -$_.rowCount } else { [int]::MaxValue } }

# ── Build output ──────────────────────────────────────────────────────────────
$output = [ordered]@{
    generatedAt  = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    objectCount  = $sorted.Count
    summary      = [ordered]@{
        activeObjects      = ($sorted | Where-Object { $_.usageClassification -eq 'active' }).Count
        lowActivityObjects = ($sorted | Where-Object { $_.usageClassification -eq 'low-activity' }).Count
        legacyObjects      = ($sorted | Where-Object { $_.usageClassification -eq 'legacy' }).Count
        emptyObjects       = ($sorted | Where-Object { $_.usageClassification -eq 'empty' }).Count
    }
    global       = if ($globalRaw) {
        [ordered]@{
            workflowCount        = $globalRaw.workflowCount
            workflowsByStatus    = $globalRaw.workflowsByStatus
        }
    } else { $null }
    objects      = @($sorted)
}

$outFile = Join-Path $cleanDir 'operational-insights.json'
$output | ConvertTo-Json -Depth 15 | Set-Content $outFile -Encoding UTF8
Write-Host "Cleaned $($sorted.Count) object insights → $outFile" -ForegroundColor Green

$active = $output.summary.activeObjects
$legacy = $output.summary.legacyObjects
$empty  = $output.summary.emptyObjects
Write-Host "  Active: $active | Low-activity: $($output.summary.lowActivityObjects) | Legacy: $legacy | Empty: $empty" -ForegroundColor DarkGray
