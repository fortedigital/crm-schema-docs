<#
.SYNOPSIS
    Discovers and fetches SObject metadata based on objectSource in config.json.

.DESCRIPTION
    objectSource modes
    ------------------
    custom      Fetches all custom objects in the org (API names ending in __c),
                excluding custom settings. This is the default.

    namespace   Fetches all objects with the given namespace prefix.
                Set objectSource.namespace to the package namespace (e.g. "mypkg").
                If namespace is empty, fetches org-specific custom objects
                (custom objects with no namespace prefix).

    filter      Fetches objects matching a raw SOQL WHERE clause on EntityDefinition.
                Set objectSource.filter, e.g.:
                  "IsCustomizable = true AND IsCustomSetting = false"

.OUTPUTS
    data/raw/objects.json — array of EntityDefinition records.
    All downstream gather/clean/generate scripts derive their object list from this file.
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/config.json"
)

. "$PSScriptRoot/connect.ps1"

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$outDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.rawDir))
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

Connect-Salesforce -ConfigPath $ConfigPath

$src  = $config.objectSource
$mode = $src.mode

Write-Host "Object discovery mode: $mode"

$select = 'QualifiedApiName, Label, IsCustomizable, IsCustomSetting, NamespacePrefix, KeyPrefix, DurableId'

$objects = switch ($mode) {

    'custom' {
        # All custom objects (API name ends in __c), excluding custom settings
        $q = "SELECT $select FROM EntityDefinition WHERE QualifiedApiName LIKE '%\_\_c' ESCAPE '\' AND IsCustomSetting = false"
        Invoke-SalesforceToolingQuery $q
    }

    'namespace' {
        $ns = $src.namespace
        if ($ns) {
            # Objects with the given namespace prefix
            $q = "SELECT $select FROM EntityDefinition WHERE NamespacePrefix = '$ns'"
        } else {
            # Org-specific custom objects (no namespace prefix, name ends in __c)
            $q = "SELECT $select FROM EntityDefinition WHERE NamespacePrefix = null AND QualifiedApiName LIKE '%\_\_c' ESCAPE '\' AND IsCustomSetting = false"
        }
        Invoke-SalesforceToolingQuery $q
    }

    'filter' {
        $f = $src.filter
        if (-not $f) {
            Write-Error "Set objectSource.filter to a SOQL WHERE clause in config.json."
            exit 1
        }
        $q = "SELECT $select FROM EntityDefinition WHERE $f"
        Invoke-SalesforceToolingQuery $q
    }

    default {
        Write-Error "Unknown objectSource.mode '$mode'. Valid values: custom, namespace, filter."
        exit 1
    }
}

$outFile = Join-Path $outDir 'objects.json'
$objects | ConvertTo-Json -Depth 10 | Set-Content $outFile -Encoding UTF8
Write-Host "Saved $($objects.Count) object definitions → $outFile" -ForegroundColor Green
