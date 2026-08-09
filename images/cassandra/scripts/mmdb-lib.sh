#!/usr/bin/env bash
# shellcheck shell=bash
# Shared helpers for the my-multidb-server-cassandra init stages.
set -euo pipefail

MMDB_CONF=/etc/cassandra/cassandra.yaml
MMDB_DATA_DIR=/var/lib/cassandra
export MMDB_CONF MMDB_DATA_DIR

stage() { printf '[%s] %s\n' "$MMDB_STAGE" "$*"; }
die() { printf '[%s] FATAL: %s\n' "${MMDB_STAGE:-mmdb}" "$*" >&2; exit 1; }

is_true() {
    case "${1:-}" in true|TRUE|True|1|yes|YES|on|ON) return 0 ;; *) return 1 ;; esac
}
