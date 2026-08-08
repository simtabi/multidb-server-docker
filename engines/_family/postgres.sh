#!/usr/bin/env bash
# shellcheck shell=bash
#
# Family hooks: PostgreSQL (SPEC section 22.2).
#
# Descriptors carry the declarative facts. These are the few operations that
# genuinely need code, and they are per FAMILY rather than per engine so that
# two engines of the same family share one implementation.
#
# The caller provides: engine_exec, secret, compress_ext, and the loaded
# DBTK_ENGINE_* descriptor values.

# In the sidecar the engine is a remote host over TCP, which requires a
# password. From the host we exec inside the container and reach it over the
# socket, where peer auth applies and no credential is needed. Setting this
# here rather than in the generic driver keeps engine specifics with the engine.
if [ "${IN_CONTAINER:-0}" = "1" ] && [ -r "/run/secrets/${DBTK_ENGINE_ROOT_SECRET:-pg_superuser_password.txt}" ]; then
    PGPASSWORD="$(tr -d '\n' < "/run/secrets/${DBTK_ENGINE_ROOT_SECRET:-pg_superuser_password.txt}")"
    export PGPASSWORD
fi

# Readiness. Deliberately NOT hook_list_databases: that answers "are there
# user databases", and a healthy fresh server has none, so using it as a
# readiness probe waits forever on a container that is already up.
hook_ping() {
    engine_exec "$DBTK_ENGINE_NAME" pg_isready -U postgres >/dev/null 2>&1
}

# Databases a backup should cover: everything connectable that is not a
# template.
hook_list_databases() {
    engine_exec "$DBTK_ENGINE_NAME" psql -U postgres -tAc \
        "SELECT datname FROM pg_database WHERE datallowconn AND NOT datistemplate" \
        | tr -d '\r' | grep -v '^$'
}

hook_dump_database() {
    local db="$1" out="$2"
    if [ -n "$(compress_ext)" ]; then
        engine_exec "$DBTK_ENGINE_NAME" pg_dump -U postgres -Fc --no-password "$db" \
            | zstd -q -T0 -"${DBTK_BACKUP_ZSTD_LEVEL:-9}" -o "$out" -f
    else
        engine_exec "$DBTK_ENGINE_NAME" pg_dump -U postgres -Fc --no-password "$db" > "$out"
    fi
}

# Roles and grants live only here. A per-database dump restores into a server
# nobody can log into, which is why this runs on every backup.
hook_dump_globals() {
    local out="$1"
    if [ -n "$(compress_ext)" ]; then
        engine_exec "$DBTK_ENGINE_NAME" pg_dumpall -U postgres --globals-only --no-password \
            | zstd -q -T0 -"${DBTK_BACKUP_ZSTD_LEVEL:-9}" -o "$out" -f
    else
        engine_exec "$DBTK_ENGINE_NAME" pg_dumpall -U postgres --globals-only --no-password > "$out"
    fi
}

hook_recreate_database() {
    local db="$1"
    engine_exec "$DBTK_ENGINE_NAME" psql -U postgres -q -c "DROP DATABASE IF EXISTS \"$db\";" >/dev/null
    engine_exec "$DBTK_ENGINE_NAME" psql -U postgres -q -c "CREATE DATABASE \"$db\";" >/dev/null
}

# --no-owner keeps the restore working when roles differ between source and
# target; globals are restored separately.
hook_restore_database() {
    local db="$1"
    engine_exec "$DBTK_ENGINE_NAME" pg_restore -U postgres -d "$db" --no-owner --clean --if-exists
}

# Tables present, as distinct from rows. A database with no tables was empty
# at dump time, which is a legitimate state; a database WITH tables but no
# rows means the restore lost the data. Only the second is a failure.
hook_object_count() {
    local db="$1"
    engine_exec "$DBTK_ENGINE_NAME" psql -U postgres -d "$db" -tAc \
        "SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema')" \
        2>/dev/null | tr -d ' \r'
}

hook_row_count() {
    local db="$1"
    engine_exec "$DBTK_ENGINE_NAME" psql -U postgres -d "$db" -tAc \
        "SELECT COALESCE(SUM(n_live_tup), 0) FROM pg_stat_user_tables" 2>/dev/null | tr -d ' \r'
}
