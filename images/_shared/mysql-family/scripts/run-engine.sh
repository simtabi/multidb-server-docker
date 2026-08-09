#!/usr/bin/env bash
#
# The supervised engine service.
#
# As with PostgreSQL, the upstream docker-entrypoint.sh owns first-run
# initialisation, the MYSQL_*/MARIADB_* env semantics, the _FILE convention,
# and /docker-entrypoint-initdb.d. We invoke it; we do not reimplement it
# (SPEC section 6.1).
#
# Runs as root so the official entrypoint can drop to the mysql user itself,
# keeping first-run behaviour identical to the official image.

MDB_STAGE=mdb-engine
export MDB_STAGE
# shellcheck source=mdb-lib.sh
source /usr/local/lib/mdb/mdb-lib.sh

stage "starting $MDB_DAEMON via the official entrypoint"

exec /usr/local/bin/docker-entrypoint.sh "$MDB_DAEMON"
