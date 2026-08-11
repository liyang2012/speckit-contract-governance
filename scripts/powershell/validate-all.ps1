#!/usr/bin/env pwsh
# Contract Governance extension: validate-all.ps1
# Orchestrate full contract governance validation: boundary + registry.
#
# Usage: validate-all.ps1 [-Phase plan|tasks|all] [-FeatureDir <path>] [-BootstrapOk]
param(
    [string]$Phase = "all",
    [string]$FeatureDir = "",
    [switch]$BootstrapOk,
    [switch]$Help
)
$ErrorActionPreference = 'Stop'

function Show-Usage {
    @"
Usage: validate-all.ps1 [-Phase plan|tasks|all] [-FeatureDir <path>] [-BootstrapOk]

Run full contract governance validation: FE/BE boundary + registry + consumer.

Options:
  -Phase <phase>     Validation phase: plan, tasks, all (default: all)
  -FeatureDir <path> Validate a specific feature directory
  -BootstrapOk       Allow skip when contracts/ does not exist
  -Help              Show this help
"@
}

if ($Help) { Show-Usage; exit 0 }

if ($Phase -notin @("plan", "tasks", "all")) {
    Write-Error "ERROR: -Phase must be plan, tasks, or all; current: $Phase"
    exit 1
}

$scriptDir = $PSScriptRoot

# Build arguments for sub-scripts
$boundaryArgs = @()
$registryArgs = @()

switch ($Phase) {
    "plan"  { $boundaryArgs += "-Plan" }
    "tasks" { $boundaryArgs += "-Tasks" }
    "all"   { $boundaryArgs += "-All" }
}

if ($FeatureDir) {
    $boundaryArgs += @("-FeatureDir", $FeatureDir)
    $registryArgs += @("-FeatureDir", $FeatureDir)
}

if ($BootstrapOk) {
    $registryArgs += "-BootstrapOk"
}

# Run boundary validation
& "$scriptDir/validate-boundary.ps1" @boundaryArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Run registry validation
& "$scriptDir/validate-registry.ps1" @registryArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "[contract-governance] Full validation passed ($Phase)"
