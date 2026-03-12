<#
.SYNOPSIS
    Fetches property metadata for each discovered HubSpot object.

.DESCRIPTION
    Input:  data/raw/objects.json  (from get-objects.ps1)
    Output: data/raw/fields/<objectName>.json  — full properties array per object

    Uses the CRM Properties API:
      GET /crm/v3/properties/{objectType}?archived=false
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/config.json"
)

. "$PSScriptRoot/connect.ps1"

$config    = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rawDir    = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.rawDir))
$fieldsDir = Join-Path $rawDir 'fields'
New-Item -ItemType Directory -Path $fieldsDir -Force | Out-Null

# Object list from get-objects.ps1
$objectsFile = Join-Path $rawDir 'objects.json'
if (-not (Test-Path $objectsFile)) {
    Write-Error "data/raw/objects.json not found. Run get-objects.ps1 first."
    exit 1
}
$objects = Get-Content $objectsFile -Raw | ConvertFrom-Json

Connect-HubSpot -ConfigPath $ConfigPath

$total = $objects.Count; $current = 0

foreach ($obj in $objects) {
    $current++
    $objectType = $obj.name

    try {
        $properties = Invoke-HubSpotGetPaged "/crm/v3/properties/$objectType" `
            -ResultsProperty 'results' -PageSize 500

        $outFile = Join-Path $fieldsDir "$objectType.json"
        $properties | ConvertTo-Json -Depth 5 | Set-Content $outFile -Encoding UTF8

        Write-Host "[$current/$total] $objectType — $($properties.Count) properties" -ForegroundColor Green
    }
    catch {
        Write-Warning "[$current/$total] $objectType — properties fetch failed: $_"
    }
}

Write-Host "Fields saved → $fieldsDir" -ForegroundColor Green
