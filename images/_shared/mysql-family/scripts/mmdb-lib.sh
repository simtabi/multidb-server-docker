#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared helpers for the my-multidb-server MySQL-family s6 init stages.
#
# One set of scripts serves both engines. DESIGN.md D-17 warned that MySQL
# (Oracle Linux 9) and MariaDB (Ubuntu 24.04) do not share a base OS, and that
# remains true for package managers and client binary names -- but the thing
# that actually mattered turned out to be common: BOTH read /etc/mysql/conf.d,
# and MariaDB includes it last, so a file dropped there wins on either engine.
# The engine-specific parts are supplied by MMDB_ENGINE, baked at build time.

set -euo pipefail

MMDB_ENGINE="${MMDB_ENGINE:-mysql}"

MMDB_CONF_DIR=/etc/mysql/conf.d
MMDB_CERT_DIR=/run/mmdb/certs
MMDB_INITDB_DIR=/docker-entrypoint-initdb.d
MMDB_DATA_DIR="${MMDB_DATA_DIR:-/var/lib/mysql}"

case "$MMDB_ENGINE" in
    mysql)
        MMDB_DAEMON=mysqld
        MMDB_CLIENT=mysql
        MMDB_ADMIN=mysqladmin
        MMDB_CONF_SECTION=mysqld
        MMDB_ROOT_PW_ENV=MYSQL_ROOT_PASSWORD
        ;;
    mariadb)
        MMDB_DAEMON=mariadbd
        MMDB_CLIENT=mariadb
        MMDB_ADMIN=mariadb-admin
        MMDB_CONF_SECTION=mariadbd
        MMDB_ROOT_PW_ENV=MARIADB_ROOT_PASSWORD
        ;;
    *)
        printf 'unknown MMDB_ENGINE: %s\n' "$MMDB_ENGINE" >&2; exit 1 ;;
esac

export MMDB_ENGINE MMDB_CONF_DIR MMDB_CERT_DIR MMDB_INITDB_DIR MMDB_DATA_DIR \
       MMDB_DAEMON MMDB_CLIENT MMDB_ADMIN MMDB_CONF_SECTION MMDB_ROOT_PW_ENV

stage() { printf '[%s] %s\n' "$MMDB_STAGE" "$*"; }
die() { printf '[%s] FATAL: %s\n' "${MMDB_STAGE:-mmdb}" "$*" >&2; exit 1; }

# Has the data directory already been initialised?
datadir_initialised() { [[ -d "$MMDB_DATA_DIR/mysql" ]]; }

is_true() {
    case "${1:-}" in
        true|TRUE|True|1|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

# Per-engine env lookup: MMDB_MYSQL_FOO or MMDB_MARIADB_FOO.
engine_env() {
    local suffix="$1" default="${2:-}" name value
    case "$MMDB_ENGINE" in
        mysql)   name="MMDB_MYSQL_${suffix}" ;;
        mariadb) name="MMDB_MARIADB_${suffix}" ;;
    esac
    value="${!name:-}"
    printf '%s' "${value:-$default}"
}
