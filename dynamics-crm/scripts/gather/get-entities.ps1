<#
.SYNOPSIS
    Discovers and fetches EntityDefinition metadata based on entitySource in config.json.

.DESCRIPTION
    entitySource modes
    ------------------
    solution  Fetches all entities that belong to a named Dataverse solution.
              Set entitySource.solution to the solution's unique name.

    custom    Fetches all custom entities in the org (IsCustomEntity eq true).

    filter    Fetches entities matching a raw OData filter string on EntityDefinitions.
              Set entitySource.filter, e.g.: "IsCustomEntity eq true and IsValidForAdvancedFind eq true"

.OUTPUTS
    data/raw/entities.json — array of entity definition objects.
    All downstream gather/clean/generate scripts derive their entity list from this file.
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

Connect-Dataverse -ConfigPath $ConfigPath

$select = @(
    'MetadataId'
    'LogicalName'
    'SchemaName'
    'DisplayName'
    'Description'
    'EntitySetName'
    'PrimaryIdAttribute'
    'PrimaryNameAttribute'
    'IsCustomEntity'
    'ObjectTypeCode'
) -join ','

$src  = $config.entitySource
$mode = $src.mode

Write-Host "Entity discovery mode: $mode"

$entities = switch ($mode) {

    'solution' {
        $solName = $src.solution
        if (-not $solName -or $solName -eq '<solution-unique-name>') {
            Write-Error "Set entitySource.solution to the solution's unique name in config.json."
            exit 1
        }

        # Resolve solution → solutionid
        $sol = Invoke-DataverseGet "solutions?`$select=solutionid,uniquename&`$filter=uniquename eq '$solName'"
        if (-not $sol) {
            Write-Error "Solution '$solName' not found in this environment."
            exit 1
        }
        $solId = $sol[0].solutionid
        Write-Host "Solution: $solName  ($solId)"

        # Get entity MetadataIds from solution components (componenttype = 1 = Entity)
        $components = Invoke-DataverseGet "solutioncomponents?`$select=objectid&`$filter=_solutionid_value eq $solId and componenttype eq 1"
        $metaIds = [System.Collections.Generic.HashSet[string]]($components | ForEach-Object { [string]$_.objectid })
        Write-Host "Entity components in solution: $($metaIds.Count)"

        if ($metaIds.Count -eq 0) {
            Write-Warning "No entity components found in solution '$solName'."
            @()
            break
        }

        # Fetch all EntityDefinitions and filter client-side by MetadataId.
        # Using a server-side OR filter over many GUIDs risks hitting URL length limits.
        $all = Invoke-DataverseGet "EntityDefinitions?`$select=$select"
        $all | Where-Object { $metaIds.Contains([string]$_.MetadataId) }
    }

    'custom' {
        Invoke-DataverseGet "EntityDefinitions?`$select=$select&`$filter=IsCustomEntity eq true"
    }

    'filter' {
        $f = $src.filter
        if (-not $f) {
            Write-Error "Set entitySource.filter to an OData filter string in config.json."
            exit 1
        }
        Invoke-DataverseGet "EntityDefinitions?`$select=$select&`$filter=$f"
    }

    default {
        Write-Error "Unknown entitySource.mode '$mode'. Valid values: solution, custom, filter."
        exit 1
    }
}

$outFile = Join-Path $outDir 'entities.json'
$entities | ConvertTo-Json -Depth 10 | Set-Content $outFile -Encoding UTF8
Write-Host "Saved $($entities.Count) entity definitions → $outFile" -ForegroundColor Green
