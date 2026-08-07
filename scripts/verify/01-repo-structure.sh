#!/usr/bin/env bash
# verify: repository layout matches SPEC.md section 15
# tags: fast structure
# phase: 1

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "$DBTK_ROOT" || exit 1

for d in images/pg images/mysql images/mariadb images/cli \
         overrides/pg overrides/mysql overrides/mariadb \
         caddy scripts scripts/verify rls docs .github/workflows; do
    need_dir "$DBTK_ROOT/$d"
done

for f in Makefile .env.example .gitignore .gitattributes .editorconfig \
         README.md CONTRIBUTING.md SECURITY.md CODE_OF_CONDUCT.md CHANGELOG.md LICENSE \
         CLAUDE.md DESIGN.md docs/SPEC.md docs/KIT.md; do
    need_file "$DBTK_ROOT/$f"
done

# SPEC section 15 requires named volumes for data, never bind mounts: WSL2
# performance and file permissions both depend on it.
if [[ -f docker-compose.yml ]]; then
    if grep -nE '^\s*-\s*\./.*:/var/lib/(postgresql|mysql)' docker-compose.yml; then
        vfail "data is bind-mounted; SPEC section 15 requires named volumes"
    fi
fi

# The org convention forbids a second README acting as a docs index.
if [[ -f docs/README.md ]]; then
    vfail "docs/README.md exists; the docs index is README.md's Documentation section"
fi

vinfo "layout matches SPEC section 15"
