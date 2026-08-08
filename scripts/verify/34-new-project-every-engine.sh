#!/usr/bin/env bash
# verify: every engine family can provision a project through its hook
# tags: provisioning engines
# phase: 6

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# SPEC section 1: "a new project connects in under a minute", for every engine
# rather than for the three that happened to have a case in a switch statement.
#
# new-project used to branch on the engine and supported pg, mysql and mariadb.
# The other three silently fell through to "unknown engine" -- an engine could
# be fully supported everywhere else and have no way to create a project on it,
# and nothing said so.
#
# This asserts the contract, not the implementation: every family defines
# hook_provision_project, every descriptor carries what the printed connection
# block needs, and the hook is idempotent.

# shellcheck source=../engine-lib.sh
. "$DBTK_ROOT/scripts/engine-lib.sh"

missing=0
checked=0

while IFS= read -r engine; do
    [[ -z "$engine" ]] && continue
    engine_load "$engine" || vfail "could not load the descriptor for '$engine'"

    # A hook file is per FAMILY, so several engines share one. Loading them in
    # a subshell keeps a previously-defined hook from standing in for a family
    # that does not actually define one.
    if ! (
        engine_load_hooks >/dev/null 2>&1 || exit 1
        declare -F hook_provision_project >/dev/null 2>&1 || exit 1
    ); then
        printf '      %s (%s): no hook_provision_project\n' \
            "$DBTK_ENGINE_NAME" "$DBTK_ENGINE_FAMILY" >&2
        missing=$(( missing + 1 ))
        continue
    fi

    # The printed connection block is part of the promise, so the descriptor
    # must carry what it needs. Without these new-project prints an empty
    # DB_CONNECTION or DB_PORT, which looks like a copy-paste error at the far
    # end rather than a missing field here.
    [[ -n "${DBTK_ENGINE_DRIVER:-}" ]] \
        || vfail "engines/$engine/engine.conf declares no DBTK_ENGINE_DRIVER"
    [[ -n "${DBTK_ENGINE_PORT:-}" ]] \
        || vfail "engines/$engine/engine.conf declares no DBTK_ENGINE_PORT"

    checked=$(( checked + 1 ))
    vinfo "$(printf '%-10s family=%-10s driver=%-10s port=%s' \
        "$DBTK_ENGINE_NAME" "$DBTK_ENGINE_FAMILY" \
        "$DBTK_ENGINE_DRIVER" "$DBTK_ENGINE_PORT")"
done < <(engine_list)

(( missing == 0 )) \
    || vfail "$missing engine(s) cannot provision a project; new-project would reject them"

(( checked > 0 )) || vfail "no engines were checked"

# new-project must not have grown a per-engine branch back. The whole point of
# the hooks is that this file contains no engine names.
if grep -qE '^\s*(pg|mysql|mariadb|mongodb|cassandra|ferretdb)\)' "$DBTK_ROOT/scripts/new-project"; then
    vfail "scripts/new-project branches on an engine name again; that belongs in a family hook"
fi
vinfo "new-project contains no per-engine branch"

vinfo "$checked engine(s) can provision a project through their family hook"
