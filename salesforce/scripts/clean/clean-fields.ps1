<#
.SYNOPSIS
    Cleans raw field metadata for each Salesforce SObject.

.DESCRIPTION
    Input:  data/raw/fields/<Object>.json     (one per object)
            data/raw/list-view-usage/<Object>.json  (optional)
    Output: data/clean/fields/<Object>.json

    Per field:
      - Maps Salesforce type to a simple type (string, int, decimal, guid, etc.)
      - Extracts required level (nillable: false → yes)
      - Joins list view usage count if available
      - Drops compound container fields (type: address, location)
      - Drops binary fields (type: base64)
      - Drops fields with no label
      - Drops deprecated/hidden fields
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/../gather/config.json"
)

$config    = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rawDir    = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.rawDir))
$cleanDir  = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.cleanDir))
$fieldsDir = Join-Path $cleanDir 'fields'
New-Item -ItemType Directory -Path $fieldsDir -Force | Out-Null

# ── Type map ──────────────────────────────────────────────────────────────────
$typeMap = @{
    'id'               = 'guid'
    'reference'        = 'guid'
    'string'           = 'string'
    'textarea'         = 'string'
    'email'            = 'string'
    'phone'            = 'string'
    'url'              = 'string'
    'encryptedstring'  = 'string'
    'combobox'         = 'string'
    'anyType'          = 'string'
    'int'              = 'int'
    'double'           = 'decimal'
    'currency'         = 'decimal'
    'percent'          = 'decimal'
    'boolean'          = 'bool'
    'date'             = 'datetime'
    'datetime'         = 'datetime'
    'time'             = 'datetime'
    'picklist'         = 'picklist'
    'multipicklist'    = 'picklist'
}

# Types that represent compound containers or binaries — drop the container, keep sub-fields
$skipTypes = [System.Collections.Generic.HashSet[string]]@(
    'address', 'location', 'base64'
)

# ── Object list from clean output ─────────────────────────────────────────────
$objectsFile = Join-Path $cleanDir 'objects.json'
if (-not (Test-Path $objectsFile)) {
    Write-Error "data/clean/objects.json not found. Run clean-objects.ps1 first."
    exit 1
}
$objectNames = (Get-Content $objectsFile -Raw | ConvertFrom-Json) |
               ForEach-Object { $_.apiName }

$total = $objectNames.Count; $current = 0

foreach ($apiName in $objectNames) {
    $current++
    $rawFile = Join-Path $rawDir "fields/$apiName.json"

    if (-not (Test-Path $rawFile)) {
        Write-Warning "[$current/$total] $apiName — raw fields file not found, skipping"
        continue
    }

    $raw = Get-Content $rawFile -Raw | ConvertFrom-Json

    # Load list-view usage counts if available
    $viewUsage = @{}
    $usageFile = Join-Path $rawDir "list-view-usage/$apiName.json"
    if (Test-Path $usageFile) {
        $vu = Get-Content $usageFile -Raw | ConvertFrom-Json
        $vu.fieldUsage.PSObject.Properties | ForEach-Object { $viewUsage[$_.Name] = [int]$_.Value }
    }

    $clean = $raw | Where-Object {
        # Drop compound container fields (sub-fields like BillingStreet are kept)
        $_.type -notin $skipTypes          -and
        # Drop binary types
        $_.type -ne 'base64'               -and
        # Drop fields with no label
        ($_.label ?? '').Trim()            -and
        # Drop deprecated/hidden fields
        -not $_.deprecatedAndHidden
    } | ForEach-Object {
        [PSCustomObject]@{
            apiName       = $_.name
            label         = ($_.label ?? '').Trim()
            type          = $typeMap[$_.type] ?? 'string'
            required      = if (-not $_.nillable -and $_.createable) { 'yes' } else { 'no' }
            isPrimaryId   = ($_.name -eq 'Id')
            isPrimaryName = [bool]$_.nameField
            isCustom      = [bool]$_.custom
            referenceTo   = $_.referenceTo ?? @()
            viewUsage     = $viewUsage[$_.name] ?? 0
        }
    }

    $outFile = Join-Path $fieldsDir "$apiName.json"
    $clean | ConvertTo-Json -Depth 5 | Set-Content $outFile -Encoding UTF8
    Write-Host "[$current/$total] $apiName — $($clean.Count) fields" -ForegroundColor Green
}

Write-Host "Fields cleaned → $fieldsDir" -ForegroundColor Green
