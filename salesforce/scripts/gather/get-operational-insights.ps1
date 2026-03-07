<#
.SYNOPSIS
    Gathers operational insights for each Salesforce object — row counts, activity,
    data quality signals, duplicate rates, and automation touchpoints.

.DESCRIPTION
    For every object in data/raw/objects.json this script collects:

      • Row counts and data volumes
      • Activity / freshness (records modified/created in recent windows)
      • Data quality (null primary name count)
      • Duplicate rates (records sharing the same Name value)
      • Automation touchpoints (ApexTriggers, ValidationRules per object)

    Depends on get-objects.ps1 and get-fields.ps1 having run first.

.OUTPUTS
    data/raw/operational-insights/<apiName>.json — one file per object
    data/raw/operational-insights/_global.json  — org-wide automation summary

.PARAMETER ConfigPath
    Path to config.json. Defaults to the config.json next to this script.

.PARAMETER Object
    Optional. Run for a single object API name only (e.g. 'My_Object__c').
    Useful for testing before running against all objects.

.PARAMETER Refresh
    Force re-fetch of all objects, even if output files already exist.
    Without this switch, objects with existing output files are skipped (resume mode).

.EXAMPLE
    .\get-operational-insights.ps1 -Object My_Object__c

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
    $objectDefs = $objectDefs | Where-Object { ($_.QualifiedApiName ?? $_.qualifiedApiName) -eq $Object }
    if ($objectDefs.Count -eq 0) {
        Write-Error "Object '$Object' not found in objects.json."
        exit 1
    }
    $objectDefs = @($objectDefs)
    Write-Host "Filtered to single object: $Object" -ForegroundColor Cyan
}

# When running standalone with -Object, clear any inherited token so Connect-Salesforce
# does a fresh interactive auth rather than reusing a potentially-expired token.
if ($Object -and $env:SF_TOKEN) {
    Write-Host "Clearing inherited token — will re-authenticate" -ForegroundColor DarkGray
    Remove-Item Env:SF_TOKEN        -ErrorAction SilentlyContinue
    Remove-Item Env:SF_INSTANCE_URL -ErrorAction SilentlyContinue
    Remove-Item Env:SF_API_VERSION  -ErrorAction SilentlyContinue
}

if (-not $Refresh) {
    $before = $objectDefs.Count
    $objectDefs = @($objectDefs | Where-Object {
        $name = $_.QualifiedApiName ?? $_.qualifiedApiName
        -not (Test-Path (Join-Path $outDir "$name.json"))
    })
    $skipped = $before - $objectDefs.Count
    Write-Host "Resume mode (default): skipping $skipped already-fetched objects, $($objectDefs.Count) remaining" -ForegroundColor Cyan
    if ($objectDefs.Count -eq 0) {
        Write-Host "All objects already fetched. Use -Refresh to force re-fetch." -ForegroundColor Green
        exit 0
    }
}

Connect-Salesforce -ConfigPath $ConfigPath

