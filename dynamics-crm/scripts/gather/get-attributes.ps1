<#
.SYNOPSIS
    Fetches attribute (field) metadata for each entity listed in config.json.

.DESCRIPTION
    For each entity, fetches:
      - Core attribute metadata (name, type, required level, etc.)
      - SourceType (simple / calculated / rollup)
      - Lookup targets (which entities a lookup field points to)
      - Option set values (picklist, multi-select, state, status options)

.OUTPUTS
    data/raw/attributes/<entity>.json — one file per entity
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/config.json"
)

. "$PSScriptRoot/connect.ps1"

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$outDir = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.rawDir))) 'attributes'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

Connect-Dataverse -ConfigPath $ConfigPath
Confirm-DataverseAuth -ConfigPath $ConfigPath

# Entity list is produced by get-entities.ps1 — must run first
$entitiesFile = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.rawDir))) 'entities.json'
if (-not (Test-Path $entitiesFile)) {
    Write-Error "entities.json not found. Run get-entities.ps1 first."
    exit 1
}
$entityNames = (Get-Content $entitiesFile -Raw | ConvertFrom-Json) |
               ForEach-Object { $_.LogicalName ?? $_.logicalName }

$select = @(
    'LogicalName'
    'SchemaName'
    'DisplayName'
    'Description'
    'AttributeType'
    'AttributeTypeName'
    'RequiredLevel'
    'IsPrimaryId'
    'IsPrimaryName'
    'IsCustomAttribute'
    'AttributeOf'         # virtual/calculation parent field
    'SourceType'          # null/0 = simple, 1 = calculated, 2 = rollup
) -join ','

$total   = $entityNames.Count
$current = 0

foreach ($entity in $entityNames) {
    $current++
    Write-Host "[$current/$total] $entity..." -NoNewline

    $url   = "EntityDefinitions(LogicalName='$entity')/Attributes?`$select=$select"
    $attrs = Invoke-DataverseGet -RelativeUrl $url

    # ── Enrich: lookup targets ────────────────────────────────────────────
    $lookupMap = @{}
    try {
        $lookupUrl = "EntityDefinitions(LogicalName='$entity')/Attributes/Microsoft.Dynamics.CRM.LookupAttributeMetadata?`$select=LogicalName,Targets"
        $lookups   = Invoke-DataverseGet -RelativeUrl $lookupUrl
        foreach ($l in $lookups) {
            if ($l.Targets) { $lookupMap[$l.LogicalName] = $l.Targets }
        }
    } catch {
        Write-Warning "  Could not fetch lookup targets for $entity`: $_"
    }

    # ── Enrich: picklist option sets ──────────────────────────────────────
    # Each attribute may reference a local OptionSet or a GlobalOptionSet — expand both.
    $optionMap = @{}
    foreach ($castType in @(
        'PicklistAttributeMetadata'
        'MultiSelectPicklistAttributeMetadata'
        'StateAttributeMetadata'
        'StatusAttributeMetadata'
    )) {
        try {
            $osUrl = "EntityDefinitions(LogicalName='$entity')/Attributes/Microsoft.Dynamics.CRM.${castType}?`$select=LogicalName&`$expand=OptionSet,GlobalOptionSet"
            $osList = Invoke-DataverseGet -RelativeUrl $osUrl
            foreach ($os in $osList) {
                $opts = if     ($os.OptionSet       -and $os.OptionSet.Options)       { $os.OptionSet.Options }
                        elseif ($os.GlobalOptionSet -and $os.GlobalOptionSet.Options) { $os.GlobalOptionSet.Options }
                        else   { $null }
                if ($opts) { $optionMap[$os.LogicalName] = $opts }
            }
        } catch {
            Write-Warning "  Option set fetch failed ($castType): $_"
        }
    }

    # ── Merge enrichment data into main attributes ────────────────────────
    foreach ($attr in $attrs) {
        $name = $attr.LogicalName
        if ($lookupMap.ContainsKey($name)) {
            $attr | Add-Member -NotePropertyName '_LookupTargets' -NotePropertyValue $lookupMap[$name] -Force
        }
        if ($optionMap.ContainsKey($name)) {
            $attr | Add-Member -NotePropertyName '_OptionSetOptions' -NotePropertyValue $optionMap[$name] -Force
        }
    }

    $outFile = Join-Path $outDir "$entity.json"
    $attrs | ConvertTo-Json -Depth 20 | Set-Content $outFile -Encoding UTF8

    $lookupCount  = $lookupMap.Count
    $optionCount  = $optionMap.Count
    Write-Host " $($attrs.Count) attributes ($lookupCount lookups, $optionCount option sets)" -ForegroundColor Green
}

Write-Host "Attributes saved → $outDir" -ForegroundColor Green
