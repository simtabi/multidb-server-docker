#!/usr/bin/env bash
# shellcheck shell=bash
#
# Family hooks: MySQL and MariaDB (SPEC section 22.2).
#
# One implementation for both engines. Everything that differs between them --
# the client binary, the dump tool, the root secret -- comes from the
# descriptor, which is exactly what the descriptor is for.

# In the sidecar the engine is a remote host; from the host we are already
# exec'ing inside its container and there is no host to name.
_mysql_host_args() {
    if [ "${IN_CONTAINER:-0}" = "1" ]; then printf '%s\n%s\n' '-h' "$DBTK_ENGINE_NAME"; fi
}

_mysql_args() {
    local pw; pw="$(secret "$DBTK_ENGINE_ROOT_SECRET")"
    local hargs=()
    while IFS= read -r a; do [ -n "$a" ] && hargs+=("$a"); done < <(_mysql_host_args)
    printf '%s\n' ${hargs[@]+"${hargs[@]}"} "-uroot" "-p$pw"
}

_mysql_run() {
    local args=()
    while IFS= read -r a; do [ -n "$a" ] && args+=("$a"); done < <(_mysql_args)
    engine_exec "$DBTK_ENGINE_NAME" "$DBTK_ENGINE_CLIENT" ${args[@]+"${args[@]}"} "$@"
}

# Readiness. Deliberately NOT hook_list_databases: that answers "are there
# user databases", and a healthy fresh server has none, so using it as a
# readiness probe waits forever on a container that is already up.
hook_ping() {
    _mysql_run -N -B -e "SELECT 1" >/dev/null 2>&1
}

hook_list_databases() {
    _mysql_run -N -B -e \
        "SELECT schema_name FROM information_schema.schemata
         WHERE schema_name NOT IN ('information_schema','performance_schema','mysql','sys')" \
        2>/dev/null | tr -d '\r' | grep -v '^$'
}

# --routines and --events are the two the defaults silently omit, so a
# "complete" dump without them is quietly incomplete until you need a procedure.
hook_dump_database() {
    local db="$1" out="$2" dumper args=()
    dumper="$(printf '%s' "$DBTK_ENGINE_DUMP" | awk '{print $1}')"
    while IFS= read -r a; do [ -n "$a" ] && args+=("$a"); done < <(_mysql_args)

    if [ -n "$(compress_ext)" ]; then
        engine_exec "$DBTK_ENGINE_NAME" "$dumper" ${args[@]+"${args[@]}"} \
            --single-transaction --routines --triggers --events --quick "$db" \
            | zstd -q -T0 -"${DBTK_BACKUP_ZSTD_LEVEL:-9}" -o "$out" -f
    else
        engine_exec "$DBTK_ENGINE_NAME" "$dumper" ${args[@]+"${args[@]}"} \
            --single-transaction --routines --triggers --events --quick "$db" > "$out"
    fi
}

# MySQL has no equivalent of pg_dumpall --globals-only: grants live in the
# mysql schema, which is dumped as an ordinary database when included.
hook_dump_globals() { return 0; }

hook_recreate_database() {
    local db="$1"
    _mysql_run -e "DROP DATABASE IF EXISTS \`$db\`;
                   CREATE DATABASE \`$db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
}

hook_restore_database() {
    local db="$1"
    local args=()
    while IFS= read -r a; do [ -n "$a" ] && args+=("$a"); done < <(_mysql_args)
    engine_exec "$DBTK_ENGINE_NAME" "$DBTK_ENGINE_CLIENT" ${args[@]+"${args[@]}"} "$db"
}

# Tables present, as distinct from rows. A database with no tables was empty
# at dump time, which is a legitimate state; a database WITH tables but no
# rows means the restore lost the data. Only the second is a failure.
hook_object_count() {
    local db="$1"
    _mysql_run -N -B -e \
        "SELECT count(*) FROM information_schema.tables WHERE table_schema = '$db'" \
        2>/dev/null | tr -d ' \r'
}

hook_row_count() {
    local db="$1"
    _mysql_run -N -B -e \
        "SELECT COALESCE(SUM(table_rows), 0) FROM information_schema.tables
         WHERE table_schema = '$db'" 2>/dev/null | tr -d ' \r'
}
