#!/usr/bin/env bash
#
# Stage 4: multi-project provisioning.
#
# Same triplet contract as PostgreSQL (SPEC section 6):
# MMDB_MYSQL_DATABASES / MMDB_MARIADB_DATABASES = "db:user:password,...".
#
# Emitted into /docker-entrypoint-initdb.d rather than executed here, because
# the upstream entrypoint owns first-run initialisation.

MMDB_STAGE=mmdb-provision
export MMDB_STAGE
# shellcheck source=mmdb-lib.sh
source /usr/local/lib/mmdb/mmdb-lib.sh

triplets="$(engine_env DATABASES '')"

if [[ -z "$triplets" ]]; then
    stage "no triplets configured; nothing to provision"
    exit 0
fi

if datadir_initialised; then
    stage "data directory already initialised; provisioning is a first-run concern, skipping"
    exit 0
fi

sql="$MMDB_INITDB_DIR/50-mmdb-provision.sql"
: > "$sql"
count=0

IFS=',' read -ra entries <<< "$triplets"
for entry in "${entries[@]}"; do
    [[ -z "$entry" ]] && continue

    db="${entry%%:*}"
    rest="${entry#*:}"
    user="${rest%%:*}"
    pass="${rest#*:}"

    [[ -n "$db" && -n "$user" ]] || die "malformed triplet (want db:user:password): $entry"

    if [[ "$pass" == "__FILE__" ]]; then
        secret_file="/run/secrets/${MMDB_ENGINE}_${user}_password.txt"
        [[ -r "$secret_file" ]] || die "triplet for '$db' uses __FILE__ but $secret_file is not readable"
        pass="$(tr -d '\n' < "$secret_file")"
    fi
    [[ -n "$pass" ]] || die "triplet for '$db' has an empty password"

    esc_pass="${pass//\'/\'\'}"

    # The backticks below are MySQL identifier quoting inside printf FORMAT
    # strings, not command substitution; single quotes are what keeps them
    # literal, which is exactly right.
    # shellcheck disable=SC2016
    {
        printf -- "-- project: %s\n" "$db"
        printf 'CREATE DATABASE IF NOT EXISTS `%s` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\n' "$db"
        printf "CREATE USER IF NOT EXISTS '%s'@'%%' IDENTIFIED BY '%s';\n" "$user" "$esc_pass"

        # Isolation comes from granting only on this project's database. Unlike
        # PostgreSQL there is no implicit public grant to revoke, so a role
        # simply has no reach outside what is granted here.
        printf 'GRANT ALL PRIVILEGES ON `%s`.* TO %s;\n' "$db" "'$user'@'%'"

        # A read-only companion, mirroring the PostgreSQL side.
        printf "CREATE USER IF NOT EXISTS '%s_readonly'@'%%' IDENTIFIED BY '%s';\n" "$user" "$esc_pass"
        printf 'GRANT SELECT ON `%s`.* TO %s;\n' "$db" "'${user}_readonly'@'%'"
        printf '\n'
    } >> "$sql"

    count=$(( count + 1 ))
done

printf 'FLUSH PRIVILEGES;\n' >> "$sql"
chmod 0644 "$sql"
stage "queued $count project(s) for provisioning at first init"
