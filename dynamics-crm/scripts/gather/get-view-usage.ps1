<#
.SYNOPSIS
    Counts how many saved views include each field for every configured entity.

.DESCRIPTION
    Input:  data/raw/entities.json  (for ObjectTypeCode mapping)
    Output: data/raw/view-usage/<entity>.json

    For each entity, queries all SavedQuery records by returnedtypecode,
    parses the layoutxml to find field columns, and counts occurrences.

    Depends on get-entities.ps1 having run first (needs entities.json).
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/config.json"
)

. "$PSScriptRoot/connect.ps1"

$config   = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rawDir   = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.rawDir))
$outDir   = Join-Path $rawDir 'view-usage'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

# ── Load ObjectTypeCode mapping from already-gathered entity data ─────────────
$entitiesFile = Join-Path $rawDir 'entities.json'
if (-not (Test-Path $entitiesFile)) {
    Write-Error "entities.json not found at $entitiesFile. Run get-entities.ps1 first."
    exit 1
}
$entityDefs = Get-Content $entitiesFile -Raw | ConvertFrom-Json
$typeCodeMap = @{}
foreach ($e in $entityDefs) {
    $name = $e.LogicalName ?? $e.logicalName
    $code = $e.ObjectTypeCode ?? $e.objectTypeCode
    if ($name -and $code) { $typeCodeMap[$name] = [int]$code }
}

Connect-Dataverse -ConfigPath $ConfigPath

$total = $entityDefs.Count; $current = 0

foreach ($entity in ($entityDefs | ForEach-Object { $_.LogicalName ?? $_.logicalName })) {
    $current++

    $typeCode = $typeCodeMap[$entity]
    if (-not $typeCode) {
        Write-Warning "[$current/$total] $entity — no ObjectTypeCode found, skipping"
        continue
    }

    $url   = "savedqueries?`$select=name,layoutxml&`$filter=returnedtypecode eq $typeCode"
    $views = Invoke-DataverseGet -RelativeUrl $url

    # Parse layoutxml and count field column occurrences across all views
    $fieldCounts = @{}
    $parsedViews = 0

    foreach ($view in $views) {
        if (-not $view.layoutxml) { continue }
        try {
            $xml   = [xml]$view.layoutxml
            $cells = $xml.SelectNodes('//cell')
            foreach ($cell in $cells) {
                $name = $cell.name
                if ($name) {
                    $fieldCounts[$name] = ($fieldCounts[$name] ?? 0) + 1
                }
            }
            $parsedViews++
        } catch {
            # Malformed layoutxml — skip silently
        }
    }

    $result = [PSCustomObject]@{
        entity      = $entity
        totalViews  = $views.Count
        parsedViews = $parsedViews
        fieldUsage  = $fieldCounts
    }

    $outFile = Join-Path $outDir "$entity.json"
    $result | ConvertTo-Json -Depth 5 | Set-Content $outFile -Encoding UTF8
    Write-Host "[$current/$total] $entity — $($views.Count) views, $($fieldCounts.Count) fields with usage" -ForegroundColor Green
}

Write-Host "View usage saved → $outDir" -ForegroundColor Green
