#!/usr/bin/env bash
# shellcheck shell=bash
# Shared helpers for the db-toolkit-cassandra init stages.
set -euo pipefail

DBTK_CONF=/etc/cassandra/cassandra.yaml
DBTK_DATA_DIR=/var/lib/cassandra
export DBTK_CONF DBTK_DATA_DIR

stage() { printf '[%s] %s\n' "$DBTK_STAGE" "$*"; }
die() { printf '[%s] FATAL: %s\n' "${DBTK_STAGE:-dbtk}" "$*" >&2; exit 1; }

is_true() {
    case "${1:-}" in true|TRUE|True|1|yes|YES|on|ON) return 0 ;; *) return 1 ;; esac
}
