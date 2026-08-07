#!/usr/bin/env bash
#
# Stage 1: ownership and permissions.

DBTK_STAGE=dbtk-perms
export DBTK_STAGE
# The absolute path is correct inside the image; this tells shellcheck where
# to find the same file in the repository.
# shellcheck source=dbtk-lib.sh
source /usr/local/lib/dbtk/dbtk-lib.sh

stage "fixing ownership and permissions ($DBTK_ENGINE)"

install -d -o mysql -g mysql -m 0755 /var/run/mysqld
install -d -o mysql -g mysql -m 0700 "$DBTK_CERT_DIR"
install -d -m 0755 "$DBTK_CONF_DIR"
install -d -m 0755 "$DBTK_INITDB_DIR"

if datadir_initialised; then
    stage "existing data directory detected at $DBTK_DATA_DIR"
else
    stage "no data directory yet; the official entrypoint will initialise it"
fi
