<#
.SYNOPSIS
    Fetches field metadata for each discovered SObject via the describe endpoint.

.DESCRIPTION
    Input:  data/raw/objects.json  (from get-objects.ps1)
    Output: data/raw/describe/<Object>.json  — full describe response (reused by get-relationships.ps1)
            data/raw/fields/<Object>.json    — fields array only

    Uses the REST API:  GET /services/data/v{ver}/sobjects/{ObjectName}/describe
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/config.json"
)

. "$PSScriptRoot/connect.ps1"

$config     = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rawDir     = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.rawDir))
$describeDir = Join-Path $rawDir 'describe'
$fieldsDir   = Join-Path $rawDir 'fields'
New-Item -ItemType Directory -Path $describeDir -Force | Out-Null
New-Item -ItemType Directory -Path $fieldsDir   -Force | Out-Null

# Object list from get-objects.ps1
$objectsFile = Join-Path $rawDir 'objects.json'
if (-not (Test-Path $objectsFile)) {
    Write-Error "data/raw/objects.json not found. Run get-objects.ps1 first."
    exit 1
}
$objects = Get-Content $objectsFile -Raw | ConvertFrom-Json
$apiNames = $objects | ForEach-Object { $_.QualifiedApiName ?? $_.qualifiedApiName }

Connect-Salesforce -ConfigPath $ConfigPath

$total = $apiNames.Count; $current = 0

foreach ($apiName in $apiNames) {
    $current++

    try {
        $describe = Invoke-SalesforceGet "sobjects/$apiName/describe"

        # Save full describe (reused by get-relationships.ps1 — no extra API call needed)
        $describeFile = Join-Path $describeDir "$apiName.json"
        $describe | ConvertTo-Json -Depth 10 | Set-Content $describeFile -Encoding UTF8

        # Save fields array only
        $fieldsFile = Join-Path $fieldsDir "$apiName.json"
        $describe.fields | ConvertTo-Json -Depth 5 | Set-Content $fieldsFile -Encoding UTF8

        Write-Host "[$current/$total] $apiName — $($describe.fields.Count) fields" -ForegroundColor Green
    }
    catch {
        Write-Warning "[$current/$total] $apiName — describe failed: $_"
    }
}

Write-Host "Fields saved → $fieldsDir" -ForegroundColor Green
