#!/usr/bin/env bash
# verify: check-env refuses sentinel passwords and missing required vars
# tags: fast security
# phase: 2

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# SPEC decision 6 and section 9: "make check-env refuses to start with sentinel
# passwords". A check-env that can be satisfied by a placeholder is not a gate.

need_file "$DBTK_ROOT/scripts/check-env"
[[ -x "$DBTK_ROOT/scripts/check-env" ]] || vfail "scripts/check-env is not executable"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A sentinel value must be rejected.
cp "$DBTK_ROOT/.env.example" "$tmp/.env"
printf 'DBTK_PG_SUPERUSER_PASSWORD=CHANGE_ME\n' >> "$tmp/.env"

if DBTK_ENV_FILE="$tmp/.env" "$DBTK_ROOT/scripts/check-env" >/dev/null 2>&1; then
    vfail "check-env accepted a CHANGE_ME sentinel password"
fi
vinfo "sentinel password rejected"

# A plaintext password (rather than a _FILE reference) must be rejected.
cp "$DBTK_ROOT/.env.example" "$tmp/.env2"
printf 'DBTK_PG_SUPERUSER_PASSWORD=dbtk-throwaway-plaintext\n' >> "$tmp/.env2"

if DBTK_ENV_FILE="$tmp/.env2" "$DBTK_ROOT/scripts/check-env" >/dev/null 2>&1; then
    vfail "check-env accepted a plaintext password; the _FILE convention is mandatory"
fi
vinfo "plaintext password rejected"

# The unmodified template must pass.
cp "$DBTK_ROOT/.env.example" "$tmp/.env3"
DBTK_ENV_FILE="$tmp/.env3" "$DBTK_ROOT/scripts/check-env" >/dev/null 2>&1 \
    || vfail "check-env rejected the unmodified .env.example template"
vinfo "clean template accepted"
