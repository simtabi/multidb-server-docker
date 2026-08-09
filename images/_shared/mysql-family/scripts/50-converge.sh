#!/usr/bin/env bash
#
# Stage 5: cluster-level convergence, applied on EVERY start.
#
# Stage 4 emits into /docker-entrypoint-initdb.d, which the upstream entrypoint
# runs exactly once. That is right for project provisioning and wrong for
# anything a later change may need to introduce -- enabling the pooler on a
# volume created months ago must not require destroying the data.
#
# What it converges is the pooler's own account. ProxySQL cannot use root:
# root is restricted to the local socket, which is correct hardening and
# deliberately not relaxed here. It gets a narrow account instead, the same way
# pgBouncer does on the PostgreSQL side (DESIGN.md D-35):
#
#   * SELECT on mysql.user, to read password VERIFIERS -- never cleartext;
#   * REPLICATION CLIENT, for ProxySQL's monitor module.
#
# Nothing else. A compromised pooler account cannot read application data.

MMDB_STAGE=mmdb-converge
export MMDB_STAGE
# shellcheck source=mmdb-lib.sh
source /usr/local/lib/mmdb/mmdb-lib.sh

secret=/run/secrets/proxysql_admin_password.txt

if [[ ! -r "$secret" ]]; then
    stage "no proxysql secret mounted; nothing to converge"
    exit 0
fi

pw="$(tr -d '\n' < "$secret")"

# The root secret's filename follows the engine, the same way every other
# per-engine path here does.
root_secret="/run/secrets/${MMDB_ENGINE}_root_password.txt"
[[ -r "$root_secret" ]] || { stage "no root secret at $root_secret; skipping"; exit 0; }
root_pw="$(tr -d '\n' < "$root_secret")"
esc_pw="${pw//\'/\'\'}"

# Bounded wait. An unbounded one turns "the engine failed to start" into a
# container that hangs with no explanation.
deadline=$(( SECONDS + 90 ))
until "$MMDB_CLIENT" --protocol=socket -uroot \
        -p"$root_pw" -e "SELECT 1" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
        stage "engine did not become ready within 90s; skipping convergence"
        exit 0
    fi
    sleep 2
done

"$MMDB_CLIENT" --protocol=socket -uroot \
    -p"$root_pw" <<SQL
CREATE USER IF NOT EXISTS 'proxysql'@'%' IDENTIFIED BY '${esc_pw}';
ALTER USER 'proxysql'@'%' IDENTIFIED BY '${esc_pw}';
GRANT USAGE, REPLICATION CLIENT ON *.* TO 'proxysql'@'%';
GRANT SELECT ON mysql.user TO 'proxysql'@'%';
FLUSH PRIVILEGES;
SQL

stage "converged the pooler account"
