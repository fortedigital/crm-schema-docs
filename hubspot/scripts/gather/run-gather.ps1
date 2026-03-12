<#
.SYNOPSIS
    Orchestrates the full data-gathering phase for HubSpot object metadata.

.DESCRIPTION
    1. Authenticate once via HubSpot Private App token; export to env vars
       for child processes.
    2. Run get-objects, get-fields, get-relationships, and
       get-operational-insights in sequence.

.PARAMETER ConfigPath
    Path to config.json. Defaults to the config.json next to this script.

.EXAMPLE
    .\run-gather.ps1
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/config.json"
)

. "$PSScriptRoot/connect.ps1"

$start = Get-Date
Write-Host "=== HubSpot data gather — $(Get-Date -Format 'yyyy-MM-dd HH:mm') ===" -ForegroundColor Cyan

# ── 1. Authenticate once ──────────────────────────────────────────────────────
Connect-HubSpot -ConfigPath $ConfigPath
# $env:HUBSPOT_TOKEN and $env:HUBSPOT_PORTAL_ID are now set for child processes

# ── 2. Run gather scripts ─────────────────────────────────────────────────────
$scripts = @(
    'get-objects.ps1'               # must run first — all subsequent scripts depend on objects.json
    'get-fields.ps1'                # fetches properties per object
    'get-relationships.ps1'         # reads standard associations + custom schemas
    'get-operational-insights.ps1'  # must run after objects (uses objects.json)
)

foreach ($script in $scripts) {
    $scriptPath = Join-Path $PSScriptRoot $script
    Write-Host "`n--- $script ---" -ForegroundColor Yellow
    pwsh -NoProfile -File $scriptPath -ConfigPath $ConfigPath
    if ($LASTEXITCODE -ne 0) {
        Write-Error "$script exited with code $LASTEXITCODE. Aborting."
        exit $LASTEXITCODE
    }
}

# ── 3. Summary ────────────────────────────────────────────────────────────────
$elapsed = (Get-Date) - $start
$config  = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rawDir  = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.rawDir))

$files = Get-ChildItem $rawDir -Recurse -File -Filter '*.json'
Write-Host "`n=== Done in $([int]$elapsed.TotalSeconds)s — $($files.Count) files in $rawDir ===" -ForegroundColor Cyan
