<#
.SYNOPSIS
    Flattens raw HubSpot object metadata into clean JSON.

.DESCRIPTION
    Input:  data/raw/objects.json
    Output: data/clean/objects.json

    Normalises the raw API response to a flat object with consistent field names.
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

$raw = Get-Content (Join-Path $rawDir 'objects.json') -Raw | ConvertFrom-Json

$clean = $raw | ForEach-Object {
    [PSCustomObject]@{
        name                = $_.name
        label               = ($_.label ?? '').Trim()
        objectTypeId        = $_.objectTypeId ?? ''
        isCustom            = [bool]$_.isCustom
        isStandard          = [bool]$_.isStandard
        primaryNameProperty = $_.primaryNameProperty ?? ''
        fullyQualifiedName  = $_.fullyQualifiedName ?? $_.name
    }
}

$outFile = Join-Path $cleanDir 'objects.json'
$clean | ConvertTo-Json -Depth 5 | Set-Content $outFile -Encoding UTF8
Write-Host "Cleaned $($clean.Count) object definitions → $outFile" -ForegroundColor Green
