#!/usr/bin/env bash
# verify: every shell script is shellcheck-clean
# tags: fast structure
# phase: 1

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v shellcheck >/dev/null 2>&1 \
    || vfail "shellcheck is not installed; CONTRIBUTING.md requires it (brew install shellcheck)"

output="$("$MMDB_ROOT/scripts/lint.sh" 2>&1)" || {
    printf '%s\n' "$output" >&2
    vfail "shellcheck reported problems"
}

vinfo "$(printf '%s' "$output" | head -1)"
