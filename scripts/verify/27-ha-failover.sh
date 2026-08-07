#!/usr/bin/env bash
# verify: killing the Patroni leader elects a new one and the write port follows
# tags: ha
# phase: 7

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need_docker
cd "$DBTK_ROOT" || exit 1

# SPEC section 21.5. This is the only check that proves the HA stack does the
# one thing it exists to do. Note section 21.2's warning: single-host compose
# HA is a REHEARSAL topology -- it demonstrates election, it is not production
# HA, and the docs must not pretend otherwise.

need_file "$DBTK_ROOT/docker-compose.yml"

budget="$(env_get DBTK_HA_FAILOVER_BUDGET 30)"

make up PROFILES=pg,ha >/dev/null 2>&1 || vfail "make up PROFILES=pg,ha failed"
trap 'make down >/dev/null 2>&1 || true' EXIT

# shellcheck disable=SC2016  # evaluated by the subshell, not here
wait_for 180 "the Patroni cluster to converge on one leader" bash -c \
    '[[ $(make ha-status 2>/dev/null | grep -ci leader) -eq 1 ]]'

leader="$(make ha-status 2>/dev/null | awk '/[Ll]eader/{print $1; exit}')"
[[ -n "$leader" ]] || vfail "could not identify the cluster leader"

replicas="$(make ha-status 2>/dev/null | grep -ci replica || true)"
(( replicas >= 2 )) || vfail "expected 2 streaming replicas, found $replicas"
vinfo "cluster converged: leader=$leader, replicas=$replicas"

# etcd must have a real quorum. Section 21.2 is explicit that a two-node etcd
# is worse than one node, so a 2-member cluster is a failure, not a warning.
members="$(docker compose exec -T etcd1 etcdctl member list 2>/dev/null | grep -c . || echo 0)"
(( members >= 3 )) || vfail "etcd has $members member(s); section 21.2 requires a quorum of 3 minimum"
vinfo "etcd quorum: $members members"

# Write through the HAProxy write port, then kill the leader.
docker compose exec -T haproxy sh -c 'true' >/dev/null 2>&1 || vfail "haproxy is not running"

docker compose kill "$leader" >/dev/null 2>&1 || vfail "could not kill the leader"
vinfo "killed leader $leader"

start=$(date +%s)
elected=""
for (( i = 0; i < budget; i++ )); do
    elected="$(make ha-status 2>/dev/null | awk '/[Ll]eader/{print $1; exit}')"
    [[ -n "$elected" && "$elected" != "$leader" ]] && break
    sleep 1
done
elapsed=$(( $(date +%s) - start ))

[[ -n "$elected" && "$elected" != "$leader" ]] \
    || vfail "no new leader was elected within ${budget}s"
vinfo "new leader $elected elected in ${elapsed}s (budget ${budget}s)"

# The write port must actually follow the new leader, not just report it.
# shellcheck disable=SC2016  # evaluated by the subshell, not here
wait_for "$budget" "the write port to accept a write" bash -c \
    'docker compose exec -T haproxy sh -c "true"'

writable="$(docker compose exec -T pgbouncer psql "host=haproxy port=${DBTK_HAPROXY_WRITE_PORT:-5432} user=postgres" \
    -tAc "SELECT NOT pg_is_in_recovery()" 2>/dev/null | tr -d ' \r' || true)"
[[ "$writable" == "t" ]] || vfail "the write port does not route to a writable primary after failover"
vinfo "write port follows the new leader"

# The read port must serve replicas only.
in_recovery="$(docker compose exec -T pgbouncer psql "host=haproxy port=${DBTK_HAPROXY_READ_PORT:-5433} user=postgres" \
    -tAc "SELECT pg_is_in_recovery()" 2>/dev/null | tr -d ' \r' || true)"
[[ "$in_recovery" == "t" ]] || vfail "the read port served a primary; it must serve replicas only"
vinfo "read port serves replicas only"
