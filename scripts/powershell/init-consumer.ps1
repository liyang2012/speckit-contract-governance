#!/usr/bin/env pwsh
# Contract Governance extension: init-consumer.ps1
# Initialize a frontend Consumer Contract under contracts/_consumers/.
#
# Usage: init-consumer.ps1 -Consumer <name> [-Type frontend]
param(
    [string]$Consumer = "",
    [string]$Type = "frontend",
    [switch]$Help
)
$ErrorActionPreference = 'Stop'

function Show-Usage {
    @"
Usage: init-consumer.ps1 -Consumer <consumer-name> [-Type frontend]

Initialize frontend Consumer Contract under contracts/_consumers/.

Options:
  -Consumer <name>  Consumer name, e.g. web-app
  -Type <type>      Consumer type, currently only 'frontend'; default frontend
  -Help             Show this help
"@
}

if ($Help) { Show-Usage; exit 0 }

# Load configurable values from contract-governance-config.yml
. "$PSScriptRoot/common-config.ps1"

# Use config default when -Consumer is omitted
if (-not $Consumer) {
    $Consumer = $CG_DEFAULT_CONSUMER
    Write-Host "[contract-governance] Using config default consumer: $Consumer"
}

if (-not $Consumer) {
    Write-Error "ERROR: -Consumer is required (or set default_consumer in config)"
    Show-Usage
    exit 1
}

if ($Consumer -notmatch '^[A-Za-z0-9_.\-]+$') {
    Write-Error "ERROR: Consumer name may only contain letters, digits, underscores, dots, and hyphens: $Consumer"
    exit 1
}

if ($Type -ne 'frontend') {
    Write-Error "ERROR: Currently only -Type frontend is supported"
    exit 1
}

# --- Locate repo root --------------------------------------------------------

. "$PSScriptRoot/common-utils.ps1"

$repoRoot      = Find-RepoRoot -StartDir $PSScriptRoot
if (-not $repoRoot) { $repoRoot = Get-Location }

$contractsDir  = Join-Path $repoRoot "contracts"
$consumersDir  = Join-Path $contractsDir "_consumers"
$consumerFile  = Join-Path $consumersDir "$Consumer.yaml"

if (-not (Test-Path $consumersDir)) {
    New-Item -ItemType Directory -Path $consumersDir -Force | Out-Null
}

$serviceMap = Join-Path $contractsDir "SERVICE-MAP.md"
if (-not (Test-Path $serviceMap)) {
    Write-Warning "[contract-governance] Missing contracts/SERVICE-MAP.md; Consumer Contract can be created but Provider services still need init-registry"
}

if (-not (Test-Path $consumerFile)) {
    @"
# Frontend Consumer Contract: $Consumer
# This file is maintained during $Consumer's speckit-plan phase.
# Only records frontend consumption expectations; does not define backend Provider endpoints.
# Provider endpoints are maintained in contracts/<service>/api.yaml by the owning service.
#
# Example:
# consumes:
#   http:
#     - provider: my-service
#       operationId: listReleaseRecords
#       usage: Release record list page
#       required_fields:
#         - id
#         - appName
#       status: PENDING
#       evidence:
#         page: src/modules/user/pages/UserList.vue
#         client: src/modules/user/services/userApi.ts
#       changes:
#         - change_id: "2026-06-05-001"
#           type: breaking
#           path: "/api/v1/releases"
#           method: "GET"
#           summary: "Response adds pagination structure"
#           since: "2026-06-05"
#           ack: PENDING_ACK   # PENDING_ACK (not yet adapted) / ACKNOWLEDGED (adapted)

consumer: $Consumer
type: $Type

consumes:
  http: []
"@ | Set-Content -Path $consumerFile -Encoding UTF8
    Write-Host "[contract-governance] Created contracts/_consumers/$Consumer.yaml"
} else {
    Write-Host "[contract-governance] contracts/_consumers/$Consumer.yaml already exists, not overwritten"
}

if ((Test-Path $serviceMap) -and -not (Select-String -Path $serviceMap -SimpleMatch "contracts/_consumers/$Consumer.yaml" -Quiet)) {
    $mapContent = Get-Content $serviceMap -Raw
    $row = "| $Consumer | $Type | - | ``contracts/_consumers/$Consumer.yaml`` |"
    if ($mapContent -match '## Consumers') {
        $mapContent = [regex]::Replace(
            $mapContent,
            '(## Consumers\s*\r?\n\s*\r?\n\| Consumer \| Type \| Framework \| Contract \|\s*\r?\n\|[-| ]+\|)',
            "`$1`r`n$row",
            1
        )
    } else {
        $mapContent = $mapContent.TrimEnd() + "`r`n`r`n## Consumers`r`n`r`n| Consumer | Type | Framework | Contract |`r`n|----------|------|-----------|----------|`r`n$row`r`n"
    }
    Set-Content -Path $serviceMap -Value $mapContent -Encoding UTF8
    Write-Host "[contract-governance] Added $Consumer to contracts/SERVICE-MAP.md"
}

Write-Host "[contract-governance] Frontend Consumer Contract initialization complete: $Consumer ($Type)"
