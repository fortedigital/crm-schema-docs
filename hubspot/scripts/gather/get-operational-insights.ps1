<#
.SYNOPSIS
    Gathers operational insights for each HubSpot object — record counts,
    activity, data quality signals, and automation (workflow) touchpoints.

.DESCRIPTION
    For every object in data/raw/objects.json this script collects:

      - Record counts and data volumes
      - Activity / freshness (records modified/created in recent windows)
      - Data quality (null primary name count)
      - Automation touchpoints (workflows per object type)

    Depends on get-objects.ps1 having run first.

.OUTPUTS
    data/raw/operational-insights/<objectName>.json — one file per object
    data/raw/operational-insights/_global.json     — portal-wide automation summary

.PARAMETER ConfigPath
    Path to config.json. Defaults to the config.json next to this script.

.PARAMETER Object
    Optional. Run for a single object name only (e.g. 'deals').
    Useful for testing before running against all objects.

.PARAMETER Refresh
    Force re-fetch of all objects, even if output files already exist.
    Without this switch, objects with existing output files are skipped (resume mode).

.EXAMPLE
    .\get-operational-insights.ps1 -Object deals

.EXAMPLE
    .\get-operational-insights.ps1 -Refresh
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/config.json",
    [string]$Object,
    [switch]$Refresh
)

. "$PSScriptRoot/connect.ps1"

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rawDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.rawDir))
$outDir = Join-Path $rawDir 'operational-insights'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

# ── Load object definitions ──────────────────────────────────────────────────
$objectsFile = Join-Path $rawDir 'objects.json'
if (-not (Test-Path $objectsFile)) {
    Write-Error "objects.json not found at $objectsFile. Run get-objects.ps1 first."
    exit 1
}
$objectDefs = Get-Content $objectsFile -Raw | ConvertFrom-Json

if ($Object) {
    $objectDefs = $objectDefs | Where-Object { $_.name -eq $Object }
    if ($objectDefs.Count -eq 0) {
        Write-Error "Object '$Object' not found in objects.json."
        exit 1
    }
    $objectDefs = @($objectDefs)
    Write-Host "Filtered to single object: $Object" -ForegroundColor Cyan
}

# When running standalone with -Object, clear any inherited token so Connect-HubSpot
# re-reads config rather than reusing a potentially-stale token.
if ($Object -and $env:HUBSPOT_TOKEN) {
    Write-Host "Clearing inherited token — will re-read config" -ForegroundColor DarkGray
    Remove-Item Env:HUBSPOT_TOKEN     -ErrorAction SilentlyContinue
    Remove-Item Env:HUBSPOT_PORTAL_ID -ErrorAction SilentlyContinue
}

if (-not $Refresh) {
    $before     = $objectDefs.Count
    $objectDefs = @($objectDefs | Where-Object {
        -not (Test-Path (Join-Path $outDir "$($_.name).json"))
    })
    $skipped = $before - $objectDefs.Count
    Write-Host "Resume mode: skipping $skipped already-fetched objects, $($objectDefs.Count) remaining" -ForegroundColor Cyan
    if ($objectDefs.Count -eq 0) {
        Write-Host "All objects already fetched. Use -Refresh to force re-fetch." -ForegroundColor Green
        exit 0
    }
}

Connect-HubSpot -ConfigPath $ConfigPath

