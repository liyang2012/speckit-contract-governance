#!/usr/bin/env pwsh
param(
    [string]$Service = "",
    [string]$Consumer = "",
    [ValidateSet('text', 'json', 'sarif')][string]$Format = 'text',
    [switch]$StrictWarnings,
    [string]$RuntimeOpenApi = "",
    [string]$EventOld = "",
    [string]$EventNew = "",
    [switch]$Help
)
$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host "Usage: audit-contracts.ps1 [-Service <name>] [-Consumer <name>] [-Format text|json|sarif] [-StrictWarnings] [-RuntimeOpenApi <file>] [-EventOld <file> -EventNew <file>]"
    exit 0
}

. "$PSScriptRoot/common-utils.ps1"
$repoRoot = Find-RepoRoot -StartDir $PSScriptRoot
if (-not $repoRoot) { $repoRoot = Get-Location }
$analyzer = Join-Path $PSScriptRoot "../python/contract_analyzer.py"

$python = $null
foreach ($candidate in @('python3', 'python')) {
    $command = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($command) { $python = $command.Source; break }
}
if (-not $python) { Write-Error "Contract audit requires python3/python"; exit 1 }
& $python -X utf8 -c "import yaml" 2>$null
if ($LASTEXITCODE -ne 0) { Write-Error "Contract audit requires PyYAML; run: $python -m pip install pyyaml"; exit 1 }

if ($RuntimeOpenApi) {
    if (-not $Service) { Write-Error "-RuntimeOpenApi requires -Service"; exit 1 }
    $contract = Join-Path $repoRoot "contracts/$Service/api.yaml"
    & $python -X utf8 $analyzer runtime-diff --contract $contract --runtime $RuntimeOpenApi --service $Service --format $Format
    exit $LASTEXITCODE
}

if ($EventOld -or $EventNew) {
    if (-not $EventOld -or -not $EventNew) { Write-Error "-EventOld and -EventNew must be provided together"; exit 1 }
    & $python -X utf8 $analyzer event-diff --old $EventOld --new $EventNew --format $Format
    exit $LASTEXITCODE
}

$auditArgs = @($analyzer, 'validate', '--repo-root', $repoRoot, '--format', $Format)
if ($Service) { $auditArgs += @('--service', $Service) }
if ($Consumer) { $auditArgs += @('--consumer', $Consumer) }
if ($StrictWarnings) { $auditArgs += '--strict-warnings' }
& $python -X utf8 @auditArgs
exit $LASTEXITCODE
