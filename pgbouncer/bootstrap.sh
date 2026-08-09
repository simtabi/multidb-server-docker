#!/bin/sh
#
# Hand pgBouncer its own credential, then start it.
#
# The image has no _FILE convention and its own entrypoint warns that
# `docker inspect` exposes environment variables. So the password is read from
# the mounted secret into the process environment of PID 1 at exec time: never
# in an image layer, never in the compose file, never in `docker inspect`.
#
# This is the ONLY credential pgBouncer holds. Application users are resolved
# with auth_query against a narrow SECURITY DEFINER function -- see
# docs/pooling.md.

set -eu

[ -r "${DB_PASSWORD_FILE:?DB_PASSWORD_FILE is required}" ] \
    || { echo "pgbouncer: cannot read $DB_PASSWORD_FILE" >&2; exit 1; }

DB_PASSWORD="$(tr -d '\n' < "$DB_PASSWORD_FILE")"
export DB_PASSWORD

exec /entrypoint.sh /usr/bin/pgbouncer /etc/pgbouncer/pgbouncer.ini
