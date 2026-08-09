#!/usr/bin/env bash
# verify: check-env refuses sentinel passwords and missing required vars
# tags: fast security
# phase: 2

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# SPEC decision 6 and section 9: "make check-env refuses to start with sentinel
# passwords". A check-env that can be satisfied by a placeholder is not a gate.

need_file "$MDB_ROOT/scripts/check-env"
[[ -x "$MDB_ROOT/scripts/check-env" ]] || vfail "scripts/check-env is not executable"

tmp="$(mktemp -d)"
add_cleanup "rm -rf '$tmp'"

# A sentinel value must be rejected.
cp "$MDB_ROOT/.env.example" "$tmp/.env"
printf 'MDB_PG_SUPERUSER_PASSWORD=CHANGE_ME\n' >> "$tmp/.env"

if MDB_ENV_FILE="$tmp/.env" "$MDB_ROOT/scripts/check-env" >/dev/null 2>&1; then
    vfail "check-env accepted a CHANGE_ME sentinel password"
fi
vinfo "sentinel password rejected"

# A plaintext password (rather than a _FILE reference) must be rejected.
cp "$MDB_ROOT/.env.example" "$tmp/.env2"
printf 'MDB_PG_SUPERUSER_PASSWORD=mdb-throwaway-plaintext\n' >> "$tmp/.env2"

if MDB_ENV_FILE="$tmp/.env2" "$MDB_ROOT/scripts/check-env" >/dev/null 2>&1; then
    vfail "check-env accepted a plaintext password; the _FILE convention is mandatory"
fi
vinfo "plaintext password rejected"

# The unmodified template must pass.
cp "$MDB_ROOT/.env.example" "$tmp/.env3"
MDB_ENV_FILE="$tmp/.env3" "$MDB_ROOT/scripts/check-env" >/dev/null 2>&1 \
    || vfail "check-env rejected the unmodified .env.example template"
vinfo "clean template accepted"
