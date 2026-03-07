<#
.SYNOPSIS
    Orchestrates the full diagram and CSV generation phase.

.DESCRIPTION
    Runs generate-diagrams and generate-entity-csvs in sequence.
    Reads from data/clean/ and writes to diagrams/ and entities/.
    No authentication required — operates on local files only.

.EXAMPLE
    .\run-generate.ps1
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/../gather/config.json"
)

$start = Get-Date
Write-Host "=== Dynamics 365 generate — $(Get-Date -Format 'yyyy-MM-dd HH:mm') ===" -ForegroundColor Cyan

$scripts = @(
    'generate-diagrams.ps1'
    'generate-entity-csvs.ps1'
    'generate-md.ps1'
    'generate-html.ps1'
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
