#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared helpers for the db-toolkit MySQL-family s6 init stages.
#
# One set of scripts serves both engines. DESIGN.md D-17 warned that MySQL
# (Oracle Linux 9) and MariaDB (Ubuntu 24.04) do not share a base OS, and that
# remains true for package managers and client binary names -- but the thing
# that actually mattered turned out to be common: BOTH read /etc/mysql/conf.d,
# and MariaDB includes it last, so a file dropped there wins on either engine.
# The engine-specific parts are supplied by DBTK_ENGINE, baked at build time.

set -euo pipefail

DBTK_ENGINE="${DBTK_ENGINE:-mysql}"

DBTK_CONF_DIR=/etc/mysql/conf.d
DBTK_CERT_DIR=/run/dbtk/certs
DBTK_INITDB_DIR=/docker-entrypoint-initdb.d
DBTK_DATA_DIR="${DBTK_DATA_DIR:-/var/lib/mysql}"

case "$DBTK_ENGINE" in
    mysql)
        DBTK_DAEMON=mysqld
        DBTK_CLIENT=mysql
        DBTK_ADMIN=mysqladmin
        DBTK_CONF_SECTION=mysqld
        DBTK_ROOT_PW_ENV=MYSQL_ROOT_PASSWORD
        ;;
    mariadb)
        DBTK_DAEMON=mariadbd
        DBTK_CLIENT=mariadb
        DBTK_ADMIN=mariadb-admin
        DBTK_CONF_SECTION=mariadbd
        DBTK_ROOT_PW_ENV=MARIADB_ROOT_PASSWORD
        ;;
    *)
        printf 'unknown DBTK_ENGINE: %s\n' "$DBTK_ENGINE" >&2; exit 1 ;;
esac

export DBTK_ENGINE DBTK_CONF_DIR DBTK_CERT_DIR DBTK_INITDB_DIR DBTK_DATA_DIR \
       DBTK_DAEMON DBTK_CLIENT DBTK_ADMIN DBTK_CONF_SECTION DBTK_ROOT_PW_ENV

stage() { printf '[%s] %s\n' "$DBTK_STAGE" "$*"; }
die() { printf '[%s] FATAL: %s\n' "${DBTK_STAGE:-dbtk}" "$*" >&2; exit 1; }

# Has the data directory already been initialised?
datadir_initialised() { [[ -d "$DBTK_DATA_DIR/mysql" ]]; }

is_true() {
    case "${1:-}" in
        true|TRUE|True|1|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

# Per-engine env lookup: DBTK_MYSQL_FOO or DBTK_MARIADB_FOO.
engine_env() {
    local suffix="$1" default="${2:-}" name value
    case "$DBTK_ENGINE" in
        mysql)   name="DBTK_MYSQL_${suffix}" ;;
        mariadb) name="DBTK_MARIADB_${suffix}" ;;
    esac
    value="${!name:-}"
    printf '%s' "${value:-$default}"
}
