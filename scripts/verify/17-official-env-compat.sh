#!/usr/bin/env bash
# verify: our images honour the official images' env and initdb.d semantics
# tags: compat
# phase: 3

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need_docker

# SPEC section 6.1 names this as the integration risk to respect: the upstream
# entrypoints own first-run init, the POSTGRES_*/MYSQL_* env semantics, the
# _FILE convention, and /docker-entrypoint-initdb.d. s6 WRAPS them; it must not
# replace them. This check is what proves we did not quietly reimplement them.

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- POSTGRES_* scenarios -----------------------------------------------------
img="$(image_name pg)"
need_image "$img"

printf 'filepass123\n' > "$tmp/pgpass"
printf 'CREATE TABLE initdb_ran(v text);\nINSERT INTO initdb_ran VALUES ('"'"'yes'"'"');\n' > "$tmp/01-init.sql"

name="dbtk-verify-compat-pg-$$"
track_container "$name"

# POSTGRES_PASSWORD_FILE (the _FILE convention), POSTGRES_USER, POSTGRES_DB,
# and a mounted initdb.d script must all behave exactly as upstream.
docker run -d --name "$name" \
    -e POSTGRES_PASSWORD_FILE=/run/secrets/pgpass \
    -e POSTGRES_USER=custom_user \
    -e POSTGRES_DB=custom_db \
    -v "$tmp/pgpass:/run/secrets/pgpass:ro" \
    -v "$tmp/01-init.sql:/docker-entrypoint-initdb.d/01-init.sql:ro" \
    "$img" >/dev/null || vfail "PG failed to start with POSTGRES_PASSWORD_FILE"

wait_for 60 "custom_user to accept connections" \
    docker exec "$name" pg_isready -U custom_user -d custom_db

docker exec -e PGPASSWORD=filepass123 "$name" \
    psql -U custom_user -d custom_db -tAc "SELECT 1" >/dev/null 2>&1 \
    || vfail "POSTGRES_PASSWORD_FILE was not honoured"
vinfo "POSTGRES_PASSWORD_FILE, POSTGRES_USER, POSTGRES_DB honoured"

ran="$(docker exec -e PGPASSWORD=filepass123 "$name" \
    psql -U custom_user -d custom_db -tAc "SELECT v FROM initdb_ran" 2>/dev/null | tr -d ' ')"
[[ "$ran" == "yes" ]] || vfail "/docker-entrypoint-initdb.d script did not run"
vinfo "/docker-entrypoint-initdb.d executed"

# --- MYSQL_* / MARIADB_* scenarios -------------------------------------------
compat_mysql_family() {
    local engine="$1" prefix="$2" client="$3" img name
    img="$(image_name "$engine")"
    need_image "$img"

    printf 'filepass456\n' > "$tmp/${engine}pass"
    printf 'CREATE TABLE initdb_ran(v text);\nINSERT INTO initdb_ran VALUES ("yes");\n' \
        > "$tmp/${engine}-init.sql"

    name="dbtk-verify-compat-$engine-$$"
    track_container "$name"

    docker run -d --name "$name" \
        -e "${prefix}_ROOT_PASSWORD_FILE=/run/secrets/pw" \
        -e "${prefix}_DATABASE=custom_db" \
        -e "${prefix}_USER=custom_user" \
        -e "${prefix}_PASSWORD=userpass" \
        -v "$tmp/${engine}pass:/run/secrets/pw:ro" \
        -v "$tmp/${engine}-init.sql:/docker-entrypoint-initdb.d/01-init.sql:ro" \
        "$img" >/dev/null || vfail "$engine failed to start with ${prefix}_ROOT_PASSWORD_FILE"

    wait_for 90 "$engine custom_user to connect" \
        docker exec "$name" "$client" -ucustom_user -puserpass custom_db -e "SELECT 1"

    docker exec "$name" "$client" -uroot -pfilepass456 -e "SELECT 1" >/dev/null 2>&1 \
        || vfail "${prefix}_ROOT_PASSWORD_FILE was not honoured"

    local ran
    ran="$(docker exec "$name" "$client" -ucustom_user -puserpass custom_db -N -B \
        -e "SELECT v FROM initdb_ran" 2>/dev/null | tr -d ' \r')"
    [[ "$ran" == "yes" ]] || vfail "$engine /docker-entrypoint-initdb.d script did not run"

    vinfo "$engine: ${prefix}_ROOT_PASSWORD_FILE, _DATABASE, _USER and initdb.d honoured"
}

compat_mysql_family mysql MYSQL mysql
compat_mysql_family mariadb MARIADB mariadb
