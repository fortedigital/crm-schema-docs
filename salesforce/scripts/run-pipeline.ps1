<#
.SYNOPSIS
    Runs the full Salesforce object-documentation pipeline.

.DESCRIPTION
    Executes the three stages in order:
      1. Gather   — pull metadata from Salesforce (requires auth via sf CLI)
      2. Clean    — transform raw data into normalised JSON
      3. Generate — write diagrams/*.mmd, objects/*.csv, and *.md

    Any stage can be skipped with the corresponding -Skip* switch.

.PARAMETER ConfigPath
    Path to config.json. Defaults to gather/config.json.

.PARAMETER SelectOrg
    Pass through to run-gather.ps1: launch sf CLI org picker before gathering.

.PARAMETER SkipGather
    Skip the gather stage (use existing data/raw/ files).

.PARAMETER SkipClean
    Skip the clean stage (use existing data/clean/ files).

.PARAMETER SkipGenerate
    Skip the generate stage.

.EXAMPLE
    # Full pipeline, first run
    .\run-pipeline.ps1 -SelectOrg

.EXAMPLE
    # Re-run clean + generate only (raw data already present)
    .\run-pipeline.ps1 -SkipGather

.EXAMPLE
    # Re-generate outputs only (clean data already present)
    .\run-pipeline.ps1 -SkipGather -SkipClean
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath   = "$PSScriptRoot/gather/config.json",
    [switch]$SelectOrg,
    [switch]$SkipGather,
    [switch]$SkipClean,
    [switch]$SkipGenerate
)

$totalStart = Get-Date
Write-Host "=== Salesforce pipeline — $(Get-Date -Format 'yyyy-MM-dd HH:mm') ===" -ForegroundColor Cyan
Write-Host "Stages: Gather=$(-not $SkipGather)  Clean=$(-not $SkipClean)  Generate=$(-not $SkipGenerate)" -ForegroundColor DarkGray
Write-Host ""

function Invoke-Stage($label, $scriptPath, $extraArgs = @()) {
    Write-Host "════ $label ════" -ForegroundColor Yellow
    $stageStart = Get-Date

    $allArgs = @('-NoProfile', '-File', $scriptPath, '-ConfigPath', $ConfigPath) + $extraArgs
    pwsh @allArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Error "$label failed (exit $LASTEXITCODE). Aborting pipeline."
        exit $LASTEXITCODE
    }

    $elapsed = [int]((Get-Date) - $stageStart).TotalSeconds
    Write-Host "Done in ${elapsed}s`n" -ForegroundColor DarkGray
}

# ── 1. Gather ─────────────────────────────────────────────────────────────────
if (-not $SkipGather) {
    $gatherArgs = if ($SelectOrg) { @('-SelectOrg') } else { @() }
    Invoke-Stage 'Gather' "$PSScriptRoot/gather/run-gather.ps1" $gatherArgs
} else {
    Write-Host "Gather — skipped`n" -ForegroundColor DarkGray
}

# ── 2. Clean ──────────────────────────────────────────────────────────────────
if (-not $SkipClean) {
    Invoke-Stage 'Clean' "$PSScriptRoot/clean/run-clean.ps1"
} else {
    Write-Host "Clean — skipped`n" -ForegroundColor DarkGray
}

# ── 3. Generate ───────────────────────────────────────────────────────────────
if (-not $SkipGenerate) {
    Invoke-Stage 'Generate' "$PSScriptRoot/generate/run-generate.ps1"
} else {
    Write-Host "Generate — skipped`n" -ForegroundColor DarkGray
}

$totalElapsed = [int]((Get-Date) - $totalStart).TotalSeconds
Write-Host "=== Pipeline complete in ${totalElapsed}s ===" -ForegroundColor Cyan
