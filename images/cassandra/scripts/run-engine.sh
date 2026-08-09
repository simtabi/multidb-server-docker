#!/usr/bin/env bash
#
# The supervised engine. As with every other engine here, the upstream
# entrypoint owns first-run initialisation and we invoke it rather than
# reimplementing it (SPEC section 6.1).

MMDB_STAGE=mmdb-engine
export MMDB_STAGE
# shellcheck source=mmdb-lib.sh
source /usr/local/lib/mmdb/mmdb-lib.sh

stage "starting Cassandra via the official entrypoint"
exec /usr/local/bin/docker-entrypoint.sh cassandra -f
