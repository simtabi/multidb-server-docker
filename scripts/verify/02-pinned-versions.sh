#!/usr/bin/env bash
# verify: no floating tags anywhere; every upstream image is digest-pinned
# tags: fast structure security
# phase: 1

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "$DBTK_ROOT" || exit 1

# DESIGN.md D-05 is why this check exists rather than being a convention:
# nfrastack/db-backup:latest currently publishes ONLY linux/arm64, so an amd64
# runner following a floating tag fails outright. Pinning prevents it.

candidates=()
while IFS= read -r f; do
    [ -n "$f" ] && candidates+=("$f")
done < <(
    find . -type f \( -name 'Dockerfile*' -o -name 'docker-compose*.yml' -o -name 'compose*.yml' \) \
        -not -path './.git/*' | sort
)

if (( ${#candidates[@]} == 0 )); then
    vinfo "no Dockerfiles, compose files, or workflows exist yet"
    exit 0
fi

violations=0

for f in "${candidates[@]}"; do
    # A FROM or image: referencing :latest, or carrying no tag at all.
    while IFS= read -r line; do
        printf '      %s: %s\n' "${f#./}" "$line" >&2
        (( violations++ )) || true
    done < <(grep -nE '^[^#]*(FROM|image:)[[:space:]]+[^[:space:]]+:latest' "$f" || true)

    # Any FROM/image without an @sha256 digest.
    while IFS= read -r line; do
        case "$line" in
            *@sha256:*|*\$\{*|*scratch*) continue ;;
        esac
        printf '      %s: not digest-pinned: %s\n' "${f#./}" "$line" >&2
        (( violations++ )) || true
    done < <(grep -nE '^[^#]*(FROM|image:)[[:space:]]+[a-zA-Z0-9]' "$f" || true)
done

(( violations == 0 )) || vfail "$violations unpinned image reference(s); CLAUDE.md requires pinned digests, no latest"

vinfo "checked ${#candidates[@]} file(s); all image references pinned"
