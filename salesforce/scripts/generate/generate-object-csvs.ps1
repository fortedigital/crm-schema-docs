<#
.SYNOPSIS
    Generates object CSV files from clean field data.

.DESCRIPTION
    Input:  data/clean/fields/<Object>.json  (one per object)
    Output: objects/<Object>.csv             (one per object)

    CSV columns:
      api_name      — field API name
      label         — human-readable label
      type          — simplified type (string, int, decimal, guid, picklist, …)
      required      — yes / no
      is_custom     — yes / no  (custom field added outside standard schema)
      usage         — number of list views this field appears in as a column
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
               ForEach-Object { $_.apiName }

function ConvertTo-CsvField($value) {
    $s = [string]$value
    if ($s -match '[,"\r\n]') { return '"' + ($s -replace '"', '""') + '"' }
    return $s
}

$total = $objectNames.Count; $current = 0

foreach ($apiName in $objectNames) {
    $current++
    $cleanFile = Join-Path $cleanDir "fields/$apiName.json"

    if (-not (Test-Path $cleanFile)) {
        Write-Warning "[$current/$total] $apiName — clean fields file not found, skipping"
        continue
    }

    $fields = Get-Content $cleanFile -Raw | ConvertFrom-Json

    # ── Preserve manual columns from existing CSV ─────────────────────────────
    $manual  = @{}
    $outFile = Join-Path $objectsDir "$apiName.csv"
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
    $lines.Add('api_name,label,type,required,is_custom,usage,bu_usage,comment')

    foreach ($f in $fields) {
        $existing = $manual[$f.apiName]
        $line = @(
            ConvertTo-CsvField $f.apiName
            ConvertTo-CsvField $f.label
            ConvertTo-CsvField $f.type
            ConvertTo-CsvField $f.required
            ConvertTo-CsvField (if ($f.isCustom) { 'yes' } else { 'no' })
            ConvertTo-CsvField ($f.viewUsage ?? 0)
            ConvertTo-CsvField ($existing?.bu_usage ?? '')
            ConvertTo-CsvField ($existing?.comment  ?? '')
        ) -join ','
        $lines.Add($line)
    }

    $lines | Set-Content $outFile -Encoding UTF8
    Write-Host "[$current/$total] $apiName.csv — $($fields.Count) fields" -ForegroundColor Green
}

Write-Host "Object CSVs written → $objectsDir" -ForegroundColor Green
