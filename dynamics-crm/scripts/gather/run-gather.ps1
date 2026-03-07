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
Confirm-DataverseAuth -ConfigPath $ConfigPath
# $env:DATAVERSE_TOKEN and $env:DATAVERSE_URL are now set for child processes

# ── 2. Clean raw output directory ────────────────────────────────────────────
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rawDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.rawDir))
if (Test-Path $rawDir) {
    Remove-Item "$rawDir/*" -Recurse -Force
    Write-Host "Cleared $rawDir" -ForegroundColor DarkGray
}

# ── 3. Run gather scripts ──────────────────────────────────────────────────────
$scripts = @(
    'get-entities.ps1'              # must run first — downstream scripts depend on its output
    'get-attributes.ps1'
    'get-relationships.ps1'
    'get-view-usage.ps1'
    'get-operational-insights.ps1'  # must run after entities + relationships
)

foreach ($script in $scripts) {
    $scriptPath = Join-Path $PSScriptRoot $script
    Write-Host "`n--- $script ---" -ForegroundColor Yellow
    pwsh -NoProfile -File $scriptPath -ConfigPath $ConfigPath
    if ($LASTEXITCODE -eq 91) {
        # Child script detected auth failure — use Confirm-DataverseAuth to prompt + retry
        $script:Connection = $null
        Remove-Item Env:DATAVERSE_TOKEN -ErrorAction SilentlyContinue
        Remove-Item Env:DATAVERSE_URL   -ErrorAction SilentlyContinue
        Confirm-DataverseAuth -ConfigPath $ConfigPath
        # If we get here, reauthentication succeeded — retry the failed script
        Write-Host "`n--- $script (retry) ---" -ForegroundColor Yellow
        pwsh -NoProfile -File $scriptPath -ConfigPath $ConfigPath
        if ($LASTEXITCODE -ne 0) {
            Write-Error "$script exited with code $LASTEXITCODE after retry. Aborting."
            exit $LASTEXITCODE
        }
    } elseif ($LASTEXITCODE -ne 0) {
        Write-Error "$script exited with code $LASTEXITCODE. Aborting."
        exit $LASTEXITCODE
    }
}

# ── 4. Summary ────────────────────────────────────────────────────────────────
$elapsed = (Get-Date) - $start

$files = Get-ChildItem $rawDir -Recurse -File -Filter '*.json'
Write-Host "`n=== Done in $([int]$elapsed.TotalSeconds)s — $($files.Count) files in $rawDir ===" -ForegroundColor Cyan
