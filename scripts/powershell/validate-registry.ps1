#!/usr/bin/env pwsh
# Contract Governance extension: validate-registry.ps1
# Validate microservice contract registry and frontend Consumer Contracts.
#
# Usage: validate-registry.ps1 [-Service <name>] [-Consumer <name>] [-FeatureDir <path>] [-BootstrapOk]
param(
    [string]$Service = "",
    [string]$Consumer = "",
    [string]$FeatureDir = "",
    [switch]$BootstrapOk,
    [switch]$Help
)
$ErrorActionPreference = 'Stop'

function Show-Usage {
    @"
Usage: validate-registry.ps1 [-Service <name>] [-Consumer <name>] [-FeatureDir <path>] [-BootstrapOk]

Validate contracts/ microservice contract registry and frontend Consumer Contracts.

Options:
  -Service <name>     Only validate the specified service
  -Consumer <name>    Only validate the specified consumer
  -FeatureDir <path>  Use specified feature's plan.md for microservice scope detection
  -BootstrapOk        Allow skip when contracts/ does not exist
  -Help               Show this help
"@
}

if ($Help) { Show-Usage; exit 0 }

$strict = -not $BootstrapOk

# Load configurable values from contract-governance-config.yml
. "$PSScriptRoot/common-config.ps1"

# --- Locate repo root --------------------------------------------------------

. "$PSScriptRoot/common-utils.ps1"

$repoRoot     = Find-RepoRoot -StartDir $PSScriptRoot
if (-not $repoRoot) { $repoRoot = Get-Location }

$contractsDir = Join-Path $repoRoot "contracts"
$registryDir  = Join-Path $contractsDir "_registry"
$consumersDir = Join-Path $contractsDir "_consumers"

$failures = @()
$warnings = @()

# --- Resolve feature dir -----------------------------------------------------

$planFile = $null
if ($FeatureDir) {
    $p = if ([System.IO.Path]::IsPathRooted($FeatureDir)) { $FeatureDir } else { Join-Path $repoRoot $FeatureDir }
    $pf = Join-Path $p "plan.md"
    if (Test-Path $pf) { $planFile = $pf }
} elseif ($env:SPECIFY_FEATURE_DIRECTORY) {
    $pf = Join-Path $env:SPECIFY_FEATURE_DIRECTORY "plan.md"
    if (Test-Path $pf) { $planFile = $pf }
}

function Plan-MentionsMicroservice {
    if (-not $planFile) { return $false }
    return Test-ContentMatches $planFile @("微服务", "服务边界", "Feign", "RocketMQ", "MQ", "contracts/", "api\.yaml", "_consumers", "消费契约", "Provider", "Consumer", "PENDING", "RESOLVED", "MISMATCH", "跨服务", "直连数据库")
}

function Plan-AllowsSharedFrontendFeign {
    if (-not $planFile) { return $false }
    return Test-ContentMatches $planFile @("共用接口例外", "前端API.*Feign.*例外", "Feign.*前端API.*例外")
}

function Test-ContentMatches {
    param([string]$File, [string[]]$Patterns)
    foreach ($p in $Patterns) {
        if (Select-String -Path $File -Pattern $p -CaseSensitive:$false -Quiet) { return $true }
    }
    return $false
}

# --- Early exit for missing contracts/ ----------------------------------------

if (-not (Test-Path $contractsDir)) {
    if ($Service -and $strict) {
        $failures += "Specified --Service $Service but repo lacks contracts/; run init-registry.ps1 -Service $Service first"
    } elseif ($Consumer -and $strict) {
        $failures += "Specified --Consumer $Consumer but repo lacks contracts/; run init-consumer.ps1 -Consumer $Consumer first"
    } elseif ((Plan-MentionsMicroservice) -and $strict) {
        $failures += "Current feature involves microservices/contracts but repo lacks contracts/; run init-registry first"
    } else {
        Write-Host "[contract-governance] contracts/ not found, bootstrap mode allowed, skipping registry validation"
        exit 0
    }
}

# --- Structural checks --------------------------------------------------------

