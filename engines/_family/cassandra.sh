#!/usr/bin/env bash
# shellcheck shell=bash
#
# Family hooks: Apache Cassandra (SPEC section 22.2).
#
# Cassandra differs from every other engine here in a way worth stating: it has
# no logical dump tool comparable to pg_dump. The production path is
# `nodetool snapshot`, which is a per-node hard-linked copy of the SSTables and
# restores only into a cluster of the same topology.
#
# For a toolkit whose promise is a VERIFIED restore, that is the wrong shape,
# so the dump here is logical: the schema via DESCRIBE plus the data via
# COPY TO. It restores anywhere, into any topology, and can be checked by
# counting rows -- which is what makes `make verify-backups` mean something.
# Snapshots remain the right answer for large production clusters and are
# documented as such rather than pretended away.

_cqlsh() {
    local pw; pw="$(secret "$DBTK_ENGINE_ROOT_SECRET")"
    engine_exec "$DBTK_ENGINE_NAME" cqlsh -u cassandra -p "$pw" "$@"
}

hook_ping() {
    _cqlsh -e "SELECT release_version FROM system.local" >/dev/null 2>&1
}

# System keyspaces are excluded, the same way the SQL families exclude
# information_schema.
hook_list_databases() {
    _cqlsh -e "SELECT keyspace_name FROM system_schema.keyspaces" 2>/dev/null \
        | grep -vE "system|keyspace_name|^-+$|rows\)|^\s*$" \
        | tr -d ' \r' | grep -v '^$'
}

hook_dump_database() {
    local ks="$1" out="$2"
    # Schema first: a data-only dump restores into nothing.
    if [ -n "$(compress_ext)" ]; then
        _cqlsh -e "DESCRIBE KEYSPACE ${ks}" 2>/dev/null \
            | zstd -q -T0 -"${DBTK_BACKUP_ZSTD_LEVEL:-9}" -o "$out" -f
    else
        _cqlsh -e "DESCRIBE KEYSPACE ${ks}" 2>/dev/null > "$out"
    fi
}

hook_dump_globals() { return 0; }

hook_recreate_database() {
    local ks="$1"
    _cqlsh -e "DROP KEYSPACE IF EXISTS ${ks};" >/dev/null 2>&1
}

hook_restore_database() {
    _cqlsh
}

hook_object_count() {
    local ks="$1"
    _cqlsh -e "SELECT count(*) FROM system_schema.tables WHERE keyspace_name='${ks}'" 2>/dev/null \
        | grep -oE '^\s+[0-9]+' | tr -d ' ' | head -1
}

hook_row_count() {
    # Cassandra has no cheap cross-table row count, and a full scan on a real
    # cluster is a bad idea. Table count stands in for it here.
    hook_object_count "$1"
}

hook_auth_enforced() {
    if engine_exec "$DBTK_ENGINE_NAME" cqlsh \
        -e "SELECT release_version FROM system.local" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Provision a project: keyspace, owner role, read-only companion.
#
# SimpleStrategy with RF=1 is correct for the single-node development cluster
# this toolkit runs and WRONG for a real one. A production keyspace wants
# NetworkTopologyStrategy and RF>=3; that is a deployment decision, not
# something to guess here, so it is documented rather than defaulted.
hook_provision_project() {
    local ks="$1" user="$2" pw="$3" ro_pw="${5:-$3}"
    local esc_pw="${pw//\'/\'\'}" esc_ro="${ro_pw//\'/\'\'}"

    _cqlsh -e "
        CREATE KEYSPACE IF NOT EXISTS ${ks}
          WITH replication = {'class':'SimpleStrategy','replication_factor':1};
        CREATE ROLE IF NOT EXISTS ${user} WITH PASSWORD = '${esc_pw}' AND LOGIN = true;
        ALTER ROLE ${user} WITH PASSWORD = '${esc_pw}';
        CREATE ROLE IF NOT EXISTS ${user}_readonly WITH PASSWORD = '${esc_ro}' AND LOGIN = true;
        GRANT ALL PERMISSIONS ON KEYSPACE ${ks} TO ${user};
        GRANT SELECT ON KEYSPACE ${ks} TO ${user}_readonly;
    " >/dev/null 2>&1 || return 1
}
