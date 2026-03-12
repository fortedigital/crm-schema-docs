<#
.SYNOPSIS
    Counts how many list views include each field for every discovered SObject.

.DESCRIPTION
    Input:  data/raw/objects.json  (for object list)
    Output: data/raw/list-view-usage/<Object>.json

    For each object, queries all list views via the REST API, then fetches the
    describe for each list view to identify its columns. Counts how many list
    views include each field (fieldNameOrPath).

    Depends on get-objects.ps1 having run first.

    API endpoints used:
      GET /services/data/v{ver}/sobjects/{Object}/listviews
      GET /services/data/v{ver}/sobjects/{Object}/listviews/{id}/describe
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/config.json"
)

. "$PSScriptRoot/connect.ps1"

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rawDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.rawDir))
$outDir = Join-Path $rawDir 'list-view-usage'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

# Object list from get-objects.ps1
$objectsFile = Join-Path $rawDir 'objects.json'
if (-not (Test-Path $objectsFile)) {
    Write-Error "data/raw/objects.json not found. Run get-objects.ps1 first."
    exit 1
}
$objects  = Get-Content $objectsFile -Raw | ConvertFrom-Json
$apiNames = $objects | ForEach-Object { $_.QualifiedApiName ?? $_.qualifiedApiName }

Connect-Salesforce -ConfigPath $ConfigPath

$total = $apiNames.Count; $current = 0

foreach ($apiName in $apiNames) {
    $current++

    try {
        $listViewsResp = Invoke-SalesforceGet "sobjects/$apiName/listviews"
        $listViews     = $listViewsResp.listviews ?? @()
    }
    catch {
        Write-Warning "[$current/$total] $apiName — listviews failed: $_"
        continue
    }

    $fieldCounts  = @{}
    $parsedViews  = 0

    foreach ($lv in $listViews) {
        if (-not $lv.id) { continue }
        try {
            $desc = Invoke-SalesforceGet "sobjects/$apiName/listviews/$($lv.id)/describe"
            foreach ($col in $desc.columns) {
                $fieldName = $col.fieldNameOrPath
                if ($fieldName) {
                    $fieldCounts[$fieldName] = ($fieldCounts[$fieldName] ?? 0) + 1
                }
            }
            $parsedViews++
        }
        catch {
            # Single list view describe failed — skip silently
        }
    }

    $result = [PSCustomObject]@{
        object      = $apiName
        totalViews  = $listViews.Count
        parsedViews = $parsedViews
        fieldUsage  = $fieldCounts
    }

    $outFile = Join-Path $outDir "$apiName.json"
    $result | ConvertTo-Json -Depth 5 | Set-Content $outFile -Encoding UTF8
    Write-Host "[$current/$total] $apiName — $($listViews.Count) views, $($fieldCounts.Count) fields with usage" -ForegroundColor Green
}

Write-Host "List view usage saved → $outDir" -ForegroundColor Green
