#!/usr/bin/env pwsh
# Contract Governance extension: PowerShell smoke test suite.
# Runs basic assertions against all PS1 scripts to catch regressions.
#
# Usage: pwsh test-smoke.ps1
# Exit code: 0 = all pass, 1 = at least one failure.

$ErrorActionPreference = 'Stop'

$ScriptDir = $PSScriptRoot
$Pass = 0
$Fail = 0
$TestsRun = 0

# --- Helpers ------------------------------------------------------------------

function Setup-TestDir {
    $script:TestDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cg-test-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -ItemType Directory -Path $TestDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TestDir ".specify") -Force | Out-Null
    Push-Location $TestDir
}

function Teardown-TestDir {
    Pop-Location
    if ($TestDir -and (Test-Path $TestDir)) {
        Remove-Item -Recurse -Force $TestDir -ErrorAction SilentlyContinue
    }
}

function Assert-Exit {
    param(
        [string]$Label,
        [int]$Expected,
        [int]$Actual,
        [string]$Output = ""
    )
    $script:TestsRun++
    if ($Actual -eq $Expected) {
        Write-Host "  PASS: $Label"
        $script:Pass++
    } else {
        Write-Host "  FAIL: $Label (expected exit=$Expected, got exit=$Actual)" -ForegroundColor Red
        if ($Output) {
            Write-Host "  Captured output:"
            Write-Host $Output
        }
        $script:Fail++
    }
}

function Assert-FileExists {
    param([string]$Label, [string]$File)
    $script:TestsRun++
    if (Test-Path $File) {
        Write-Host "  PASS: $Label"
        $script:Pass++
    } else {
        Write-Host "  FAIL: $Label (file not found: $File)" -ForegroundColor Red
        $script:Fail++
    }
}

function Assert-OutputContains {
    param([string]$Label, [string]$Expected, [string]$Output)
    $script:TestsRun++
    if ($Output -and $Output.Contains($Expected)) {
        Write-Host "  PASS: $Label"
        $script:Pass++
    } else {
        Write-Host "  FAIL: $Label (output missing: '$Expected')" -ForegroundColor Red
        $script:Fail++
    }
}

function Invoke-Capture {
    param([string]$Script, [string[]]$Arguments)
    $rc = 0
    $output = ""
    try {
        $output = & pwsh -NoProfile -File $Script @Arguments 2>&1 | Out-String
        $rc = $LASTEXITCODE
        if ($null -eq $rc) { $rc = 0 }
    } catch {
        $rc = 1
        $output = $_.Exception.Message
    }
    return @{ ExitCode = $rc; Output = $output }
}

# --- Test: -Help flags -------------------------------------------------------

Write-Host "=== Test: -Help flags ==="
$scripts = @("init-registry.ps1", "init-consumer.ps1", "validate-boundary.ps1", "validate-registry.ps1", "diff-contract.ps1", "validate-all.ps1")
foreach ($s in $scripts) {
    $scriptPath = Join-Path $ScriptDir $s
    if (-not (Test-Path $scriptPath)) {
        Write-Host "  SKIP: $s not found"
        continue
    }
    $result = Invoke-Capture -Script $scriptPath -Arguments @("-Help")
    Assert-Exit -Label "$s -Help exits 0" -Expected 0 -Actual $result.ExitCode -Output $result.Output
}

# --- Test: init-registry -----------------------------------------------------

Write-Host ""
Write-Host "=== Test: init-registry ==="
Setup-TestDir

$scriptPath = Join-Path $ScriptDir "init-registry.ps1"
$result = Invoke-Capture -Script $scriptPath -Arguments @("-Service", "test-svc", "-Database", "db_test")
Assert-Exit -Label "init-registry exits 0" -Expected 0 -Actual $result.ExitCode -Output $result.Output
Assert-FileExists -Label "SERVICE-MAP.md created" -File (Join-Path $TestDir "contracts/SERVICE-MAP.md")
Assert-FileExists -Label "_registry/test-svc.yaml created" -File (Join-Path $TestDir "contracts/_registry/test-svc.yaml")
Assert-FileExists -Label "test-svc/api.yaml created" -File (Join-Path $TestDir "contracts/test-svc/api.yaml")
Assert-FileExists -Label "test-svc/events/.gitkeep created" -File (Join-Path $TestDir "contracts/test-svc/events/.gitkeep")
Assert-OutputContains -Label "init-registry prints success message" -Expected "init" -Output $result.Output

