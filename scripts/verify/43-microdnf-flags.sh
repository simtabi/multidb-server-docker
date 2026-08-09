#!/usr/bin/env bash
# verify: no Dockerfile passes a dnf-only flag to microdnf
# tags: fast images
# phase: 1

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# microdnf is not dnf, and the ways it is not are discovered one CI round at a
# time. It is a deliberately minimal client: it takes install/update/remove/
# clean/repoquery and a short list of options, and it rejects anything else
# outright with "error: Unknown option --x" -- at BUILD time, on a runner,
# minutes into a matrix job.
#
# Two of those cost a round trip each here. `microdnf remove --noautoremove`
# was written to keep rpm from garbage-collecting openssl-libs along with
# mysql-shell; the option is dnf's and microdnf has never had it. The fix,
# `microdnf update --exclude='mysql*'`, was the same mistake again -- microdnf
# has no --exclude either (rpm-software-management/microdnf#119, open since
# 2020) -- and that one broke two engine versions that had just gone green.
#
# What works is --disablerepo, which microdnf does support. That is not
# something to remember; it is something to enforce. Any future dnf habit --
# --best, --allowerasing, --nobest, --skip-broken -- fails the same way and is
# equally invisible on a laptop that never runs the build.
#
# The list is dnf options that microdnf(8) does not document. It is deliberately
# not exhaustive: it covers the ones plausibly reached for while hardening or
# trimming an image, which is what these Dockerfiles do.

cd "$MDB_ROOT" || exit 1

# Flags dnf accepts and microdnf does not.
dnf_only="--noautoremove --exclude --best --nobest --allowerasing --skip-broken
          --downloadonly --security --bugfix --obsoletes --refresh --assumeno"

offenders=""
scanned=0

while IFS= read -r df; do
    [[ -f "$df" ]] || continue
    scanned=$(( scanned + 1 ))

    # Only lines that actually invoke microdnf. A comment mentioning --exclude
    # -- like the one in images/mysql/Dockerfile explaining why it is absent --
    # is documentation, not a call, and failing on it would push people to
    # delete the explanation.
    while IFS= read -r line; do
        code="${line%%#*}"
        case "$code" in *microdnf*) ;; *) continue ;; esac
        for flag in $dnf_only; do
            case "$code" in
                *"$flag"*)
                    offenders+="        ${df#./}: $flag in: $(printf '%s' "$code" | sed 's/^[[:space:]]*//' | cut -c1-60)"$'\n'
                    ;;
            esac
        done
    done < "$df"
done < <(find "$MDB_ROOT/images" -name Dockerfile -type f 2>/dev/null)

(( scanned > 0 )) || vfail "no Dockerfiles found under images/; this check would pass vacuously"

if [[ -n "$offenders" ]]; then
    printf '%s' "$offenders" >&2
    vfail "a Dockerfile passes a dnf-only flag to microdnf; the build fails with
       'Unknown option' on the runner. microdnf supports --disablerepo,
       --enablerepo, --setopt and --nodocs; it does not support dnf's
       package-selection or transaction flags."
fi

vinfo "$scanned Dockerfile(s): no dnf-only flags passed to microdnf"
