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

MMDB_STAGE=mmdb-engine
export MMDB_STAGE
# shellcheck source=mmdb-lib.sh
source /usr/local/lib/mmdb/mmdb-lib.sh

stage "starting $MMDB_DAEMON via the official entrypoint"

exec /usr/local/bin/docker-entrypoint.sh "$MMDB_DAEMON"
