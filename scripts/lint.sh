#!/usr/bin/env bash
#
# Run shellcheck over every shell script here. Must pass with no warnings.
# (This line must not begin with the tool's name, or it parses as a directive.)
#
# Written for bash 3.2, because that is what macOS ships and SPEC section 1
# makes macOS a first-class platform. No mapfile, no associative arrays.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

if ! command -v shellcheck >/dev/null 2>&1; then
    printf 'shellcheck is not installed.\n' >&2
    printf '  macOS:  brew install shellcheck\n' >&2
    printf '  Debian: apt-get install shellcheck\n' >&2
    exit 1
fi

files=()

while IFS= read -r f; do
    [ -n "$f" ] && files+=("$f")
done < <(find . -type f \( -name '*.sh' -o -name '*.bash' \) -not -path './.git/*' | sort)

# Extensionless executables under scripts/ are scripts too.
for f in scripts/*; do
    [ -f "$f" ] || continue
    [ -x "$f" ] || continue
    case "$f" in
        *.sh|*.bash) continue ;;
    esac
    files+=("$f")
done

if [ ${#files[@]} -eq 0 ]; then
    printf 'no shell scripts found\n'
    exit 0
fi

printf 'shellcheck: %d file(s)\n' "${#files[@]}"
# -x follows `source` directives so lib.sh helpers resolve instead of raising
# SC1091 in every check.
shellcheck -x --severity=style --color=auto "${files[@]}"
printf '✓ shellcheck clean\n'
