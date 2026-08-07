#!/usr/bin/env bash
# verify: engines run non-root, cap-dropped, and read-only where tolerated
# tags: security hardening
# phase: 4

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need_docker

# DESIGN.md D-18 and D-19.
#
# D-19: s6-overlay must start as root to run its init stages, then drop to the
# engine user. So the container user IS root, and the honest assertion is that
# no *engine* process runs as uid 0 -- not that the container is rootless.
#
# D-18: read_only rootfs needs an explicit tmpfs list per engine. If an engine
# cannot tolerate it, that belongs in the decision log, not in a silently
# dropped hardening claim.

img="$(image_name pg)"
need_image "$img"

name="dbtk-verify-harden-$$"
track_container "$name"

docker run -d --name "$name" \
    -e POSTGRES_PASSWORD=verifyonly \
    --read-only \
    --cap-drop ALL --cap-add CHOWN --cap-add SETUID --cap-add SETGID --cap-add DAC_OVERRIDE \
    --security-opt no-new-privileges \
    --tmpfs /run --tmpfs /tmp --tmpfs /var/run/postgresql \
    "$img" >/dev/null || vfail "container failed to start read-only with dropped capabilities"

wait_for 60 "postgres to accept connections read-only" docker exec "$name" pg_isready -U postgres
vinfo "engine boots with --read-only, cap-drop ALL, and no-new-privileges"

# No engine process may run as root.
root_procs="$(docker exec "$name" ps -eo user,comm 2>/dev/null | awk '$1=="root" && $2 ~ /postgres/ {print $2}' | sort -u || true)"
[[ -z "$root_procs" ]] || vfail "postgres processes running as root: $root_procs"
vinfo "no postgres process runs as uid 0"

# The data directory must not be world-readable.
perms="$(docker exec "$name" stat -c '%a' /var/lib/postgresql/data 2>/dev/null || echo '?')"
case "$perms" in
    700|750) vinfo "PGDATA permissions $perms" ;;
    *) vfail "PGDATA permissions are $perms; PostgreSQL requires 700 or 750" ;;
esac
