#!/usr/bin/env bash
#
# Stage 1: ownership and permissions.
#
# This must run before certificates are placed: PostgreSQL refuses to start if
# a server key is group- or world-readable, so the order in the s6 dependency
# graph is not cosmetic.

MMDB_STAGE=mmdb-perms
export MMDB_STAGE
# The absolute path is correct inside the image; this tells shellcheck where
# to find the same file in the repository.
# shellcheck source=mmdb-lib.sh
source /usr/local/lib/mmdb/mmdb-lib.sh

stage "fixing ownership and permissions"

install -d -o postgres -g postgres -m 0775 /var/run/postgresql
install -d -o postgres -g postgres -m 0700 "$MMDB_CERT_DIR"
install -d -m 0755 "$MMDB_CONF_DIR"
install -d -m 0755 "$MMDB_INITDB_DIR"

# The data directory itself is created and chmodded by the official entrypoint
# on first run. On subsequent runs we only correct the parent, never PGDATA, so
# we cannot fight the upstream initdb behaviour.
if [[ -d "$(dirname "$PGDATA_DIR")" ]]; then
    chown postgres:postgres "$(dirname "$PGDATA_DIR")" 2>/dev/null || true
fi

if pgdata_initialised; then
    stage "existing data directory detected at $PGDATA_DIR"
else
    stage "no data directory yet; the official entrypoint will run initdb"
fi
