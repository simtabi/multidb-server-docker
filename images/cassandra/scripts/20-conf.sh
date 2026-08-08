#!/usr/bin/env bash
#
# Enable authentication and authorization.
#
# The upstream image ships:
#   authenticator: AllowAllAuthenticator
#   authorizer:    AllowAllAuthorizer
#
# Which means no credentials are required and no permissions are enforced.
# SPEC section 9 forbids that anywhere, and SPEC section 22.3 makes correcting
# it a build-time default for every engine in this toolkit.
#
# These are edited in cassandra.yaml rather than passed as environment, because
# the image's entrypoint templates only a handful of settings and these are not
# among them.

DBTK_STAGE=dbtk-conf
export DBTK_STAGE
# shellcheck source=dbtk-lib.sh
source /usr/local/lib/dbtk/dbtk-lib.sh

stage "enabling authentication and authorization"

sed -i \
    -e 's/^authenticator:.*/authenticator: PasswordAuthenticator/' \
    -e 's/^authorizer:.*/authorizer: CassandraAuthorizer/' \
    -e 's/^role_manager:.*/role_manager: CassandraRoleManager/' \
    "$DBTK_CONF"

grep -q '^authenticator: PasswordAuthenticator' "$DBTK_CONF" \
    || die "could not enable PasswordAuthenticator; refusing to start wide open"
grep -q '^authorizer: CassandraAuthorizer' "$DBTK_CONF" \
    || die "could not enable CassandraAuthorizer; refusing to start wide open"

# With authentication on, the system_auth keyspace holds the credentials. Its
# default replication factor of 1 means losing one node loses the ability to
# log in, so it is raised on any real cluster; a single-node dev instance
# cannot exceed 1.
stage "authentication and authorization enabled"

# A mounted override wins, as everywhere else in the toolkit.
if [ -d /dbtk/overrides ] && [ -n "$(ls -A /dbtk/overrides 2>/dev/null)" ]; then
    cp -f /dbtk/overrides/*.yaml /etc/cassandra/ 2>/dev/null || true
    stage "applied mounted overrides"
fi