# Run again - should not overwrite
$result = Invoke-Capture -Script $scriptPath -Arguments @("-Service", "test-svc", "-Database", "db_test")
Assert-OutputContains -Label "init-registry does not overwrite existing" -Expected "exist" -Output $result.Output.ToLower()

Teardown-TestDir

# --- Test: init-consumer -----------------------------------------------------

Write-Host ""
Write-Host "=== Test: init-consumer ==="
Setup-TestDir

$scriptPath = Join-Path $ScriptDir "init-consumer.ps1"
$result = Invoke-Capture -Script $scriptPath -Arguments @("-Consumer", "my-web")
Assert-Exit -Label "init-consumer exits 0" -Expected 0 -Actual $result.ExitCode -Output $result.Output
Assert-FileExists -Label "_consumers/my-web.yaml created" -File (Join-Path $TestDir "contracts/_consumers/my-web.yaml")

Teardown-TestDir

# With config default (no -Consumer)
Setup-TestDir
$result = Invoke-Capture -Script $scriptPath -Arguments @()
Assert-Exit -Label "init-consumer with config default exits 0" -Expected 0 -Actual $result.ExitCode -Output $result.Output
Assert-OutputContains -Label "init-consumer uses config default" -Expected "web-app" -Output $result.Output
Teardown-TestDir

# --- Test: validate-registry on clean setup ----------------------------------

Write-Host ""
Write-Host "=== Test: validate-registry (clean) ==="
Setup-TestDir

& pwsh -NoProfile -Command "& '$(Join-Path $ScriptDir 'init-registry.ps1')' -Service svc-a -Database db_a" 2>&1 | Out-Null
& pwsh -NoProfile -Command "& '$(Join-Path $ScriptDir 'init-consumer.ps1')' -Consumer web-app" 2>&1 | Out-Null

$scriptPath = Join-Path $ScriptDir "validate-registry.ps1"
$result = Invoke-Capture -Script $scriptPath -Arguments @("-BootstrapOk")
Assert-Exit -Label "validate-registry exits 0 on clean setup" -Expected 0 -Actual $result.ExitCode -Output $result.Output
Assert-OutputContains -Label "validate-registry reports pass" -Output $result.Output -Expected "pass"

Teardown-TestDir

# --- Test: validate-registry detects bad x-changelog -------------------------

Write-Host ""
Write-Host "=== Test: validate-registry (bad x-changelog) ==="
Setup-TestDir

& pwsh -NoProfile -Command "& '$(Join-Path $ScriptDir 'init-registry.ps1')' -Service svc-b -Database db_b" 2>&1 | Out-Null

$badChangelog = @"

x-changelog:
  - id: "2026-01-01-001"
    version: ""
    date: "2026-01-01"
    type: invalid-type
    path: "/api/v1/foo"
    method: "GET"
    operationId: "getFoo"
"@
$existingContent = Get-Content (Join-Path $TestDir "contracts/svc-b/api.yaml") -Raw
$existingContent + $badChangelog | Out-File -FilePath (Join-Path $TestDir "contracts/svc-b/api.yaml") -Encoding utf8

$scriptPath = Join-Path $ScriptDir "validate-registry.ps1"
$result = Invoke-Capture -Script $scriptPath -Arguments @()
Assert-Exit -Label "validate-registry exits 1 on bad x-changelog type" -Expected 1 -Actual $result.ExitCode -Output $result.Output
Assert-OutputContains -Label "detects invalid x-changelog type" -Expected "invalid" -Output $result.Output.ToLower()
Teardown-TestDir

# --- Test: validate-registry detects Feign path violation --------------------

Write-Host ""
Write-Host "=== Test: validate-registry (Feign path) ==="
Setup-TestDir

& pwsh -NoProfile -Command "& '$(Join-Path $ScriptDir 'init-registry.ps1')' -Service svc-c -Database db_c" 2>&1 | Out-Null

$apiContent = @"
openapi: 3.0.3
info:
  title: svc-c API
  version: 0.0.1
paths:
  /api/v1/items:
    get:
      operationId: listItems
      tags:
        - Feign
components:
  schemas: {}
"@
$apiContent | Out-File -FilePath (Join-Path $TestDir "contracts/svc-c/api.yaml") -Encoding utf8

