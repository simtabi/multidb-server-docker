#!/usr/bin/env bash
#
# The supervised engine. As with every other engine here, the upstream
# entrypoint owns first-run initialisation and we invoke it rather than
# reimplementing it (SPEC section 6.1).

MDB_STAGE=mdb-engine
export MDB_STAGE
# shellcheck source=mdb-lib.sh
source /usr/local/lib/mdb/mdb-lib.sh

stage "starting Cassandra via the official entrypoint"
exec /usr/local/bin/docker-entrypoint.sh cassandra -f
