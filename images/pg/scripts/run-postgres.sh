#!/usr/bin/env bash
#
# The supervised engine service.
#
# SPEC section 6.1 names this as the integration risk to respect: the upstream
# docker-entrypoint.sh owns first-run initdb, the POSTGRES_* env semantics, the
# _FILE convention, and /docker-entrypoint-initdb.d. We invoke it; we do not
# reimplement it. Everything my-multidb-server adds has already happened in the init
# stages before this point.
#
# Runs as root on purpose: the official entrypoint re-executes itself as the
# postgres user via gosu, and letting it do that keeps first-run behaviour
# byte-for-byte compatible with the official image (DESIGN.md D-19).

MMDB_STAGE=mmdb-postgres
export MMDB_STAGE
# The absolute path is correct inside the image; this tells shellcheck where
# to find the same file in the repository.
# shellcheck source=mmdb-lib.sh
source /usr/local/lib/mmdb/mmdb-lib.sh

stage "starting PostgreSQL via the official entrypoint"

# Optional embedded helpers exist so a standalone `docker run` can self-report
# and self-back-up. They are OFF under compose, which runs them as separate
# services instead (SPEC section 6.1).
if is_true "${MMDB_PG_EMBED_EXPORTER:-false}"; then
    stage "embedded exporter requested"
fi

exec /usr/local/bin/docker-entrypoint.sh postgres