if (Test-Path $contractsDir) {
    if (-not (Test-Path (Join-Path $contractsDir "SERVICE-MAP.md"))) { $failures += "Missing contracts/SERVICE-MAP.md" }
    if (-not (Test-Path $registryDir)) { $failures += "Missing contracts/_registry/" }
}

# --- Gather files -------------------------------------------------------------

$registryFiles = @()
if ($failures.Count -eq 0 -and (Test-Path $registryDir)) {
    if ($Service) {
        $f = Join-Path $registryDir "$Service.yaml"
        if (Test-Path $f) { $registryFiles = @($f) }
        else { $failures += "Service registry not found: contracts/_registry/$Service.yaml" }
    } else {
        $registryFiles = @(Get-ChildItem $registryDir -Filter "*.yaml" | Select-Object -ExpandProperty FullName)
        if ($registryFiles.Count -eq 0) { $failures += "No service registry files in contracts/_registry/" }
    }
}

$consumerFiles = @()
if (Test-Path $contractsDir) {
    if ($Consumer) {
        $f = Join-Path $consumersDir "$Consumer.yaml"
        if (Test-Path $f) { $consumerFiles = @($f) }
        else { $failures += "Consumer contract not found: contracts/_consumers/$Consumer.yaml" }
    } elseif (Test-Path $consumersDir) {
        $consumerFiles = @(Get-ChildItem $consumersDir -Filter "*.yaml" | Select-Object -ExpandProperty FullName)
    }
}

# --- YAML helpers -------------------------------------------------------------

function Get-YamlScalar {
    param([string]$File, [string]$Key)
    $line = Select-String -Path $File -Pattern "^\s*$Key\s*:" | Select-Object -First 1
    if (-not $line) { return "" }
    $val = ($line.Line -replace "^\s*$Key\s*:\s*", "") -replace '\s*#.*$', ''
    $val = $val.Trim().Trim('"').Trim("'")
    return $val
}

function Get-ApiPath {
    param([string]$File)
    $inCf = $false
    foreach ($line in Get-Content $File) {
        if ($line -match '^\s*contract_files:') { $inCf = $true; continue }
        if ($inCf -and $line -match '^[^\s]') { $inCf = $false }
        if ($inCf -and $line -match '^\s+api:\s*(.+)$') {
            return ($Matches[1] -replace '\s*#.*$', '').Trim().Trim('"').Trim("'")
        }
    }
    return ""
}

function Get-OpenApiOperations {
    param([string]$File)
    $currentPath = ""; $currentMethod = ""; $operationId = ""; $tags = ""
    $inOp = $false; $inTags = $false
    $results = @()

    foreach ($line in Get-Content $File) {
        if ($line -match '^\s{2}(/[^:]+):') {
            if ($inOp -and $currentPath -and $currentMethod) {
                $results += [PSCustomObject]@{ Path=$currentPath; Method=$currentMethod; OperationId=$operationId; Tags=$tags }
            }
            $currentPath = $Matches[1].TrimEnd(':')
            $inOp = $false; $inTags = $false
            continue
        }
        if ($line -match '^\s{4}(get|post|put|delete|patch|options|head):') {
            if ($inOp -and $currentPath -and $currentMethod) {
                $results += [PSCustomObject]@{ Path=$currentPath; Method=$currentMethod; OperationId=$operationId; Tags=$tags }
            }
            $currentMethod = $Matches[1]
            $operationId = ""; $tags = ""; $inOp = $true; $inTags = $false
            continue
        }
        if ($inOp -and $line -match '^\s{6}operationId:\s*(.+)$') {
            $operationId = $Matches[1].Trim()
            continue
        }
        if ($inOp -and $line -match '^\s{6}tags:\s*(.*)$') {
            $tagVal = $Matches[1].Trim()
            $inTags = ($tagVal -eq "")
            if ($tagVal) { $tags = $tagVal }
            continue
        }
        if ($inOp -and $inTags -and $line -match '^\s{8}-\s*(.+)$') {
            $t = $Matches[1].Trim()
            $tags = if ($tags) { "$tags,$t" } else { $t }
            continue
        }
    }
    if ($inOp -and $currentPath -and $currentMethod) {
        $results += [PSCustomObject]@{ Path=$currentPath; Method=$currentMethod; OperationId=$operationId; Tags=$tags }
    }
    return $results
}

