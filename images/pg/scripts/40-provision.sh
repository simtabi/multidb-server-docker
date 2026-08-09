#!/usr/bin/env bash
#
# Stage 4: multi-project provisioning.
#
# SPEC section 8 and the danielptv triplet format: MDB_PG_DATABASES holds
# `database:username:password` entries, comma-separated. The password may be
# the literal __FILE__, which resolves to secrets/pg_<user>_password.txt mounted
# at /run/secrets.
#
# The work is emitted into /docker-entrypoint-initdb.d rather than executed
# here, because the upstream entrypoint owns first-run initialisation and SPEC
# section 6.1 is explicit that s6 wraps that contract rather than replacing it.

MDB_STAGE=mdb-provision
export MDB_STAGE
# The absolute path is correct inside the image; this tells shellcheck where
# to find the same file in the repository.
# shellcheck source=mdb-lib.sh
source /usr/local/lib/mdb/mdb-lib.sh

triplets="${MDB_PG_DATABASES:-}"

if [[ -z "$triplets" ]]; then
    stage "no MDB_PG_DATABASES set; nothing to provision"
    exit 0
fi

if pgdata_initialised; then
    stage "data directory already initialised; provisioning is a first-run concern, skipping"
    exit 0
fi

extensions="${MDB_PG_INIT_EXTENSIONS:-}"
sql="$MDB_INITDB_DIR/50-mdb-provision.sql"

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
        secret_file="/run/secrets/pg_${user}_password.txt"
        [[ -r "$secret_file" ]] || die "triplet for '$db' uses __FILE__ but $secret_file is not readable"
        pass="$(tr -d '\n' < "$secret_file")"
    fi
    [[ -n "$pass" ]] || die "triplet for '$db' has an empty password"

    # Single-quote escaping for SQL literals.
    esc_pass="${pass//\'/\'\'}"

    {
        printf -- "-- project: %s\n" "$db"
        printf "CREATE ROLE %s LOGIN PASSWORD '%s';\n" "$user" "$esc_pass"
        printf "CREATE DATABASE %s OWNER %s;\n" "$db" "$user"

        # Isolation. Without revoking the public grant every role could connect
        # to every database, which is the failure SPEC section 18 calls out as
        # "cross-access denied" and which looks correct until it is tested.
        printf "REVOKE ALL ON DATABASE %s FROM PUBLIC;\n" "$db"
        printf "GRANT CONNECT, TEMPORARY ON DATABASE %s TO %s;\n" "$db" "$user"

        # A read-only companion role, per SPEC section 8.
        printf "CREATE ROLE %s_readonly NOLOGIN;\n" "$user"
        printf "GRANT CONNECT ON DATABASE %s TO %s_readonly;\n" "$db" "$user"
    } >> "$sql"

    if [[ -n "$extensions" ]]; then
        printf "\\\\connect %s\n" "$db" >> "$sql"
        IFS=',' read -ra exts <<< "$extensions"
        for ext in "${exts[@]}"; do
            ext="${ext// /}"
            [[ -z "$ext" ]] && continue
            printf 'CREATE EXTENSION IF NOT EXISTS "%s" CASCADE;\n' "$ext" >> "$sql"
        done
        printf "GRANT ALL ON SCHEMA public TO %s;\n" "$user" >> "$sql"
        printf "\\\\connect postgres\n" >> "$sql"
    fi

    printf '\n' >> "$sql"
    count=$(( count + 1 ))
done

chmod 0644 "$sql"
stage "queued $count project(s) for provisioning at first init"
