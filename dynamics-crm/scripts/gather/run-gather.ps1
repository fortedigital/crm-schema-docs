<#
.SYNOPSIS
    Orchestrates the full data-gathering phase for Dynamics 365 entity metadata.

.DESCRIPTION
    1. Authenticate once via Dataverse OAuth2.
    2. Run get-entities, get-attributes, get-relationships, and get-view-usage in sequence.
       The auth token is passed to child processes via environment variables
       so each step re-uses the same token without re-authenticating.

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
Write-Host "=== Dynamics 365 data gather — $(Get-Date -Format 'yyyy-MM-dd HH:mm') ===" -ForegroundColor Cyan

# ── 1. Authenticate once ──────────────────────────────────────────────────────
Connect-Dataverse -ConfigPath $ConfigPath
# $env:DATAVERSE_TOKEN and $env:DATAVERSE_URL are now set for child processes

# ── 3. Run gather scripts ──────────────────────────────────────────────────────
$scripts = @(
    'get-entities.ps1'        # must run first — get-view-usage depends on its output
    'get-attributes.ps1'
    'get-relationships.ps1'
    'get-view-usage.ps1'
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

# ── 4. Summary ────────────────────────────────────────────────────────────────
$elapsed = (Get-Date) - $start
$config  = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rawDir  = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.rawDir))

$files = Get-ChildItem $rawDir -Recurse -File -Filter '*.json'
Write-Host "`n=== Done in $([int]$elapsed.TotalSeconds)s — $($files.Count) files in $rawDir ===" -ForegroundColor Cyan
