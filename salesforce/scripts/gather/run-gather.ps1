<#
.SYNOPSIS
    Orchestrates the full data-gathering phase for Salesforce object metadata.

.DESCRIPTION
    1. (Optional) Use sf CLI to pick an org and update config.json.
    2. Authenticate once via sf CLI; export token to env vars for child processes.
    3. Run get-objects, get-fields, get-relationships, get-list-view-usage in sequence.

.PARAMETER ConfigPath
    Path to config.json. Defaults to the config.json next to this script.

.PARAMETER SelectOrg
    If set, launch the interactive org picker before gathering.

.EXAMPLE
    # First run — pick org interactively, then gather
    .\run-gather.ps1 -SelectOrg

.EXAMPLE
    # Subsequent runs — org already in config.json
    .\run-gather.ps1
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/config.json",
    [switch]$SelectOrg
)

. "$PSScriptRoot/connect.ps1"

$start = Get-Date
Write-Host "=== Salesforce data gather — $(Get-Date -Format 'yyyy-MM-dd HH:mm') ===" -ForegroundColor Cyan

# ── 1. Org selection ──────────────────────────────────────────────────────────
if ($SelectOrg) {
    Select-SalesforceOrg -ConfigPath $ConfigPath
}

# ── 2. Authenticate once ──────────────────────────────────────────────────────
Connect-Salesforce -ConfigPath $ConfigPath
# $env:SF_TOKEN, $env:SF_INSTANCE_URL, $env:SF_API_VERSION are now set for child processes

# ── 3. Run gather scripts ─────────────────────────────────────────────────────
$scripts = @(
    'get-objects.ps1'          # must run first — all subsequent scripts depend on objects.json
    'get-fields.ps1'           # also saves full describe/ cache
    'get-relationships.ps1'    # reads from describe/ cache — no extra API calls
    'get-list-view-usage.ps1'
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
