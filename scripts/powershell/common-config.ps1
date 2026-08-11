# Contract Governance extension: common-config.ps1
# Lightweight loader for contract-governance-config.yml.
# Dot-source this file from other scripts to populate $CG_* variables.
# Falls back to built-in defaults if config file is not found.

function Import-CGConfig {
    # Defaults (must stay in sync with config-template.yml documentation)
    $script:CG_DEFAULT_CONSUMER      = "web-app"
    $script:CG_PROJECT_NAME          = ""
    $script:CG_PENDING_MAX_AGE_DAYS  = 30
    $script:CG_INTERNAL_PATH_PREFIX  = "/internal/"
    $script:CG_INTERNAL_HTTP_TAG     = "内部API"
    $script:CG_INTERNAL_SERVICE_AUTH_MODE = "provider-defined"
    $script:CG_FRONTEND_KEYWORDS     = @()
    $script:CG_RESPONSE_WRAPPER_SCHEMAS = @()
    $script:CG_ALLOWED_TAGS          = @("前端API", "Feign", "内部API", "外部API")
    $script:CG_CONSUMER_STATUSES     = @("PENDING", "RESOLVED", "MISMATCH")
    $script:CG_CHANGELOG_TYPES       = @("breaking", "non-breaking", "deprecated")
    $script:CG_CHANGE_ACK_VALUES     = @("PENDING_ACK", "ACKNOWLEDGED")

    # Locate config file
    $extDir = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
    $configFile = $null
    $installed = Join-Path $extDir "contract-governance-config.yml"
    $template  = Join-Path $extDir "config-template.yml"
    if (Test-Path $installed) { $configFile = $installed }
    elseif (Test-Path $template) { $configFile = $template }

    if (-not $configFile) { return }

    $content = Get-Content $configFile -Raw

    # Parse simple scalar: prefer top-level key, then defaults.<key>.
    function Get-ConfigScalar {
        param([string]$Key)
        if ($content -match "(?m)^$Key\s*:\s*(.+?)(?:\s*#.*)?$") {
            return ($Matches[1].Trim()).Trim('"').Trim("'")
        }
        if ($content -match "(?ms)^defaults\s*:\s*.*?^\s+$Key\s*:\s*(.+?)(?:\s*#.*)?$") {
            return ($Matches[1].Trim()).Trim('"').Trim("'")
        }
        return $null
    }

    # Parse YAML list items under a known key
    function Get-ConfigList {
        param([string]$Key)
        $lines = Get-Content $configFile
        $inBlock = $false
        $items = @()
        $inDefaults = $false
        foreach ($line in $lines) {
            if ($line -match "^$Key\s*:") { $inBlock = $true; continue }
            if ($line -match '^defaults\s*:\s*$') { $inDefaults = $true; continue }
            if ($inDefaults -and $line -match '^[^\s#]') { $inDefaults = $false }
            if ($inDefaults -and $line -match "^\s+$Key\s*:") { $inBlock = $true; continue }
            if ($inBlock -and $line -match '^[^\s#]') { break }
            if ($inBlock -and $line -match '^\s*[A-Za-z0-9_.-]+\s*:') { break }
            if ($inBlock -and $line -match '^\s*-\s*(.+)$') {
                $val = ($Matches[1].Trim()).Trim('"').Trim("'") -replace '\s*#.*$', ''
                if ($val) { $items += $val }
            }
        }
        return $items
    }

    $v = Get-ConfigScalar "default_consumer"
    if ($v) { $script:CG_DEFAULT_CONSUMER = $v }

    $v = Get-ConfigScalar "project_name"
    if ($v) { $script:CG_PROJECT_NAME = $v }

    $v = Get-ConfigScalar "pending_max_age_days"
    if ($null -ne $v -and $v -ne '') { $script:CG_PENDING_MAX_AGE_DAYS = [int]$v }

    $v = Get-ConfigScalar "internal_path_prefix"
    if ($v) { $script:CG_INTERNAL_PATH_PREFIX = $v }

    $v = Get-ConfigScalar "internal_http_tag"
    if ($v) { $script:CG_INTERNAL_HTTP_TAG = $v }

    $v = Get-ConfigScalar "internal_service_auth_mode"
    if ($v) { $script:CG_INTERNAL_SERVICE_AUTH_MODE = $v }

    $v = Get-ConfigScalar "frontend_keywords"
    if ($v) { $script:CG_FRONTEND_KEYWORDS = ($v -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } }

    $v = Get-ConfigScalar "response_wrapper_schemas"
    if ($v) { $script:CG_RESPONSE_WRAPPER_SCHEMAS = ($v -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } }

    $list = Get-ConfigList "allowed_tags"
    if ($list.Count -gt 0) { $script:CG_ALLOWED_TAGS = $list }

    $list = Get-ConfigList "consumer_statuses"
    if ($list.Count -gt 0) { $script:CG_CONSUMER_STATUSES = $list }

    $list = Get-ConfigList "changelog_types"
    if ($list.Count -gt 0) { $script:CG_CHANGELOG_TYPES = $list }

    $list = Get-ConfigList "change_ack_values"
    if ($list.Count -gt 0) { $script:CG_CHANGE_ACK_VALUES = $list }
}

Import-CGConfig
