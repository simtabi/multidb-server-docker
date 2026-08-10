#!/usr/bin/env bash
#
# Stage 5: cluster-level convergence, applied on EVERY start.
#
# Stage 4 emits into /docker-entrypoint-initdb.d, which the upstream entrypoint
# runs exactly once, on first init. That is right for project provisioning --
# re-running CREATE DATABASE against a live cluster would be wrong -- but it is
# wrong for cluster-level objects that a later change may need to introduce.
#
# The concrete case is the pooler. Enabling the `pooler` profile on a checkout
# whose volume was created months earlier must work; requiring `make destroy`
# to gain a connection pooler would be an absurd trade. So the objects the
# pooler needs are converged here, idempotently, after the server is accepting
# connections.
#
# This runs as a oneshot AFTER mdb-postgres, so it must wait for readiness
# itself rather than assuming it.

MDB_STAGE=mdb-converge
export MDB_STAGE
# The absolute path is correct inside the image; this tells shellcheck where
# to find the same file in the repository.
# shellcheck source=mdb-lib.sh
source /usr/local/lib/mdb/mdb-lib.sh

secret=/run/secrets/pgbouncer_password.txt

# This stage converges more than one thing, so nothing here may exit early on
# behalf of the others. An absent pgbouncer secret used to `exit 0` for the
# whole script, which silently skipped PITR setup entirely -- the stanza was
# never created and archiving never started, on a container that reported
# converging successfully.
converge_pgbouncer=0
[[ -r "$secret" ]] && converge_pgbouncer=1

# Bounded wait. An unbounded one turns "PostgreSQL failed to start" into a
# container that hangs with no explanation, which is strictly worse.
# 300 seconds, not 60 -- a fresh volume's full initialisation can exceed the
# short budget on a loaded machine -- and timing out is a FAILURE, not a
# skip-with-success. The mysql-family twin of this script exited 0 here and
# left the pooler looping on Access denied against an engine whose log said
# the convergence service started successfully.
deadline=$(( SECONDS + 300 ))
until gosu postgres pg_isready -q -h /var/run/postgresql 2>/dev/null; do
    if (( SECONDS >= deadline )); then
        stage "PostgreSQL not ready after 300s; convergence FAILED"
        exit 1
    fi
    sleep 1
done

if (( converge_pgbouncer )); then
pw="$(tr -d '\n' < "$secret")"
esc_pw="${pw//\'/\'\'}"

# The pooler authenticates application users with auth_query rather than
# holding their passwords. It therefore needs:
#
#   1. a login role of its own -- the ONLY credential the pooler ever stores;
#   2. a way to read password verifiers, which lives in pg_shadow and is
#      superuser-only.
#
# (2) is granted through a SECURITY DEFINER function rather than by making the
# pooler a superuser. The function is deliberately narrow: it takes a single
# username and returns that one row. Note the WHERE clause excludes superusers,
# so a compromised pooler role cannot obtain the superuser's verifier.
#
# search_path is pinned inside the function because a SECURITY DEFINER function
# that resolves unqualified names through the caller's search_path is a
# privilege-escalation bug (CVE-2018-1058 is the canonical example).

gosu postgres psql -v ON_ERROR_STOP=1 -q --no-psqlrc -h /var/run/postgresql \
    -d postgres <<SQL
DO \$mdb\$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pgbouncer') THEN
        ALTER ROLE pgbouncer WITH LOGIN PASSWORD '${esc_pw}';
    ELSE
        CREATE ROLE pgbouncer WITH LOGIN PASSWORD '${esc_pw}';
    END IF;
END
\$mdb\$;

CREATE SCHEMA IF NOT EXISTS pgbouncer AUTHORIZATION pgbouncer;

CREATE OR REPLACE FUNCTION pgbouncer.get_auth(p_username TEXT)
RETURNS TABLE(username TEXT, password TEXT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog
AS \$mdb\$
    SELECT usename::TEXT, passwd::TEXT
      FROM pg_shadow
     WHERE usename = p_username
       AND NOT usesuper;
\$mdb\$;

REVOKE ALL ON FUNCTION pgbouncer.get_auth(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pgbouncer.get_auth(TEXT) TO pgbouncer;
SQL

stage "converged pooler auth objects"
else
    stage "no pgbouncer secret mounted; skipping the pooler objects"
fi

# -----------------------------------------------------------------------------
# PITR: create the stanza and take the first backup
# -----------------------------------------------------------------------------
# stanza-create needs a RUNNING server, which is exactly why this is here and
# the archive settings are in stage 2: archive_mode cannot be reloaded, and a
# stanza cannot be created before there is something to query.
#
# Both are idempotent, so a restart re-checks rather than re-does.
if is_true "${MDB_PG_PITR:-false}"; then
    stanza="${MDB_PGBACKREST_STANZA:-mdb}"

    if gosu postgres pgbackrest --stanza="$stanza" stanza-create 2>&1 | grep -qi 'error'; then
        stage "WARNING: stanza-create reported an error; PITR is NOT active"
    else
        stage "pgBackRest stanza '$stanza' ready"
    fi

    # A stanza with no full backup can archive WAL and restore nothing: recovery
    # replays forward FROM a base backup, so without one the segments are
    # inert. Taking it here means PITR is usable from first boot rather than
    # from whenever someone remembers to run a backup.
    if ! gosu postgres pgbackrest --stanza="$stanza" info 2>/dev/null | grep -q 'full backup'; then
        stage "taking the initial full backup (PITR needs a base to replay from)"
        gosu postgres pgbackrest --stanza="$stanza" --type=full backup >/dev/null 2>&1 \
            || stage "WARNING: the initial full backup failed; PITR is NOT usable yet"
    fi

    if gosu postgres pgbackrest --stanza="$stanza" check >/dev/null 2>&1; then
        stage "pgBackRest check passed: archiving and the repository both work"
    else
        stage "WARNING: pgBackRest check failed; archiving may not be working"
    fi
fi
