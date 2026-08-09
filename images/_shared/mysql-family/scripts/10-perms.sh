#!/usr/bin/env bash
#
# Stage 1: ownership and permissions.

MDB_STAGE=mdb-perms
export MDB_STAGE
# The absolute path is correct inside the image; this tells shellcheck where
# to find the same file in the repository.
# shellcheck source=mdb-lib.sh
source /usr/local/lib/mdb/mdb-lib.sh

stage "fixing ownership and permissions ($MDB_ENGINE)"

install -d -o mysql -g mysql -m 0755 /var/run/mysqld
install -d -o mysql -g mysql -m 0700 "$MDB_CERT_DIR"
install -d -m 0755 "$MDB_CONF_DIR"
install -d -m 0755 "$MDB_INITDB_DIR"

# The binary log directory, when PITR is on.
#
# Deliberately NOT inside the data directory, which is where MySQL puts binlogs
# by default. A recovery log stored inside the thing it recovers goes when that
# goes -- `make destroy`, a corrupted volume, a botched upgrade -- which is
# every scenario it exists for. 0700 because the binlog contains every row
# written, so it is as sensitive as the data itself.
if is_true "$(engine_env PITR false)"; then
    install -d -o mysql -g mysql -m 0700 "$(dirname "${MDB_BINLOG_BASENAME:-/var/lib/mdb-binlog/binlog}")"
fi

if datadir_initialised; then
    stage "existing data directory detected at $MDB_DATA_DIR"
else
    stage "no data directory yet; the official entrypoint will initialise it"
fi
