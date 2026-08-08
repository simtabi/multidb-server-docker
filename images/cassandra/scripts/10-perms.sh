#!/usr/bin/env bash
DBTK_STAGE=dbtk-perms
export DBTK_STAGE
# shellcheck source=dbtk-lib.sh
source /usr/local/lib/dbtk/dbtk-lib.sh

stage "fixing ownership and permissions"
install -d -o cassandra -g cassandra -m 0700 "$DBTK_DATA_DIR"
install -d -m 0755 /dbtk/overrides /run/dbtk
