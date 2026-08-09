#!/usr/bin/env bash
# verify: every vulnerability waiver carries a reason and a revisit condition
# tags: fast security
# phase: 1

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "$MDB_ROOT" || exit 1

# SPEC section 18, criterion 11b: "trivy clean or waived with notes".
#
# The "with notes" half is the part that decays. A scanner is easy to make
# green by pasting CVE IDs into an ignore file, and six months later nobody can
# tell which of them were reasoned about and which were pasted to unblock a
# build. This check makes that impossible: a bare ID fails.
#
# It deliberately does NOT run trivy. Scanning belongs in CI, where the images
# exist and the vulnerability database can be fetched; what belongs in the
# harness is the discipline around the waivers, which is checkable offline and
# in a second.

need_file "$MDB_ROOT/.trivyignore"

# CI must actually scan. A waiver file is meaningless if nothing enforces it,
# and this is exactly the pairing that rots -- the scan step gets removed to
# unblock something and the ignore file stays, looking like coverage.
grep -q 'trivy image' "$MDB_ROOT/.github/workflows/ci.yml" \
    || vfail "no 'trivy image' scan in .github/workflows/ci.yml; the waiver file implies a scan that does not run"
grep -q 'ignorefile .trivyignore' "$MDB_ROOT/.github/workflows/ci.yml" \
    || vfail "the CI scan does not pass --ignorefile .trivyignore; waivers would be ignored"
vinfo "CI scans images and honours the waiver file"

# The action was compromised in March 2026: 75 of its 76 version tags were
# force-pushed to steal CI secrets. Referencing it by tag is the exact
# supply-chain risk a scanner exists to reduce.
if grep -q 'aquasecurity/trivy-action@v' "$MDB_ROOT/.github/workflows/ci.yml"; then
    vfail "ci.yml uses aquasecurity/trivy-action by tag; that action's tags were
       force-pushed in a 2026 supply-chain attack. Install the pinned binary
       and verify it against the release checksums instead."
fi
vinfo "scanner is a pinned, checksum-verified binary rather than a tagged action"

waivers=0
bad=0

while IFS= read -r line; do
    # Blank lines and pure comments are prose, not waivers.
    case "$line" in ''|'#'*) continue ;; esac

    id="${line%%#*}"
    id="${id//[[:space:]]/}"
    [[ -n "$id" ]] || continue

    waivers=$(( waivers + 1 ))

    # A reason means: something after a '#', on the same line, that is not
    # empty. Requiring the ID and the note to travel together is the whole
    # point -- a note in a header block above a list of IDs drifts away from
    # the entries it was written for.
    case "$line" in
        *'#'*)
            note="${line#*#}"
            note="${note#"${note%%[![:space:]]*}"}"
            if (( ${#note} < 20 )); then
                printf '      %s: reason too short to be a reason\n' "$id" >&2
                bad=$(( bad + 1 ))
            elif [[ "$note" != *"revisit"* ]]; then
                printf '      %s: no revisit condition; a permanent waiver is a decision nobody will re-make\n' "$id" >&2
                bad=$(( bad + 1 ))
            fi
            ;;
        *)
            printf '      %s: waived with no reason at all\n' "$id" >&2
            bad=$(( bad + 1 ))
            ;;
    esac
done < "$MDB_ROOT/.trivyignore"

(( bad == 0 )) || vfail "$bad waiver(s) lack a reason or a revisit condition"

if (( waivers == 0 )); then
    vinfo "no vulnerabilities are waived"
else
    vinfo "$waivers waiver(s), each with a reason and a revisit condition"
fi
