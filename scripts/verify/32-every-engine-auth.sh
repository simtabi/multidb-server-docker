#!/usr/bin/env bash
# verify: no engine, of any paradigm, accepts unauthenticated connections
# tags: security auth engines
# phase: 6

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=../engine-lib.sh
source "$DBTK_ROOT/scripts/engine-lib.sh"

cd "$DBTK_ROOT" || exit 1

# SPEC section 22.3. This is the check that makes "every engine authenticates"
# a property of the toolkit rather than a claim about three of them.
#
# It matters most for the engines added last, because both of them ship
# insecure and correcting that is the main reason to use this toolkit rather
# than the upstream images directly:
#
#   MongoDB    runs with NO authentication unless root credentials are supplied
#   Cassandra  ships AllowAllAuthenticator AND AllowAllAuthorizer
#
# A new engine inherits this check by existing. That is the point: an engine
# with no coverage is an engine nobody can trust, and remembering to add a
# check per engine is exactly the discipline that fails quietly.

need_docker

checked=0
skipped=0

for engine in $(engine_list); do
    engine_load "$engine" || vfail "could not load the descriptor for $engine"

    # Not every engine has a hooks implementation yet; say so rather than
    # passing silently, which would read as coverage that does not exist.
    if ! engine_load_hooks 2>/dev/null; then
        vinfo "$engine: SKIPPED, no family hooks for '${DBTK_ENGINE_FAMILY}'"
        skipped=$(( skipped + 1 ))
        continue
    fi

    if ! declare -f hook_auth_enforced >/dev/null 2>&1; then
        vfail "$engine: family '${DBTK_ENGINE_FAMILY}' declares no hook_auth_enforced; auth cannot be proven"
    fi

    ver="$(engine_version "$engine")"
    img="${DBTK_IMAGE_PREFIX:-ghcr.io/simtabi}/db-toolkit-${engine}:${ver}"

    # A referenced engine is not published by us, so it runs the pinned
    # upstream image (SPEC section 22.5).
    if [[ "${DBTK_ENGINE_PUBLISH:-derive}" == "reference" ]]; then
        img="$(awk -v e="$engine" -v v="$ver" '$1==e && $2==v {print $3; exit}' images/bases.tsv)"
    fi

    if ! image_exists "$img"; then
        vinfo "$engine: SKIPPED, image not built ($img)"
        skipped=$(( skipped + 1 ))
        continue
    fi

    name="dbtk-verify-auth-${engine}-$$"
    track_container "$name"

    pw="dbtk-throwaway-verify"

    # Not every engine takes its root password from an environment variable.
    # Cassandra reads it from a mounted secret file, so an env-only container
    # keeps the default credential and every probe with the throwaway password
    # fails -- which looks like "never became ready" rather than the setup
    # error it is. The descriptor already names the file, so mount one.
    secrets_dir="$(mktemp -d)"
    add_cleanup "rm -rf '$secrets_dir'"
    printf '%s' "$pw" > "$secrets_dir/${DBTK_ENGINE_ROOT_SECRET}"
    chmod 0644 "$secrets_dir/${DBTK_ENGINE_ROOT_SECRET}"
    # Every engine's root password reaches it by a different variable name,
    # which the descriptor already declares. Passing them all is harmless: an
    # engine ignores the ones that are not its own.
    docker run -d --name "$name" \
        -e POSTGRES_PASSWORD="$pw" \
        -e MYSQL_ROOT_PASSWORD="$pw" \
        -e MARIADB_ROOT_PASSWORD="$pw" \
        -e MONGO_INITDB_ROOT_USERNAME=root \
        -e MONGO_INITDB_ROOT_PASSWORD="$pw" \
        -e MAX_HEAP_SIZE=1G -e HEAP_NEWSIZE=200M \
        -v "$secrets_dir:/run/secrets:ro" \
        "$img" >/dev/null 2>&1 \
        || vfail "$engine: container failed to start from $img"

    # The hooks are written against this contract; here every call targets the
    # throwaway container rather than a compose service.
    # shellcheck disable=SC2034  # read by the family hooks
    IN_CONTAINER=0
    engine_exec() { shift; docker exec -i "$name" "$@"; }
    secret() { printf '%s' "$pw"; }
    compress_ext() { printf ''; }

    # Cassandra is genuinely slow to become queryable: a JVM to warm and a
    # gossip round to complete. The budget reflects that rather than assuming
    # every engine behaves like PostgreSQL.
    budget=90
    engine_is_heavy && budget=300

    ready=0
    for (( i = 0; i < budget; i++ )); do
        if hook_ping; then ready=1; break; fi
        sleep 1
    done

    if (( ! ready )); then
        docker logs "$name" 2>&1 | tail -8 >&2
        vfail "$engine: never became ready within ${budget}s"
    fi

    # THE assertion.
    if hook_auth_enforced; then
        vinfo "$(printf '%-10s %-12s auth enforced' "$engine" "$DBTK_ENGINE_PARADIGM")"
    else
        vfail "$engine ACCEPTS UNAUTHENTICATED CONNECTIONS. SPEC section 22.3 forbids it."
    fi

    docker rm -f "$name" >/dev/null 2>&1 || true
    checked=$(( checked + 1 ))
done

(( checked > 0 )) || vfail "no engines were checked; this proves nothing"
vinfo "$checked engine(s) enforce authentication${skipped:+, $skipped skipped}"
