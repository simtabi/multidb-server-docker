#!/usr/bin/env bash
#
# Rotate the default superuser, and provision projects.
#
# Enabling PasswordAuthenticator is only half the job. It creates a superuser
# named `cassandra` whose password is also `cassandra` -- documented, universal,
# and the first thing any scanner tries. Auth that is on but uses a publicly
# known credential is barely better than auth that is off, so this stage
# replaces it with the generated secret.
#
# It runs AFTER the engine, because the password can only be changed over CQL
# and that needs a running server. s6 orders it by dependency; readiness is
# polled here because a longrun counts as "started" the moment it execs, not
# when the database is queryable.

DBTK_STAGE=dbtk-provision
export DBTK_STAGE
# shellcheck source=dbtk-lib.sh
source /usr/local/lib/dbtk/dbtk-lib.sh

SECRET=/run/secrets/cassandra_root_password.txt
[ -r "$SECRET" ] || { stage "no root secret mounted; leaving credentials alone"; exit 0; }
NEW_PW="$(tr -d '\n' < "$SECRET")"
[ -n "$NEW_PW" ] || die "the root secret is empty"

stage "waiting for Cassandra to accept CQL"
ready=0
for _ in $(seq 1 120); do
    if cqlsh -u cassandra -p cassandra -e "SELECT release_version FROM system.local" >/dev/null 2>&1; then
        ready=1; break
    fi
    # Already rotated on a previous boot? Then there is nothing to do.
    if cqlsh -u cassandra -p "$NEW_PW" -e "SELECT release_version FROM system.local" >/dev/null 2>&1; then
        stage "superuser password already rotated"
        exit 0
    fi
    sleep 5
done

(( ready )) || die "Cassandra never became queryable; refusing to leave the default password in place"

stage "rotating the default cassandra superuser password"
# Single-quote escaping for CQL string literals.
esc="${NEW_PW//\'/\'\'}"
cqlsh -u cassandra -p cassandra \
    -e "ALTER ROLE cassandra WITH PASSWORD = '${esc}';" >/dev/null 2>&1 \
    || die "could not rotate the superuser password"

# Cassandra caches credentials and role lookups (roles_validity_in_ms and
# credentials_validity_in_ms, both 2s by default), so an ALTER ROLE is not
# visible to the very next connection. Verifying once fails on a change that
# actually worked, so this retries across the cache window before giving up.
verified=0
for _ in $(seq 1 12); do
    if cqlsh -u cassandra -p "$NEW_PW" -e "SELECT release_version FROM system.local" >/dev/null 2>&1; then
        verified=1; break
    fi
    sleep 2
done
(( verified )) || die "the rotated password does not work after 24s; refusing to continue"

stage "default superuser credential replaced"

# Projects: keyspace plus a least-privilege role, the same triplet contract
# every other engine honours (SPEC section 22.2).
triplets="${DBTK_CASSANDRA_DATABASES:-}"
[ -z "$triplets" ] && exit 0

IFS=',' read -ra entries <<< "$triplets"
for entry in "${entries[@]}"; do
    [ -z "$entry" ] && continue
    ks="${entry%%:*}"; rest="${entry#*:}"
    user="${rest%%:*}"; pass="${rest#*:}"
    [ -n "$ks" ] && [ -n "$user" ] || die "malformed triplet (want keyspace:user:password): $entry"

    if [ "$pass" = "__FILE__" ]; then
        f="/run/secrets/cassandra_${user}_password.txt"
        [ -r "$f" ] || die "triplet for '$ks' uses __FILE__ but $f is not readable"
        pass="$(tr -d '\n' < "$f")"
    fi
    esc_p="${pass//\'/\'\'}"

    # SimpleStrategy with RF 1 suits a single-node dev instance; a real cluster
    # wants NetworkTopologyStrategy, which is a deployment decision rather than
    # something this can guess.
    cqlsh -u cassandra -p "$NEW_PW" -e "
        CREATE KEYSPACE IF NOT EXISTS ${ks}
          WITH replication = {'class':'SimpleStrategy','replication_factor':1};
        CREATE ROLE IF NOT EXISTS ${user} WITH PASSWORD = '${esc_p}' AND LOGIN = true;
        GRANT ALL PERMISSIONS ON KEYSPACE ${ks} TO ${user};" >/dev/null 2>&1 \
        || stage "WARNING: could not provision keyspace ${ks}"
    stage "provisioned keyspace ${ks} owned by ${user}"
done
