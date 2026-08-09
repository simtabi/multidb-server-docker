#!/usr/bin/env bash
# verify: Caddy serves every UI over HTTPS and phpMyAdmin sees both engines
# tags: ui caddy
# phase: 4

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need_docker
cd "$MDB_ROOT" || exit 1

# SPEC section 18: "Caddy serves every UI at its *.db.localhost hostname over
# HTTPS" and "Both MySQL and MariaDB run concurrently with phpMyAdmin seeing
# both via one UI".

need_file "$MDB_ROOT/caddy/Caddyfile.tmpl"
need_file "$MDB_ROOT/docker-compose.yml"

domain="$(env_get MDB_UI_DOMAIN db.localhost)"

make up PROFILES=pg,mysql,mariadb,ui >/dev/null 2>&1 || vfail "make up with the ui profile failed"
add_cleanup 'make down'

# shellcheck disable=SC2016  # evaluated by the subshell, not here
wait_for 90 "caddy to start" bash -c \
    'docker compose ps --format "{{.Service}}" | grep -q "^caddy$"'

# Each UI must answer over HTTPS through Caddy. Caddy's internal CA is not in
# any trust store, so --no-check-certificate is correct here; what is asserted
# is that TLS is served and the app responds, not that the local CA chains to a
# public root.
#
# "Container running" is NOT readiness: pgAdmin's container reports running
# roughly 25 seconds before gunicorn starts listening, and Caddy answers 502 in
# the meantime. So each route is polled until it answers, with a budget -- a UI
# that never comes up still fails.
ui_status() {
    docker compose exec -T caddy \
        wget -qO /dev/null --no-check-certificate --server-response \
        "https://${1}.${domain}/" 2>&1 \
        | awk '$1 ~ /^HTTP\// {print $2}' | tail -1
}

for ui in adminer pgadmin pma; do
    code=""
    for _ in $(seq 1 60); do
        code="$(ui_status "$ui" || true)"
        case "$code" in
            200|301|302) break ;;
        esac
        sleep 2
    done
    case "$code" in
        200|301|302) vinfo "https://${ui}.${domain} -> $code" ;;
        *) vfail "https://${ui}.${domain} returned '${code:-no response}' after 120s" ;;
    esac
done

# phpMyAdmin must be wired to both MySQL-family servers via PMA_HOSTS.
hosts="$(docker compose exec -T phpmyadmin printenv PMA_HOSTS 2>/dev/null | tr -d ' \r' || true)"
[[ "$hosts" == *mysql* && "$hosts" == *mariadb* ]] \
    || vfail "PMA_HOSTS is '$hosts'; it must list both mysql and mariadb"
vinfo "phpMyAdmin PMA_HOSTS=$hosts"

# Adminer and pgAdmin must open ready to log in, not asking for a hostname.
server="$(docker compose exec -T adminer printenv ADMINER_DEFAULT_SERVER 2>/dev/null | tr -d ' \r' || true)"
[[ -n "$server" ]] || vfail "ADMINER_DEFAULT_SERVER is unset; SPEC section 7 requires UIs pre-wired"
vinfo "Adminer default server: $server"

docker compose exec -T pgadmin test -f /pgadmin4/servers.json 2>/dev/null \
    || vfail "pgAdmin has no baked servers.json; SPEC section 7 requires it pre-provisioned"
vinfo "pgAdmin servers.json present"
