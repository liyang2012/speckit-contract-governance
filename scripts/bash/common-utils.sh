#!/usr/bin/env bash
# Contract Governance extension: common-utils.sh
# Shared utility functions used by validate-boundary.sh, validate-registry.sh, etc.
# Source this file after common-config.sh to get repo root detection and feature dir resolution.

# ─── Repo root detection ─────────────────────────────────────────────────────

# Find the nearest ancestor (or self) containing a .specify directory.
find_specify_root() {
    local dir="${1:-$(pwd)}"
    dir="$(cd -- "$dir" 2>/dev/null && pwd)" || return 1
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/.specify" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# Default get_repo_root: start from the script's own location.
get_repo_root() {
    local script_dir="${1:-$(pwd)}"
    find_specify_root "$script_dir" || pwd
}

# Default read_feature_json_feature_directory: return empty (caller handles fallback).
read_feature_json_feature_directory() {
    printf '%s' ''
}

# ─── Feature directory resolution ────────────────────────────────────────────

# Normalize a raw path: resolve relative paths against REPO_ROOT, canonicalize if it's a dir.
# Usage: normalize_feature_dir "<raw-path>" "<repo-root>"
normalize_feature_dir() {
    local raw="$1"
    local repo_root="${2:-$(pwd)}"
    [[ -z "$raw" ]] && return 1
    [[ "$raw" != /* ]] && raw="$repo_root/$raw"
    if [[ -d "$raw" ]]; then
        (cd "$raw" && pwd -P)
        return 0
    fi
    printf '%s\n' "$raw"
}

# Resolve the active feature directory from (in order):
#   1. Explicit --feature-dir argument
#   2. $SPECIFY_FEATURE_DIRECTORY env var
#   3. .specify/feature.json (if readable)
#   4. Newest subdirectory under specs/
# Usage: resolve_feature_dir "<feature-dir-arg>" "<repo-root>"
resolve_feature_dir() {
    local feature_dir_arg="$1"
    local repo_root="$2"

    if [[ -n "$feature_dir_arg" ]]; then
        normalize_feature_dir "$feature_dir_arg" "$repo_root"
        return 0
    fi

    if [[ -n "${SPECIFY_FEATURE_DIRECTORY:-}" ]]; then
        normalize_feature_dir "$SPECIFY_FEATURE_DIRECTORY" "$repo_root"
        return 0
    fi

    local from_json=""
    from_json="$(read_feature_json_feature_directory "$repo_root" 2>/dev/null || true)"
    if [[ -n "$from_json" ]]; then
        normalize_feature_dir "$from_json" "$repo_root"
        return 0
    fi

    local newest=""
    if [[ -d "$repo_root/specs" ]]; then
        newest="$(find "$repo_root/specs" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort | tail -n 1 || true)"
    fi
    if [[ -n "$newest" ]]; then
        normalize_feature_dir "$newest" "$repo_root"
        return 0
    fi

    return 1
}

# ─── String helpers ──────────────────────────────────────────────────────────

# Trim leading/trailing whitespace and strip inline comments from a YAML scalar value.
trim_value() {
    local value="$1"
    value="${value%%#*}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

# Strip surrounding single or double quotes from a value.
strip_quotes() {
    local value="$1"
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    printf '%s' "$value"
}
