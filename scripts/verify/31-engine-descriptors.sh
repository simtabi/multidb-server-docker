#!/usr/bin/env bash
# verify: every engine descriptor is complete, consistent, and honestly declared
# tags: fast structure engines
# phase: 6

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=../engine-lib.sh
source "$DBTK_ROOT/scripts/engine-lib.sh"

cd "$DBTK_ROOT" || exit 1

# SPEC section 22.1: engines are declared, not hardcoded. This check is what
# makes that a rule rather than an intention — a descriptor missing a key would
# otherwise surface as a confusing runtime failure several layers away from the
# file that actually needs fixing.

engines="$(engine_list)"
[[ -n "$engines" ]] || vfail "no engine descriptors found in engines/"

count=0
for e in $engines; do
    engine_load "$e" || vfail "could not load the descriptor for '$e'"
    rel="${DBTK_ENGINE_CONF#"$DBTK_ROOT"/}"

    for key in $DBTK_ENGINE_REQUIRED_KEYS; do
        [[ -n "${!key:-}" ]] || vfail "$rel: required key $key is missing or empty"
    done

    # The default version must be one the engine actually supports, or every
    # consumer picks a version with no pinned base image.
    engine_supports_version "$DBTK_ENGINE_DEFAULT_VERSION" \
        || vfail "$rel: default version $DBTK_ENGINE_DEFAULT_VERSION is not in VERSIONS ($DBTK_ENGINE_VERSIONS)"

    # Every supported version needs a digest-pinned base.
    for v in $DBTK_ENGINE_VERSIONS; do
        awk -v e="$DBTK_ENGINE_NAME" -v v="$v" '$1==e && $2==v {found=1} END {exit !found}' \
            images/bases.tsv \
            || vfail "$rel: version $v has no pinned base in images/bases.tsv"
    done

    case "$DBTK_ENGINE_PARADIGM" in
        relational|document|wide-column|key-value) ;;
        *) vfail "$rel: unknown paradigm '$DBTK_ENGINE_PARADIGM'" ;;
    esac

    # Pooling must be one of the two honest answers. SPEC section 22.4 is
    # explicit that a uniform pooling abstraction would be a lie, so a
    # descriptor has to commit to external or driver.
    case "$DBTK_ENGINE_POOLING" in
        external)
            [[ -n "${DBTK_ENGINE_POOLER_IMAGE:-}" ]] \
                || vfail "$rel: pooling=external but no POOLER_IMAGE declared"
            [[ "$DBTK_ENGINE_POOLER_IMAGE" == *"@sha256:"* ]] \
                || vinfo "note: $DBTK_ENGINE_NAME pooler image is not digest-pinned yet"
            ;;
        driver)
            [[ -z "${DBTK_ENGINE_POOLER_IMAGE:-}" ]] \
                || vfail "$rel: pooling=driver but a POOLER_IMAGE is declared; pick one"
            [[ -n "${DBTK_ENGINE_POOLING_RATIONALE:-}" ]] \
                || vfail "$rel: pooling=driver must say WHY, so the docs can explain it"
            ;;
        *) vfail "$rel: pooling must be 'external' or 'driver', got '$DBTK_ENGINE_POOLING'" ;;
    esac

    # Licensing is load-bearing for an OSS project that publishes images.
    # A non-OSI licence is allowed, but it must be labelled rather than
    # discovered by a user later.
    # Licensing decides what we are allowed to PUBLISH, not merely what to
    # document. Every artefact this repository publishes should be
    # OSI-licensed, so that a downstream user never has to reason about our
    # supply chain to know what they are running.
    #
    # A source-available engine is still fully supported — it is referenced
    # from its upstream image rather than rebuilt under our namespace, which
    # leaves the licence obligation where it belongs.
    case "${DBTK_ENGINE_PUBLISH:-}" in
        derive|reference) ;;
        *) vfail "$rel: PUBLISH must be 'derive' or 'reference', got '${DBTK_ENGINE_PUBLISH:-unset}'" ;;
    esac

    case "$DBTK_ENGINE_OSI_APPROVED" in
        true) ;;
        false)
            [[ -n "${DBTK_ENGINE_LICENSE_NOTE:-}" ]] \
                || vfail "$rel: OSI_APPROVED=false requires a LICENSE_NOTE explaining the implications"
            [[ "$DBTK_ENGINE_PUBLISH" == "reference" ]] \
                || vfail "$rel: $DBTK_ENGINE_LICENSE is not OSI-approved, so PUBLISH must be 'reference'.
       Publishing a derived image would distribute non-OSI binaries under an
       MIT project's namespace. Reference the upstream image instead."
            vinfo "$DBTK_ENGINE_NAME: $DBTK_ENGINE_LICENSE is not OSI-approved; referenced, not published"
            ;;
        *) vfail "$rel: OSI_APPROVED must be true or false, got '$DBTK_ENGINE_OSI_APPROVED'" ;;
    esac

    # An engine that upstream ships without authentication must say so, because
    # the image is then obliged to correct it (SPEC section 22.3).
    if [[ "${DBTK_ENGINE_AUTH_OFF_BY_DEFAULT_UPSTREAM:-false}" == "true" ]]; then
        vinfo "$DBTK_ENGINE_NAME: upstream ships auth OFF; the image must enable it"
    fi

    count=$(( count + 1 ))
    vinfo "$(printf '%-10s %-12s pooling=%-9s %s' \
        "$DBTK_ENGINE_NAME" "$DBTK_ENGINE_PARADIGM" "$DBTK_ENGINE_POOLING" "$DBTK_ENGINE_LICENSE")"
done

vinfo "$count engine descriptor(s) valid"

# Loading one engine must not leave another's values behind, or a consumer
# iterating over engines silently uses stale settings for the optional keys.
engine_load cassandra >/dev/null 2>&1 || true
heavy_after_cassandra="${DBTK_ENGINE_HEAVY:-unset}"
engine_load pg >/dev/null 2>&1 || true
heavy_after_pg="${DBTK_ENGINE_HEAVY:-unset}"

[[ "$heavy_after_cassandra" == "true" && "$heavy_after_pg" == "unset" ]] \
    || vfail "descriptor state leaks between loads (HEAVY was '$heavy_after_pg' after loading pg)"
vinfo "descriptor loads are isolated: no state leaks between engines"
