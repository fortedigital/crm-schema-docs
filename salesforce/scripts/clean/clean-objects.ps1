<#
.SYNOPSIS
    Flattens raw Salesforce EntityDefinition metadata into clean JSON.

.DESCRIPTION
    Input:  data/raw/objects.json
    Output: data/clean/objects.json

    Normalises the Tooling API response to a flat object with consistent field names.
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
    $apiName = $_.QualifiedApiName ?? $_.qualifiedApiName
    [PSCustomObject]@{
        apiName           = $apiName
        label             = ($_.Label ?? $_.label ?? '').Trim()
        isCustom          = $apiName -like '*__c'
        isCustomSetting   = [bool]($_.IsCustomSetting ?? $_.isCustomSetting)
        namespace         = $_.NamespacePrefix ?? $_.namespacePrefix ?? ''
        keyPrefix         = $_.KeyPrefix ?? $_.keyPrefix ?? ''
    }
}

$outFile = Join-Path $cleanDir 'objects.json'
$clean | ConvertTo-Json -Depth 5 | Set-Content $outFile -Encoding UTF8
Write-Host "Cleaned $($clean.Count) object definitions → $outFile" -ForegroundColor Green