function Get-XChangelogEntries {
    param([string]$File)
    $inCl = $false; $inEntry = $false
    $id = ""; $typeVal = ""; $dateVal = ""; $summaryVal = ""
    $results = @()
    foreach ($line in Get-Content $File) {
        if ($line -match '^x-changelog:') { $inCl = $true; continue }
        if ($inCl -and $line -match '^[^[:space:]#]') { $inCl = $false }
        if ($inCl -and $line -match '^\s*-\s*id:\s*(.+)$') {
            if ($inEntry -and $id) {
                $results += [PSCustomObject]@{ Id=$id; Type=$typeVal; Date=$dateVal; Summary=$summaryVal }
            }
            $id = ($Matches[1].Trim()).Trim('"').Trim("'")
            $typeVal = ""; $dateVal = ""; $summaryVal = ""; $inEntry = $true
            continue
        }
        if ($inCl -and $inEntry) {
            if ($line -match '^\s+type:\s*(.+)$')    { $typeVal    = $Matches[1].Trim(); continue }
            if ($line -match '^\s+date:\s*(.+)$')    { $dateVal    = ($Matches[1].Trim()).Trim('"').Trim("'"); continue }
            if ($line -match '^\s+summary:\s*(.+)$') { $summaryVal = ($Matches[1].Trim()).Trim('"').Trim("'"); continue }
        }
    }
    if ($inEntry -and $id) {
        $results += [PSCustomObject]@{ Id=$id; Type=$typeVal; Date=$dateVal; Summary=$summaryVal }
    }
    return $results
}

# --- Validate x-changelog -----------------------------------------------------

function Validate-XChangelog {
    param([string]$ServiceName, [string]$ApiFile)
    $content = Get-Content $ApiFile -Raw
    if ($content -notmatch '(?m)^x-changelog:') { return }

    $entries = Get-XChangelogEntries $ApiFile
    $pendingCount = 0
    foreach ($e in $entries) {
        if (-not $e.Type) { $script:failures += "$ServiceName/api.yaml x-changelog entry $e.Id missing type" }
        if ($e.Type -and $e.Type -notin $CG_CHANGELOG_TYPES) {
            $script:failures += "$ServiceName/api.yaml x-changelog entry $e.Id invalid type: $($e.Type) (only $($CG_CHANGELOG_TYPES -join '/') allowed)"
        }
        if (-not $e.Date) { $script:failures += "$ServiceName/api.yaml x-changelog entry $e.Id missing date" }
        if (-not $e.Summary) { $script:warnings += "$ServiceName/api.yaml x-changelog entry $e.Id missing summary" }
        if ($e.Type -eq "breaking") { $pendingCount++ }
    }
    if ($pendingCount -gt 0) {
        Write-Host "[contract-governance] Note: $ServiceName/api.yaml has $pendingCount breaking change(s) in x-changelog; consumers need to review"
    }
}

# --- Validate API file --------------------------------------------------------

