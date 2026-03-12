<#
.SYNOPSIS
    Extracts child relationship metadata from cached describe files.

.DESCRIPTION
    Input:  data/raw/objects.json    (for object list)
            data/raw/describe/<Object>.json  (produced by get-fields.ps1 — no extra API calls)
    Output: data/raw/relationships/<Object>.json  — childRelationships array per object

    Child relationships represent the one-to-many view from the parent object.
    Each entry records the child object, the lookup field, the relationship name,
    and whether the relationship is a Master-Detail (cascadeDelete: true).
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/config.json"
)

$config      = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rawDir      = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.rawDir))
$describeDir = Join-Path $rawDir 'describe'
$relsDir     = Join-Path $rawDir 'relationships'
New-Item -ItemType Directory -Path $relsDir -Force | Out-Null

# Object list from get-objects.ps1
$objectsFile = Join-Path $rawDir 'objects.json'
if (-not (Test-Path $objectsFile)) {
    Write-Error "data/raw/objects.json not found. Run get-objects.ps1 first."
    exit 1
}
$objects  = Get-Content $objectsFile -Raw | ConvertFrom-Json
$apiNames = $objects | ForEach-Object { $_.QualifiedApiName ?? $_.qualifiedApiName }

$total = $apiNames.Count; $current = 0

foreach ($apiName in $apiNames) {
    $current++
    $describeFile = Join-Path $describeDir "$apiName.json"

    if (-not (Test-Path $describeFile)) {
        Write-Warning "[$current/$total] $apiName — describe file not found, skipping (run get-fields.ps1 first)"
        continue
    }

    $describe = Get-Content $describeFile -Raw | ConvertFrom-Json

    # childRelationships: this object is the parent; childSObject has a lookup/master-detail back here
    $rels = $describe.childRelationships | Where-Object {
        # Skip deprecated or hidden relationships
        -not $_.deprecatedAndHidden  -and
        # Skip relationships with no name (polymorphic/system)
        $_.relationshipName
    } | ForEach-Object {
        [PSCustomObject]@{
            childSObject     = $_.childSObject
            field            = $_.field
            relationshipName = $_.relationshipName
            cascadeDelete    = [bool]$_.cascadeDelete
            restrictedDelete = [bool]$_.restrictedDelete
        }
    }

    $outFile = Join-Path $relsDir "$apiName.json"
    $rels | ConvertTo-Json -Depth 5 | Set-Content $outFile -Encoding UTF8
    Write-Host "[$current/$total] $apiName — $($rels.Count) child relationships" -ForegroundColor Green
}

Write-Host "Relationships saved → $relsDir" -ForegroundColor Green
