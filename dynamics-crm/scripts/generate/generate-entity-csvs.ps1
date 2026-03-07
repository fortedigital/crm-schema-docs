<#
.SYNOPSIS
    Generates entity CSV files from clean attribute data.

.DESCRIPTION
    Input:  data/clean/attributes/<entity>.json  (one per entity)
    Output: entities/<entity>.csv                (one per entity)

    CSV columns:
      logical_name   — field API name
      display_name   — human-readable label
      type           — simplified type (string, int, guid, picklist, …)
      required       — yes / no
      source_type    — simple / calculated / rollup
      is_lookup      — yes / no  (lookup/reference field)
      lookup_targets — target entity names for lookup fields
      option_values  — available option set values (value:label pairs)
      is_custom      — yes / no  (custom field added outside standard schema)
      usage          — number of saved views this field appears in as a column
      bu_usage       — qualitative notes on which business units use it  [manual]
      comment        — free-text annotation                               [manual]

    Manual columns (bu_usage, comment) are preserved across regenerations:
    if the CSV already exists, the script reads those two columns by logical_name
    and carries them forward into the new file.
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/../gather/config.json"
)

$config      = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$cleanDir    = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.cleanDir))
$entitiesDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.entitiesDir))
New-Item -ItemType Directory -Path $entitiesDir -Force | Out-Null

# Entity list from clean output
$entitiesFile = Join-Path $cleanDir 'entities.json'
if (-not (Test-Path $entitiesFile)) {
    Write-Error "data/clean/entities.json not found. Run the clean stage first."
    exit 1
}
$entityNames = (Get-Content $entitiesFile -Raw | ConvertFrom-Json) |
               ForEach-Object { $_.logicalName ?? $_.LogicalName }

function ConvertTo-CsvField($value) {
    $s = [string]$value
    if ($s -match '[,"\r\n]') { return '"' + ($s -replace '"', '""') + '"' }
    return $s
}

$total = $entityNames.Count; $current = 0

foreach ($entity in $entityNames) {
    $current++
    $cleanFile = Join-Path $cleanDir "attributes/$entity.json"

    if (-not (Test-Path $cleanFile)) {
        Write-Warning "[$current/$total] $entity — clean file not found, skipping"
        continue
    }

    $attrs = Get-Content $cleanFile -Raw | ConvertFrom-Json

    # ── Preserve manual columns from existing CSV ─────────────────────────────
    $manual = @{}
    $outFile = Join-Path $entitiesDir "$entity.csv"
    if (Test-Path $outFile) {
        Import-Csv $outFile | ForEach-Object {
            $manual[$_.logical_name] = @{
                bu_usage = $_.bu_usage ?? ''
                comment  = $_.comment  ?? ''
            }
        }
    }

    # ── Write new CSV ─────────────────────────────────────────────────────────
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('logical_name,display_name,type,required,source_type,is_lookup,lookup_targets,option_values,is_custom,usage,bu_usage,comment')

    foreach ($a in $attrs) {
        $existing = $manual[$a.logicalName]
        $line = @(
            ConvertTo-CsvField $a.logicalName
            ConvertTo-CsvField $a.displayName
            ConvertTo-CsvField $a.type
            ConvertTo-CsvField $a.required
            ConvertTo-CsvField ($a.sourceType ?? 'simple')
            ConvertTo-CsvField $(if ($a.isLookup) { 'yes' } else { 'no' })
            ConvertTo-CsvField ($a.lookupTargets ?? '')
            ConvertTo-CsvField ($a.optionValues ?? '')
            ConvertTo-CsvField $(if ($a.isCustom) { 'yes' } else { 'no' })
            ConvertTo-CsvField ($a.viewUsage ?? 0)
            ConvertTo-CsvField ($existing?.bu_usage ?? '')
            ConvertTo-CsvField ($existing?.comment  ?? '')
        ) -join ','
        $lines.Add($line)
    }

    $lines | Set-Content $outFile -Encoding UTF8
    Write-Host "[$current/$total] $entity.csv — $($attrs.Count) attributes" -ForegroundColor Green
}

Write-Host "Entity CSVs written → $entitiesDir" -ForegroundColor Green
