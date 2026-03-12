<#
.SYNOPSIS
    Generates object CSV files from clean property data.

.DESCRIPTION
    Input:  data/clean/fields/<objectName>.json  (one per object)
    Output: objects/<objectName>.csv             (one per object)

    CSV columns:
      api_name      — property API name
      label         — human-readable label
      type          — simplified type (string, decimal, bool, picklist, datetime)
      required      — yes / no
      is_custom     — yes / no  (custom property added outside HubSpot standard schema)
      group         — property group name
      bu_usage      — qualitative notes on which business units use it  [manual]
      comment       — free-text annotation                               [manual]

    Manual columns (bu_usage, comment) are preserved across regenerations:
    if the CSV already exists, the script reads those two columns by api_name
    and carries them forward into the new file.
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/../gather/config.json"
)

$config     = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$cleanDir   = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.cleanDir))
$objectsDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.objectsDir))
New-Item -ItemType Directory -Path $objectsDir -Force | Out-Null

# Object list from clean output
$objectsFile = Join-Path $cleanDir 'objects.json'
if (-not (Test-Path $objectsFile)) {
    Write-Error "data/clean/objects.json not found. Run the clean stage first."
    exit 1
}
$objectNames = (Get-Content $objectsFile -Raw | ConvertFrom-Json) |
               ForEach-Object { $_.name }

function ConvertTo-CsvField($value) {
    $s = [string]$value
    if ($s -match '[,"\r\n]') { return '"' + ($s -replace '"', '""') + '"' }
    return $s
}

$total = $objectNames.Count; $current = 0

foreach ($objectName in $objectNames) {
    $current++
    $cleanFile = Join-Path $cleanDir "fields/$objectName.json"

    if (-not (Test-Path $cleanFile)) {
        Write-Warning "[$current/$total] $objectName — clean fields file not found, skipping"
        continue
    }

    $fields = Get-Content $cleanFile -Raw | ConvertFrom-Json

    # ── Preserve manual columns from existing CSV ─────────────────────────────
    $manual  = @{}
    $outFile = Join-Path $objectsDir "$objectName.csv"
    if (Test-Path $outFile) {
        Import-Csv $outFile | ForEach-Object {
            $manual[$_.api_name] = @{
                bu_usage = $_.bu_usage ?? ''
                comment  = $_.comment  ?? ''
            }
        }
    }

    # ── Write new CSV ─────────────────────────────────────────────────────────
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('api_name,label,type,required,is_custom,group,bu_usage,comment')

    foreach ($f in $fields) {
        $existing = $manual[$f.apiName]
        $line = @(
            ConvertTo-CsvField $f.apiName
            ConvertTo-CsvField $f.label
            ConvertTo-CsvField $f.type
            ConvertTo-CsvField $f.required
            ConvertTo-CsvField (if ($f.isCustom) { 'yes' } else { 'no' })
            ConvertTo-CsvField $f.groupName
            ConvertTo-CsvField ($existing?.bu_usage ?? '')
            ConvertTo-CsvField ($existing?.comment  ?? '')
        ) -join ','
        $lines.Add($line)
    }

    $lines | Set-Content $outFile -Encoding UTF8
    Write-Host "[$current/$total] $objectName.csv — $($fields.Count) properties" -ForegroundColor Green
}

Write-Host "Object CSVs written → $objectsDir" -ForegroundColor Green
