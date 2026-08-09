#!/usr/bin/env bash
# verify: settings and recovery data survive rebuilds, restarts and destroy
# tags: fast structure backup
# phase: 1

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "$DBTK_ROOT" || exit 1

# What must survive what.
#
# Three different lifetimes get confused with each other, and each confusion
# has a distinct failure:
#
#   * CONFIGURATION is regenerated from .env at every start. It does not need
#     to persist -- it needs to be reproducible, which is stronger. A setting
#     that only exists inside a container is lost on the next rebuild.
#   * DATA lives in named volumes and survives `make down`, a rebuild, and
#     container recreation. Anything in a container's writable layer does not.
#   * RECOVERY DATA -- the pgBackRest repository and the binary logs -- must
#     survive even `make destroy`, because the moment you most want a backup is
#     immediately after destroying something.

# 1. Every path an image declares as a VOLUME must be mapped to a NAMED volume.
#
# An unmapped VOLUME gets an anonymous one, which compose discards on recreate:
# the data appears to persist across restarts and vanishes on the first
# `docker compose up --force-recreate`.
need_file "$DBTK_ROOT/compose.engines.yml"
# shellcheck source=../engine-lib.sh
. "$DBTK_ROOT/scripts/engine-lib.sh"

unmapped=0
while IFS= read -r engine; do
    [[ -z "$engine" ]] && continue
    engine_load "$engine" || continue
    grep -q -- "- ${DBTK_ENGINE_NAME}_data:${DBTK_ENGINE_DATA_DIR}" "$DBTK_ROOT/compose.engines.yml" \
        || { printf '      %s: data dir %s is not mapped to a named volume\n' \
                "$DBTK_ENGINE_NAME" "$DBTK_ENGINE_DATA_DIR" >&2; unmapped=$(( unmapped + 1 )); }
done < <(engine_list)
(( unmapped == 0 )) || vfail "$unmapped engine(s) would write data to an anonymous volume"
vinfo "every engine's data directory is a named volume"

# 2. Recovery data lives in its OWN volume, never inside the data volume.
while IFS= read -r engine; do
    [[ -z "$engine" ]] && continue
    engine_load "$engine" || continue
    [[ "${DBTK_ENGINE_PITR_CAPABLE:-false}" == "true" ]] || continue

    repo="${DBTK_ENGINE_PITR_REPO_PATH:?}"
    case "$repo" in
        "$DBTK_ENGINE_DATA_DIR"/*|"$DBTK_ENGINE_DATA_DIR")
            vfail "$DBTK_ENGINE_NAME keeps recovery data at $repo, inside its data directory.
       A backup stored inside the thing it backs up goes when that goes." ;;
    esac
    grep -q -- "- ${DBTK_ENGINE_NAME}_pitr:${repo}" "$DBTK_ROOT/compose.engines.yml" \
        || vfail "$DBTK_ENGINE_NAME: $repo is not mapped to a named volume; binlogs would die with the container"
done < <(engine_list)
vinfo "recovery repositories are separate named volumes"

# 3. `make destroy` must not take the recovery repositories with it.
grep -q 'is_recovery_volume' "$DBTK_ROOT/scripts/destroy" \
    || vfail "scripts/destroy does not distinguish recovery volumes; --all would delete the backups
       along with the data they exist to recover"
grep -q -- '--include-recovery' "$DBTK_ROOT/scripts/destroy" \
    || vfail "scripts/destroy has no explicit opt-in for deleting recovery volumes"
vinfo "destroy keeps recovery repositories unless explicitly told otherwise"

# 4. Configuration is generated at start, so it is reproducible rather than
#    merely persistent. A rebuild must not lose a setting.
for f in images/pg/scripts/20-conf.sh images/_shared/mysql-family/scripts/20-conf.sh; do
    need_file "$DBTK_ROOT/$f"
    grep -q 'DBTK_CONF_DIR\|conf=' "$DBTK_ROOT/$f" \
        || vfail "$f no longer generates configuration at start"
done
vinfo "engine configuration is regenerated from .env on every start"

# 5. Host-side state that must never be silently replaced.
grep -q 'Refusing to overwrite it' "$DBTK_ROOT/scripts/init" \
    || vfail "scripts/init no longer refuses to overwrite an existing .env; regenerating it would
       orphan every password already in use"
vinfo "init refuses to overwrite an existing environment file"

vinfo "configuration reproduces, data persists, recovery data outlives destroy"
