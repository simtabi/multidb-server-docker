#!/usr/bin/env bash
MDB_STAGE=mdb-perms
export MDB_STAGE
# shellcheck source=mdb-lib.sh
source /usr/local/lib/mdb/mdb-lib.sh

stage "fixing ownership and permissions"
install -d -o cassandra -g cassandra -m 0700 "$MDB_DATA_DIR"
install -d -m 0755 /mdb/overrides /run/mdb