# ── Helper: safe CRM count query ──────────────────────────────────────────────
function Invoke-HsCount {
    param(
        [string]$ObjectType,
        $FilterGroups = @()
    )
    try {
        $resp = Invoke-HubSpotSearch -ObjectType $ObjectType -FilterGroups $FilterGroups -Limit 1
        $n = $resp.total
        Write-Host "  [count] $ObjectType filters=$($FilterGroups.Count) → $n" -ForegroundColor DarkGray
        return $n
    } catch {
        Write-Host "  [count] FAILED: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# ── Helper: epoch ms timestamp ────────────────────────────────────────────────
function Get-EpochMs([int]$DaysAgo) {
    return [DateTimeOffset]::UtcNow.AddDays(-$DaysAgo).ToUnixTimeMilliseconds().ToString()
}

# ── Helper: date range filter group ───────────────────────────────────────────
function New-DateFilter([string]$Property, [string]$EpochMs) {
    return @{
        filters = @(@{
            propertyName = $Property
            operator     = 'GTE'
            value        = $EpochMs
        })
    }
}

# ── 1. Global automation summary (portal-wide, run once) ─────────────────────
Write-Host "`n--- Global automation summary ---" -ForegroundColor Yellow

$globalInsights = [ordered]@{}

try {
    $allFlows = Invoke-HubSpotGetPaged '/automation/v4/flows' -ResultsProperty 'results' -PageSize 100
    $globalInsights['workflowCount'] = $allFlows.Count
    $globalInsights['workflowsByStatus'] = @{
        active   = ($allFlows | Where-Object { $_.enabled -eq $true }).Count
        inactive = ($allFlows | Where-Object { $_.enabled -ne $true }).Count
    }
    Write-Host "  Workflows: $($allFlows.Count) total ($($globalInsights.workflowsByStatus.active) active)" -ForegroundColor DarkGray
} catch {
    Write-Warning "Could not fetch automation flows: $_"
    $allFlows = @()
    $globalInsights['workflowCount'] = $null
    $globalInsights['workflowsByStatus'] = @{ active = 0; inactive = 0 }
}

$globalFile = Join-Path $outDir '_global.json'
$globalInsights | ConvertTo-Json -Depth 5 | Set-Content $globalFile -Encoding UTF8
Write-Host "Global automation summary → $globalFile" -ForegroundColor Green

# ── 2. Build per-object workflow lookup map ───────────────────────────────────
$flowsByObjectTypeId = @{}
foreach ($flow in $allFlows) {
    $oid = $flow.objectTypeId
    if (-not $oid) { continue }
    if (-not $flowsByObjectTypeId[$oid]) {
        $flowsByObjectTypeId[$oid] = [System.Collections.Generic.List[object]]::new()
    }
    $flowsByObjectTypeId[$oid].Add($flow)
}

# ── 3. Per-object operational insights ───────────────────────────────────────
$total   = $objectDefs.Count
$current = 0

foreach ($objDef in $objectDefs) {
    $current++
    $objectType         = $objDef.name
    $label              = $objDef.label
    $objectTypeId       = $objDef.objectTypeId
    $primaryNameProp    = $objDef.primaryNameProperty

    Write-Host "`n[$current/$total] $objectType (label=$label, typeId=$objectTypeId)" -ForegroundColor Yellow

    $insight = [ordered]@{ objectType = $objectType }

    # ── Row count ─────────────────────────────────────────────────────────────
    Write-Host "  Fetching row count..." -ForegroundColor DarkCyan
    $totalCount = Invoke-HsCount -ObjectType $objectType
    $insight['rowCount'] = $totalCount
    Write-Host "  Total records: $totalCount" -ForegroundColor Cyan

    # ── Activity / freshness ──────────────────────────────────────────────────
    Write-Host "  Fetching activity/freshness..." -ForegroundColor DarkCyan

    $modifiedLast30  = Invoke-HsCount -ObjectType $objectType -FilterGroups @(New-DateFilter 'hs_lastmodifieddate' (Get-EpochMs 30))
    $modifiedLast90  = Invoke-HsCount -ObjectType $objectType -FilterGroups @(New-DateFilter 'hs_lastmodifieddate' (Get-EpochMs 90))
    $modifiedLast365 = Invoke-HsCount -ObjectType $objectType -FilterGroups @(New-DateFilter 'hs_lastmodifieddate' (Get-EpochMs 365))
    $createdLast30   = Invoke-HsCount -ObjectType $objectType -FilterGroups @(New-DateFilter 'hs_createdate' (Get-EpochMs 30))
    $createdLast90   = Invoke-HsCount -ObjectType $objectType -FilterGroups @(New-DateFilter 'hs_createdate' (Get-EpochMs 90))

    $insight['activity'] = [ordered]@{
        modifiedLast30Days  = $modifiedLast30
        modifiedLast90Days  = $modifiedLast90
        modifiedLast365Days = $modifiedLast365
        createdLast30Days   = $createdLast30
        createdLast90Days   = $createdLast90
    }

    # Usage classification
    $insight['usageClassification'] = if ($null -eq $totalCount -or $totalCount -eq 0) {
        'empty'
    } elseif ($null -ne $modifiedLast90 -and $modifiedLast90 -gt 0) {
        'active'
    } elseif ($null -ne $modifiedLast365 -and $modifiedLast365 -gt 0) {
        'low-activity'
    } else {
        'legacy'
    }

    # ── Data quality: null primary name ───────────────────────────────────────
    if ($primaryNameProp -and $totalCount -and $totalCount -gt 0) {
        Write-Host "  Fetching data quality ($primaryNameProp)..." -ForegroundColor DarkCyan
        try {
            $nullFilter = @{
                filters = @(@{
                    propertyName = $primaryNameProp
                    operator     = 'NOT_HAS_PROPERTY'
                })
            }
            $nullCount = Invoke-HsCount -ObjectType $objectType -FilterGroups @($nullFilter)
            $insight['dataQuality'] = [ordered]@{
                primaryNameProperty = $primaryNameProp
                recordsWithNullName = $nullCount
                nullNamePct         = if ($totalCount -and $totalCount -gt 0 -and $null -ne $nullCount) {
                    [math]::Round($nullCount / $totalCount * 100, 1)
                } else { $null }
            }
        } catch {
            Write-Warning "  Data quality check failed for $primaryNameProp: $_"
        }
    }

    # ── Automation: workflows per object type ─────────────────────────────────
    Write-Host "  Collecting automations..." -ForegroundColor DarkCyan

    $objFlows = if ($objectTypeId -and $flowsByObjectTypeId[$objectTypeId]) {
        @($flowsByObjectTypeId[$objectTypeId])
    } else { @() }

    Write-Host "  Workflows: $($objFlows.Count)" -ForegroundColor DarkGray

    $insight['automation'] = [ordered]@{
        workflowTotal    = $objFlows.Count
        workflowsActive  = ($objFlows | Where-Object { $_.enabled -eq $true }).Count
        workflowsInactive = ($objFlows | Where-Object { $_.enabled -ne $true }).Count
        workflows        = @($objFlows | ForEach-Object {
            [ordered]@{
                id      = $_.id
                name    = $_.name
                enabled = [bool]$_.enabled
            }
        })
    }

    # ── Write per-object file ─────────────────────────────────────────────────
    $outFile = Join-Path $outDir "$objectType.json"
    $insight | ConvertTo-Json -Depth 10 | Set-Content $outFile -Encoding UTF8

    $status = $insight['usageClassification']
    $rc     = if ($null -ne $totalCount) { $totalCount } else { '?' }
    Write-Host "  ✓ $objectType — records=$rc status=$status" -ForegroundColor Green
}

Write-Host "`nOperational insights saved → $outDir" -ForegroundColor Green
