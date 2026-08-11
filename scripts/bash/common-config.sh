#!/usr/bin/env bash
# Contract Governance extension: common-config.sh
# Lightweight loader for contract-governance-config.yml.
# Source this file from other scripts to populate CG_* variables.
# Falls back to built-in defaults if config file is not found.

_cg_load_config() {
    # Defaults (must stay in sync with config-template.yml documentation)
    CG_DEFAULT_CONSUMER="web-app"
    CG_PROJECT_NAME=""
    CG_PENDING_MAX_AGE_DAYS="30"
    CG_INTERNAL_PATH_PREFIX="/internal/"
    CG_INTERNAL_HTTP_TAG="内部API"
    CG_INTERNAL_SERVICE_AUTH_MODE="provider-defined"
    CG_FRONTEND_KEYWORDS=""
    CG_RESPONSE_WRAPPER_SCHEMAS=""
    CG_ALLOWED_TAGS_CSV="前端API,Feign,内部API,外部API"
    CG_CONSUMER_STATUSES_CSV="PENDING,RESOLVED,MISMATCH"
    CG_CHANGELOG_TYPES_CSV="breaking,non-breaking,deprecated"
    CG_CHANGE_ACK_VALUES_CSV="PENDING_ACK,ACKNOWLEDGED"

    local config_file=""
    # Try: <extension-dir>/contract-governance-config.yml (installed copy)
    local script_dir
    script_dir="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local ext_dir
    ext_dir="$(CDPATH="" cd "$script_dir/../.." 2>/dev/null && pwd)"
    if [[ -f "$ext_dir/contract-governance-config.yml" ]]; then
        config_file="$ext_dir/contract-governance-config.yml"
    # Try: <extension-dir>/config-template.yml (development fallback)
    elif [[ -f "$ext_dir/config-template.yml" ]]; then
        config_file="$ext_dir/config-template.yml"
    fi

    [[ -z "$config_file" ]] && return 0

    # Parse simple scalar values from YAML. Prefer top-level keys from the
    # extension template, and fall back to the project-local defaults: block.
    local val

    _cg_parse_scalar() {
        local key="$1"
        awk -v key="$key" '
            function clean(value) {
                sub(/^[^:]+:[[:space:]]*/, "", value)
                gsub(/[[:space:]]*#.*/, "", value)
                gsub(/["'"'"']/, "", value)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                return value
            }
            $0 ~ "^" key ":" {
                print clean($0)
                exit
            }
            /^defaults:[[:space:]]*$/ {
                in_defaults=1
                next
            }
            in_defaults && /^[^[:space:]#]/ {
                in_defaults=0
            }
            in_defaults && $0 ~ "^[[:space:]]+" key ":" {
                print clean($0)
                exit
            }
        ' "$config_file"
    }

    val="$(_cg_parse_scalar "default_consumer")"
    [[ -n "$val" ]] && CG_DEFAULT_CONSUMER="$val"

    val="$(_cg_parse_scalar "project_name")"
    [[ -n "$val" ]] && CG_PROJECT_NAME="$val"

    val="$(_cg_parse_scalar "pending_max_age_days")"
    [[ -n "$val" ]] && CG_PENDING_MAX_AGE_DAYS="$val"

    val="$(_cg_parse_scalar "internal_path_prefix")"
    [[ -n "$val" ]] && CG_INTERNAL_PATH_PREFIX="$val"

    val="$(_cg_parse_scalar "internal_http_tag")"
    [[ -n "$val" ]] && CG_INTERNAL_HTTP_TAG="$val"

    val="$(_cg_parse_scalar "internal_service_auth_mode")"
    [[ -n "$val" ]] && CG_INTERNAL_SERVICE_AUTH_MODE="$val"

    val="$(_cg_parse_scalar "frontend_keywords")"
    [[ -n "$val" ]] && CG_FRONTEND_KEYWORDS="$val"

    val="$(_cg_parse_scalar "response_wrapper_schemas")"
    [[ -n "$val" ]] && CG_RESPONSE_WRAPPER_SCHEMAS="$val"

    # Parse simple YAML list items under a known key
    # Usage: _cg_parse_list "allowed_tags"
    _cg_parse_list() {
        local key="$1"
        awk -v key="$key" '
            BEGIN { in_block=0; in_defaults=0; first=1 }
            $0 ~ "^" key ":" { in_block=1; first=1; next }
            /^defaults:[[:space:]]*$/ { in_defaults=1; next }
            in_defaults && /^[^[:space:]#]/ { in_defaults=0 }
            in_defaults && $0 ~ "^[[:space:]]+" key ":" { in_block=1; first=1; next }
            in_block && /^[^[:space:]#]/ { exit }
            in_block && /^[[:space:]]*[A-Za-z0-9_.-]+:[[:space:]]*/ { exit }
            in_block && /^[[:space:]]*-/ {
                sub(/^[[:space:]]*-[[:space:]]*/, "")
                gsub(/[[:space:]]*#.*/, "")
                gsub(/["'"'"']/, "")
                gsub(/^[[:space:]]+|[[:space:]]+$/, "")
                if ($0 != "") {
                    if (!first) printf ","
                    printf "%s", $0
                    first=0
                }
            }
        ' "$config_file"
    }

    local tags_csv
    tags_csv="$(_cg_parse_list "allowed_tags")"
    [[ -n "$tags_csv" ]] && CG_ALLOWED_TAGS_CSV="$tags_csv"

    local statuses_csv
    statuses_csv="$(_cg_parse_list "consumer_statuses")"
    [[ -n "$statuses_csv" ]] && CG_CONSUMER_STATUSES_CSV="$statuses_csv"

    local changelog_types_csv
    changelog_types_csv="$(_cg_parse_list "changelog_types")"
    [[ -n "$changelog_types_csv" ]] && CG_CHANGELOG_TYPES_CSV="$changelog_types_csv"

    local ack_csv
    ack_csv="$(_cg_parse_list "change_ack_values")"
    [[ -n "$ack_csv" ]] && CG_CHANGE_ACK_VALUES_CSV="$ack_csv"

    return 0
}

_cg_load_config
