#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared helpers for db-toolkit verify checks.
#
# Contract for every check script:
#   exit 0  -> PASS
#   exit 3  -> SKIP (genuinely inapplicable here; a reason is mandatory)
#   other   -> FAIL
#
# SKIP is not a way to make a red check quiet. A feature that does not exist
# yet must FAIL, not skip. Skip only when the check cannot apply to this
# machine or profile selection at all, and always say why.

set -euo pipefail

DBTK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DBTK_ROOT

readonly VERIFY_EXIT_SKIP=3

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
    C_DIM=''; C_OFF=''
fi
readonly C_DIM C_OFF

# Informational line inside a check.
vinfo() { printf '      %s%s%s\n' "$C_DIM" "$*" "$C_OFF"; }

# Fail this check with a reason.
vfail() { printf '      FAIL: %s\n' "$*" >&2; exit 1; }

# Skip this check with a mandatory reason.
vskip() {
    [[ -n "${1:-}" ]] || { printf '      SKIP called with no reason\n' >&2; exit 1; }
    printf '      SKIP: %s\n' "$*"
    exit "$VERIFY_EXIT_SKIP"
}

# Docker is required. CLAUDE.md is explicit: if docker is unavailable we stop
# and say so rather than mocking, so this is a FAIL and never a SKIP.
need_docker() {
    docker info >/dev/null 2>&1 \
        || vfail "docker is not running (docker info failed); this harness never mocks it"
}

# Read a variable from .env, falling back to .env.example, then to a default.
env_get() {
    local key="$1" default="${2:-}" file val
    for file in "$DBTK_ROOT/.env" "$DBTK_ROOT/.env.example"; do
        [[ -f "$file" ]] || continue
        val="$(grep -E "^${key}=" "$file" 2>/dev/null | tail -1 | cut -d= -f2- || true)"
        if [[ -n "$val" ]]; then printf '%s\n' "$val"; return 0; fi
    done
    printf '%s\n' "$default"
}

# Is an engine selected by the active profiles?
engine_selected() {
    local engine="$1" profiles
    profiles="${COMPOSE_PROFILES:-$(env_get DBTK_PROFILES 'pg,ui')}"
    [[ ",${profiles}," == *",${engine},"* ]]
}

# Does a local image exist?
image_exists() { docker image inspect "$1" >/dev/null 2>&1; }

# Fully-qualified name for one of our engine images.
#   image_name pg      -> ghcr.io/simtabi/db-toolkit-pg:17
#   image_name mariadb -> ghcr.io/simtabi/db-toolkit-mariadb:11.4
image_name() {
    local engine="$1" prefix ver
    prefix="${DBTK_IMAGE_PREFIX:-ghcr.io/simtabi}"
    case "$engine" in
        pg)      ver="$(env_get DBTK_PG_VERSION 17)" ;;
        mysql)   ver="$(env_get DBTK_MYSQL_VERSION 8.4)" ;;
        mariadb) ver="$(env_get DBTK_MARIADB_VERSION 11.4)" ;;
        cli)     ver="dev" ;;
        *)       vfail "unknown engine: $engine" ;;
    esac
    printf '%s/db-toolkit-%s:%s\n' "$prefix" "$engine" "$ver"
}

# Fail with a clear message when the image a check needs has not been built.
need_image() {
    local img="$1"
    image_exists "$img" || vfail "image not built yet: $img (run: make build)"
}

# Run a throwaway container and always clean it up.
CLEANUP_CONTAINERS=()
cleanup_containers() {
    local c
    for c in "${CLEANUP_CONTAINERS[@]:-}"; do
        [[ -n "$c" ]] && docker rm -f "$c" >/dev/null 2>&1 || true
    done
}
trap cleanup_containers EXIT

track_container() { CLEANUP_CONTAINERS+=("$1"); }

# Wait until a command succeeds, or fail after a budget in seconds.
wait_for() {
    local budget="$1" what="$2"; shift 2
    local i
    for (( i = 0; i < budget; i++ )); do
        if "$@" >/dev/null 2>&1; then return 0; fi
        sleep 1
    done
    vfail "timed out after ${budget}s waiting for: $what"
}

# Require a file to exist, else fail with a useful message.
need_file() {
    [[ -f "$1" ]] || vfail "expected file does not exist yet: ${1#"$DBTK_ROOT"/}"
}

# Require a directory to exist.
need_dir() {
    [[ -d "$1" ]] || vfail "expected directory does not exist yet: ${1#"$DBTK_ROOT"/}"
}

# Run a command, capturing output, and fail with the full output on error.
# Reading the complete error output first is the self-heal rule; this makes
# that output available rather than swallowing it.
run_or_fail() {
    local out rc=0
    out="$("$@" 2>&1)" || rc=$?
    if (( rc != 0 )); then
        printf '      command failed (rc=%s): %s\n' "$rc" "$*" >&2
        printf '      %s\n' "$out" >&2
        exit 1
    fi
    printf '%s' "$out"
}
