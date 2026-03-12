<#
.SYNOPSIS
    Discovers HubSpot CRM objects (standard and/or custom) based on config.json.

.DESCRIPTION
    objectSource modes
    ------------------
    all         Fetches standard objects (contacts, companies, deals, etc.) and
                all custom objects discovered via GET /crm/v3/schemas. Default.

    standard    Fetches only the well-known standard HubSpot objects.

    custom      Fetches only custom objects discovered via GET /crm/v3/schemas.

    filter      Fetches only the specific object names listed in objectSource.filter.
                Example: ["contacts", "companies", "my_custom_object"]

.OUTPUTS
    data/raw/objects.json — array of object definitions.
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

Connect-HubSpot -ConfigPath $ConfigPath

$src  = $config.objectSource
$mode = $src.mode

Write-Host "Object discovery mode: $mode"

# ── Fetch custom schemas from CRM Schemas API ─────────────────────────────────
function Get-CustomSchemas {
    try {
        $schemas = Invoke-HubSpotGetPaged '/crm/v3/schemas' -ResultsProperty 'results'
        return $schemas
    } catch {
        Write-Warning "Could not fetch custom schemas: $_"
        return @()
    }
}

function Convert-SchemaToObject($schema) {
    [PSCustomObject]@{
        name                = $schema.name
        label               = $schema.labels?.singular ?? $schema.name
        objectTypeId        = $schema.objectTypeId
        isCustom            = $true
        isStandard          = $false
        primaryNameProperty = $schema.primaryDisplayProperty ?? 'hs_object_id'
        fullyQualifiedName  = $schema.fullyQualifiedName ?? $schema.name
    }
}

function Convert-StandardToObject($std) {
    [PSCustomObject]@{
        name                = $std.name
        label               = $std.label
        objectTypeId        = $std.objectTypeId
        isCustom            = $false
        isStandard          = $true
        primaryNameProperty = $std.primaryNameProperty
        fullyQualifiedName  = $std.name
    }
}

$objects = switch ($mode) {

    'all' {
        $result = [System.Collections.Generic.List[object]]::new()
        foreach ($s in $script:StandardObjects) {
            $result.Add((Convert-StandardToObject $s))
        }
        foreach ($schema in (Get-CustomSchemas)) {
            $result.Add((Convert-SchemaToObject $schema))
        }
        $result.ToArray()
    }

    'standard' {
        $script:StandardObjects | ForEach-Object { Convert-StandardToObject $_ }
    }

    'custom' {
        Get-CustomSchemas | ForEach-Object { Convert-SchemaToObject $_ }
    }

    'filter' {
        $filterNames = [System.Collections.Generic.HashSet[string]](
            [System.StringComparer]::OrdinalIgnoreCase
        )
        foreach ($n in $src.filter) { $filterNames.Add($n) | Out-Null }

        $result = [System.Collections.Generic.List[object]]::new()

        # Match standard objects
        foreach ($s in $script:StandardObjects) {
            if ($filterNames.Contains($s.name)) {
                $result.Add((Convert-StandardToObject $s))
            }
        }

        # Match custom objects
        foreach ($schema in (Get-CustomSchemas)) {
            if ($filterNames.Contains($schema.name) -or $filterNames.Contains($schema.fullyQualifiedName)) {
                $result.Add((Convert-SchemaToObject $schema))
            }
        }
        $result.ToArray()
    }

    default {
        Write-Error "Unknown objectSource.mode '$mode'. Valid values: all, standard, custom, filter."
        exit 1
    }
}

$outFile = Join-Path $outDir 'objects.json'
$objects | ConvertTo-Json -Depth 10 | Set-Content $outFile -Encoding UTF8

$std    = ($objects | Where-Object { $_.isStandard }).Count
$custom = ($objects | Where-Object { $_.isCustom }).Count
Write-Host "Saved $($objects.Count) object definitions ($std standard, $custom custom) → $outFile" -ForegroundColor Green
