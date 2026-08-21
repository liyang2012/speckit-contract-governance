#!/usr/bin/env pwsh
param(
    [string]$Service = "",
    [string]$Base = "",
    [switch]$Write,
    [string[]]$ConsumerFiles = @(),
    [ValidateSet('text', 'json')][string]$Format = 'text',
    [switch]$Help
)
$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host "Usage: diff-contract.ps1 -Service <name> [-Base <git-ref>] [-Write] [-ConsumerFiles <file>] [-Format text|json]"
    exit 0
}
if (-not $Service) { Write-Error "-Service is required"; exit 1 }
if ($ConsumerFiles.Count -gt 0 -and -not $Write) {
    Write-Error "-ConsumerFiles modifies Consumer contracts and requires -Write"
    exit 1
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
if (-not $python) { Write-Error "diff-contract requires python3/python"; exit 1 }

$arguments = @($analyzer, 'changelog', '--repo-root', $repoRoot, '--service', $Service, '--format', $Format)
if ($Base) { $arguments += @('--base', $Base) }
if ($Write) { $arguments += '--write' }
foreach ($consumer in $ConsumerFiles) { $arguments += @('--consumer', $consumer) }
& $python -X utf8 @arguments
exit $LASTEXITCODE
