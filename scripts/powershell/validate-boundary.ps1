#!/usr/bin/env pwsh
# Contract Governance extension: validate-boundary.ps1
# Validate FE/BE/Contract boundaries in plan.md / tasks.md.
#
# Usage: validate-boundary.ps1 [-Plan] [-Tasks] [-All] [-FeatureDir <path>]
param(
    [switch]$Plan,
    [switch]$Tasks,
    [switch]$All,
    [string]$FeatureDir = "",
    [switch]$Help
)
$ErrorActionPreference = 'Stop'

# Load configurable values from contract-governance-config.yml
. "$PSScriptRoot/common-config.ps1"

function Show-Usage {
    @"
Usage: validate-boundary.ps1 [-Plan] [-Tasks] [-All] [-FeatureDir <path>]

Validate FE/BE/Contract boundaries in current Spec Kit feature.

Options:
  -Plan              Only validate plan.md
  -Tasks             Only validate tasks.md
  -All               Validate both plan.md and tasks.md (default)
  -FeatureDir <path> Validate a specific feature directory
  -Help              Show this help
"@
}

if ($Help) { Show-Usage; exit 0 }

$mode = 'all'
if ($Plan)  { $mode = 'plan' }
if ($Tasks) { $mode = 'tasks' }
if ($All)   { $mode = 'all' }

# --- Locate repo root --------------------------------------------------------

. "$PSScriptRoot/common-utils.ps1"

$repoRoot = Find-RepoRoot -StartDir $PSScriptRoot
if (-not $repoRoot) { $repoRoot = Get-Location }

# --- Resolve feature dir -----------------------------------------------------

$featurePath = Resolve-FeatureDir -RepoRoot $repoRoot -FeatureDirArg $FeatureDir
if (-not $featurePath -or -not (Test-Path $featurePath -PathType Container)) {
    Write-Host "[contract-governance] No active feature directory found, skipping boundary validation"
    exit 0
}

$planFile  = Join-Path $featurePath "plan.md"
$tasksFile = Join-Path $featurePath "tasks.md"

$failures = @()
$warnings = @()

# --- Helpers ------------------------------------------------------------------

function Test-ContentMatches {
    param([string]$File, [string[]]$Patterns)
    foreach ($p in $Patterns) {
        if (Select-String -Path $File -Pattern $p -CaseSensitive:$false -Quiet) { return $true }
    }
    return $false
}

function Test-LiteralMatches {
    param([string]$File, [string[]]$Literals)
    foreach ($lit in $Literals) {
        if (Select-String -Path $File -Pattern $lit -SimpleMatch -Quiet) { return $true }
    }
    return $false
}

function Test-UnresolvedTemplate {
    param([string]$File)
    $markers = @("[FEATURE]", "[FEATURE NAME]", "[###-feature", "[service-name]",
                 "[module-name]", "[path]", "[endpoint", "[Title]", "[language]",
                 "[framework]", "NEEDS CLARIFICATION", "TXXX")
    return Test-LiteralMatches -File $File -Literals $markers
}

# Build frontend keyword list from config
$frontendExtra = @()
if ($CG_FRONTEND_KEYWORDS) { $frontendExtra = $CG_FRONTEND_KEYWORDS }

function Plan-MentionsFrontend  { Test-ContentMatches $planFile (@("frontend", "front-end", "\bFE\b", "前端", "Vue", "Vite", "React", "Playwright") + $frontendExtra) }
function Plan-MentionsBackend   { Test-ContentMatches $planFile @("backend", "back-end", "\bBE\b", "后端", "Spring", "微服务", "controller", "service", "mapper", "Gradle", "JUnit", "Feign") }
function Plan-MentionsContract  { Test-ContentMatches $planFile @("contracts/", "api\.yaml", "openapi", "_consumers", "消费契约", "_consumers/[A-Za-z0-9_.\-]+\.yaml", "接口契约", "Provider", "Consumer", "PENDING", "RESOLVED", "Result<", "PageResult<", "错误码", "Feign", "DTO", "ViewModel", "FormModel") }

function Tasks-MentionsFrontend { Test-ContentMatches $tasksFile (@("\[FE\]", "frontend", "front-end", "前端", "Vue", "Vite", "React", "Playwright", "\.vue", "\.ts") + $frontendExtra) }
function Tasks-MentionsBackend  { Test-ContentMatches $tasksFile @("\[BE\]", "backend", "back-end", "后端", "Spring", "controller", "service", "manager", "mapper", "repository", "Gradle", "JUnit", "Feign", "src/main/java", "src/test/java") }
function Tasks-MentionsContract { Test-ContentMatches $tasksFile @("\[Contract\]", "contracts/", "api\.yaml", "openapi", "_consumers", "消费契约", "_consumers/[A-Za-z0-9_.\-]+\.yaml", "接口契约", "契约测试", "Provider", "Consumer", "PENDING", "RESOLVED", "DTO", "ViewModel", "FormModel") }