function Validate-ApiFile {
    param([string]$ServiceName, [string]$ApiFile)
    if (-not (Test-Path $ApiFile)) { $script:failures += "$ServiceName api.yaml does not exist: $ApiFile"; return }

    $content = Get-Content $ApiFile -Raw
    if ($content -notmatch '(?m)^openapi:') { $script:failures += "$ServiceName/api.yaml missing openapi version" }
    if ($content -notmatch '(?m)^paths:')   { $script:failures += "$ServiceName/api.yaml missing paths" }
    if ($content -notmatch '(?m)^components:') { $script:failures += "$ServiceName/api.yaml missing components" }

    Validate-XChangelog $ServiceName $ApiFile

    if ($content -notmatch '(?m)^paths:\s*\{\}') {
        if ($content -notmatch 'operationId:') { $script:failures += "$ServiceName/api.yaml has non-empty paths but no operationId" }
        if ($content -notmatch '/api/v[0-9]+/' -and $content -notmatch [regex]::Escape($CG_INTERNAL_PATH_PREFIX)) {
            $script:failures += "$ServiceName/api.yaml has non-empty paths but neither /api/vN/ nor $CG_INTERNAL_PATH_PREFIX internal paths"
        }

        $ops = Get-OpenApiOperations $ApiFile
        foreach ($op in $ops) {
            $label = "$ServiceName/api.yaml $($op.Method) $($op.Path)"
            if ($op.OperationId) { $label += " ($($op.OperationId))" }

            if (-not $op.Tags) {
                $script:failures += "$label missing tags; must declare at least one of: $($CG_ALLOWED_TAGS -join ' / ')"
                continue
            }
            $tagsPattern = ($CG_ALLOWED_TAGS -join '|')
            if ($op.Tags -notmatch $tagsPattern) {
                $script:failures += "$label tags must include at least one of: $($CG_ALLOWED_TAGS -join ' / '); current: $($op.Tags)"
            }
            if ($op.Tags -match 'Feign' -and $op.Path -notlike "*$CG_INTERNAL_PATH_PREFIX*") {
                $script:failures += "$label tagged Feign but path does not contain $CG_INTERNAL_PATH_PREFIX; Feign endpoints must not be exposed to frontend"
            }
            if ($op.Tags -match [regex]::Escape($CG_INTERNAL_HTTP_TAG) -and $op.Path -notlike "*$CG_INTERNAL_PATH_PREFIX*") {
                $script:failures += "$label tagged $CG_INTERNAL_HTTP_TAG but path does not contain $CG_INTERNAL_PATH_PREFIX; internal HTTP endpoints must not be exposed to frontend"
            }
            if ($op.Tags -match '前端API' -and $op.Tags -match 'Feign') {
                if (-not (Plan-AllowsSharedFrontendFeign)) {
                    $script:failures += "$label tagged both 前端API and Feign; shared use requires plan.md exception declaration"
                }
            }
            if ($op.Tags -match '前端API' -and $op.Tags -match [regex]::Escape($CG_INTERNAL_HTTP_TAG)) {
                $script:failures += "$label tagged both 前端API and $CG_INTERNAL_HTTP_TAG; internal HTTP operations must not be shared with frontend"
            }
        }
    }
}

# --- Validate registry file ---------------------------------------------------

function Validate-RegistryFile {
    param([string]$RegistryFile)
    $fileService = [System.IO.Path]::GetFileNameWithoutExtension($RegistryFile)

    $svc = Get-YamlScalar $RegistryFile "service"
    if (-not $svc) { $script:failures += "$fileService registry missing service field" }
    if ($svc -and $svc -ne $fileService) { $script:failures += "$RegistryFile service=$svc does not match filename $fileService" }

    $db = Get-YamlScalar $RegistryFile "database"
    if (-not $db) { $script:failures += "$fileService registry missing database field" }

    $content = Get-Content $RegistryFile -Raw
    if ($content -notmatch '(?m)^\s*contract_files:') { $script:failures += "$fileService registry missing contract_files" }
    if ($content -notmatch '(?m)^\s*consumes:')       { $script:failures += "$fileService registry missing consumes" }
    if ($content -notmatch '(?m)^\s*feign:')           { $script:failures += "$fileService registry missing consumes.feign" }
    if ($content -notmatch '(?m)^\s*http:')            { $script:failures += "$fileService registry missing consumes.http" }
    if ($content -notmatch '(?m)^\s*mq:')              { $script:failures += "$fileService registry missing consumes.mq" }

    $apiPath = Get-ApiPath $RegistryFile
    if (-not $apiPath) {
        $script:failures += "$fileService registry missing contract_files.api"
    } else {
        if ($apiPath -notlike "$fileService/*") {
            $script:failures += "$fileService registry contract_files.api must point to own service directory; current: $apiPath"
        }
        Validate-ApiFile $fileService (Join-Path $contractsDir $apiPath)
    }

    # Check consumer statuses
    $statusLines = Select-String -Path $RegistryFile -Pattern "^\s*status:" | ForEach-Object { $_.Line }
    foreach ($sl in $statusLines) {
        $status = ($sl -replace '.*status:\s*', '').Trim().Trim('"').Trim("'")
        if ($status -and $status -notin $CG_CONSUMER_STATUSES) {
            $script:failures += "$fileService registry uses invalid Consumer status: $status"
        }
    }

    if ($content -match 'status:\s*[''"]?MISMATCH') {
        if ($content -notmatch 'mismatches:') { $script:failures += "$fileService registry has MISMATCH status but missing mismatches records" }
        if ($content -notmatch 'resolution:') { $script:failures += "$fileService registry has MISMATCH but missing resolution" }
    }
}

