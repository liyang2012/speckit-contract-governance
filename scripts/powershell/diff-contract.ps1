#!/usr/bin/env pwsh
# Contract Governance extension: diff-contract.ps1
# Detect contract changes via git diff and generate x-changelog entries.
#
# Usage: diff-contract.ps1 -Service <name> [-Base <git-ref>] [-Write] [-ConsumerFiles <file>]
param(
    [string]$Service = "",
    [string]$Base = "",
    [switch]$Write,
    [string[]]$ConsumerFiles = @(),
    [switch]$Help
)
$ErrorActionPreference = 'Stop'

function Show-Usage {
    @"
Usage: diff-contract.ps1 -Service <service-name> [-Base <git-ref>] [-Write] [-ConsumerFiles <file>]

Compare contracts/<service>/api.yaml git version with current, detect operation changes and generate x-changelog.

Options:
  -Service <name>   Service name, e.g. my-service
  -Base <ref>       Git base branch or commit (default HEAD)
  -Write            Append generated x-changelog to api.yaml
  -ConsumerFiles <file>  Sync breaking changes to specified consumer file (repeatable; requires -Write)
  -Help             Show this help
"@
}

if ($Help) { Show-Usage; exit 0 }

if (-not $Service) {
    Write-Error "ERROR: -Service is required"
    Show-Usage
    exit 1
}

if ($ConsumerFiles.Count -gt 0 -and -not $Write) {
    Write-Host "ERROR: -ConsumerFiles modifies consumer contracts and requires -Write" -ForegroundColor Red
    exit 1
}

# --- Locate repo root --------------------------------------------------------

. "$PSScriptRoot/common-utils.ps1"

$repoRoot     = Find-RepoRoot -StartDir $PSScriptRoot
if (-not $repoRoot) { $repoRoot = Get-Location }

$contractsDir = Join-Path $repoRoot "contracts"
$apiFile      = Join-Path $contractsDir "$Service/api.yaml"

if (-not (Test-Path $apiFile)) {
    Write-Error "ERROR: contracts/$Service/api.yaml not found"
    exit 1
}

# --- Extract operations -------------------------------------------------------

function Get-Operations {
    param([string]$FileOrContent)
    $lines = if (Test-Path $FileOrContent) { Get-Content $FileOrContent } else { $FileOrContent -split "`n" }
    $currentPath = ""; $currentMethod = ""; $operationId = ""
    $inOp = $false
    $results = @()

    foreach ($line in $lines) {
        if ($line -match '^\s{2}(/[^:]+):') {
            if ($inOp -and $currentPath -and $currentMethod) {
                $results += [PSCustomObject]@{ Path=$currentPath; Method=$currentMethod; OperationId=$operationId }
            }
            $currentPath = $Matches[1].TrimEnd(':')
            $inOp = $false
            continue
        }
        if ($line -match '^\s{4}(get|post|put|delete|patch|options|head):') {
            if ($inOp -and $currentPath -and $currentMethod) {
                $results += [PSCustomObject]@{ Path=$currentPath; Method=$currentMethod; OperationId=$operationId }
            }
            $currentMethod = $Matches[1]
            $operationId = ""; $inOp = $true
            continue
        }
        if ($inOp -and $line -match '^\s{6}operationId:\s*(.+)$') {
            $operationId = $Matches[1].Trim()
            continue
        }
    }
    if ($inOp -and $currentPath -and $currentMethod) {
        $results += [PSCustomObject]@{ Path=$currentPath; Method=$currentMethod; OperationId=$operationId }
    }
    return $results
}

function Get-ExistingChangelogIds {
    param([string]$File)
    $inCl = $false
    $ids = @()
    foreach ($line in Get-Content $File) {
        if ($line -match '^x-changelog:') { $inCl = $true; continue }
        if ($inCl -and $line -match '^[^[:space:]#]') { $inCl = $false }
        if ($inCl -and $line -match '^\s*-\s*id:\s*(.+)$') {
            $ids += ($Matches[1].Trim()).Trim('"').Trim("'")
        }
    }
    return $ids
}

# --- Get old version from git -------------------------------------------------

$gitRelative = "contracts/$Service/api.yaml"
$baseRef = if ($Base) { $Base } else { "HEAD" }

$savedEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $oldApi = git -C $repoRoot show "${baseRef}:$gitRelative" 2>&1
    $gitOk = $LASTEXITCODE -eq 0
} finally {
    $ErrorActionPreference = $savedEAP
}

if (-not $gitOk -or -not $oldApi) {
    Write-Host "[diff-contract] contracts/$Service/api.yaml not found in git (new contract), skipping change detection"
    exit 0
}

# --- Compare operations -------------------------------------------------------

$oldOps = Get-Operations ($oldApi -join "`n")
$newOps = Get-Operations $apiFile

$oldKeys = $oldOps | ForEach-Object { "$($_.Method) $($_.Path)" } | Sort-Object -Unique
$newKeys = $newOps | ForEach-Object { "$($_.Method) $($_.Path)" } | Sort-Object -Unique

$removedKeys = $oldKeys | Where-Object { $_ -notin $newKeys }
$addedKeys   = $newKeys | Where-Object { $_ -notin $oldKeys }

function Find-OpId {
    param($Ops, [string]$Path, [string]$Method)
    $match = $Ops | Where-Object { $_.Path -eq $Path -and $_.Method -eq $Method } | Select-Object -First 1
    if ($match) { return $match.OperationId }
    return ""
}

$today = Get-Date -Format "yyyy-MM-dd"
$seq = 1

$breakingChanges = @()
foreach ($key in $removedKeys) {
    $method, $path = $key -split ' ', 2
    $opId = Find-OpId $oldOps $path $method
    $changeId = "$today-$($seq.ToString('D3'))"
    $breakingChanges += [PSCustomObject]@{ Id=$changeId; Method=$method; Path=$path; OpId=$opId; Summary="operation removed" }
    $seq++
}

$nonBreakingChanges = @()
foreach ($key in $addedKeys) {
    $method, $path = $key -split ' ', 2
    $opId = Find-OpId $newOps $path $method
    $changeId = "$today-$($seq.ToString('D3'))"
    $nonBreakingChanges += [PSCustomObject]@{ Id=$changeId; Method=$method; Path=$path; OpId=$opId; Summary="new operation" }
    $seq++
}

# Replace path-only changes with the shared schema-aware OpenAPI analyzer.
$semanticAnalyzer = Join-Path $PSScriptRoot "../python/contract_analyzer.py"
if (Test-Path $semanticAnalyzer) {
    $python = $null
    foreach ($candidate in @('python3', 'python')) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) { $python = $command.Source; break }
    }
    if (-not $python) {
        Write-Error "Semantic contract diff requires python3/python"
        exit 1
    }
    & $python -X utf8 -c "import yaml" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Semantic contract diff requires PyYAML; run: $python -m pip install pyyaml"
        exit 1
    }

    $oldTemp = New-TemporaryFile
    try {
        Set-Content -Path $oldTemp -Value ($oldApi -join "`n") -Encoding utf8
        $semanticOutput = & $python -X utf8 $semanticAnalyzer diff --repo-root $repoRoot --service $Service --old-file $oldTemp --new-file $apiFile --format tsv 2>&1
        $semanticRc = $LASTEXITCODE
        if ($semanticRc -ne 0 -and $semanticRc -ne 2) {
            $semanticOutput | ForEach-Object { Write-Host $_ -ForegroundColor Red }
            Write-Error "OpenAPI semantic change detection failed"
            exit 1
        }

        $breakingChanges = @()
        $nonBreakingChanges = @()
        $seq = 1
        foreach ($line in $semanticOutput) {
            if (-not $line) { continue }
            $parts = $line -split "`t", 7
            if ($parts.Count -lt 6) { continue }
            $changeType, $method, $path, $opId, $changeCode, $description = $parts[0..5]
            $impacted = if ($parts.Count -ge 7) { $parts[6] } else { "" }
            if ($impacted) { $description = "$description; impacted Consumers: $impacted" }
            $changeId = "$today-$($seq.ToString('D3'))"
            $entry = [PSCustomObject]@{ Id=$changeId; Method=$method; Path=$path; OpId=$opId; Summary=$description }
            if ($changeType -eq 'breaking') { $breakingChanges += $entry }
            else { $nonBreakingChanges += $entry }
            $seq++
        }
    } finally {
        Remove-Item $oldTemp -Force -ErrorAction SilentlyContinue
    }
}

# --- Deduplicate against existing changelog -----------------------------------

$existingIds = Get-ExistingChangelogIds $apiFile

