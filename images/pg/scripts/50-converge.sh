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
# This runs as a oneshot AFTER dbtk-postgres, so it must wait for readiness
# itself rather than assuming it.

DBTK_STAGE=dbtk-converge
export DBTK_STAGE
# The absolute path is correct inside the image; this tells shellcheck where
# to find the same file in the repository.
# shellcheck source=dbtk-lib.sh
source /usr/local/lib/dbtk/dbtk-lib.sh

secret=/run/secrets/pgbouncer_password.txt

if [[ ! -r "$secret" ]]; then
    stage "no pgbouncer secret mounted; nothing to converge"
    exit 0
fi

# Bounded wait. An unbounded one turns "PostgreSQL failed to start" into a
# container that hangs with no explanation, which is strictly worse.
deadline=$(( SECONDS + 60 ))
until gosu postgres pg_isready -q -h /var/run/postgresql 2>/dev/null; do
    if (( SECONDS >= deadline )); then
        stage "PostgreSQL did not become ready within 60s; skipping convergence"
        exit 0
    fi
    sleep 1
done

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
DO \$dbtk\$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pgbouncer') THEN
        ALTER ROLE pgbouncer WITH LOGIN PASSWORD '${esc_pw}';
    ELSE
        CREATE ROLE pgbouncer WITH LOGIN PASSWORD '${esc_pw}';
    END IF;
END
\$dbtk\$;

CREATE SCHEMA IF NOT EXISTS pgbouncer AUTHORIZATION pgbouncer;

CREATE OR REPLACE FUNCTION pgbouncer.get_auth(p_username TEXT)
RETURNS TABLE(username TEXT, password TEXT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog
AS \$dbtk\$
    SELECT usename::TEXT, passwd::TEXT
      FROM pg_shadow
     WHERE usename = p_username
       AND NOT usesuper;
\$dbtk\$;

REVOKE ALL ON FUNCTION pgbouncer.get_auth(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pgbouncer.get_auth(TEXT) TO pgbouncer;
SQL

stage "converged pooler auth objects"
