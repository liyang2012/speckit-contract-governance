# Contract Governance extension: common-utils.ps1
# Shared utility functions for repo root detection and feature dir resolution.
# Dot-source this file from other scripts: . "$PSScriptRoot/common-utils.ps1"

function Find-RepoRoot {
    param([string]$StartDir)
    $current = Resolve-Path $StartDir
    while ($true) {
        if (Test-Path (Join-Path $current '.specify')) { return $current }
        $parent = Split-Path $current -Parent
        if ($parent -eq $current) { return $null }
        $current = $parent
    }
}

function Resolve-FeatureDir {
    param(
        [string]$RepoRoot,
        [string]$FeatureDirArg = "",
        [string]$SpecsSubdir = "specs"
    )
    # 1. Explicit argument
    if ($FeatureDirArg) {
        $path = $FeatureDirArg
        if (-not [System.IO.Path]::IsPathRooted($path)) { $path = Join-Path $RepoRoot $path }
        if (Test-Path $path -PathType Container) { return (Resolve-Path $path).Path }
        return $path
    }
    # 2. Environment variable
    if ($env:SPECIFY_FEATURE_DIRECTORY) {
        $path = $env:SPECIFY_FEATURE_DIRECTORY
        if (-not [System.IO.Path]::IsPathRooted($path)) { $path = Join-Path $RepoRoot $path }
        if (Test-Path $path -PathType Container) { return (Resolve-Path $path).Path }
        return $path
    }
    # 3. Newest subdirectory under specs/
    $specsDir = Join-Path $RepoRoot $SpecsSubdir
    if (Test-Path $specsDir -PathType Container) {
        $dirs = Get-ChildItem $specsDir -Directory | Sort-Object Name
        if ($dirs) { return $dirs[-1].FullName }
    }
    return $null
}
