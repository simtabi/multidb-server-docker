#!/usr/bin/env bash
# verify: Caddy serves every UI over HTTPS and phpMyAdmin sees both engines
# tags: ui caddy
# phase: 4

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need_docker
cd "$DBTK_ROOT" || exit 1

# SPEC section 18: "Caddy serves every UI at its *.db.localhost hostname over
# HTTPS" and "Both MySQL and MariaDB run concurrently with phpMyAdmin seeing
# both via one UI".

need_file "$DBTK_ROOT/caddy/Caddyfile.tmpl"
need_file "$DBTK_ROOT/docker-compose.yml"

domain="$(env_get DBTK_UI_DOMAIN db.localhost)"

make up PROFILES=pg,mysql,mariadb,ui >/dev/null 2>&1 || vfail "make up with the ui profile failed"
trap 'make down >/dev/null 2>&1 || true' EXIT

# shellcheck disable=SC2016  # evaluated by the subshell, not here
wait_for 90 "caddy to start" bash -c \
    'docker compose ps --format "{{.Service}}" | grep -q "^caddy$"'

# Each UI must answer over HTTPS through Caddy. Caddy's internal CA is not in
# any trust store, so -k is correct here; what we assert is that TLS is served
# and the app responds, not that the local CA chains to a public root.
for ui in adminer pgadmin pma; do
    code="$(docker compose exec -T caddy \
        wget -qO /dev/null --no-check-certificate --server-response \
        "https://${ui}.${domain}/" 2>&1 | awk '/HTTP\//{print $2}' | tail -1 || true)"
    case "$code" in
        200|301|302) vinfo "https://${ui}.${domain} -> $code" ;;
        *) vfail "https://${ui}.${domain} returned '${code:-no response}'" ;;
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
