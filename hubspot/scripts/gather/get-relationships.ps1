<#
.SYNOPSIS
    Discovers association (relationship) definitions between HubSpot objects.

.DESCRIPTION
    Input:  data/raw/objects.json  (for object list and objectTypeIds)
    Output: data/raw/relationships/<objectName>.json  — associations per object

    Two sources of association definitions:
      1. Standard: well-known HubSpot associations defined in connect.ps1
         (contacts→companies, deals→line_items, etc.)
      2. Custom objects: associations declared in GET /crm/v3/schemas/{objectType}
         are added automatically.

    Only associations where BOTH objects appear in the discovered set are kept.
    The output is keyed by the FROM object; each entry describes a relationship
    to a target object.
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/config.json"
)

. "$PSScriptRoot/connect.ps1"

$config  = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rawDir  = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.rawDir))
$relsDir = Join-Path $rawDir 'relationships'
New-Item -ItemType Directory -Path $relsDir -Force | Out-Null

# Object list from get-objects.ps1
$objectsFile = Join-Path $rawDir 'objects.json'
if (-not (Test-Path $objectsFile)) {
    Write-Error "data/raw/objects.json not found. Run get-objects.ps1 first."
    exit 1
}
$objects = Get-Content $objectsFile -Raw | ConvertFrom-Json

# Build lookup maps by name and by objectTypeId
$objectByName   = @{}
$objectByTypeId = @{}
foreach ($o in $objects) {
    $objectByName[$o.name]           = $o
    $objectByTypeId[$o.objectTypeId] = $o
}

Connect-HubSpot -ConfigPath $ConfigPath

# ── 1. Collect all association definitions ────────────────────────────────────
$allAssociations = [System.Collections.Generic.List[object]]::new()

# Standard associations from connect.ps1
foreach ($assoc in $script:StandardAssociations) {
    $allAssociations.Add([PSCustomObject]@{
        fromObject  = $assoc.fromObject
        toObject    = $assoc.toObject
        cardinality = $assoc.cardinality
        label       = $assoc.label
        category    = 'HUBSPOT_DEFINED'
    })
}

# Custom object associations from schemas
$customObjects = $objects | Where-Object { $_.isCustom -eq $true }
foreach ($obj in $customObjects) {
    try {
        $schema = Invoke-HubSpotGet "/crm/v3/schemas/$($obj.name)"
        foreach ($assoc in $schema.associations) {
            $toTypeId = $assoc.toObjectTypeId
            $toObj    = $objectByTypeId[$toTypeId]
            if (-not $toObj) { continue }
            $allAssociations.Add([PSCustomObject]@{
                fromObject  = $obj.name
                toObject    = $toObj.name
                cardinality = 'ManyToMany'
                label       = $assoc.name ?? "$($obj.name)_to_$($toObj.name)"
                category    = 'USER_DEFINED'
            })
        }
    }
    catch {
        Write-Warning "Could not fetch schema for $($obj.name): $_"
    }
}

# ── 2. Filter and group by fromObject ─────────────────────────────────────────
$grouped = @{}
foreach ($o in $objects) { $grouped[$o.name] = [System.Collections.Generic.List[object]]::new() }

$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($assoc in $allAssociations) {
    $from = $assoc.fromObject
    $to   = $assoc.toObject
    $key  = "$from|$to"

    if ($seen.Contains($key)) { continue }
    if (-not $objectByName.ContainsKey($from)) { continue }
    if (-not $objectByName.ContainsKey($to))   { continue }

    $seen.Add($key) | Out-Null
    $grouped[$from].Add($assoc)
}

# ── 3. Write per-object files ─────────────────────────────────────────────────
$total = $objects.Count; $current = 0

foreach ($obj in $objects) {
    $current++
    $name    = $obj.name
    $rels    = $grouped[$name]
    $outFile = Join-Path $relsDir "$name.json"

    $rels | ConvertTo-Json -Depth 5 | Set-Content $outFile -Encoding UTF8
    Write-Host "[$current/$total] $name — $($rels.Count) associations" -ForegroundColor Green
}

Write-Host "Relationships saved → $relsDir" -ForegroundColor Green