$scriptPath = Join-Path $ScriptDir "validate-registry.ps1"
$result = Invoke-Capture -Script $scriptPath -Arguments @()
Assert-Exit -Label "validate-registry exits 1 on Feign without /internal/" -Expected 1 -Actual $result.ExitCode -Output $result.Output
Assert-OutputContains -Label "detects Feign path violation" -Expected "/internal/" -Output $result.Output

Teardown-TestDir

# --- Test: validate-boundary skips gracefully --------------------------------

Write-Host ""
Write-Host "=== Test: validate-boundary (no feature) ==="
Setup-TestDir

$scriptPath = Join-Path $ScriptDir "validate-boundary.ps1"
$result = Invoke-Capture -Script $scriptPath -Arguments @("-All")
Assert-Exit -Label "validate-boundary exits 0 when no feature dir" -Expected 0 -Actual $result.ExitCode -Output $result.Output
Assert-OutputContains -Label "validate-boundary reports skip" -Expected "skip" -Output $result.Output.ToLower()

Teardown-TestDir

# --- Test: diff-contract detects breaking change -----------------------------

Write-Host ""
Write-Host "=== Test: diff-contract (breaking change) ==="
Setup-TestDir

& pwsh -NoProfile -Command "& '$(Join-Path $ScriptDir 'init-registry.ps1')' -Service svc-e -Database db_e" 2>&1 | Out-Null

$apiWithOp = @"
openapi: 3.0.3
info:
  title: svc-e API
  version: 0.0.1
paths:
  /api/v1/orders:
    get:
      operationId: listOrders
      tags:
        - 前端API
components:
  schemas: {}
"@
$apiWithOp | Out-File -FilePath (Join-Path $TestDir "contracts/svc-e/api.yaml") -Encoding utf8

Push-Location $TestDir
git init -q 2>$null
git add -A 2>$null
git -c user.name="Contract Governance Tests" -c user.email="contract-governance-tests@example.invalid" commit -q -m "init" 2>$null
Pop-Location

$apiEmpty = @"
openapi: 3.0.3
info:
  title: svc-e API
  version: 0.0.2
paths: {}
components:
  schemas: {}
"@
$apiEmpty | Out-File -FilePath (Join-Path $TestDir "contracts/svc-e/api.yaml") -Encoding utf8

$scriptPath = Join-Path $ScriptDir "diff-contract.ps1"
$result = Invoke-Capture -Script $scriptPath -Arguments @("-Service", "svc-e")
Assert-Exit -Label "diff-contract exits 2 on breaking change" -Expected 2 -Actual $result.ExitCode -Output $result.Output
Assert-OutputContains -Label "diff-contract reports breaking" -Expected "breaking" -Output $result.Output.ToLower()

$result = Invoke-Capture -Script $scriptPath -Arguments @("-Service", "svc-e", "-ConsumerFiles", "contracts/_consumers/web-app.yaml")
Assert-Exit -Label "diff-contract rejects consumer writes without -Write" -Expected 1 -Actual $result.ExitCode -Output $result.Output
Assert-OutputContains -Label "diff-contract explains consumer write guard" -Expected "requires -Write" -Output $result.Output
Teardown-TestDir

# --- Test: validate-all orchestrates -----------------------------------------

Write-Host ""
Write-Host "=== Test: validate-all ==="
Setup-TestDir

& pwsh -NoProfile -Command "& '$(Join-Path $ScriptDir 'init-registry.ps1')' -Service svc-f -Database db_f" 2>&1 | Out-Null

$scriptPath = Join-Path $ScriptDir "validate-all.ps1"
$result = Invoke-Capture -Script $scriptPath -Arguments @("-BootstrapOk")
Assert-Exit -Label "validate-all exits 0 on clean setup" -Expected 0 -Actual $result.ExitCode -Output $result.Output
Assert-OutputContains -Label "validate-all reports pass" -Expected "pass" -Output $result.Output.ToLower()

Teardown-TestDir

# --- Summary -----------------------------------------------------------------

Write-Host ""
Write-Host "=================================="
Write-Host "  Total: $TestsRun | Pass: $Pass | Fail: $Fail"
Write-Host "=================================="

if ($Fail -gt 0) {
    exit 1
}
Write-Host "  All smoke tests passed."
exit 0
