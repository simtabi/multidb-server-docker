#!/usr/bin/env bash
# shellcheck shell=bash
#
# The engine descriptor loader (SPEC section 22.1).
#
# Everything generic in the toolkit reads engines through this file. The rule
# that keeps the abstraction real: if something can be expressed in a
# descriptor, it must NOT appear as an `if engine == ...` branch anywhere else.
#
# Usage:
#   source scripts/engine-lib.sh
#   engine_load pg              # populates MMDB_ENGINE_* for that engine
#   for e in $(engine_list); do ... done

# Deliberately no `set -e` here: this is sourced by scripts that set their own
# options, and overriding a caller's shell settings from a library is rude.

MMDB_ENGINES_DIR="${MMDB_ENGINES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../engines" 2>/dev/null && pwd)}"

# Keys every descriptor must declare. A missing one is a descriptor bug, and
# check 31 fails on it rather than letting the gap surface as a confusing
# runtime error three layers away.
# shellcheck disable=SC2034  # consumed by scripts that source this library
MMDB_ENGINE_REQUIRED_KEYS="
MMDB_ENGINE_NAME
MMDB_ENGINE_TITLE
MMDB_ENGINE_FAMILY
MMDB_ENGINE_PARADIGM
MMDB_ENGINE_VERSIONS
MMDB_ENGINE_DEFAULT_VERSION
MMDB_ENGINE_PORT
MMDB_ENGINE_DATA_DIR
MMDB_ENGINE_USER
MMDB_ENGINE_ROOT_SECRET
MMDB_ENGINE_PING
MMDB_ENGINE_CLIENT
MMDB_ENGINE_DUMP
MMDB_ENGINE_RESTORE
MMDB_ENGINE_BACKUP_EXT
MMDB_ENGINE_AUTH_METHOD
MMDB_ENGINE_POOLING
MMDB_ENGINE_LICENSE
MMDB_ENGINE_OSI_APPROVED
"

# Every engine directory that carries a descriptor, in a stable order.
engine_list() {
    local d
    for d in "$MMDB_ENGINES_DIR"/*/engine.conf; do
        [ -e "$d" ] || continue
        # The engine's NAME, not its directory: the directory is "postgres"
        # while the engine everything else refers to is "pg".
        grep -m1 '^MMDB_ENGINE_NAME=' "$d" | cut -d= -f2- | tr -d '"'
    done | sort
}

# Map an engine name back to its descriptor path.
engine_conf_path() {
    local want="$1" d name
    for d in "$MMDB_ENGINES_DIR"/*/engine.conf; do
        [ -e "$d" ] || continue
        name="$(grep -m1 '^MMDB_ENGINE_NAME=' "$d" | cut -d= -f2- | tr -d '"')"
        if [ "$name" = "$want" ]; then printf '%s\n' "$d"; return 0; fi
    done
    return 1
}

# Load one engine's descriptor into the environment.
#
# Previously loaded MMDB_ENGINE_* values are cleared first, so loading engine B
# after engine A cannot leave A's optional keys visible and silently wrong.
engine_load() {
    local want="$1" conf key
    conf="$(engine_conf_path "$want")" || {
        printf 'engine-lib: no descriptor for engine "%s" in %s\n' "$want" "$MMDB_ENGINES_DIR" >&2
        return 1
    }

    for key in $(set | grep -oE '^MMDB_ENGINE_[A-Z0-9_]+' | sort -u); do
        case "$key" in
            MMDB_ENGINE_REQUIRED_KEYS|MMDB_ENGINES_DIR) continue ;;
        esac
        unset "$key" 2>/dev/null || true
    done

    # shellcheck disable=SC1090  # path resolved at runtime from the engine name
    . "$conf"
    MMDB_ENGINE_CONF="$conf"
    MMDB_ENGINE_DIR="$(dirname "$conf")"
    export MMDB_ENGINE_CONF MMDB_ENGINE_DIR
}

# Load the family hooks for the currently loaded engine.
#
# Hooks are per FAMILY, not per engine: MySQL and MariaDB share one
# implementation because everything that differs between them -- client binary,
# dump tool, root secret -- comes from the descriptor.
#
# The caller must already provide engine_exec, secret and compress_ext; the
# hooks are written against that contract.
engine_load_hooks() {
    local family="${MMDB_ENGINE_FAMILY:-}"
    [ -n "$family" ] || { printf 'engine-lib: no engine loaded\n' >&2; return 1; }

    local hooks="$MMDB_ENGINES_DIR/_family/${family}.sh"
    [ -f "$hooks" ] || {
        printf 'engine-lib: no hooks for family "%s" (expected %s)\n' "$family" "$hooks" >&2
        return 1
    }
    # shellcheck disable=SC1090  # path resolved at runtime from the family
    . "$hooks"
}

# Does this engine declare a capability?
engine_has_external_pooler() { [ "${MMDB_ENGINE_POOLING:-}" = "external" ]; }
engine_is_heavy()            { [ "${MMDB_ENGINE_HEAVY:-false}" = "true" ]; }
engine_tls_always()          { [ "${MMDB_ENGINE_TLS_ALWAYS:-false}" = "true" ]; }

# Is a version on this engine's supported menu?
engine_supports_version() {
    local want="$1" v
    for v in ${MMDB_ENGINE_VERSIONS:-}; do
        [ "$v" = "$want" ] && return 0
    done
    return 1
}

# Engines whose descriptor says they need an external pooler, for compose
# generation and for the prod guard in check-env.
engine_list_with_pooler() {
    local e
    for e in $(engine_list); do
        ( engine_load "$e" >/dev/null 2>&1 && engine_has_external_pooler && printf '%s\n' "$e" )
    done
}
