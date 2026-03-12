<#
.SYNOPSIS
    Cleans raw property metadata for each HubSpot object.

.DESCRIPTION
    Input:  data/raw/fields/<objectName>.json  (one per object)
    Output: data/clean/fields/<objectName>.json

    Per property:
      - Maps HubSpot type to a simple type (string, int, decimal, bool, picklist, datetime)
      - Marks required if the property has hasUniqueValue: true (strong identifier)
      - Flags is_custom: true if hubspotDefined: false
      - Drops hidden, archived, and internal properties
      - Drops binary/coordinate types (object_coordinates, json)
      - Drops properties with no label
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
    'string'           = 'string'
    'phone_number'     = 'string'
    'number'           = 'decimal'
    'bool'             = 'bool'
    'date'             = 'datetime'
    'datetime'         = 'datetime'
    'enumeration'      = 'picklist'
}

# Types to skip entirely (internal/binary)
$skipTypes = [System.Collections.Generic.HashSet[string]]@(
    'object_coordinates', 'json'
)

# ── Object list from clean output ─────────────────────────────────────────────
$objectsFile = Join-Path $cleanDir 'objects.json'
if (-not (Test-Path $objectsFile)) {
    Write-Error "data/clean/objects.json not found. Run clean-objects.ps1 first."
    exit 1
}
$objects = Get-Content $objectsFile -Raw | ConvertFrom-Json
$total = $objects.Count; $current = 0

foreach ($obj in $objects) {
    $current++
    $objectName = $obj.name
    $rawFile    = Join-Path $rawDir "fields/$objectName.json"

    if (-not (Test-Path $rawFile)) {
        Write-Warning "[$current/$total] $objectName — raw fields file not found, skipping"
        continue
    }

    $raw = Get-Content $rawFile -Raw | ConvertFrom-Json

    $clean = $raw | Where-Object {
        # Drop hidden/internal properties
        -not $_.hidden                           -and
        # Drop archived properties
        -not $_.archived                         -and
        # Drop internal types
        $_.type -notin $skipTypes                -and
        # Drop properties with no label
        ($_.label ?? '').Trim()
    } | ForEach-Object {
        [PSCustomObject]@{
            apiName      = $_.name
            label        = ($_.label ?? '').Trim()
            type         = $typeMap[$_.type] ?? 'string'
            fieldType    = $_.fieldType ?? ''
            required     = if ($_.hasUniqueValue) { 'yes' } else { 'no' }
            isCustom     = -not [bool]$_.hubspotDefined
            groupName    = $_.groupName ?? ''
            description  = ($_.description ?? '').Trim()
            options      = if ($_.type -eq 'enumeration') {
                @($_.options | ForEach-Object { $_.label })
            } else { @() }
        }
    }

    $outFile = Join-Path $fieldsDir "$objectName.json"
    $clean | ConvertTo-Json -Depth 5 | Set-Content $outFile -Encoding UTF8
    Write-Host "[$current/$total] $objectName — $($clean.Count) properties" -ForegroundColor Green
}

Write-Host "Fields cleaned → $fieldsDir" -ForegroundColor Green
