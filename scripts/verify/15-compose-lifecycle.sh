#!/usr/bin/env bash
# verify: make up boots the default profile healthy and make down keeps data
# tags: compose lifecycle
# phase: 2

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need_docker

# SPEC section 18: "clone, make init, make up -> PG + Adminer running in two
# commands". SPEC section 15: "make down never touches data" -- the check that
# matters most here, because a down that eats a volume is discovered exactly
# once, in anger.

need_file "$DBTK_ROOT/docker-compose.yml"

cd "$DBTK_ROOT" || exit 1

docker compose config >/dev/null 2>&1 || vfail "docker-compose.yml is not valid"
vinfo "compose file is valid"

make up >/dev/null 2>&1 || vfail "make up failed"

# shellcheck disable=SC2016  # evaluated by the subshell, not here
wait_for 90 "pg service to report healthy" bash -c \
    'docker compose ps --format "{{.Service}} {{.Health}}" | grep -q "^pg healthy$"'
vinfo "pg reports healthy"

docker compose ps --format '{{.Service}}' | grep -q '^adminer$' \
    || vfail "adminer is not running under the default pg,ui profile"
vinfo "adminer is up"

# Write a marker, take the stack down, bring it back, and prove data survived.
docker compose exec -T pg psql -U postgres -q \
    -c "CREATE TABLE IF NOT EXISTS lifecycle_marker(v text); INSERT INTO lifecycle_marker VALUES ('survived');" \
    >/dev/null 2>&1 || vfail "could not write the marker row"

make down >/dev/null 2>&1 || vfail "make down failed"

vols="$(docker volume ls --format '{{.Name}}' | grep -c '^dbtk_' || true)"
(( vols > 0 )) || vfail "make down removed data volumes; SPEC section 15 forbids it"
vinfo "$vols data volume(s) survived make down"

make up >/dev/null 2>&1 || vfail "make up failed on the second boot"
# shellcheck disable=SC2016  # evaluated by the subshell, not here
wait_for 90 "pg to report healthy again" bash -c \
    'docker compose ps --format "{{.Service}} {{.Health}}" | grep -q "^pg healthy$"'

val="$(docker compose exec -T pg psql -U postgres -tAc "SELECT v FROM lifecycle_marker" 2>/dev/null | tr -d ' \r')"
[[ "$val" == "survived" ]] || vfail "data did not survive down/up (got '$val')"
vinfo "data survived a full down/up cycle"

make down >/dev/null 2>&1 || true