# --- Validate consumer file ---------------------------------------------------

function Validate-ConsumerFile {
    param([string]$ConsumerFile)
    $fileConsumer = [System.IO.Path]::GetFileNameWithoutExtension($ConsumerFile)

    $consumer = Get-YamlScalar $ConsumerFile "consumer"
    if (-not $consumer) { $script:failures += "$fileConsumer consumer contract missing consumer field" }
    if ($consumer -and $consumer -ne $fileConsumer) { $script:failures += "$ConsumerFile consumer=$consumer does not match filename $fileConsumer" }

    $ctype = Get-YamlScalar $ConsumerFile "type"
    if (-not $ctype) { $script:failures += "$fileConsumer consumer contract missing type field" }
    if ($ctype -and $ctype -ne "frontend") { $script:failures += "$fileConsumer consumer contract type must be frontend; current: $ctype" }

    $content = Get-Content $ConsumerFile -Raw
    if ($content -notmatch '(?m)^\s*consumes:') { $script:failures += "$fileConsumer consumer contract missing consumes" }
    if ($content -notmatch '(?m)^\s*http:')     { $script:failures += "$fileConsumer consumer contract missing consumes.http" }

    # Check statuses
    $statusLines = Select-String -Path $ConsumerFile -Pattern "^\s*status:" | ForEach-Object { $_.Line }
    foreach ($sl in $statusLines) {
        $status = ($sl -replace '.*status:\s*', '').Trim().Trim('"').Trim("'")
        if ($status -and $status -notin $CG_CONSUMER_STATUSES) {
            $script:failures += "$fileConsumer consumer contract uses invalid status: $status"
        }
    }

    if ($content -match 'status:\s*[''"]?MISMATCH') {
        if ($content -notmatch 'mismatches:') { $script:failures += "$fileConsumer consumer contract has MISMATCH but missing mismatches" }
        if ($content -notmatch 'resolution:') { $script:failures += "$fileConsumer consumer contract has MISMATCH but missing resolution" }
    }

    # Check http entries: provider + operationId + status
    # Simplified: parse via regex for provider/operationId/status blocks
    $providers = Select-String -Path $ConsumerFile -Pattern "^\s{4}-\s*provider:\s*(.+)$" | ForEach-Object { ($Matches[1].Trim()).Trim('"').Trim("'") }
    $opIds     = Select-String -Path $ConsumerFile -Pattern "^\s+operationId:\s*(.+)$" | ForEach-Object { ($Matches[1].Trim()).Trim('"').Trim("'") }
    $statuses  = Select-String -Path $ConsumerFile -Pattern "^\s+status:\s*(.+)$" | ForEach-Object { ($Matches[1].Trim()).Trim('"').Trim("'") }

    $hasEntries = $false
    for ($i = 0; $i -lt $providers.Count; $i++) {
        $hasEntries = $true
        $prov = $providers[$i]
        $opid = if ($i -lt $opIds.Count) { $opIds[$i] } else { "" }
        $stat = if ($i -lt $statuses.Count) { $statuses[$i] } else { "" }

        if (-not $prov) { $script:failures += "$fileConsumer consumer contract has http entry without provider"; continue }
        if (-not $opid) { $script:failures += "$fileConsumer consumer contract $prov missing operationId" }
        if (-not $stat) { $script:failures += "$fileConsumer consumer contract $prov.$opid missing status" }

        if ($stat -and $stat -notin $CG_CONSUMER_STATUSES) {
            $script:failures += "$fileConsumer consumer contract $prov.$opid invalid status: $stat"
        }

        # Check provider is registered
        $provRegistry = Join-Path $registryDir "$prov.yaml"
        $provApi      = Join-Path $contractsDir "$prov/api.yaml"
        if (-not (Test-Path $provRegistry)) { $script:failures += "$fileConsumer consumer contract references unregistered Provider: contracts/_registry/$prov.yaml" }
        if (-not (Test-Path $provApi))      { $script:failures += "$fileConsumer consumer contract references non-existent Provider API: contracts/$prov/api.yaml"; continue }
        if (-not $opid) { continue }

        # Check operationId tags
        if (Test-Path $provApi) {
            $ops = Get-OpenApiOperations $provApi
            $matchedOp = $ops | Where-Object { $_.OperationId -eq $opid } | Select-Object -First 1
            if (-not $matchedOp) {
                if ($stat -eq "RESOLVED") { $script:failures += "$fileConsumer consumer contract marks $prov.$opid as RESOLVED but Provider api.yaml does not declare this operationId" }
                continue
            }
            if ($matchedOp.Tags -match 'Feign') {
                if ($stat -eq "MISMATCH") {
                    $script:warnings += "$fileConsumer consumer contract records MISMATCH for Feign operation $prov.$opid; ensure resolution includes migration plan"
                } else {
                    $script:failures += "$fileConsumer consumer contract must not consume Feign operation: $prov.$opid"
                }
            } elseif ($matchedOp.Tags -notmatch '前端API|外部API') {
                $script:failures += "$fileConsumer consumer contract $prov.$opid not tagged 前端API or 外部API; current tags: $($matchedOp.Tags)"
            }
        }
    }

    if (-not $hasEntries) { $script:warnings += "$fileConsumer consumer contract has no consumes.http entries yet" }
}