$breakingChanges    = $breakingChanges    | Where-Object { $_.Id -notin $existingIds }
$nonBreakingChanges = $nonBreakingChanges | Where-Object { $_.Id -notin $existingIds }

if (-not $breakingChanges -and -not $nonBreakingChanges) {
    Write-Host "[diff-contract] contracts/$Service/api.yaml: no new changes detected"
    exit 0
}

# --- Report -------------------------------------------------------------------

Write-Host "[diff-contract] contracts/$Service/api.yaml change detection:"
Write-Host ""

if ($breakingChanges) {
    Write-Host "  Breaking changes ($($breakingChanges.Count)):" -ForegroundColor Red
    foreach ($c in $breakingChanges) {
        $label = "$($c.Method) $($c.Path)"
        if ($c.OpId) { $label += " ($($c.OpId))" }
        Write-Host "    - [$($c.Id)] $label`: $($c.Summary)"
    }
}

if ($nonBreakingChanges) {
    Write-Host "  Non-breaking changes ($($nonBreakingChanges.Count)):" -ForegroundColor Green
    foreach ($c in $nonBreakingChanges) {
        $label = "$($c.Method) $($c.Path)"
        if ($c.OpId) { $label += " ($($c.OpId))" }
        Write-Host "    - [$($c.Id)] $label`: $($c.Summary)"
    }
}

# --- Generate x-changelog YAML ------------------------------------------------

function Build-ChangelogYaml {
    $yaml = ""
    $allChanges = @($breakingChanges | ForEach-Object { @{ Entry=$_; Type="breaking" } }) +
                  @($nonBreakingChanges | ForEach-Object { @{ Entry=$_; Type="non-breaking" } })

    foreach ($item in $allChanges) {
        $c = $item.Entry
        $t = $item.Type
        $yaml += "  - id: `"$($c.Id)`"`n"
        $yaml += "    version: `"`"`n"
        $yaml += "    date: `"$today`"`n"
        $yaml += "    type: $t`n"
        $yaml += "    path: `"$($c.Path)`"`n"
        $yaml += "    method: `"$($c.Method)`"`n"
        $yaml += "    operationId: `"$($c.OpId)`"`n"
        $yaml += "    summary: `"$($c.Summary)`"`n"
    }
    return $yaml
}

$changelogYaml = Build-ChangelogYaml
if (-not $changelogYaml) {
    Write-Host "[diff-contract] All changes already exist in x-changelog"
    exit 0
}

Write-Host ""
Write-Host "  Generated x-changelog:"
Write-Host "  ─────────────────────"
Write-Host "x-changelog:"
Write-Host $changelogYaml
Write-Host "  ─────────────────────"

# --- Write to api.yaml --------------------------------------------------------

if ($Write) {
    $content = Get-Content $apiFile -Raw
    if ($content -match '(?m)^x-changelog:') {
        # Append to existing x-changelog section
        $lines = Get-Content $apiFile
        $output = @()
        $inCl = $false
        $inserted = $false
        foreach ($line in $lines) {
            $output += $line
            if ($line -match '^x-changelog:') { $inCl = $true; continue }
            if ($inCl -and $line -match '^[^[:space:]#]') {
                if (-not $inserted) {
                    $output = $output[0..($output.Count-2)] + ($changelogYaml -split "`n") + $output[($output.Count-1)..($output.Count-1)]
                    $inserted = $true
                }
                $inCl = $false
            }
        }
        if ($inCl -and -not $inserted) {
            $output += ($changelogYaml -split "`n")
        }
        $output | Set-Content -Path $apiFile -Encoding UTF8
    } else {
        # Append new x-changelog section
        Add-Content -Path $apiFile -Value "`nx-changelog:`n$changelogYaml" -Encoding UTF8
    }
    Write-Host "[diff-contract] x-changelog written to contracts/$Service/api.yaml"
}

# --- Consumer changes section -------------------------------------------------

