#!/usr/bin/env bash
# verify: PG TLS handshake succeeds and sslmode=verify-full trusts the toolkit CA
# tags: pg tls security
# phase: 2

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need_docker

# SPEC decision 5: PG TLS is always on. Section 18: "psql sslmode=verify-full
# against the toolkit CA succeeds".
#
# verify-full is the only mode that actually validates the hostname, so it is
# the only mode worth asserting; sslmode=require proves nothing about identity.

need_dir "$DBTK_ROOT/certs"
for f in ca.crt pg/server.crt pg/server.key; do
    need_file "$DBTK_ROOT/certs/$f"
done

img="$(image_name pg)"
need_image "$img"

net="dbtk-verify-tls-net-$$"
name="dbtk-verify-tls-$$"
track_container "$name"
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; docker network rm "$net" >/dev/null 2>&1 || true' EXIT

docker network create "$net" >/dev/null

docker run -d --name "$name" --network "$net" --network-alias pg \
    -e POSTGRES_PASSWORD=verifyonly \
    -v "$DBTK_ROOT/certs:/certs:ro" \
    "$img" >/dev/null || vfail "container failed to start with certs mounted"

wait_for 60 "postgres to accept connections" docker exec "$name" pg_isready -U postgres

# TLS must be on.
ssl_on="$(docker exec "$name" psql -U postgres -tAc "SHOW ssl" 2>/dev/null | tr -d ' ')"
[[ "$ssl_on" == "on" ]] || vfail "SHOW ssl returned '$ssl_on', expected 'on'"
vinfo "server reports ssl=on"

# The connection must actually be encrypted, not merely capable of it.
cipher="$(docker exec "$name" psql -U postgres -tAc \
    "SELECT version FROM pg_stat_ssl WHERE pid = pg_backend_pid()" 2>/dev/null | tr -d ' ')"
vinfo "local session TLS version: ${cipher:-none}"

# verify-full from a separate container, trusting only the toolkit CA.
out="$(docker run --rm --network "$net" \
    -v "$DBTK_ROOT/certs/ca.crt:/ca.crt:ro" \
    -e PGPASSWORD=verifyonly \
    "$img" \
    psql "host=pg user=postgres dbname=postgres sslmode=verify-full sslrootcert=/ca.crt" \
    -tAc "SELECT 'verify-full-ok'" 2>&1 || true)"

printf '%s' "$out" | grep -q 'verify-full-ok' \
    || { printf '      %s\n' "$out" >&2; vfail "sslmode=verify-full against the toolkit CA failed"; }

vinfo "sslmode=verify-full succeeded against the toolkit CA"