function Plan-MentionsFeignInternal { Test-ContentMatches $planFile @("Feign", "/internal/", "内部接口", "服务间", "服务调用", "前端不可访问", "不暴露给前端") }
function Tasks-MentionsGateway { Test-ContentMatches $tasksFile @("网关", "访问控制", "内部接口", "前端不可访问", "不暴露给前端", "internal", "Gateway", "gateway", "Nginx", "路由", "鉴权", "服务间认证", "认证透传", "traceId") }

# --- Validate plan.md ---------------------------------------------------------

function Validate-Plan {
    if (-not (Test-Path $planFile)) {
        $script:failures += "plan.md not found: $planFile"
        return
    }
    if (Test-UnresolvedTemplate $planFile) {
        $script:failures += "plan.md contains unresolved template placeholders or NEEDS CLARIFICATION"
    }
    if (-not (Test-ContentMatches $planFile @("Upstream Dependencies", "上游依赖"))) {
        $script:failures += "plan.md must declare Upstream Dependencies"
    }
    if (-not (Test-ContentMatches $planFile @("测试策略", "完成定义", "test strategy", "definition of done"))) {
        $script:failures += "plan.md must contain test strategy and definition of done"
    }

    $fe = Plan-MentionsFrontend
    $be = Plan-MentionsBackend
    $ct = Plan-MentionsContract

    if ($fe -and $be -and -not $ct) {
        $script:failures += "plan.md covers both FE and BE but declares no Contract boundary"
    }
    if ($ct) {
        $contractsDir = Join-Path $repoRoot "contracts"
        if (-not (Test-Path $contractsDir)) {
            $script:warnings += "plan.md references contracts but repo lacks contracts/ directory; run contract-governance init first"
        }
        $serviceMapFile = Join-Path $contractsDir "SERVICE-MAP.md"
        if (-not (Test-Path $serviceMapFile)) {
            $script:warnings += "plan.md references contracts but SERVICE-MAP.md is missing; run contract-governance init first"
        }
        if (-not (Test-ContentMatches $planFile @("contracts/[A-Za-z0-9_.\-]+/api\.yaml", "contracts/_registry/[A-Za-z0-9_.\-]+\.yaml", "contracts/_consumers/[A-Za-z0-9_.\-]+\.yaml", "specs/.*/contracts", "contracts/"))) {
            $script:failures += "plan.md contract section must reference explicit contracts/ paths"
        }
    }
    if (-not $fe -and -not $be) {
        $script:warnings += "plan.md does not clearly indicate frontend or backend scope"
    }
}

# --- Validate tasks.md --------------------------------------------------------

function Validate-Tasks {
    if (-not (Test-Path $tasksFile)) {
        $script:failures += "tasks.md not found: $tasksFile"
        return
    }
    if (Test-UnresolvedTemplate $tasksFile) {
        $script:failures += "tasks.md contains unresolved template placeholders"
    }
    if (-not (Test-ContentMatches $tasksFile @("^- \[ \] T[0-9]{3}"))) {
        $script:failures += "tasks.md must use Spec Kit task numbering format, e.g. '- [ ] T001 ...'"
    }
    if (-not (Tasks-MentionsContract)) {
        $script:failures += "tasks.md must contain contract or contract-test tasks"
    }
    if (-not (Test-ContentMatches $tasksFile @("test", "测试", "验证", "Playwright", "JUnit", "pytest", "契约测试", "灰盒", "E2E", "quickstart"))) {
        $script:failures += "tasks.md must contain verification or test tasks"
    }
    if (-not (Test-ContentMatches $tasksFile @("Downstream Contract", "下游契约", "delivery-note", "archive 摘要", "交付摘要"))) {
        $script:failures += "tasks.md must include a final delivery task referencing Downstream Contract"
    }

    if ((Plan-MentionsFrontend) -and -not (Tasks-MentionsFrontend)) {
        $script:failures += "plan.md scopes frontend but tasks.md has no frontend tasks"
    }
    if ((Plan-MentionsBackend) -and -not (Tasks-MentionsBackend)) {
        $script:failures += "plan.md scopes backend but tasks.md has no backend tasks"
    }
    if ((Plan-MentionsContract) -and -not (Tasks-MentionsContract)) {
        $script:failures += "plan.md declares contracts but tasks.md has no contract tasks"
    }
    if ((Plan-MentionsFeignInternal) -and -not (Tasks-MentionsGateway)) {
        $script:failures += "plan.md involves Feign/internal but tasks.md lacks gateway/access-control/isolation tasks"
    }
}

# --- Dispatch -----------------------------------------------------------------

switch ($mode) {
    'plan'  { Validate-Plan }
    'tasks' { Validate-Tasks }
    'all'   {
        if (Test-Path $planFile)  { Validate-Plan }  else { $warnings += "plan.md not found, skipping plan validation" }
        if (Test-Path $tasksFile) { Validate-Tasks } else { $warnings += "tasks.md not found, skipping tasks validation" }
    }
}

foreach ($w in $warnings) { Write-Warning "[contract-governance] Warning: $w" }

if ($failures) {
    Write-Error "[contract-governance] Boundary validation failed: $featurePath" -ErrorAction Continue
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    Write-Host "[contract-governance] Suggestion: define Contract boundaries before splitting FE/BE implementation tasks."
    exit 1
}

Write-Host "[contract-governance] Boundary validation passed: $featurePath ($mode)"
