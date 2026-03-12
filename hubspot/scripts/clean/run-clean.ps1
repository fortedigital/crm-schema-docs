<#
.SYNOPSIS
    Orchestrates the full data-cleaning phase.

.DESCRIPTION
    Runs clean-objects, clean-fields, clean-relationships, and
    clean-operational-insights in sequence.
    Reads from data/raw/ and writes to data/clean/.
    No authentication required — operates on local files only.

.EXAMPLE
    .\run-clean.ps1
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/../gather/config.json"
)

$start = Get-Date
Write-Host "=== HubSpot data clean — $(Get-Date -Format 'yyyy-MM-dd HH:mm') ===" -ForegroundColor Cyan

$scripts = @(
    'clean-objects.ps1'
    'clean-fields.ps1'
    'clean-relationships.ps1'
    'clean-operational-insights.ps1'
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

$elapsed = (Get-Date) - $start
Write-Host "`n=== Done in $([int]$elapsed.TotalSeconds)s ===" -ForegroundColor Cyan
