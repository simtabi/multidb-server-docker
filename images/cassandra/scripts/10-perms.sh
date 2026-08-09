#!/usr/bin/env bash
MMDB_STAGE=mmdb-perms
export MMDB_STAGE
# shellcheck source=mmdb-lib.sh
source /usr/local/lib/mmdb/mmdb-lib.sh

stage "fixing ownership and permissions"
install -d -o cassandra -g cassandra -m 0700 "$MMDB_DATA_DIR"
install -d -m 0755 /mmdb/overrides /run/mmdb
