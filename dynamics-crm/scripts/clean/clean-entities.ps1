<#
.SYNOPSIS
    Flattens raw EntityDefinition metadata into clean JSON.

.DESCRIPTION
    Input:  data/raw/entities.json
    Output: data/clean/entities.json

    Transforms Dataverse Label objects into plain strings.
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

function Get-Label($obj) {
    if ($null -eq $obj) { return '' }
    $label = $obj.UserLocalizedLabel?.Label
    if (-not $label) { $label = ($obj.LocalizedLabels | Select-Object -First 1)?.Label }
    return ($label ?? '').Trim()
}

$raw = Get-Content (Join-Path $rawDir 'entities.json') -Raw | ConvertFrom-Json

$clean = $raw | ForEach-Object {
    [PSCustomObject]@{
        logicalName          = $_.LogicalName
        displayName          = Get-Label $_.DisplayName
        description          = Get-Label $_.Description
        entitySetName        = $_.EntitySetName
        primaryIdAttribute   = $_.PrimaryIdAttribute
        primaryNameAttribute = $_.PrimaryNameAttribute
        isCustomEntity       = $_.IsCustomEntity
        objectTypeCode       = $_.ObjectTypeCode
    }
}

$outFile = Join-Path $cleanDir 'entities.json'
$clean | ConvertTo-Json -Depth 5 | Set-Content $outFile -Encoding UTF8
Write-Host "Cleaned $($clean.Count) entity definitions → $outFile" -ForegroundColor Green
