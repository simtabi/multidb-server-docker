#!/usr/bin/env bash
# verify: every DBTK_ variable in use is documented in .env.example
# tags: fast structure
# phase: 1

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "$DBTK_ROOT" || exit 1

need_file "$DBTK_ROOT/.env.example"

# SPEC section 13: "One .env.example, every variable documented inline".
# An undocumented variable is a variable nobody can discover.

documented=()
while IFS= read -r v; do
    [ -n "$v" ] && documented+=("$v")
done < <(
    grep -oE '^#?[[:space:]]*DBTK_[A-Z0-9_]+=' .env.example \
        | sed -E 's/^#?[[:space:]]*//; s/=$//' | sort -u
)

# Internal variables, deliberately NOT documented in .env.example.
#
# These are not user configuration: they are set by the toolkit itself or baked
# into an image at build time. DBTK_ENGINE in particular is an ENV in each
# MySQL-family Dockerfile that selects which half of the shared init scripts
# applies (D-29); documenting it in .env.example would invite a user to set it
# and quietly mismatch the image they are running.
#
# The rule this check enforces is "every variable a user can meaningfully set
# is documented", so the list is kept explicit and short rather than allowing a
# pattern that could hide a real omission.
INTERNAL_VARS='DBTK_ROOT|DBTK_ENV_FILE|DBTK_IMAGE_PREFIX|DBTK_ENGINE|DBTK_STAGE|DBTK_CONF_DIR|DBTK_CERT_DIR|DBTK_INITDB_DIR|DBTK_DATA_DIR|DBTK_OVERRIDE_CONF_DIR|DBTK_DAEMON|DBTK_CLIENT|DBTK_ADMIN|DBTK_CONF_SECTION|DBTK_ROOT_PW_ENV'

# Only files that actually consume variables at runtime. Scripts under
# scripts/verify are excluded: they name variables in order to assert on them,
# which is not the same as depending on them being configured.
used=()
while IFS= read -r v; do
    [ -n "$v" ] && used+=("$v")
done < <(
    grep -rhoE '\bDBTK_[A-Z0-9_]+' \
        --include='*.yml' --include='*.yaml' --include='Dockerfile*' \
        --include='*.tmpl' --include='*.cnf' \
        images caddy overrides . 2>/dev/null \
        | grep -vE "^(${INTERNAL_VARS})\$" | sort -u
)

if (( ${#used[@]} == 0 )); then
    vinfo "no DBTK_ variables consumed yet; ${#documented[@]} documented and ready"
    exit 0
fi

missing=0
for v in "${used[@]}"; do
    [[ "$v" == "DBTK_ROOT" ]] && continue
    if ! printf '%s\n' "${documented[@]}" | grep -qx "$v"; then
        printf '      %s is used but not documented in .env.example\n' "$v" >&2
        (( missing++ )) || true
    fi
done

(( missing == 0 )) || vfail "$missing undocumented DBTK_ variable(s)"

vinfo "${#used[@]} variable(s) in use, all documented"
