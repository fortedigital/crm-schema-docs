<#
.SYNOPSIS
    Cleans raw attribute metadata for each entity.

.DESCRIPTION
    Input:  data/raw/attributes/<entity>.json  (one per entity)
    Output: data/clean/attributes/<entity>.json

    Per attribute:
      - Extracts display name from Dataverse Label object
      - Maps AttributeTypeName to a simple type (string, int, decimal, guid, etc.)
      - Extracts required level (yes / no)
      - Classifies source type (simple / calculated / rollup)
      - Detects lookup fields and extracts target entities
      - Extracts option set values for picklist fields
      - Joins view usage count from data/raw/view-usage/<entity>.json if present
      - Drops virtual shadow attributes (AttributeOf != null)
      - Drops binary / internal types (Image, File, Virtual, CalendarRules)
      - Drops attributes with no display name (system internals)
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/../gather/config.json"
)

$config   = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rawDir   = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.rawDir))
$cleanDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.cleanDir))
$attrDir  = Join-Path $cleanDir 'attributes'
New-Item -ItemType Directory -Path $attrDir -Force | Out-Null

# ── Helpers ───────────────────────────────────────────────────────────────────
function Get-Label($obj) {
    if ($null -eq $obj) { return '' }
    $label = $obj.UserLocalizedLabel?.Label
    if (-not $label) { $label = ($obj.LocalizedLabels | Select-Object -First 1)?.Label }
    return ($label ?? '').Trim()
}

function Format-OptionSetOptions($options) {
    if (-not $options -or $options.Count -eq 0) { return '' }
    $pairs = foreach ($opt in $options) {
        $label = Get-Label $opt.Label
        if ($label) { "$($opt.Value):$label" }
    }
    return ($pairs -join '; ')
}

function Get-SourceTypeLabel($sourceType) {
    switch ($sourceType) {
        1       { 'calculated' }
        2       { 'rollup' }
        default { 'simple' }
    }
}

$typeMap = @{
    StringType              = 'string'
    MemoType                = 'string'
    EntityNameType          = 'string'
    IntegerType             = 'int'
    BigIntType              = 'int'
    DecimalType             = 'decimal'
    MoneyType               = 'decimal'
    DoubleType              = 'decimal'
    BooleanType             = 'bool'
    DateTimeType            = 'datetime'
    UniqueidentifierType    = 'guid'
    LookupType              = 'guid'
    CustomerType            = 'guid'
    OwnerType               = 'guid'
    PartyListType           = 'guid'
    StateType               = 'picklist'
    StatusType              = 'picklist'
    PicklistType            = 'picklist'
    MultiSelectPicklistType = 'picklist'
}

$skipTypes = [System.Collections.Generic.HashSet[string]]@(
    'ImageType', 'FileType', 'VirtualType', 'CalendarRulesType', 'ManagedPropertyType'
)

# ── Entity list from gather output ───────────────────────────────────────────
$entitiesFile = Join-Path $rawDir 'entities.json'
if (-not (Test-Path $entitiesFile)) {
    Write-Error "entities.json not found at $entitiesFile. Run the gather stage first."
    exit 1
}
$entityNames = (Get-Content $entitiesFile -Raw | ConvertFrom-Json) |
               ForEach-Object { $_.LogicalName ?? $_.logicalName }

# ── Process each entity ───────────────────────────────────────────────────────
$total = $entityNames.Count; $current = 0

foreach ($entity in $entityNames) {
    $current++
    $rawFile = Join-Path $rawDir "attributes/$entity.json"

    if (-not (Test-Path $rawFile)) {
        Write-Warning "[$current/$total] $entity — raw file not found, skipping"
        continue
    }

    $raw = Get-Content $rawFile -Raw | ConvertFrom-Json

    # Load view-usage counts if available (produced by get-view-usage.ps1)
    $viewUsage = @{}
    $viewUsageFile = Join-Path $rawDir "view-usage/$entity.json"
    if (Test-Path $viewUsageFile) {
        $vu = Get-Content $viewUsageFile -Raw | ConvertFrom-Json
        # fieldUsage is a JSON object — convert to hashtable
        $vu.fieldUsage.PSObject.Properties | ForEach-Object { $viewUsage[$_.Name] = [int]$_.Value }
    }

    $clean = $raw | Where-Object {
        # Drop virtual shadow attributes (e.g. _parentcustomerid_value)
        -not $_.AttributeOf                                    -and
        # Drop binary / unrenderable types
        $_.AttributeTypeName.Value -notin $skipTypes           -and
        # Drop attributes with no display name
        (Get-Label $_.DisplayName)
    } | ForEach-Object {
        $typeName = $_.AttributeTypeName?.Value ?? $_.AttributeType
        $simpleType = $typeMap[$typeName] ?? 'string'
        $isLookup = $typeName -in @('LookupType', 'CustomerType', 'OwnerType', 'PartyListType')

        [PSCustomObject]@{
            logicalName    = $_.LogicalName
            displayName    = Get-Label $_.DisplayName
            type           = $simpleType
            required       = if ($_.RequiredLevel.Value -in @('SystemRequired', 'ApplicationRequired')) { 'yes' } else { 'no' }
            sourceType     = Get-SourceTypeLabel $_.SourceType
            isLookup       = $isLookup
            lookupTargets  = if ($isLookup -and $_._LookupTargets) { ($_._LookupTargets -join ', ') } else { '' }
            optionValues   = if ($_._OptionSetOptions) { Format-OptionSetOptions $_._OptionSetOptions } else { '' }
            isPrimaryId    = [bool]$_.IsPrimaryId
            isPrimaryName  = [bool]$_.IsPrimaryName
            isCustom       = [bool]$_.IsCustomAttribute
            viewUsage      = $viewUsage[$_.LogicalName] ?? 0
        }
    }

    $outFile = Join-Path $attrDir "$entity.json"
    $clean | ConvertTo-Json -Depth 5 | Set-Content $outFile -Encoding UTF8
    Write-Host "[$current/$total] $entity — $($clean.Count) attributes" -ForegroundColor Green
}

Write-Host "Attributes cleaned → $attrDir" -ForegroundColor Green
