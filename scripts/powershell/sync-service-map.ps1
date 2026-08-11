#!/usr/bin/env pwsh
param([switch]$Write, [switch]$Help)
$ErrorActionPreference = 'Stop'

if ($Help) { Write-Host "Usage: sync-service-map.ps1 [-Write]"; exit 0 }
. "$PSScriptRoot/common-utils.ps1"
$repoRoot = Find-RepoRoot -StartDir $PSScriptRoot
if (-not $repoRoot) { $repoRoot = Get-Location }
$analyzer = Join-Path $PSScriptRoot "../python/contract_analyzer.py"

$python = $null
foreach ($candidate in @('python3', 'python')) {
    $command = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($command) { $python = $command.Source; break }
}
if (-not $python) { Write-Error "SERVICE-MAP sync requires python3/python"; exit 1 }
& $python -c "import yaml" 2>$null
if ($LASTEXITCODE -ne 0) { Write-Error "SERVICE-MAP sync requires PyYAML; run: $python -m pip install pyyaml"; exit 1 }

$mapArgs = @($analyzer, 'service-map', '--repo-root', $repoRoot)
if ($Write) { $mapArgs += '--write' }
& $python @mapArgs
exit $LASTEXITCODE
