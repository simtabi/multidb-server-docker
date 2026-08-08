#!/usr/bin/env bash
#
# The optional embedded metrics exporter.
#
# SPEC section 6.1: embedded helpers exist so a standalone `docker run` can
# self-report without the rest of the stack. They are OFF by default and stay
# off under compose, which runs the exporter as its own service instead --
# one concern per container, except where the container IS the whole stack.

DBTK_STAGE=dbtk-exporter
export DBTK_STAGE
# The absolute path is correct inside the image; this tells shellcheck where
# to find the same file in the repository.
# shellcheck source=dbtk-lib.sh
source /usr/local/lib/dbtk/dbtk-lib.sh

if ! is_true "${DBTK_PG_EMBED_EXPORTER:-false}"; then
    stage "embedded exporter disabled (DBTK_PG_EMBED_EXPORTER); idling"
    # s6 supervises longruns and restarts them when they exit, so a disabled
    # service cannot simply return -- that would be a restart loop. Blocking
    # forever costs one sleeping process and no CPU, and keeps the service
    # definition static rather than rewriting the s6 tree at boot.
    exec tail -f /dev/null
fi

stage "starting postgres_exporter on :9187"

# Connects over the local unix socket as the postgres OS user, so no password
# is needed and no credential has to be handed to the exporter. The official
# image's pg_hba trusts local socket connections; TCP still requires scram.
export DATA_SOURCE_NAME="postgresql:///${POSTGRES_DB:-postgres}?host=/var/run/postgresql&sslmode=disable"

exec s6-setuidgid postgres \
    /usr/local/bin/postgres_exporter \
    --web.listen-address=":9187" \
    --web.telemetry-path="/metrics"
