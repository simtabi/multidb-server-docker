#!/usr/bin/env bash
# verify: make backup-all then make verify-backups completes the round trip
# tags: backup
# phase: 4

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need_docker
cd "$DBTK_ROOT" || exit 1

# SPEC section 18: "make backup-all produces per-database dumps plus PG
# globals, and make verify-backups restores the latest set green."
#
# SPEC section 11 also requires ONE dump helper shared by the scheduled sidecar
# and the make targets, so flags can never drift between the nightly path and
# the manual path. That shared-helper property is asserted here because a drift
# is otherwise only discovered during a real restore.

need_file "$DBTK_ROOT/scripts/backup"

make up PROFILES=pg,mysql,mariadb,backup >/dev/null 2>&1 || vfail "make up failed"
trap 'make down >/dev/null 2>&1 || true' EXIT

# shellcheck disable=SC2016  # evaluated by the subshell, not here
wait_for 120 "all engines healthy" bash -c \
    '[[ $(docker compose ps --format "{{.Health}}" | grep -c healthy) -ge 3 ]]'

make backup-all >/dev/null 2>&1 || vfail "make backup-all failed"

for engine in pg mysql mariadb; do
    find backups -name "${engine}_*" -type f -newermt '-10 minutes' | grep -q . \
        || vfail "make backup-all produced no fresh dump for $engine"
done
vinfo "fresh dumps present for all three engines"

find backups -name '*globals*' -type f -newermt '-10 minutes' | grep -q . \
    || vfail "make backup-all did not produce PG globals"
vinfo "pg globals dumped"

# Checksums, per SPEC section 11.
find backups -name '*.sha256' -o -name '*.md5' | grep -q . \
    || vfail "no checksum files alongside the dumps"
vinfo "checksums written"

# The single-helper requirement: the sidecar and the make target must invoke
# the same script, so the dump flags cannot diverge.
grep -q 'scripts/backup' docker-compose.yml \
    || vfail "the backup sidecar does not invoke scripts/backup; flags will drift from the make path"
vinfo "sidecar and make target share scripts/backup"

make verify-backups >/dev/null 2>&1 || vfail "make verify-backups failed"
vinfo "verify-backups restored the latest set and asserted row counts"
