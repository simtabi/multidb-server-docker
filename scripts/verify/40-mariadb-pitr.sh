#!/usr/bin/env bash
# verify: MariaDB recovers to a point in time from its binary log
# tags: backup pitr
# phase: 5

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need_docker

# SPEC section 18, criterion 7c, for the MySQL family.
#
# PostgreSQL got PITR through WAL archiving; MySQL and MariaDB had none, so
# their recovery granularity was the last dump. The binary log is the
# equivalent mechanism and the assertion is held to the same standard as
# check 37: recovery to a chosen instant must keep what was written before it
# and drop what came after. "The server restarted" and "a binlog exists" both
# pass on a setup that cannot actually recover.

# MariaDB, not MySQL. Both write binary logs, but only MariaDB's image ships a
# tool that can READ one back: mysql:8.4 is server-minimal on Oracle Linux 9
# with no mysqlbinlog, and the only one in its repos conflicts with the server
# package. engines/mysql/engine.conf records that as PITR_CAPABLE=false rather
# than pretending otherwise, so this check follows the descriptors.
engine="${DBTK_PITR_ENGINE:-mariadb}"
img="$(image_name "$engine")"
need_image "$img"

name="dbtk-verify-mypitr-$$"
vol="dbtk-verify-mypitr-binlog-$$"
track_container "$name"

docker volume rm -f "$vol" >/dev/null 2>&1 || true
docker volume create "$vol" >/dev/null
track_volume "$vol"

upper="$(printf '%s' "$engine" | tr '[:lower:]' '[:upper:]')"
pw=dbtk-throwaway-mypitr

docker run -d --name "$name" \
    -e "${upper}_ROOT_PASSWORD=$pw" \
    -e "DBTK_${upper}_PITR=true" \
    -v "$vol:/var/lib/dbtk-binlog" \
    "$img" >/dev/null || vfail "container failed to start"

client="$( [[ "$engine" == mariadb ]] && printf 'mariadb' || printf 'mysql' )"
binlog_tool="$( [[ "$engine" == mariadb ]] && printf 'mariadb-binlog' || printf 'mysqlbinlog' )"
run_sql() { docker exec -i "$name" "$client" --protocol=socket -uroot -p"$pw" -N -B -e "$1" 2>/dev/null; }

wait_ready 180 "the engine to accept connections" \
    docker exec "$name" bash -c "$client --protocol=socket -uroot -p'$pw' -e 'SELECT 1'"

# Binary logging must be on, and in a REPLAYABLE format. STATEMENT format
# replays non-deterministic statements differently than they ran, so recovery
# would silently diverge from the database it is meant to reproduce.
log_bin="$(run_sql "SELECT @@log_bin" | tr -d ' \r')"
[[ "$log_bin" == "1" ]] || vfail "log_bin is '$log_bin'; PITR needs binary logging on, set before start"
fmt="$(run_sql "SELECT @@binlog_format" | tr -d ' \r')"
[[ "$fmt" == "ROW" ]] || vfail "binlog_format is '$fmt'; PITR needs ROW to replay deterministically"
vinfo "binary logging on, ROW format"

# On its own volume, not inside the data directory. A recovery log stored
# inside the thing it recovers goes when that goes.
basename_val="$(run_sql "SELECT @@log_bin_basename" | tr -d ' \r')"
case "$basename_val" in
    /var/lib/dbtk-binlog/*) ;;
    *) vfail "binary logs are at '$basename_val'; they must live outside the data directory" ;;
esac
vinfo "binary logs are on their own volume ($basename_val)"

run_sql "CREATE DATABASE pitrdemo; CREATE TABLE pitrdemo.t (id INT PRIMARY KEY, label VARCHAR(20));" >/dev/null
run_sql "INSERT INTO pitrdemo.t VALUES (1,'before');" >/dev/null

# The target comes from the SERVER's clock: --stop-datetime compares against
# event timestamps the server wrote, so a host/container skew of one second
# puts the target on the wrong side of a write.
target="$(run_sql "SELECT NOW()" | tr -d '\r')"
[[ -n "$target" ]] || vfail "could not read the server clock"

sleep 2
run_sql "INSERT INTO pitrdemo.t VALUES (2,'after');" >/dev/null

total="$(run_sql "SELECT COUNT(*) FROM pitrdemo.t" | tr -d ' \r')"
[[ "$total" == "2" ]] || vfail "expected 2 rows before recovery, found $total"
vinfo "wrote 'before', recorded the target, wrote 'after'"

# Close the current log so every event is on disk and readable.
run_sql "FLUSH BINARY LOGS" >/dev/null
sleep 2

# Recovery: drop to the pre-write state, then replay up to the target. Dropping
# the database stands in for restoring a base dump taken before both writes,
# which is what the documented procedure does.
run_sql "DROP DATABASE pitrdemo" >/dev/null
gone="$(run_sql "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='pitrdemo'" | tr -d ' \r')"
[[ "$gone" == "0" ]] || vfail "could not drop the database to simulate data loss"

docker exec "$name" bash -c "
    set -e
    set -o pipefail
    # ONLY the logs. MariaDB writes a .idx sidecar next to each one, and
    # binlog.[0-9]* matches those too -- the replay tool then refuses the whole
    # batch with "File is not a binary log file", which reads as a corrupt log
    # rather than a glob that caught the wrong files. binlog.index is excluded
    # for the same reason.
    logs=\$(ls -1 /var/lib/dbtk-binlog 2>/dev/null | grep -E '^binlog\.[0-9]+\$' | sort | sed 's|^|/var/lib/dbtk-binlog/|')
    [ -n \"\$logs\" ] || { echo 'no binary logs found' >&2; exit 1; }
    $binlog_tool --stop-datetime='$target' \$logs | $client --protocol=socket -uroot -p'$pw'
" > /tmp/dbtk-replay-$$.log 2>&1 || { sed -n "1,8p" /tmp/dbtk-replay-$$.log >&2; rm -f /tmp/dbtk-replay-$$.log; vfail "binlog replay failed"; }
rm -f /tmp/dbtk-replay-$$.log

# THE assertion.
kept="$(run_sql "SELECT COUNT(*) FROM pitrdemo.t WHERE label='before'" | tr -d ' \r')"
dropped="$(run_sql "SELECT COUNT(*) FROM pitrdemo.t WHERE label='after'" | tr -d ' \r')"

[[ "$kept" == "1" ]] \
    || vfail "the row written BEFORE the target is missing after recovery (found '$kept')"
[[ "$dropped" == "0" ]] \
    || vfail "the row written AFTER the target survived recovery (found '$dropped'); the target was not honoured"

# KNOWN RED at this assertion. Everything above passes: binary logging is on,
# in ROW format, on its own volume, and the writes are in the log (a replay
# with no --stop-datetime emits them). What does not work yet is the bounded
# replay: mariadb-binlog --stop-datetime emits ~41 lines and no CREATE
# DATABASE, cutting events whose timestamps are demonstrably BEFORE the target.
# Committed red deliberately, per CLAUDE.md: the check is right and the
# implementation is not finished.
vinfo "recovered to the target: the earlier write survived, the later one did not"
vinfo "$engine PITR is active and recovers to a point in time"
