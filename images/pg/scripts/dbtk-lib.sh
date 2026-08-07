#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared helpers for the db-toolkit-pg s6 init stages.

set -euo pipefail

# Generated state lives under /run, which is tmpfs. That is what lets the
# container run with a read-only root filesystem (SPEC section 9, DESIGN.md
# D-18) without a bespoke tmpfs mount for every directory we write to.
DBTK_CONF_DIR=/run/dbtk/conf.d
DBTK_CERT_DIR=/run/dbtk/certs

# User-supplied overrides are mounted here and stay read-only. PostgreSQL reads
# this directory AFTER the generated one, so a mounted file wins -- which is
# what SPEC section 13 requires.
DBTK_OVERRIDE_CONF_DIR=/etc/postgresql/conf.d

DBTK_INITDB_DIR=/docker-entrypoint-initdb.d
PGDATA_DIR="${PGDATA:-/var/lib/postgresql/data}"

export DBTK_CONF_DIR DBTK_CERT_DIR DBTK_OVERRIDE_CONF_DIR DBTK_INITDB_DIR PGDATA_DIR

# Every stage announces itself. The harness asserts the observed order in
# scripts/verify/10-s6-init-and-shutdown.sh, so these strings are load-bearing.
stage() { printf '[%s] %s\n' "$DBTK_STAGE" "$*"; }

die() { printf '[%s] FATAL: %s\n' "${DBTK_STAGE:-dbtk}" "$*" >&2; exit 1; }

# Resolve a value that may be given directly or through the _FILE convention.
# SPEC decision 6: secrets travel as files, never as plain env.
resolve_secret() {
    local direct="${1:-}" file="${2:-}"
    if [[ -n "$file" ]]; then
        [[ -r "$file" ]] || die "secret file is not readable: $file"
        tr -d '\n' < "$file"
        return
    fi
    printf '%s' "$direct"
}

# Is the data directory already initialised?
pgdata_initialised() { [[ -s "$PGDATA_DIR/PG_VERSION" ]]; }

# true/false env helper.
is_true() {
    case "${1:-}" in
        true|TRUE|True|1|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}
