#!/usr/bin/env bash
# verify: no credential is committed anywhere in the repository
# tags: fast security
# phase: 1

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "$DBTK_ROOT" || exit 1

# SPEC section 18: "repo/image-history grep finds no credential".
# Passwords travel by the _FILE convention only, so an assignment with a
# literal value on the right-hand side is a finding by definition.

files=()
if [[ -d .git ]]; then
    while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done < <(git ls-files)
else
    while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done \
        < <(find . -type f -not -path './.git/*' | sed 's|^\./||')
fi

violations=0
report() { printf '      %s\n' "$*" >&2; (( violations++ )) || true; }

for f in "${files[@]}"; do
    [[ -f "$f" ]] || continue
    case "$f" in
        docs/SPEC.md|docs/KIT.md|DESIGN.md|docs/KICKOFF-PROMPT.txt) continue ;;
        scripts/verify/03-secret-scan-repo.sh) continue ;;
    esac

    # PASSWORD= / PASSWD= / SECRET= / _KEY= with a non-empty literal that is not
    # a _FILE reference, a variable expansion, or a commented example.
    while IFS= read -r hit; do
        value="${hit#*=}"
        [[ -z "$value" ]] && continue
        case "$value" in
            *\$\{*|*\$\(*|__FILE__*|secrets/*|*_FILE|CHANGE_ME*) continue ;;
        esac
        report "$f: $hit"
    done < <(grep -nhE '^[^#]*(PASSWORD|PASSWD|SECRET|PRIVATE_KEY|ACCESS_KEY)[A-Z_]*=[^[:space:]]+' "$f" 2>/dev/null || true)

    # Private key material must never be committed.
    if grep -qE 'BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY' "$f" 2>/dev/null; then
        report "$f: contains private key material"
    fi
done

# certs/ and secrets/ must be ignored, not tracked.
for d in certs secrets; do
    if [[ -d .git ]]; then
        while IFS= read -r tracked; do
            [[ "$(basename "$tracked")" == ".gitkeep" ]] && continue
            report "$tracked is tracked; $d/ contents must stay gitignored"
        done < <(git ls-files "$d" 2>/dev/null || true)
    fi
done

(( violations == 0 )) || vfail "$violations potential credential(s) committed"

vinfo "scanned ${#files[@]} tracked file(s); no credentials found"