# --- Run validations ----------------------------------------------------------

if ($failures.Count -eq 0 -and $registryFiles.Count -gt 0) {
    foreach ($rf in $registryFiles) { Validate-RegistryFile $rf }
}
if ($failures.Count -eq 0 -and $consumerFiles.Count -gt 0) {
    foreach ($cf in $consumerFiles) { Validate-ConsumerFile $cf }
}

# Check plan cross-service DB rule
if ($planFile -and (Plan-MentionsMicroservice)) {
    $planContent = Get-Content $planFile -Raw
    if ($planContent -notmatch '禁止跨服务直连数据库|禁止跨库|不得.*直连数据库|独立数据库|跨服务.*(Feign|MQ|接口|契约)') {
        $failures += "Current plan involves microservice contracts but does not declare prohibition of cross-service direct DB access"
    }
}

# Run the shared YAML/OpenAPI semantic analyzer for schema-level checks.
$semanticAnalyzer = Join-Path $PSScriptRoot "../python/contract_analyzer.py"
if ($failures.Count -eq 0 -and (Test-Path $semanticAnalyzer)) {
    $python = $null
    foreach ($candidate in @('python3', 'python')) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) { $python = $command.Source; break }
    }
    if (-not $python) {
        $failures += "Semantic contract validation requires python3/python"
    } else {
        & $python -c "import yaml" 2>$null
        if ($LASTEXITCODE -ne 0) {
            $failures += "Semantic contract validation requires PyYAML; run: $python -m pip install pyyaml"
        } else {
            $semanticArgs = @($semanticAnalyzer, 'validate', '--repo-root', $repoRoot)
            if ($Service) { $semanticArgs += @('--service', $Service) }
            if ($Consumer) { $semanticArgs += @('--consumer', $Consumer) }
            $semanticOutput = & $python @semanticArgs 2>&1
            $semanticRc = $LASTEXITCODE
            if ($semanticOutput) { $semanticOutput | ForEach-Object { Write-Host $_ } }
            if ($semanticRc -eq 1) {
                $failures += "YAML/OpenAPI semantic validation failed"
            } elseif ($semanticRc -gt 2) {
                $failures += "YAML/OpenAPI semantic validation exited unexpectedly (exit=$semanticRc)"
            }
        }
    }
}

foreach ($w in $warnings) { Write-Warning "[contract-governance] Warning: $w" }

if ($failures) {
    Write-Error "[contract-governance] Registry validation failed"
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    Write-Host "[contract-governance] New projects: run init-registry.ps1 -Service <name>; frontend: run init-consumer.ps1 -Consumer <name>"
    exit 1
}

Write-Host "[contract-governance] Registry validation passed"