if ($breakingChanges) {
    Write-Host ""
    Write-Host "  Consumer breaking changes (append to _consumers/*.yaml http entries):"
    Write-Host "  ─────────────────────────────────────────────────────────────"
    Write-Host "      changes:"
    foreach ($c in $breakingChanges) {
        Write-Host "        - change_id: `"$($c.Id)`""
        Write-Host "          type: breaking"
        Write-Host "          path: `"$($c.Path)`""
        Write-Host "          method: `"$($c.Method)`""
        Write-Host "          summary: `"$($c.Summary)`""
        Write-Host "          since: `"$today`""
        Write-Host "          ack: PENDING_ACK"
    }
    Write-Host "  ─────────────────────────────────────────────────────────────"
}

# --- Inject consumer changes --------------------------------------------------

function Inject-ConsumerChanges {
    param([string]$ConsumerFile, [string]$OperationId, [string[]]$ChangesLines)

    $lines = Get-Content $ConsumerFile
    $n = $lines.Count

    # Step 1: find the line with matching operationId
    $target = -1
    for ($i = 0; $i -lt $n; $i++) {
        $trimmed = $lines[$i] -replace '^\s+', ''
        if ($trimmed -match '^operationId:') {
            $val = ($trimmed -replace '^operationId:\s*', '').Trim().Trim('"').Trim("'")
            if ($val -eq $OperationId) {
                $target = $i
                break
            }
        }
    }

    if ($target -eq -1) { return }

    # Step 2: find the end of this http entry
    $entryEnd = $n - 1
    for ($i = $target + 1; $i -lt $n; $i++) {
        if ($lines[$i] -match '^\s*$') { continue }
        $leading = 0
        foreach ($c in $lines[$i].ToCharArray()) {
            if ($c -eq ' ') { $leading++ } else { break }
        }
        if ($leading -le 4) {
            $entryEnd = $i - 1
            break
        }
    }
    while ($entryEnd -gt $target -and $lines[$entryEnd] -match '^\s*$') {
        $entryEnd--
    }

    # Step 3: check if there is already a changes: block in this entry
    $hasChanges = $false
    $changesStart = -1
    for ($i = $target; $i -le $entryEnd; $i++) {
        $trimmed = $lines[$i] -replace '^\s+', ''
        if ($trimmed -match '^changes:') {
            $hasChanges = $true
            $changesStart = $i
            break
        }
    }

    # Step 4: build output, injecting changes at the right place
    $output = @()
    if ($hasChanges) {
        # Find end of changes block
        $changesEnd = $entryEnd
        for ($i = $changesStart + 1; $i -le $entryEnd; $i++) {
            if ($lines[$i] -match '^\s*$') { continue }
            $leading = 0
            foreach ($c in $lines[$i].ToCharArray()) {
                if ($c -eq ' ') { $leading++ } else { break }
            }
            $trimmed = $lines[$i] -replace '^\s+', ''
            if ($leading -le 6 -and $trimmed -notmatch '^- *change_id:') {
                $changesEnd = $i - 1
                break
            }
        }
        for ($i = 0; $i -le $changesEnd; $i++) { $output += $lines[$i] }
        foreach ($cl in $ChangesLines) { $output += $cl }
        for ($i = $changesEnd + 1; $i -lt $n; $i++) { $output += $lines[$i] }
    } else {
        for ($i = 0; $i -le $entryEnd; $i++) { $output += $lines[$i] }
        $output += "      changes:"
        foreach ($cl in $ChangesLines) { $output += $cl }
        for ($i = $entryEnd + 1; $i -lt $n; $i++) { $output += $lines[$i] }
    }

    $output | Set-Content -Path $ConsumerFile -Encoding UTF8
}

if ($ConsumerFiles -and $breakingChanges) {
    foreach ($cf in $ConsumerFiles) {
        if (-not (Test-Path $cf)) {
            Write-Warning "[diff-contract] Consumer file not found: $cf"
            continue
        }
        foreach ($c in $breakingChanges) {
            if (-not $c.OpId) { continue }
            if (-not (Select-String -Path $cf -Pattern "operationId:.*$($c.OpId)" -Quiet)) { continue }

            $changesBlock = @(
                "        - change_id: `"$($c.Id)`""
                "          type: breaking"
                "          path: `"$($c.Path)`""
                "          method: `"$($c.Method)`""
                "          summary: `"$($c.Summary)`""
                "          since: `"$today`""
                "          ack: PENDING_ACK"
            )

            Inject-ConsumerChanges $cf $c.OpId $changesBlock
            Write-Host "[diff-contract] Injected breaking change $($c.Id) into $cf under $($c.OpId)"
        }
    }
}

# --- Exit code ----------------------------------------------------------------

if ($breakingChanges) { exit 2 }
exit 0
