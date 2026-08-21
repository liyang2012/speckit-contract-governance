#!/usr/bin/env pwsh
param(
    [string]$Base = "",
    [string[]]$Service = @(),
    [switch]$Ci,
    [ValidateSet('text', 'json', 'sarif')][string]$Format = 'text',
    [switch]$Help
)
$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host "Usage: check-changelog.ps1 [-Base <git-ref>] [-Service <name>] [-Ci] [-Format text|json|sarif]"
    exit 0
}

. "$PSScriptRoot/common-utils.ps1"
$repoRoot = Find-RepoRoot -StartDir (Get-Location).Path
if (-not $repoRoot) { $repoRoot = Find-RepoRoot -StartDir $PSScriptRoot }
if (-not $repoRoot) { $repoRoot = Get-Location }
$analyzer = Join-Path $PSScriptRoot "../python/contract_analyzer.py"
$python = $null
foreach ($candidate in @('python3', 'python')) {
    $command = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($command) { $python = $command.Source; break }
}
if (-not $python) { Write-Error "check-changelog requires python3/python"; exit 1 }

$arguments = @($analyzer, 'check-changelog', '--repo-root', $repoRoot, '--format', $Format)
if ($Base) { $arguments += @('--base', $Base) }
if ($Ci) { $arguments += '--ci' }
foreach ($name in $Service) { $arguments += @('--service', $name) }
& $python -X utf8 @arguments
exit $LASTEXITCODE
