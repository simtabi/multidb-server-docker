#!/usr/bin/env bash
#
# Stage 1: ownership and permissions.

MMDB_STAGE=mmdb-perms
export MMDB_STAGE
# The absolute path is correct inside the image; this tells shellcheck where
# to find the same file in the repository.
# shellcheck source=mmdb-lib.sh
source /usr/local/lib/mmdb/mmdb-lib.sh

stage "fixing ownership and permissions ($MMDB_ENGINE)"

install -d -o mysql -g mysql -m 0755 /var/run/mysqld
install -d -o mysql -g mysql -m 0700 "$MMDB_CERT_DIR"
install -d -m 0755 "$MMDB_CONF_DIR"
install -d -m 0755 "$MMDB_INITDB_DIR"

# The binary log directory, when PITR is on.
#
# Deliberately NOT inside the data directory, which is where MySQL puts binlogs
# by default. A recovery log stored inside the thing it recovers goes when that
# goes -- `make destroy`, a corrupted volume, a botched upgrade -- which is
# every scenario it exists for. 0700 because the binlog contains every row
# written, so it is as sensitive as the data itself.
if is_true "$(engine_env PITR false)"; then
    install -d -o mysql -g mysql -m 0700 "$(dirname "${MMDB_BINLOG_BASENAME:-/var/lib/mmdb-binlog/binlog}")"
fi

if datadir_initialised; then
    stage "existing data directory detected at $MMDB_DATA_DIR"
else
    stage "no data directory yet; the official entrypoint will initialise it"
fi