# ── Helper: safe SOQL COUNT query ────────────────────────────────────────────
function Invoke-SfCount {
    param([string]$Soql)
    try {
        $encoded = [System.Uri]::EscapeDataString($Soql)
        Write-Host "  [count] $Soql" -ForegroundColor DarkGray
        $resp = Invoke-SalesforceGet "query?q=$encoded"
        $n = $resp.totalSize
        Write-Host "  [count] → $n" -ForegroundColor DarkGray
        return $n
    } catch {
        Write-Host "  [count] FAILED: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# ── Helper: safe SOQL records query (no pagination, for small result sets) ───
function Invoke-SfQuery {
    param([string]$Soql)
    try {
        $encoded = [System.Uri]::EscapeDataString($Soql)
        Write-Host "  [query] $Soql" -ForegroundColor DarkGray
        $resp = Invoke-SalesforceGet "query?q=$encoded"
        $n = if ($resp.records) { $resp.records.Count } else { 0 }
        Write-Host "  [query] → $n results" -ForegroundColor DarkGray
        return $resp.records
    } catch {
        Write-Host "  [query] FAILED: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# ── Helper: safe Tooling API SOQL query ──────────────────────────────────────
function Invoke-SfTooling {
    param([string]$Soql)
    try {
        Write-Host "  [tooling] $Soql" -ForegroundColor DarkGray
        $records = Invoke-SalesforceToolingQuery $Soql
        $n = if ($records) { $records.Count } else { 0 }
        Write-Host "  [tooling] → $n results" -ForegroundColor DarkGray
        return $records
    } catch {
        Write-Host "  [tooling] FAILED: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# ── 1. Global automation summary (org-wide, run once) ───────────────────────
Write-Host "`n--- Global automation summary ---" -ForegroundColor Yellow

$globalInsights = [ordered]@{}

# All ApexTriggers — pre-fetch to build per-object lookup map
$allTriggers = Invoke-SfTooling "SELECT Id, Name, Status, TableEnumOrId FROM ApexTrigger LIMIT 5000"
$globalInsights['apexTriggerCount']    = if ($allTriggers) { $allTriggers.Count } else { 0 }
$globalInsights['apexTriggersByStatus'] = @{
    active   = ($allTriggers | Where-Object { $_.Status -eq 'Active' }).Count
    inactive = ($allTriggers | Where-Object { $_.Status -ne 'Active' }).Count
}

# All ValidationRules — pre-fetch to build per-object lookup map
$allValidationRules = Invoke-SfTooling "SELECT Id, ValidationName, Active, EntityDefinitionId FROM ValidationRule LIMIT 5000"
$globalInsights['validationRuleCount']   = if ($allValidationRules) { $allValidationRules.Count } else { 0 }
$globalInsights['validationRulesActive'] = ($allValidationRules | Where-Object { $_.Active -eq $true }).Count

$globalFile = Join-Path $outDir '_global.json'
$globalInsights | ConvertTo-Json -Depth 5 | Set-Content $globalFile -Encoding UTF8
Write-Host "Global automation summary → $globalFile" -ForegroundColor Green

# ── 2. Build per-object lookup maps from pre-fetched data ───────────────────
# ApexTrigger.TableEnumOrId is the 3-character entity key prefix (e.g. 'a01')
$triggersByKeyPrefix = @{}
if ($allTriggers) {
    foreach ($t in $allTriggers) {
        $kp = $t.TableEnumOrId
        if (-not $kp) { continue }
        if (-not $triggersByKeyPrefix[$kp]) {
            $triggersByKeyPrefix[$kp] = [System.Collections.Generic.List[object]]::new()
        }
        $triggersByKeyPrefix[$kp].Add($t)
    }
}

# ValidationRule.EntityDefinitionId matches EntityDefinition.DurableId
$validationByEntityDefId = @{}
if ($allValidationRules) {
    foreach ($vr in $allValidationRules) {
        $eid = $vr.EntityDefinitionId
        if (-not $eid) { continue }
        if (-not $validationByEntityDefId[$eid]) {
            $validationByEntityDefId[$eid] = [System.Collections.Generic.List[object]]::new()
        }
        $validationByEntityDefId[$eid].Add($vr)
    }
}

# ── 3. Per-object operational insights ───────────────────────────────────────
$total   = $objectDefs.Count
$current = 0

foreach ($objDef in $objectDefs) {
    $current++
    $apiName   = $objDef.QualifiedApiName ?? $objDef.qualifiedApiName
    $label     = $objDef.Label            ?? $objDef.label ?? $apiName
    $keyPrefix = $objDef.KeyPrefix        ?? $objDef.keyPrefix
    $durableId = $objDef.DurableId        ?? $objDef.durableId

    Write-Host "`n[$current/$total] $apiName (label=$label, keyPrefix=$keyPrefix)" -ForegroundColor Yellow

    $insight = [ordered]@{ apiName = $apiName }

    # ── Find primary name field from raw describe ─────────────────────────────
    $primaryNameField = $null
    $rawFieldsFile = Join-Path $rawDir "fields/$apiName.json"
    if (Test-Path $rawFieldsFile) {
        $rawFields = Get-Content $rawFieldsFile -Raw | ConvertFrom-Json
        $nf = $rawFields | Where-Object { $_.nameField -eq $true } | Select-Object -First 1
        $primaryNameField = if ($nf) { $nf.name } else { $null }
    }

    # ── Row count ─────────────────────────────────────────────────────────────
    Write-Host "  Fetching row count..." -ForegroundColor DarkCyan
    $totalCount = Invoke-SfCount "SELECT COUNT() FROM $apiName"
    $insight['rowCount'] = $totalCount
    Write-Host "  Total rows: $totalCount" -ForegroundColor Cyan

    # ── Activity / freshness ──────────────────────────────────────────────────
    Write-Host "  Fetching activity/freshness..." -ForegroundColor DarkCyan
    $modifiedLast30  = Invoke-SfCount "SELECT COUNT() FROM $apiName WHERE LastModifiedDate >= LAST_N_DAYS:30"
    $modifiedLast90  = Invoke-SfCount "SELECT COUNT() FROM $apiName WHERE LastModifiedDate >= LAST_N_DAYS:90"
    $modifiedLast365 = Invoke-SfCount "SELECT COUNT() FROM $apiName WHERE LastModifiedDate >= LAST_N_DAYS:365"
    $createdLast30   = Invoke-SfCount "SELECT COUNT() FROM $apiName WHERE CreatedDate >= LAST_N_DAYS:30"
    $createdLast90   = Invoke-SfCount "SELECT COUNT() FROM $apiName WHERE CreatedDate >= LAST_N_DAYS:90"

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
    if ($primaryNameField) {
        Write-Host "  Fetching data quality ($primaryNameField)..." -ForegroundColor DarkCyan
        $nullNameCount = Invoke-SfCount "SELECT COUNT() FROM $apiName WHERE $primaryNameField = null"
        $insight['dataQuality'] = [ordered]@{
            primaryNameField    = $primaryNameField
            recordsWithNullName = $nullNameCount
            nullNamePct         = if ($totalCount -and $totalCount -gt 0 -and $null -ne $nullNameCount) {
                [math]::Round($nullNameCount / $totalCount * 100, 1)
            } else { $null }
        }
    }

    # ── Duplicate detection: records sharing primary name ─────────────────────
    Write-Host "  Fetching duplicate detection..." -ForegroundColor DarkCyan
    if ($primaryNameField -and $totalCount -and $totalCount -gt 0 -and $totalCount -le 500000) {
        try {
            $dupSoql = "SELECT $primaryNameField, COUNT(Id) cnt FROM $apiName WHERE $primaryNameField != null GROUP BY $primaryNameField HAVING COUNT(Id) > 1 ORDER BY cnt DESC LIMIT 20"
            $dupRecords = Invoke-SfQuery $dupSoql
            $duplicateNames = if ($dupRecords) {
                @($dupRecords | ForEach-Object {
                    [ordered]@{
                        name  = $_.$primaryNameField
                        count = [int]$_.cnt
                    }
                })
            } else { @() }
            $insight['duplicates'] = [ordered]@{
                topRepeatedNames = @($duplicateNames)
                distinctDupNames = $duplicateNames.Count
            }
        } catch {
            $insight['duplicates'] = [ordered]@{ error = $_.Exception.Message }
        }
    }

    # ── Transformations: ApexTriggers and ValidationRules ────────────────────
    Write-Host "  Collecting automations..." -ForegroundColor DarkCyan

    $objTriggers = if ($keyPrefix -and $triggersByKeyPrefix[$keyPrefix]) {
        @($triggersByKeyPrefix[$keyPrefix])
    } else { @() }

    # Look up validation rules by DurableId (EntityDefinitionId in ValidationRule)
    $objValidationRules = if ($durableId -and $validationByEntityDefId.ContainsKey($durableId)) {
        @($validationByEntityDefId[$durableId])
    } elseif ($durableId) {
        @()
    } else {
        # Fallback: per-object Tooling query (slower, avoids DurableId issues)
        $vr = Invoke-SfTooling "SELECT Id, ValidationName, Active FROM ValidationRule WHERE EntityDefinition.QualifiedApiName = '$apiName' LIMIT 200"
        if ($vr) { @($vr) } else { @() }
    }

    Write-Host "  Triggers: $($objTriggers.Count), Validation Rules: $($objValidationRules.Count)" -ForegroundColor DarkGray

    $insight['transformations'] = [ordered]@{
        triggerTotal          = $objTriggers.Count
        triggersActive        = ($objTriggers | Where-Object { $_.Status -eq 'Active' }).Count
        triggersInactive      = ($objTriggers | Where-Object { $_.Status -ne 'Active' }).Count
        triggers              = @($objTriggers | ForEach-Object {
            [ordered]@{
                name   = $_.Name
                status = $_.Status
                active = ($_.Status -eq 'Active')
            }
        })
        validationRuleTotal   = $objValidationRules.Count
        validationRulesActive = ($objValidationRules | Where-Object { $_.Active -eq $true }).Count
        validationRules       = @($objValidationRules | ForEach-Object {
            [ordered]@{
                name   = $_.ValidationName
                active = [bool]$_.Active
            }
        })
    }

    # ── Write per-object file ─────────────────────────────────────────────────
    $outFile = Join-Path $outDir "$apiName.json"
    $insight | ConvertTo-Json -Depth 10 | Set-Content $outFile -Encoding UTF8

    $status = $insight['usageClassification']
    $rc = if ($null -ne $totalCount) { $totalCount } else { '?' }
    Write-Host "  ✓ $apiName — rows=$rc status=$status" -ForegroundColor Green
}

Write-Host "`nOperational insights saved → $outDir" -ForegroundColor Green
